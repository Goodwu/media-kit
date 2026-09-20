import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Darwin native-output lifecycle. The renderer is deliberately fail-closed:
/// until a real drawable and player target are attached, `active` is false.
final class NativeSurfaceOutput {
  struct State {
    var generation: Int = 0
    var capable = false
    var active = false
    var failureReason = "surface not attached"
  }

  private var states = [Int64: State]()
  private let lock = NSLock()
  private var layerReady = [Int64: Int]()
  private var configurations = [Int64: [String: Any]]()
  var onStateChanged: (([String: Any]) -> Void)?
  private var displayObservers = [NSObjectProtocol]()

  init() {
    NativeFrameRegistry.observeFloatFormat(handle: -1) { [weak self] _ in
      self?.refreshAll()
    }
    NativeFrameRegistry.observeFramePresented(handle: -1) { [weak self] handle in
      self?.promoteAfterPresentedFrame(handle: handle)
    }
    #if canImport(UIKit)
      displayObservers.append(NotificationCenter.default.addObserver(
        forName: UIScreen.didConnectNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.refreshAll() })
      displayObservers.append(NotificationCenter.default.addObserver(
        forName: UIScreen.didDisconnectNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.refreshAll() })
    #elseif canImport(AppKit)
      displayObservers.append(NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.refreshAll() })
      displayObservers.append(NotificationCenter.default.addObserver(
        forName: NSWindow.didChangeScreenNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.refreshAll() })
    #endif
  }

  deinit {
    for observer in displayObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  /// Current EDR headroom is the compositor's observed runtime value. It may
  /// remain 1.0 until an EDR layer has requested content, so it is diagnostic
  /// evidence rather than the pre-activation gate.
  private func currentHeadroom(handle: Int64) -> Double {
    let metrics = NativeSurfaceViewRegistry.metrics(handle: handle)
    if let value = metrics["currentHeadroom"] { return value }
    #if canImport(UIKit)
      if #available(iOS 16.0, *) { return Double(UIScreen.main.currentEDRHeadroom) }
      return 1.0
    #elseif canImport(AppKit)
      return Double(NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0)
    #else
      return 1.0
    #endif
  }

  private func displaySupportsEdr(handle: Int64) -> Bool {
    // Potential headroom proves that the current display mode can attempt EDR.
    // Actual current headroom and a visible frame are still required for
    // acceptance; using currentHeadroom here would deadlock first activation.
    return potentialHeadroom(handle: handle) > 1.0
  }

  private func potentialHeadroom(handle: Int64) -> Double {
    let metrics = NativeSurfaceViewRegistry.metrics(handle: handle)
    if let value = metrics["potentialHeadroom"] { return value }
    #if canImport(UIKit)
      if #available(iOS 16.0, *) { return Double(UIScreen.main.potentialEDRHeadroom) }
      return 1.0
    #elseif canImport(AppKit)
      if #available(macOS 10.15, *) {
        return Double(NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0)
      }
      return 1.0
    #else
      return 1.0
    #endif
  }

  @discardableResult
  func attachLayer(handle: Int64, generation: Int, rendererReady: Bool) -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    if rendererReady {
      layerReady[handle] = generation
    } else {
      layerReady.removeValue(forKey: handle)
    }
    NativeFrameRegistry.clearPresented(handle: handle)
    guard var state = states[handle] else { return report(handle: handle) }
    let candidate = canProduceFloat(handle: handle, configuration: configurations[handle], state: state)
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: candidate)
    state.active = candidate && NativeFrameRegistry.hasPresentedFrame(handle: handle)
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: state.active)
    state.failureReason = state.active ? "" : candidate ? "awaiting-first-float-frame" : "surface, frame provider, or HDR target probe incomplete"
    states[handle] = state
    return report(handle: handle)
  }

  func detachLayer(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    layerReady.removeValue(forKey: handle)
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: false)
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: false)
  }

  func create(handle: Int64, generation: Int) -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    guard states[handle]?.generation != generation else { return report(handle: handle) }
    #if os(iOS)
      #if targetEnvironment(simulator)
        let supported = false
      #else
        let supported = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 16
      #endif
    #else
      let supported = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 11
    #endif
    states[handle] = State(
      generation: generation,
      capable: supported,
      active: false,
      failureReason: supported ? "awaiting layer and player probe" : "OS does not support native EDR surface"
    )
    return report(handle: handle)
  }

  func configure(handle: Int64, generation: Int, configuration: [String: Any]) -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    guard var state = states[handle], state.generation == generation else {
      return ["capable": false, "active": false, "failureReason": "stale surface generation", "generation": generation]
    }
    configurations[handle] = configuration
    NativeFrameRegistry.advanceOutputEpoch(handle: handle)
    NativeFrameRegistry.clearPresented(handle: handle)
    NativeSurfaceViewRegistry.configure(handle: handle, configuration: configuration)
    let candidate = canProduceFloat(handle: handle, configuration: configuration, state: state)
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: candidate)
    state.active = candidate && NativeFrameRegistry.hasPresentedFrame(handle: handle)
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: state.active)
    state.failureReason = state.active ? "" : candidate ? "awaiting-first-float-frame" : "surface, frame provider, or HDR target probe incomplete"
    states[handle] = state
    return report(handle: handle)
  }

  func reset(handle: Int64, generation: Int) -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    guard var state = states[handle], state.generation == generation else {
      return ["capable": false, "active": false, "failureReason": "stale surface generation", "generation": generation]
    }
    state.active = false
    states[handle] = state
    // A reset invalidates the whole output transaction. Do not retain the
    // previous player-target proof: a later display refresh must not
    // re-promote the producer before a fresh configure call.
    configurations.removeValue(forKey: handle)
    NativeFrameRegistry.advanceOutputEpoch(handle: handle)
    // Clear display-side HDR metadata as well as the producer mode. The next
    // configure call may restore PQ/HLG; leaving the old CAEDRMetadata active
    // would make an inactive/SDR edge indistinguishable from an HDR output.
    NativeSurfaceViewRegistry.configure(handle: handle, configuration: ["transfer": "sdr"])
    NativeFrameRegistry.clearPresented(handle: handle)
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: false)
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: false)
    return report(handle: handle)
  }

  func dispose(handle: Int64, generation: Int?) {
    lock.lock(); defer { lock.unlock() }
    guard generation == nil || states[handle]?.generation == generation else { return }
    states.removeValue(forKey: handle)
    configurations.removeValue(forKey: handle)
    layerReady.removeValue(forKey: handle)
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: false)
    NativeFrameRegistry.clearPresented(handle: handle)
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: false)
  }

  private func refreshAll() {
    lock.lock()
    let handles = Array(states.keys)
    let reports = handles.map { handle -> [String: Any] in
      guard var state = states[handle] else { return report(handle: handle) }
      NativeFrameRegistry.clearPresented(handle: handle)
      let candidate = canProduceFloat(handle: handle, configuration: configurations[handle], state: state)
      NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: candidate)
      state.active = candidate && NativeFrameRegistry.hasPresentedFrame(handle: handle)
      NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: state.active)
      state.failureReason = state.active ? "" : candidate ? "awaiting-first-float-frame" : "surface, frame provider, or HDR target probe incomplete"
      states[handle] = state
      return report(handle: handle)
    }
    lock.unlock()
    for report in reports { onStateChanged?(report) }
  }

  private func targetVerified(_ configuration: [String: Any]?) -> Bool {
    guard let configuration else { return false }
    return configuration["playerTargetVerified"] as? Bool == true &&
      configuration["target-colorspace"] as? String == "bt.2020" &&
      configuration["target-trc"] as? String == "linear"
  }

  private func canProduceFloat(handle: Int64, configuration: [String: Any]?, state: State) -> Bool {
    let transfer = configuration?["transfer"] as? String
    let hdrInput = transfer == "pq" || transfer == "hlg"
    return state.capable && hdrInput && targetVerified(configuration) &&
      layerReady[handle] == state.generation &&
      NativeFrameRegistry.hasFloatProvider(handle: handle) &&
      displaySupportsEdr(handle: handle)
  }

  private func promoteAfterPresentedFrame(handle: Int64) {
    lock.lock()
    guard var state = states[handle] else { lock.unlock(); return }
    let candidate = canProduceFloat(handle: handle, configuration: configurations[handle], state: state)
    state.active = candidate && NativeFrameRegistry.hasPresentedFrame(handle: handle)
    state.failureReason = state.active ? "" : candidate ? "awaiting-first-float-frame" : "surface, frame provider, or HDR target probe incomplete"
    states[handle] = state
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: state.active)
    let result = report(handle: handle)
    lock.unlock()
    onStateChanged?(result)
  }

  private func report(handle: Int64) -> [String: Any] {
    let state = states[handle] ?? State()
    return [
      "backend": "darwin-cametal-layer",
      // Profile 8 is verified through the HLG-compatible single-layer test
      // asset. This list describes the accepted input contract for the
      // conversion surface; it does not claim native Dolby Vision metadata
      // passthrough to the display.
      "supportedInputFormats": ["sdr", "hdr10", "hlg", "dolby-vision-p5", "dolby-vision-p7", "dolby-vision-p8"],
      "supportedOutputFormats": ["extended-linear-bt2020"],
      // The shipped Darwin libmpv artifact is not guaranteed to include
      // libplacebo. Report the verified render boundary instead of claiming
      // a backend feature from the Dart/native contract alone.
      "sourceProcessing": "mpv-gpu-native-surface",
      "outputEncoding": "rgba16Float",
      "dynamicMetadataApplied": false,
      "capable": state.capable,
      "active": state.active,
      "floatOutputEnabled": NativeFrameRegistry.isFloatOutputEnabled(handle: handle),
      "framePresented": NativeFrameRegistry.hasPresentedFrame(handle: handle),
      "outputEpoch": NativeFrameRegistry.currentOutputEpoch(handle: handle),
      "hasFloatProvider": NativeFrameRegistry.hasFloatProvider(handle: handle),
      "layerReady": layerReady[handle] == state.generation,
      "targetVerified": targetVerified(configurations[handle]),
      "targetPrim": configurations[handle]?["target-prim"] as? String ?? "",
      "targetTrc": configurations[handle]?["target-trc"] as? String ?? "",
      "activationStage": state.active ? "presented-float-frame" :
        (NativeFrameRegistry.isFloatOutputEnabled(handle: handle) ? "awaiting-float-frame" : "candidate-not-ready"),
      "pixelFormat": "rgba16Float",
      "colorSpace": "extended-linear-bt2020",
      "headroom": currentHeadroom(handle: handle),
      "potentialHeadroom": potentialHeadroom(handle: handle),
      "failureReason": state.failureReason,
      "generation": state.generation,
      "handle": handle
    ]
  }
}
