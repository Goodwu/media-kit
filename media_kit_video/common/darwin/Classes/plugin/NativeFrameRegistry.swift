import CoreVideo
import Foundation

/// Process-local bridge from the mpv renderer to a native platform view.
/// The callback never exposes an engine or platform pointer to Dart.
public enum NativeFrameRegistry {
  private static var callbacks = [Int64: () -> CVPixelBuffer?]()
  private static var leaseProviders = [Int64: () -> CVPixelBuffer?]()
  private static var floatFormats = Set<Int64>()
  private static var floatOutputEnabled = Set<Int64>()
  private static var presentedFrames = Set<Int64>()
  private static var outputEpochs = [Int64: Int64]()
  private static var displayHeadrooms = [Int64: Double]()
  private static var sharedRenderers = Set<Int64>()
  private static var targetObservers = [Int64: () -> Void]()
  private static var producedEpochs = [Int64: [ObjectIdentifier: Int64]]()
  private static var formatObservers = [Int64: (Int64) -> Void]()
  private static var floatOutputObservers = [Int64: (Int64, Bool) -> Void]()
  private static var framePresentedObservers = [Int64: (Int64) -> Void]()
  private static var activeSurfaces = Set<Int64>()
  private static var activeObservers = [Int64: (Int64) -> Void]()
  private static var inFlightBuffers = [Int64: Set<ObjectIdentifier>]()
  private static var inFlightDrainedObservers = [Int64: () -> Void]()
  private static var producedFrameCounts = [Int64: Int64]()
  private static var transitionObservers = [Int64: (OutputTransition) -> Void]()
  private static var transitionSequences = [Int64: UInt64]()
  public struct DiagnosticOutputSnapshot: Equatable {
    public let epoch: Int64
    public let floatEnabled: Bool
    public let currentHeadroom: Double?
    public let surfaceActive: Bool
    public let transitionSequence: UInt64
  }
  public struct OutputTransition: Equatable {
    public let sequence: UInt64
    public let reason: String
    public let old: DiagnosticOutputSnapshot
    public let new: DiagnosticOutputSnapshot
  }
  private static let lock = NSLock()

  // Called only inside the existing registry mutex. No diagnostic lock/IO.
  private static func diagnosticSnapshotLocked(_ handle: Int64) -> DiagnosticOutputSnapshot {
    DiagnosticOutputSnapshot(epoch: outputEpochs[handle] ?? 0,
      floatEnabled: floatOutputEnabled.contains(handle), currentHeadroom: displayHeadrooms[handle],
      surfaceActive: activeSurfaces.contains(handle), transitionSequence: transitionSequences[handle] ?? 0)
  }
  public static func diagnosticOutputSnapshot(handle: Int64) -> DiagnosticOutputSnapshot {
    lock.lock(); defer { lock.unlock() }
    return diagnosticSnapshotLocked(handle)
  }
  public static func observeOutputTransitions(handle: Int64, observer: @escaping (OutputTransition) -> Void) {
    lock.lock()
    transitionObservers[handle] = observer
    transitionSequences[handle] = 0
    let initial = diagnosticSnapshotLocked(handle)
    lock.unlock()
    observer(OutputTransition(sequence: 0, reason: "registered-prior-reason-unknown", old: initial, new: initial))
  }
  // A nil observer skips capture and sequence work altogether (default off).
  private static func captureTransitionLocked(handle: Int64, old: DiagnosticOutputSnapshot?, reason: String)
    -> (OutputTransition, (OutputTransition) -> Void)? {
    guard let old, let observer = transitionObservers[handle] else { return nil }
    let sequence = (transitionSequences[handle] ?? 0) + 1
    transitionSequences[handle] = sequence
    return (OutputTransition(sequence: sequence, reason: reason, old: old,
      new: diagnosticSnapshotLocked(handle)), observer)
  }

  public static func register(handle: Int64, callback: @escaping () -> CVPixelBuffer?) {
    lock.lock(); defer { lock.unlock() }
    callbacks[handle] = callback
  }

  public static func unregister(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    callbacks.removeValue(forKey: handle)
    leaseProviders.removeValue(forKey: handle)
    floatFormats.remove(handle)
    floatOutputEnabled.remove(handle)
    presentedFrames.remove(handle)
    outputEpochs.removeValue(forKey: handle)
    displayHeadrooms.removeValue(forKey: handle)
    sharedRenderers.remove(handle)
    targetObservers.removeValue(forKey: handle)
    producedEpochs.removeValue(forKey: handle)
    formatObservers.removeValue(forKey: handle)
    floatOutputObservers.removeValue(forKey: handle)
    framePresentedObservers.removeValue(forKey: handle)
    activeSurfaces.remove(handle)
    activeObservers.removeValue(forKey: handle)
    inFlightBuffers.removeValue(forKey: handle)
    inFlightDrainedObservers.removeValue(forKey: handle)
    producedFrameCounts.removeValue(forKey: handle)
    transitionObservers.removeValue(forKey: handle)
    transitionSequences.removeValue(forKey: handle)
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
  public static func tryAcquireCurrentFrame(handle: Int64, pixelBuffer: CVPixelBuffer) -> Bool {
    lock.lock(); defer { lock.unlock() }
    let key = ObjectIdentifier(pixelBuffer as AnyObject)
    guard floatOutputEnabled.contains(handle),
          CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_64RGBAHalf,
          let epoch = outputEpochs[handle], producedEpochs[handle]?[key] == epoch,
          inFlightBuffers[handle]?.contains(key) != true else { return false }
    inFlightBuffers[handle, default: []].insert(key)
    return true
  }

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

  /// Provider claims its current buffer while holding the pool rotation lock.
  /// Registry callbacks run outside the registry lock: pool -> registry is the
  /// only nested lock order used by both acquisition and rotation.
  public static func registerLeaseProvider(handle: Int64, callback: @escaping () -> CVPixelBuffer?) {
    lock.lock(); defer { lock.unlock() }
    leaseProviders[handle] = callback
  }

  public static func acquireFrame(handle: Int64) -> CVPixelBuffer? {
    lock.lock(); let provider = leaseProviders[handle]; lock.unlock()
    return provider?()
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
    let changed = floatOutputEnabled.contains(handle) != enabled
    let old = changed && transitionObservers[handle] != nil ? diagnosticSnapshotLocked(handle) : nil
    if enabled { floatOutputEnabled.insert(handle) } else { floatOutputEnabled.remove(handle) }
    if changed {
      outputEpochs[handle] = (outputEpochs[handle] ?? 0) + 1
      producedEpochs[handle] = [:]
      presentedFrames.remove(handle)
    }
    if !enabled { presentedFrames.remove(handle) }
    let observer = floatOutputObservers[handle]
    let transition = captureTransitionLocked(handle: handle, old: old, reason: "float-output-mode-change")
    lock.unlock()
    if let transition { transition.1(transition.0) }
    observer?(handle, enabled)
  }

  public static func isFloatOutputEnabled(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return floatOutputEnabled.contains(handle)
  }

  @discardableResult
  public static func advanceOutputEpoch(handle: Int64, diagnosticReason: String = "explicit-invalidation") -> Int64 {
    lock.lock()
    let old = transitionObservers[handle] == nil ? nil : diagnosticSnapshotLocked(handle)
    let next = (outputEpochs[handle] ?? 0) + 1
    outputEpochs[handle] = next
    presentedFrames.remove(handle)
    producedEpochs[handle] = [:]
    let transition = captureTransitionLocked(handle: handle, old: old, reason: diagnosticReason)
    lock.unlock()
    if let transition { transition.1(transition.0) }
    return next
  }

  public static func setSharedRenderer(handle: Int64, enabled: Bool) {
    lock.lock(); defer { lock.unlock() }
    if enabled { sharedRenderers.insert(handle) } else { sharedRenderers.remove(handle) }
  }

  public static func hasSharedRenderer(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return sharedRenderers.contains(handle)
  }

  public static func hasAcceptedSharedTarget(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard sharedRenderers.contains(handle), let epoch = outputEpochs[handle] else { return false }
    return producedEpochs[handle]?.values.contains(epoch) == true
  }

  public struct OutputSnapshot {
    public let epoch: Int64
    public let floatEnabled: Bool
    /// Relative to UI white; this is not an absolute luminance measurement.
    public let currentHeadroom: Double?
  }

  public static func outputSnapshot(handle: Int64) -> OutputSnapshot {
    lock.lock(); defer { lock.unlock() }
    return OutputSnapshot(epoch: outputEpochs[handle] ?? 0,
                          floatEnabled: floatOutputEnabled.contains(handle),
                          currentHeadroom: displayHeadrooms[handle])
  }

  /// The native view publishes screen facts on the main thread. Render workers
  /// consume only this cache and never touch AppKit or synchronously wait on it.
  @discardableResult
  public static func publishDisplayHeadroom(handle: Int64, value: Double?) -> Bool {
    let valid = value.flatMap { $0.isFinite && $0 >= 1 ? $0 : nil }
    lock.lock()
    guard callbacks[handle] != nil, displayHeadrooms[handle] != valid else {
      lock.unlock()
      return false
    }
    let old = transitionObservers[handle] == nil ? nil : diagnosticSnapshotLocked(handle)
    displayHeadrooms[handle] = valid
    outputEpochs[handle] = (outputEpochs[handle] ?? 0) + 1
    presentedFrames.remove(handle)
    producedEpochs[handle] = [:]
    let redraw = targetObservers[handle]
    let changed = framePresentedObservers[handle] ?? framePresentedObservers[-1]
    let transition = captureTransitionLocked(handle: handle, old: old, reason: "display-headroom-change")
    lock.unlock()
    if let transition { transition.1(transition.0) }
    changed?(handle)
    redraw?()
    return true
  }

  public static func observeOutputTarget(handle: Int64, callback: @escaping () -> Void) {
    lock.lock(); defer { lock.unlock() }
    targetObservers[handle] = callback
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

  public static func isCurrentOutputFrame(handle: Int64, pixelBuffer: CVPixelBuffer) -> Bool {
    lock.lock(); defer { lock.unlock() }
    let key = ObjectIdentifier(pixelBuffer as AnyObject)
    guard let epoch = outputEpochs[handle] else { return false }
    return producedEpochs[handle]?[key] == epoch
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
