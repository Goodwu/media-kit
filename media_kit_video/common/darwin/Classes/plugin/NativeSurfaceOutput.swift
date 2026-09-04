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
    #endif
  }

  deinit {
    for observer in displayObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private var headroom: Double {
    #if canImport(UIKit)
      if #available(iOS 16.0, *) { return Double(UIScreen.main.potentialEDRHeadroom) }
      return 1.0
    #elseif canImport(AppKit)
      return Double(NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0)
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
    guard var state = states[handle] else { return report(handle: handle) }
    let transfer = configurations[handle]?["transfer"] as? String
    let hdrInput = transfer == "pq" || transfer == "hlg"
    state.active = state.capable && hdrInput && targetVerified(configurations[handle]) && layerReady[handle] == state.generation &&
      NativeFrameRegistry.hasFloatProvider(handle: handle) && headroom > 1.0
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: state.active)
    state.failureReason = state.active ? "" : "surface, frame provider, or HDR target probe incomplete"
    states[handle] = state
    return report(handle: handle)
  }

  func detachLayer(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    layerReady.removeValue(forKey: handle)
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
    NativeSurfaceViewRegistry.configure(handle: handle, configuration: configuration)
    let transfer = configuration["transfer"] as? String
    let hdrInput = transfer == "pq" || transfer == "hlg"
    state.active = state.capable && hdrInput && targetVerified(configuration) && layerReady[handle] == generation &&
      NativeFrameRegistry.hasFloatProvider(handle: handle) && headroom > 1.0
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: state.active)
    state.failureReason = state.active ? "" : "surface, frame provider, or HDR target probe incomplete"
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
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: false)
    return report(handle: handle)
  }

  func dispose(handle: Int64, generation: Int?) {
    lock.lock(); defer { lock.unlock() }
    guard generation == nil || states[handle]?.generation == generation else { return }
    states.removeValue(forKey: handle)
    configurations.removeValue(forKey: handle)
    layerReady.removeValue(forKey: handle)
    NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: false)
  }

  private func refreshAll() {
    lock.lock()
    let handles = Array(states.keys)
    let reports = handles.map { handle -> [String: Any] in
      guard var state = states[handle] else { return report(handle: handle) }
      let transfer = configurations[handle]?["transfer"] as? String
      let hdrInput = transfer == "pq" || transfer == "hlg"
      state.active = state.capable && hdrInput && targetVerified(configurations[handle]) && layerReady[handle] == state.generation &&
        NativeFrameRegistry.hasFloatProvider(handle: handle) && headroom > 1.0
      NativeFrameRegistry.setSurfaceActive(handle: handle, enabled: state.active)
      state.failureReason = state.active ? "" : "surface, frame provider, or HDR target probe incomplete"
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

  private func report(handle: Int64) -> [String: Any] {
    let state = states[handle] ?? State()
    return [
      "backend": "darwin-cametal-layer",
      "supportedInputFormats": ["sdr", "hdr10", "hlg", "dolby-vision-p5", "dolby-vision-p7"],
      "supportedOutputFormats": ["extended-linear-bt2020"],
      "sourceProcessing": "mpv-libplacebo",
      "outputEncoding": "rgba16Float",
      "dynamicMetadataApplied": false,
      "capable": state.capable,
      "active": state.active,
      "pixelFormat": "rgba16Float",
      "colorSpace": "extended-linear-bt2020",
      "headroom": headroom,
      "failureReason": state.failureReason,
      "generation": state.generation,
      "handle": handle
    ]
  }
}
