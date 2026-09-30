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
  private static var inFlightBuffers = [Int64: Set<ObjectIdentifier>]()
  private static var inFlightDrainedObservers = [Int64: () -> Void]()
  private static var producedFrameCounts = [Int64: Int64]()
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
    inFlightBuffers.removeValue(forKey: handle)
    inFlightDrainedObservers.removeValue(forKey: handle)
    producedFrameCounts.removeValue(forKey: handle)
  }

  /// Counts every frame the provider pushed into its pool. The presentation
  /// side gates redraws on this counter, not on buffer identity: the pool
  /// recycles a small set of CVPixelBuffer objects, so identity alone cannot
  /// distinguish a recycled buffer carrying a new frame from an old one.
  public static func noteFrameProduced(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    producedFrameCounts[handle, default: 0] += 1
  }

  public static func producedFrameCount(handle: Int64) -> Int64 {
    lock.lock(); defer { lock.unlock() }
    return producedFrameCounts[handle] ?? 0
  }

  /// Marks a buffer as consumed by an async presenter (in-flight Metal blit).
  /// The GL producer must not write into an in-flight buffer; consult
  /// `isInFlight` before recycling a rotated-out pool object.
  public static func markInFlight(handle: Int64, pixelBuffer: CVPixelBuffer) {
    lock.lock()
    let key = ObjectIdentifier(pixelBuffer as AnyObject)
    var inFlight = inFlightBuffers[handle] ?? []
    inFlight.insert(key)
    inFlightBuffers[handle] = inFlight
    lock.unlock()
  }

  /// Clears the in-flight mark and, when the handle has no in-flight buffers
  /// left, notifies the drain observer (e.g. to return held pool objects).
  public static func completeInFlight(handle: Int64, pixelBuffer: CVPixelBuffer) {
    lock.lock()
    let key = ObjectIdentifier(pixelBuffer as AnyObject)
    var inFlight = inFlightBuffers[handle] ?? []
    inFlight.remove(key)
    if inFlight.isEmpty {
      inFlightBuffers.removeValue(forKey: handle)
    } else {
      inFlightBuffers[handle] = inFlight
    }
    let observer = inFlight.isEmpty ? inFlightDrainedObservers[handle] : nil
    lock.unlock()
    observer?()
  }

  public static func isInFlight(handle: Int64, pixelBuffer: CVPixelBuffer) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard let inFlight = inFlightBuffers[handle] else { return false }
    return inFlight.contains(ObjectIdentifier(pixelBuffer as AnyObject))
  }

  public static func observeInFlightDrained(handle: Int64, observer: @escaping () -> Void) {
    lock.lock(); defer { lock.unlock() }
    inFlightDrainedObservers[handle] = observer
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
    // Edge-triggered: a re-assertion of the same value must not notify
    // observers again, or a presented-frame -> promote -> render feedback
    // loop keeps re-rendering the same frame (even while paused).
    let changed = activeSurfaces.contains(handle) != enabled
    if enabled { activeSurfaces.insert(handle) } else { activeSurfaces.remove(handle) }
    let observer = changed ? activeObservers[handle] : nil
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
