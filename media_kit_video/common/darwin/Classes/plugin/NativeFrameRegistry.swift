import CoreVideo
import Foundation

/// Process-local bridge from the mpv renderer to a native platform view.
/// The callback never exposes an engine or platform pointer to Dart.
public enum NativeFrameRegistry {
  private static var callbacks = [Int64: () -> CVPixelBuffer?]()
  private static var floatFormats = Set<Int64>()
  private static var floatOutputEnabled = Set<Int64>()
  private static var presentedFrames = Set<Int64>()
  private static var outputEpochs = [Int64: Int64]()
  private static var producedEpochs = [Int64: [ObjectIdentifier: Int64]]()
  private static var formatObservers = [Int64: (Int64) -> Void]()
  private static var floatOutputObservers = [Int64: (Int64, Bool) -> Void]()
  private static var framePresentedObservers = [Int64: (Int64) -> Void]()
  private static var activeSurfaces = Set<Int64>()
  private static var activeObservers = [Int64: (Int64) -> Void]()
  private static let lock = NSLock()

  public static func register(handle: Int64, callback: @escaping () -> CVPixelBuffer?) {
    lock.lock(); defer { lock.unlock() }
    callbacks[handle] = callback
  }

  public static func unregister(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    callbacks.removeValue(forKey: handle)
    floatFormats.remove(handle)
    floatOutputEnabled.remove(handle)
    presentedFrames.remove(handle)
    outputEpochs.removeValue(forKey: handle)
    producedEpochs.removeValue(forKey: handle)
    formatObservers.removeValue(forKey: handle)
    floatOutputObservers.removeValue(forKey: handle)
    framePresentedObservers.removeValue(forKey: handle)
    activeSurfaces.remove(handle)
    activeObservers.removeValue(forKey: handle)
  }

  public static func copyFrame(handle: Int64) -> CVPixelBuffer? {
    lock.lock(); let callback = callbacks[handle]; lock.unlock()
    return callback?()
  }

  public static func hasProvider(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return callbacks[handle] != nil
  }

  public static func setFloatFormat(handle: Int64, enabled: Bool) {
    lock.lock()
    if enabled { floatFormats.insert(handle) } else { floatFormats.remove(handle) }
    let observer = formatObservers[handle] ?? formatObservers[-1]
    lock.unlock()
    observer?(handle)
  }

  /// Allows the producer to render a candidate float frame. This is distinct
  /// from surface activation: the first successful Metal presentation must
  /// still be observed before the native output is reported active.
  public static func setFloatOutputEnabled(handle: Int64, enabled: Bool) {
    lock.lock()
    if enabled { floatOutputEnabled.insert(handle) } else { floatOutputEnabled.remove(handle) }
    if !enabled { presentedFrames.remove(handle) }
    let observer = floatOutputObservers[handle]
    lock.unlock()
    observer?(handle, enabled)
  }

  public static func isFloatOutputEnabled(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return floatOutputEnabled.contains(handle)
  }

  @discardableResult
  public static func advanceOutputEpoch(handle: Int64) -> Int64 {
    lock.lock(); defer { lock.unlock() }
    let next = (outputEpochs[handle] ?? 0) + 1
    outputEpochs[handle] = next
    presentedFrames.remove(handle)
    producedEpochs[handle] = [:]
    return next
  }

  public static func currentOutputEpoch(handle: Int64) -> Int64 {
    lock.lock(); defer { lock.unlock() }
    return outputEpochs[handle] ?? 0
  }

  public static func markProduced(handle: Int64, pixelBuffer: CVPixelBuffer, epoch: Int64) {
    lock.lock(); defer { lock.unlock() }
    guard callbacks[handle] != nil, outputEpochs[handle] == epoch else { return }
    let key = ObjectIdentifier(pixelBuffer as AnyObject)
    var produced = producedEpochs[handle] ?? [:]
    produced[key] = epoch
    producedEpochs[handle] = produced
  }

  public static func markPresented(handle: Int64, pixelBuffer: CVPixelBuffer) {
    lock.lock()
    let key = ObjectIdentifier(pixelBuffer as AnyObject)
    guard let producedEpoch = producedEpochs[handle]?[key],
          let currentEpoch = outputEpochs[handle],
          producedEpoch == currentEpoch,
          callbacks[handle] != nil,
          floatOutputEnabled.contains(handle) else {
      lock.unlock()
      return
    }
    presentedFrames.insert(handle)
    let observer = framePresentedObservers[handle] ?? framePresentedObservers[-1]
    lock.unlock()
    observer?(handle)
  }

  public static func markPresentationFailed(handle: Int64, pixelBuffer: CVPixelBuffer) {
    lock.lock()
    let key = ObjectIdentifier(pixelBuffer as AnyObject)
    guard let producedEpoch = producedEpochs[handle]?[key],
          producedEpoch == outputEpochs[handle] else {
      lock.unlock()
      return
    }
    presentedFrames.remove(handle)
    let observer = framePresentedObservers[handle] ?? framePresentedObservers[-1]
    lock.unlock()
    observer?(handle)
  }

  public static func clearPresented(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    presentedFrames.remove(handle)
  }

  public static func hasPresentedFrame(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return presentedFrames.contains(handle)
  }

  public static func setSurfaceActive(handle: Int64, enabled: Bool) {
    lock.lock()
    if enabled { activeSurfaces.insert(handle) } else { activeSurfaces.remove(handle) }
    let observer = activeObservers[handle]
    lock.unlock()
    observer?(handle)
  }

  public static func isSurfaceActive(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return activeSurfaces.contains(handle)
  }

  public static func observeSurfaceActive(handle: Int64, observer: @escaping (Int64) -> Void) {
    lock.lock(); defer { lock.unlock() }
    activeObservers[handle] = observer
  }

  public static func observeFloatFormat(handle: Int64, observer: @escaping (Int64) -> Void) {
    lock.lock(); defer { lock.unlock() }
    formatObservers[handle] = observer
  }

  public static func observeFloatOutput(handle: Int64, observer: @escaping (Int64, Bool) -> Void) {
    lock.lock(); defer { lock.unlock() }
    floatOutputObservers[handle] = observer
  }

  public static func observeFramePresented(handle: Int64, observer: @escaping (Int64) -> Void) {
    lock.lock(); defer { lock.unlock() }
    framePresentedObservers[handle] = observer
  }

  public static func hasFloatProvider(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return callbacks[handle] != nil && floatFormats.contains(handle)
  }
}
