import CoreVideo
import Metal
import QuartzCore

/// Converts the Metal-compatible BGRA frame produced by mpv's GL path into
/// the CAMetalLayer pixel format (normally rgba16Float).
final class MetalSurfaceBlitter {
  let supportsFloatSource = true
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let cache: CVMetalTextureCache
  private let pipeline: MTLRenderPipelineState
  private let sampler: MTLSamplerState

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
  }

  func draw(pixelBuffer: CVPixelBuffer, to drawable: CAMetalDrawable) -> Bool {
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
    command.present(drawable)
    command.commit()
    return true
  }
}
