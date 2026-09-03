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

final class NativeSurfaceView: NSObject {
  let nativeView: NSView
  private let metalLayer: CAMetalLayer
  private var blitter: MetalSurfaceBlitter?
  private var timer: Timer?
  private let handle: Int64

  init(frame: NSRect, args: Any?, onLayerReady: ((Int64, Int, Bool) -> Void)? = nil) {
    nativeView = NSView(frame: frame)
    metalLayer = CAMetalLayer()
    handle = Int64((args as? [String: Any])?["handle"] as? Int ?? -1)
    let generation = (args as? [String: Any])?["generation"] as? Int ?? 0
    super.init()
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
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.drawFrame() }
  }

  func view() -> NSView { nativeView }

  deinit {
    timer?.invalidate()
    NativeSurfaceViewRegistry.unregister(handle: handle)
  }

  private func apply(configuration: [String: Any]) {
    let transfer = configuration["transfer"] as? String
    if #available(macOS 10.15, *), transfer == "pq" {
      let metadata = configuration["masteringMetadata"] as? [String: Any]
      let minLuminance = Self.luminance(metadata, keys: ["minLuminance", "min-nits"]) ?? 0.005
      let maxLuminance = Self.luminance(metadata, keys: ["maxLuminance", "max-nits"]) ?? 1_000.0
      metalLayer.edrMetadata = CAEDRMetadata.hdr10(
        minLuminance: Float(minLuminance),
        maxLuminance: Float(maxLuminance),
        opticalOutputScale: 100.0
      )
    }
    if #available(macOS 10.14.3, *) {
      metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
    }
    if transfer == "pq" || transfer == "hlg" {
      metalLayer.wantsExtendedDynamicRangeContent = true
    }
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
    guard let pixelBuffer = NativeFrameRegistry.copyFrame(handle: handle),
          let blitter, let drawable = metalLayer.nextDrawable() else { return }
    _ = blitter.draw(pixelBuffer: pixelBuffer, to: drawable)
  }
}

final class NativeSurfaceViewFactory: NSObject, FlutterPlatformViewFactory {
  private let onLayerReady: ((Int64, Int, Bool) -> Void)?
  init(onLayerReady: ((Int64, Int, Bool) -> Void)? = nil) { self.onLayerReady = onLayerReady }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    NativeSurfaceView(frame: .zero, args: args, onLayerReady: onLayerReady).view()
  }
}
#endif
