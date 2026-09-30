import CoreVideo
import Foundation
import Metal
import QuartzCore

struct MetalSurfaceFrameTiming {
  let sequence: Int
  let cpuWaitSeconds: CFTimeInterval
  let gpuDurationSeconds: CFTimeInterval?
  let completed: Bool
}

/// Converts the Metal-compatible BGRA frame produced by mpv's GL path into
/// the CAMetalLayer pixel format (normally rgba16Float).
final class MetalSurfaceBlitter {
  let supportsFloatSource = true
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let cache: CVMetalTextureCache
  private let pipeline: MTLRenderPipelineState
  private let sampler: MTLSamplerState
  private var frameNumber = 0

  // Diagnostics-only frame sampling (PILIPLUSX_HDR_SAMPLE=1). Never compiled
  // into release builds: the production path only draws.
  #if DEBUG
  private let sampleEnabled: Bool
  private let sampleInterval: Int

  private struct SampleStats {
    let p50: Float
    let p95: Float
    let max: Float

    var description: String {
      "p50=\(p50),p95=\(p95),max=\(max)"
    }
  }

  private static let sampleFractions: [Float] = [
    1.0 / 12.0,
    3.0 / 12.0,
    5.0 / 12.0,
    7.0 / 12.0,
    9.0 / 12.0,
    11.0 / 12.0,
  ]
  #endif

  init?(device: MTLDevice?) {
    guard let device, let queue = device.makeCommandQueue() else { return nil }
    let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct VOut { float4 position [[position]]; float2 uv; };
    vertex VOut surface_vertex(uint id [[vertex_id]]) {
      constexpr float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
      constexpr float2 t[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };
      VOut out; out.position = float4(p[id], 0.0, 1.0); out.uv = t[id]; return out;
    }
    fragment half4 surface_fragment(VOut in [[stage_in]], texture2d<half> frame [[texture(0)]], sampler s [[sampler(0)]]) {
      return frame.sample(s, in.uv);
    }
    """
    guard let library = try? device.makeLibrary(source: source, options: nil),
          let vertex = library.makeFunction(name: "surface_vertex"),
          let fragment = library.makeFunction(name: "surface_fragment")
    else { return nil }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .rgba16Float
    guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.minFilter = .linear
    samplerDescriptor.magFilter = .linear
    samplerDescriptor.sAddressMode = .clampToEdge
    samplerDescriptor.tAddressMode = .clampToEdge
    guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
    var cache: CVMetalTextureCache?
    guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
          let cache else { return nil }
    self.device = device
    self.queue = queue
    self.cache = cache
    self.pipeline = pipeline
    self.sampler = sampler
    #if DEBUG
    let environment = ProcessInfo.processInfo.environment
    sampleEnabled = environment["PILIPLUSX_HDR_SAMPLE"] == "1"
    sampleInterval = max(
      1,
      Int(environment["PILIPLUSX_HDR_SAMPLE_INTERVAL"] ?? "30") ?? 30
    )
    if sampleEnabled {
      NSLog(
        "HDR frame sampler enabled interval=\(sampleInterval) " +
        "regions=6 format=rgba16Float linear"
      )
    }
    #endif
  }

  func draw(
    pixelBuffer: CVPixelBuffer,
    to drawable: CAMetalDrawable,
    timingHandler: ((MetalSurfaceFrameTiming) -> Void)? = nil
  ) -> Bool {
    frameNumber += 1
    let frameSequence = frameNumber
    #if DEBUG
    let shouldSample = sampleEnabled && frameNumber % sampleInterval == 0
    if shouldSample {
      sampleInput(pixelBuffer: pixelBuffer, frame: frameNumber)
    }
    #endif
    var textureRef: CVMetalTexture?
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat: MTLPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_64RGBAHalf
      ? .rgba16Float
      : .bgra8Unorm
    guard CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault, cache, pixelBuffer, nil, pixelFormat,
      width, height, 0, &textureRef
    ) == kCVReturnSuccess,
    let source = textureRef.flatMap(CVMetalTextureGetTexture),
    let command = queue.makeCommandBuffer()
    else { return false }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentTexture(source, index: 0)
    encoder.setFragmentSamplerState(sampler, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()

    #if DEBUG
    if shouldSample {
      addOutputSample(to: command, from: drawable.texture, frame: frameNumber)
    }
    #endif
    command.present(drawable)
    command.commit()
    // TextureHW may return this CVPixelBuffer to the GL producer immediately
    // after the render call. Wait for the Metal read to finish before the
    // three-buffer pool is allowed to recycle it. This is intentionally
    // conservative: correctness across the GL -> CVPixelBuffer -> Metal
    // boundary is required before optimizing with explicit GPU fences.
    let waitStarted = timingHandler == nil ? nil : CACurrentMediaTime()
    command.waitUntilCompleted()
    if let timingHandler, let waitStarted {
      let cpuWaitSeconds = CACurrentMediaTime() - waitStarted
      let gpuDurationSeconds: CFTimeInterval?
      if command.gpuStartTime > 0 && command.gpuEndTime >= command.gpuStartTime {
        gpuDurationSeconds = command.gpuEndTime - command.gpuStartTime
      } else {
        gpuDurationSeconds = nil
      }
      timingHandler(
        MetalSurfaceFrameTiming(
          sequence: frameSequence,
          cpuWaitSeconds: cpuWaitSeconds,
          gpuDurationSeconds: gpuDurationSeconds,
          completed: command.status == .completed
        )
      )
    }
    guard command.status == .completed else {
      let errorDescription = command.error?.localizedDescription ?? "unknown"
      NSLog(
        "HDR frame output failed status=\(command.status.rawValue) " +
        "error=\(errorDescription)"
      )
      return false
    }
    return true
  }

  #if DEBUG
  private func sampleInput(pixelBuffer: CVPixelBuffer, frame: Int) {
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let stats: [SampleStats]?
    let formatName: String
    if pixelFormat == kCVPixelFormatType_64RGBAHalf {
      stats = Self.sampleHalfPixelBuffer(pixelBuffer)
      formatName = "rgba16Float"
    } else if pixelFormat == kCVPixelFormatType_32BGRA {
      stats = Self.sampleBgraPixelBuffer(pixelBuffer)
      formatName = "bgra8Unorm"
    } else {
      NSLog(
        "HDR frame sample input frame=\(frame) unsupportedPixelFormat=" +
        "\(pixelFormat)"
      )
      return
    }
    guard let stats else {
      NSLog("HDR frame sample input frame=\(frame) unavailable")
      return
    }
    NSLog(
      "HDR frame sample input frame=\(frame) " +
      "format=\(formatName) channel=max(rgb) normalized=\(Self.format(stats))"
    )
  }

  private func addOutputSample(to command: MTLCommandBuffer, from texture: MTLTexture, frame: Int) {
    let regionSize = 8
    let width = regionSize * Self.sampleFractions.count
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: width,
      height: regionSize,
      mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = [.shaderRead, .shaderWrite]
    guard let readback = device.makeTexture(descriptor: descriptor),
          let blit = command.makeBlitCommandEncoder()
    else {
      NSLog("HDR frame sample output frame=\(frame) unavailable")
      return
    }

    let sourceWidth = texture.width
    let sourceHeight = texture.height
    for (index, fraction) in Self.sampleFractions.enumerated() {
      let x = min(
        max(Int(Float(sourceWidth) * fraction) - regionSize / 2, 0),
        max(sourceWidth - regionSize, 0)
      )
      let y = min(
        max(sourceHeight / 2 - regionSize / 2, 0),
        max(sourceHeight - regionSize, 0)
      )
      blit.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: MTLOrigin(x: x, y: y, z: 0),
        sourceSize: MTLSize(width: regionSize, height: regionSize, depth: 1),
        to: readback,
        destinationSlice: 0,
        destinationLevel: 0,
        destinationOrigin: MTLOrigin(x: index * regionSize, y: 0, z: 0)
      )
    }
    blit.endEncoding()
    command.addCompletedHandler { commandBuffer in
      guard commandBuffer.status == .completed else {
        NSLog(
          "HDR frame sample output frame=\(frame) commandStatus=\(commandBuffer.status.rawValue)"
        )
        return
      }
      let bytesPerPixel = 8
      let bytesPerRow = width * bytesPerPixel
      var bytes = [UInt16](repeating: 0, count: width * regionSize * 4)
      bytes.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress else { return }
        readback.getBytes(
          baseAddress,
          bytesPerRow: bytesPerRow,
          from: MTLRegionMake2D(0, 0, width, regionSize),
          mipmapLevel: 0
        )
      }
      var regions = [String]()
      for index in 0..<Self.sampleFractions.count {
        var values = [Float]()
        values.reserveCapacity(regionSize * regionSize)
        for y in 0..<regionSize {
          for x in 0..<regionSize {
            let pixel = ((y * width) + index * regionSize + x) * 4
            let r = Self.halfToFloat(bytes[pixel])
            let g = Self.halfToFloat(bytes[pixel + 1])
            let b = Self.halfToFloat(bytes[pixel + 2])
            values.append(max(r, max(g, b)))
          }
        }
        regions.append(Self.stats(values).description)
      }
      NSLog(
        "HDR frame sample output frame=\(frame) channel=max(rgb) " +
        "linearRegions=[\(regions.joined(separator: ";"))]"
      )
    }
  }

  private static func sampleHalfPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> [SampleStats]? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let wordsPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer) / MemoryLayout<UInt16>.size
    let pointer = baseAddress.assumingMemoryBound(to: UInt16.self)
    let radius = 4
    var regions = [SampleStats]()
    for fraction in sampleFractions {
      let centerX = Int(Float(width) * fraction)
      let centerY = height / 2
      var values = [Float]()
      values.reserveCapacity((radius * 2) * (radius * 2))
      for y in max(0, centerY - radius)..<min(height, centerY + radius) {
        for x in max(0, centerX - radius)..<min(width, centerX + radius) {
          let pixel = y * wordsPerRow + x * 4
          let r = halfToFloat(pointer[pixel])
          let g = halfToFloat(pointer[pixel + 1])
          let b = halfToFloat(pointer[pixel + 2])
          values.append(max(r, max(g, b)))
        }
      }
      regions.append(stats(values))
    }
    return regions
  }

  private static func sampleBgraPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> [SampleStats]? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
    let radius = 4
    var regions = [SampleStats]()
    for fraction in sampleFractions {
      let centerX = Int(Float(width) * fraction)
      let centerY = height / 2
      var values = [Float]()
      values.reserveCapacity((radius * 2) * (radius * 2))
      for y in max(0, centerY - radius)..<min(height, centerY + radius) {
        for x in max(0, centerX - radius)..<min(width, centerX + radius) {
          let pixel = y * bytesPerRow + x * 4
          let b = Float(pointer[pixel]) / 255.0
          let g = Float(pointer[pixel + 1]) / 255.0
          let r = Float(pointer[pixel + 2]) / 255.0
          values.append(max(r, max(g, b)))
        }
      }
      regions.append(stats(values))
    }
    return regions
  }

  private static func stats(_ values: [Float]) -> SampleStats {
    let sorted = values.filter { $0.isFinite && $0 >= 0 }.sorted()
    guard let last = sorted.last else { return SampleStats(p50: 0, p95: 0, max: 0) }
    func percentile(_ fraction: Float) -> Float {
      let index = min(Int(Float(sorted.count - 1) * fraction), sorted.count - 1)
      return sorted[index]
    }
    return SampleStats(p50: percentile(0.5), p95: percentile(0.95), max: last)
  }

  private static func format(_ stats: [SampleStats]) -> String {
    "[\(stats.map(\.description).joined(separator: ";"))]"
  }

  // Keep the diagnostic sampler compatible with the package's macOS 10.15
  // deployment target; Swift.Float16(bitPattern:) is only available on newer
  // OS versions even though the pixel format itself is supported here.
  private static func halfToFloat(_ bits: UInt16) -> Float {
    let sign = (bits & 0x8000) == 0 ? 1.0 : -1.0
    let exponent = Int((bits >> 10) & 0x1f)
    let fraction = Int(bits & 0x03ff)
    if exponent == 0 {
      return Float(sign * (fraction == 0 ? 0.0 : Foundation.pow(2.0, -14.0) * Double(fraction) / 1024.0))
    }
    if exponent == 0x1f {
      return fraction == 0 ? Float(sign) * .infinity : .nan
    }
    return Float(sign * Foundation.pow(2.0, Double(exponent - 15)) * (1.0 + Double(fraction) / 1024.0))
  }
  #endif
}
