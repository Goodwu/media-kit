#if canImport(Flutter)
import Flutter
import UIKit
import QuartzCore
import Metal

@available(iOS 13.0, *)
final class NativeSurfaceView: NSObject, FlutterPlatformView {
  let nativeView: UIView
  private let metalLayer: CAMetalLayer
  private var blitter: MetalSurfaceBlitter?
  private var timer: Timer?
  private let handle: Int64

  init(frame: CGRect, args: Any?, onLayerReady: ((Int64, Int, Bool) -> Void)? = nil) {
    nativeView = UIView(frame: frame)
    metalLayer = CAMetalLayer()
    handle = Int64((args as? [String: Any])?["handle"] as? Int ?? -1)
    let generation = (args as? [String: Any])?["generation"] as? Int ?? 0
    super.init()
    nativeView.isUserInteractionEnabled = false
    nativeView.backgroundColor = .black
    metalLayer.frame = nativeView.bounds
    metalLayer.contentsScale = UIScreen.main.scale
    metalLayer.isOpaque = true
    let device = MTLCreateSystemDefaultDevice()
    metalLayer.device = device
    metalLayer.drawableSize = CGSize(
      width: nativeView.bounds.width * metalLayer.contentsScale,
      height: nativeView.bounds.height * metalLayer.contentsScale
    )
    metalLayer.pixelFormat = .rgba16Float
    if #available(iOS 16.0, *) {
      metalLayer.wantsExtendedDynamicRangeContent = true
    }
    if #available(iOS 10.0, *) {
      metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
    }
    nativeView.layer.addSublayer(metalLayer)
    blitter = MetalSurfaceBlitter(device: device)
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.drawFrame() }
    NativeSurfaceViewRegistry.register(handle: handle) { [weak self] configuration in
      self?.apply(configuration: configuration)
    } displayMetrics: { [weak self] in
      #if canImport(UIKit)
        if #available(iOS 16.0, *) {
          let screen = self?.nativeView.window?.screen ?? UIScreen.main
          return [
            "currentHeadroom": Double(screen.currentEDRHeadroom),
            "potentialHeadroom": Double(screen.potentialEDRHeadroom),
          ]
        }
      #elseif canImport(AppKit)
        let screen = self?.nativeView.window?.screen ?? NSScreen.main
        if #available(macOS 10.15, *) {
          return [
            "currentHeadroom": screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0,
            "potentialHeadroom": screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0,
          ]
        }
      #endif
      return ["currentHeadroom": 1.0, "potentialHeadroom": 1.0]
    }
    onLayerReady?(handle, generation, blitter?.supportsFloatSource == true)
  }

  func view() -> UIView { nativeView }

  deinit {
    timer?.invalidate()
    NativeSurfaceViewRegistry.unregister(handle: handle)
  }

  private func apply(configuration: [String: Any]) {
    let transfer = configuration["transfer"] as? String
    if #available(iOS 16.0, *), transfer == "pq" || transfer == "hlg" {
      metalLayer.wantsExtendedDynamicRangeContent = true
      if transfer == "pq" {
        let metadata = configuration["masteringMetadata"] as? [String: Any]
        let minLuminance = Self.luminance(metadata, keys: ["minLuminance", "min-nits"]) ?? 0.005
        let maxLuminance = Self.luminance(metadata, keys: ["maxLuminance", "max-nits"]) ?? 1_000.0
        metalLayer.edrMetadata = CAEDRMetadata.hdr10(
          minLuminance: Float(minLuminance),
          maxLuminance: Float(maxLuminance),
          opticalOutputScale: 100.0
        )
      }
    }
    metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
  }

  private static func luminance(_ metadata: [String: Any]?, keys: [String]) -> Double? {
    guard let metadata else { return nil }
    for key in keys {
      if let value = metadata[key] as? NSNumber { return value.doubleValue }
      if let value = metadata[key] as? String, let parsed = Double(value) { return parsed }
    }
    return nil
  }

  private func drawFrame() {
    let scale = UIScreen.main.scale
    metalLayer.contentsScale = scale
    metalLayer.drawableSize = CGSize(
      width: max(1, nativeView.bounds.width * scale),
      height: max(1, nativeView.bounds.height * scale)
    )
    guard let pixelBuffer = NativeFrameRegistry.copyFrame(handle: handle),
          let blitter,
          let drawable = metalLayer.nextDrawable()
    else { return }
    _ = blitter.draw(pixelBuffer: pixelBuffer, to: drawable)
  }
}

final class NativeSurfaceViewFactory: NSObject, FlutterPlatformViewFactory {
  private let onLayerReady: ((Int64, Int, Bool) -> Void)?
  init(onLayerReady: ((Int64, Int, Bool) -> Void)? = nil) { self.onLayerReady = onLayerReady }
  func release(handle: Int64) {}
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier: Int64, arguments args: Any?) -> FlutterPlatformView {
    if #available(iOS 13.0, *) {
      return NativeSurfaceView(frame: frame, args: args, onLayerReady: onLayerReady)
    }
    return LegacyNativeSurfaceView(frame: frame)
  }
}

final class LegacyNativeSurfaceView: NSObject, FlutterPlatformView {
  private let nativeView: UIView
  init(frame: CGRect) {
    nativeView = UIView(frame: frame)
    super.init()
    nativeView.backgroundColor = .black
  }
  func view() -> UIView { nativeView }
}
#elseif canImport(FlutterMacOS)
import FlutterMacOS
import AppKit
import QuartzCore
import Metal

private final class FrameReportingView: NSView {
  var onFrameChanged: ((NSRect) -> Void)?
  private var lastReportedFrame: NSRect = .zero

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    reportFrameIfChanged()
  }

  private func reportFrameIfChanged() {
    let current = frame
    let epsilon: CGFloat = 0.25
    let changed = abs(current.origin.x - lastReportedFrame.origin.x) > epsilon ||
      abs(current.origin.y - lastReportedFrame.origin.y) > epsilon ||
      abs(current.size.width - lastReportedFrame.size.width) > epsilon ||
      abs(current.size.height - lastReportedFrame.size.height) > epsilon
    guard changed else { return }
    lastReportedFrame = current
    NSLog("NativeSurfaceView macOS frame changed frame=\(current)")
    onFrameChanged?(current)
  }
}

final class NativeSurfaceView: NSObject {
  let nativeView: NSView
  private let metalLayer: CAMetalLayer
  private var blitter: MetalSurfaceBlitter?
  private var timer: DispatchSourceTimer?
  private var drawDiagnosticsRemaining = 8
  private let handle: Int64
  private let generation: Int
  private let viewToken: DarwinViewTokenRegistry.Token

  init(
    frame: NSRect,
    args: Any?,
    onLayerReady: ((Int64, Int, Bool) -> Void)? = nil,
    onFrameChanged: ((Int64, Int, NSRect) -> Void)? = nil
  ) {
    let frameView = FrameReportingView(frame: frame)
    nativeView = frameView
    metalLayer = CAMetalLayer()
    handle = Int64((args as? [String: Any])?["handle"] as? Int ?? -1)
    generation = (args as? [String: Any])?["generation"] as? Int ?? 0
    viewToken = DarwinViewTokenRegistry.register(view: nativeView, handle: handle, generation: generation)
    super.init()
    frameView.onFrameChanged = { [weak self] frame in
      guard let self else { return }
      onFrameChanged?(self.handle, self.generation, frame)
    }
    nativeView.wantsLayer = true
    nativeView.layer = metalLayer
    metalLayer.frame = nativeView.bounds
    metalLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
    metalLayer.isOpaque = true
    let device = MTLCreateSystemDefaultDevice()
    metalLayer.device = device
    metalLayer.drawableSize = CGSize(
      width: nativeView.bounds.width * metalLayer.contentsScale,
      height: nativeView.bounds.height * metalLayer.contentsScale
    )
    metalLayer.pixelFormat = .rgba16Float
    metalLayer.wantsExtendedDynamicRangeContent = true
    if #available(macOS 10.14.3, *) {
      metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
    }
    blitter = MetalSurfaceBlitter(device: metalLayer.device)
    NativeSurfaceViewRegistry.register(handle: handle) { [weak self] configuration in
      self?.apply(configuration: configuration)
    }
    onLayerReady?(handle, generation, blitter?.supportsFloatSource == true)
    NSLog("NativeSurfaceView macOS token registered handle=\(handle) generation=\(generation) token=\(viewToken.rawValue)")
    NSLog("NativeSurfaceView macOS init handle=\(handle) generation=\(generation) frame=\(nativeView.frame)")
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
    timer.setEventHandler { [weak self] in self?.drawFrame() }
    self.timer = timer
    timer.resume()
    NSLog("NativeSurfaceView macOS timer started handle=\(handle)")
  }

  func view() -> NSView { nativeView }

  deinit {
    timer?.cancel()
    NSLog("NativeSurfaceView macOS deinit handle=\(handle) generation=\(generation) token=\(viewToken.rawValue)")
    DarwinViewTokenRegistry.unregister(viewToken, handle: handle, generation: generation)
    NativeSurfaceViewRegistry.unregister(handle: handle)
  }

  private func apply(configuration: [String: Any]) {
    let transfer = configuration["transfer"] as? String
    if #available(macOS 10.15, *), transfer == "pq" {
      let metadata = configuration["masteringMetadata"] as? [String: Any]
      let minLuminance = Self.luminance(metadata, keys: ["minLuminance", "min-nits"]) ?? 0.005
      let maxLuminance = Self.luminance(metadata, keys: ["maxLuminance", "max-nits"]) ?? 1_000.0
      let opticalOutputScale = Self.number(configuration["opticalOutputScale"]) ?? 100.0
      metalLayer.edrMetadata = CAEDRMetadata.hdr10(
        minLuminance: Float(minLuminance),
        maxLuminance: Float(maxLuminance),
        opticalOutputScale: Float(opticalOutputScale)
      )
    } else if #available(macOS 10.15, *) {
      metalLayer.edrMetadata = nil
    }
    if #available(macOS 10.14.3, *) {
      metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
    }
    if transfer == "pq" || transfer == "hlg" {
      metalLayer.wantsExtendedDynamicRangeContent = true
    } else {
      metalLayer.wantsExtendedDynamicRangeContent = false
    }
    let metadataApplied: Bool
    if #available(macOS 10.15, *) {
      metadataApplied = metalLayer.edrMetadata != nil
    } else {
      metadataApplied = false
    }
    let opticalOutputScale = Self.number(configuration["opticalOutputScale"]) ?? 100.0
    NSLog("NativeSurfaceView macOS apply handle=\(handle) transfer=\(transfer ?? "none") edrMetadata=\(metadataApplied) opticalOutputScale=\(opticalOutputScale) wantsEDR=\(metalLayer.wantsExtendedDynamicRangeContent)")
  }

  private static func number(_ value: Any?) -> Double? {
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    return nil
  }

  private static func luminance(_ metadata: [String: Any]?, keys: [String]) -> Double? {
    guard let metadata else { return nil }
    for key in keys {
      if let value = metadata[key] as? NSNumber { return value.doubleValue }
      if let value = metadata[key] as? String, let parsed = Double(value) { return parsed }
    }
    return nil
  }

  private func drawFrame() {
    let scale = nativeView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
    metalLayer.contentsScale = scale
    metalLayer.drawableSize = CGSize(
      width: max(1, nativeView.bounds.width * scale),
      height: max(1, nativeView.bounds.height * scale)
    )
    let pixelBuffer = NativeFrameRegistry.copyFrame(handle: handle)
    let drawable = metalLayer.nextDrawable()
    guard let blitter, let pixelBuffer, let drawable else {
      if drawDiagnosticsRemaining > 0 {
        drawDiagnosticsRemaining -= 1
        NSLog("NativeSurfaceView macOS draw skipped handle=\(handle) pixel=\(pixelBuffer != nil) drawable=\(drawable != nil) bounds=\(nativeView.bounds) drawableSize=\(metalLayer.drawableSize)")
      }
      return
    }
    let drawn = blitter.draw(pixelBuffer: pixelBuffer, to: drawable)
    if drawDiagnosticsRemaining > 0 {
      drawDiagnosticsRemaining -= 1
      NSLog("NativeSurfaceView macOS draw handle=\(handle) drawn=\(drawn) pixelFormat=\(CVPixelBufferGetPixelFormatType(pixelBuffer)) size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) bounds=\(nativeView.bounds) drawableSize=\(metalLayer.drawableSize)")
    }
  }
}

final class NativeSurfaceViewFactory: NSObject, FlutterPlatformViewFactory {
  private let onLayerReady: ((Int64, Int, Bool) -> Void)?
  private let onFrameChanged: ((Int64, Int, NSRect) -> Void)?
  // Keep the platform-view owner alive; otherwise returning only `view()`
  // releases the timer and frame registry immediately.
  private var surfaces = [Int64: NSObject]()
  init(
    onLayerReady: ((Int64, Int, Bool) -> Void)? = nil,
    onFrameChanged: ((Int64, Int, NSRect) -> Void)? = nil
  ) {
    self.onLayerReady = onLayerReady
    self.onFrameChanged = onFrameChanged
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let mpvWindow = (args as? [String: Any])?["mpvWindow"] as? Bool ?? false
    if mpvWindow {
      let surface = MpvWindowView(
        frame: .zero,
        args: args,
        onLayerReady: onLayerReady,
        onFrameChanged: onFrameChanged
      )
      let handle = Int64((args as? [String: Any])?["handle"] as? Int ?? -1)
      surfaces[handle] = surface
      return surface.view()
    }
    let surface = NativeSurfaceView(
      frame: .zero,
      args: args,
      onLayerReady: onLayerReady,
      onFrameChanged: onFrameChanged
    )
    let handle = Int64((args as? [String: Any])?["handle"] as? Int ?? -1)
    surfaces[handle] = surface
    return surface.view()
  }

  func release(handle: Int64) {
    surfaces.removeValue(forKey: handle)
    NSLog("NativeSurfaceViewFactory macOS released handle=\(handle)")
  }
}

/// Minimal AppKit wrapper for the W1 mpv-owned-window experiment. mpv owns
/// the child video output; this wrapper deliberately has no CAMetalLayer,
/// blitter, timer, or Flutter texture consumer.
final class MpvWindowView: NSObject {
  let nativeView: NSView
  private let handle: Int64
  private let generation: Int
  private let viewToken: DarwinViewTokenRegistry.Token
  private let onLayerReady: ((Int64, Int, Bool) -> Void)?
  private let onFrameChanged: ((Int64, Int, NSRect) -> Void)?

  init(
    frame: NSRect,
    args: Any?,
    onLayerReady: ((Int64, Int, Bool) -> Void)?,
    onFrameChanged: ((Int64, Int, NSRect) -> Void)?
  ) {
    let frameView = FrameReportingView(frame: frame)
    nativeView = frameView
    handle = Int64((args as? [String: Any])?["handle"] as? Int ?? -1)
    generation = (args as? [String: Any])?["generation"] as? Int ?? 0
    viewToken = DarwinViewTokenRegistry.register(
      view: nativeView,
      handle: handle,
      generation: generation
    )
    self.onLayerReady = onLayerReady
    self.onFrameChanged = onFrameChanged
    super.init()
    frameView.onFrameChanged = { [weak self] frame in
      guard let self else { return }
      self.onFrameChanged?(self.handle, self.generation, frame)
    }
    onLayerReady?(handle, generation, true)
    NSLog("MpvWindowView macOS init handle=\(handle) generation=\(generation) token=\(viewToken.rawValue)")
  }

  func view() -> NSView { nativeView }

  deinit {
    NSLog("MpvWindowView macOS deinit handle=\(handle) generation=\(generation) token=\(viewToken.rawValue)")
    DarwinViewTokenRegistry.unregister(viewToken, handle: handle, generation: generation)
  }
}
#endif
