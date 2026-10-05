import Foundation

/// One-shot target-contract failure. It changes a real mpv parameter, never its
/// return value. Only explicit diagnostic bundles using the shared renderer may
/// arm it. CPU fixtures prove bookkeeping, not shader/output/runtime recovery.
final class SharedRenderFailureDiagnostics {
  enum Mode: String { case bgra8 = "BGRA8", rgba16f = "RGBA16F" }
  typealias Target = NativeFrameRegistry.DiagnosticOutputSnapshot
  typealias Transition = NativeFrameRegistry.OutputTransition
  struct Attempt {
    let id: UInt64
    let epoch: Int64
    let mode: Mode
    let slot: String
    let actualDepth: UInt32
    let requestedDepth: UInt32
    let injected: Bool
  }
  struct Lease: Equatable {
    let id: UInt64
    let buffer: String
    let slot: String
    let token: CompletedRenderToken?
  }
  private final class WeakEntry {
    weak var value: SharedRenderFailureDiagnostics?
    init(_ value: SharedRenderFailureDiagnostics) { self.value = value }
  }
  private static let registryLock = NSLock()
  private static var registry: [Int64: WeakEntry] = [:]
  private static let requestedMode = configuredMode(
    bundleMarked: Bundle.main.object(forInfoDictionaryKey: "MediaKitSharedRenderFailureDiagnostics") as? Bool == true,
    sharedRenderer: true,
    explicitMode: ProcessInfo.processInfo.environment["MEDIA_KIT_SHARED_RENDER_FAILURE_MODE"])

  static func configuredMode(bundleMarked: Bool, sharedRenderer: Bool, explicitMode: String?) -> Mode? {
    guard bundleMarked, sharedRenderer, let explicitMode else { return nil }
    return Mode(rawValue: explicitMode)
  }
  static func make(handle: Int64, sharedRenderer: Bool) -> SharedRenderFailureDiagnostics? {
    guard sharedRenderer, let mode = requestedMode else { return nil }
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "media-kit-shared-render-failure-\(ProcessInfo.processInfo.processIdentifier)-\(handle).jsonl")
    let value = SharedRenderFailureDiagnostics(mode: mode, fileURL: file)
    registryLock.lock(); registry[handle] = WeakEntry(value); registryLock.unlock()
    NativeFrameRegistry.observeOutputTransitions(handle: handle) { [weak value] in value?.transition($0) }
    return value
  }
  /// The autoclosure is not evaluated when diagnostics are not requested.
  /// If the actual shared renderer is off, no diagnostic registry lock is taken.
  static func registryLookupAllowed(mode: Mode?, sharedRenderer: @autoclosure () -> Bool) -> Bool {
    mode != nil && sharedRenderer()
  }
  static func forHandle(_ handle: Int64, sharedRenderer: @autoclosure () -> Bool) -> SharedRenderFailureDiagnostics? {
    guard registryLookupAllowed(mode: requestedMode, sharedRenderer: sharedRenderer()) else { return nil }
    registryLock.lock(); defer { registryLock.unlock() }
    return registry[handle]?.value
  }
  static func unregister(handle: Int64) {
    guard requestedMode != nil else { return }
    registryLock.lock(); registry.removeValue(forKey: handle); registryLock.unlock()
  }

  let mode: Mode
  let session = UUID().uuidString
  private let lock = NSLock()
  private let clock: () -> Double
  private let began: Double
  private let duration: Double
  private let capacity: Int
  private let fileURL: URL?
  private let outputQueue = DispatchQueue(label: "media_kit.shared_render_failure_diagnostics")
  private var timer: DispatchSourceTimer?
  private var rows: [[String: Any]] = []
  private var overflow = 0
  private var output = Data()
  private var summaries = 0
  private var attemptID: UInt64 = 0
  private var leaseID: UInt64 = 0
  private var epoch: Int64?
  private var stableSuccesses = 0
  private struct TokenKey: Hashable {
    let session: String
    let sequence: UInt64
    let epoch: Int64
    init(_ token: CompletedRenderToken) {
      session = token.session; sequence = token.sequence; epoch = token.epoch
    }
  }
  private struct Evidence {
    let token: CompletedRenderToken
    var produced = false
    var copied = false
    var nativeLeaseID: UInt64?
    var eligible = false
  }
  private struct LeaseEvidence {
    let lease: Lease
    var completion: Bool?
    var presentedTime: Double?
  }
  // Bind identity for the whole bounded trial, including after transfer from
  // pendingLeases. A later callback cannot substitute another slot/token.
  private var leaseEvidence: [UInt64: LeaseEvidence] = [:]
  private var evidence: [TokenKey: Evidence] = [:]
  private var transitions: [UInt64: Transition] = [:]
  private var processedTransitions: [UInt64: Transition] = [:]
  private var lastTransition: UInt64?
  private var candidate: Target?
  private var repeatedConsumerEvents = 0
  private var staleConsumerEvents = 0
  private var state = "waitingForMode"
  private var injectedAttempt: UInt64?
  private var failureAttempt: UInt64?
  private var nextNormalAttempt: UInt64?
  private var recoveredAttempt: UInt64?
  private var observationComplete = false
  private var result = "pending"
  private var terminalReason: String?
  private let maximumAttempts: UInt64 = 64
  private var publicationViolations = 0
  private var missingLeaseToken = 0
  private var pendingLeases: [String: Lease] = [:]

  init(mode: Mode, capacity: Int = 128, duration: Double = 180,
       fileURL: URL? = nil, automaticSampling: Bool = true,
       clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    precondition(capacity > 0 && duration > 0)
    self.mode = mode; self.capacity = capacity; self.duration = duration
    self.fileURL = fileURL; self.clock = clock; self.began = clock()
    if automaticSampling, fileURL != nil {
      let source = DispatchSource.makeTimerSource(queue: outputQueue)
      source.schedule(deadline: .now() + 1, repeating: 1)
      source.setEventHandler { [weak self] in self?.writeSummary() }
      timer = source; source.resume()
    }
  }
  deinit { timer?.cancel() }

  private func append(_ row: [String: Any]) {
    if rows.count == capacity { rows.removeFirst(); overflow += 1 }
    var row = row; row["time"] = clock(); rows.append(row)
    if overflow > 0 {
      state = "invalid"; result = "invalid"; terminalReason = "eventOverflow"
      observationComplete = false
    }
  }
  private func end(state nextState: String, result nextResult: String, reason: String) {
    guard terminalReason == nil else { return }
    append(["event": "terminal", "state": nextState, "result": nextResult, "reason": reason])
    guard terminalReason == nil else { return }
    state = nextState; result = nextResult; terminalReason = reason
    observationComplete = false
  }
  private func cancel(_ reason: String) {
    end(state: "cancelled", result: "incomplete", reason: reason)
  }
  func cancelBeforeRender(_ reason: String) {
    lock.lock(); defer { lock.unlock() }
    cancel(reason)
  }
  private func alive() -> Bool {
    guard terminalReason == nil else { return false }
    if clock() - began >= duration { cancel("expiredBeforeConsumerRecovery"); return false }
    return true
  }
  private func sameGeneration(_ a: Target, _ b: Target) -> Bool {
    a.epoch == b.epoch && a.floatEnabled == b.floatEnabled && a.currentHeadroom == b.currentHeadroom
  }
  private func clearEligibility() {
    evidence.removeAll(); stableSuccesses = 0
    for id in Array(leaseEvidence.keys) {
      // A failed completion stays failed for the immutable lease lifetime.
      if leaseEvidence[id]?.completion != false { leaseEvidence[id]?.completion = nil }
      leaseEvidence[id]?.presentedTime = nil
    }
  }
  /// Registry emits outside its mutex. Concurrent callbacks can arrive in a
  /// different order: no snapshot beyond the contiguous sequence may arm.
  func transition(_ transition: Transition) {
    lock.lock(); defer { lock.unlock() }
    guard alive() else { return }
    if let previous = processedTransitions[transition.sequence] ?? transitions[transition.sequence] {
      if previous != transition { end(state: "invalid", result: "invalid", reason: "conflictingTransition") }
      return
    }
    guard transitions.count + processedTransitions.count < capacity else {
      end(state: "invalid", result: "invalid", reason: "transitionCapacity"); return
    }
    transitions[transition.sequence] = transition
    while let next = transitions.removeValue(forKey: lastTransition.map { $0 + 1 } ?? 0) {
      guard next.new.transitionSequence == next.sequence,
            next.sequence != 0 || next.old == next.new,
            next.sequence == 0 || next.old.transitionSequence == next.sequence - 1,
            candidate.map({ sameGeneration($0, next.old) }) ?? (next.sequence == 0) else {
        end(state: "invalid", result: "invalid", reason: "inconsistentTransitionChain"); return
      }
      let changed = candidate.map { !sameGeneration($0, next.new) } ?? true
      if changed && epoch == nil { clearEligibility(); state = "waitingForConsumerEvidence" }
      candidate = next.new; lastTransition = next.sequence; processedTransitions[next.sequence] = next
      append(["event": "outputTransition", "sequence": next.sequence, "reason": next.reason,
        "old": Self.targetJSON(next.old), "new": Self.targetJSON(next.new), "armed": epoch != nil])
      if terminalReason != nil { return }
      if let epoch, next.new.epoch != epoch || next.new.floatEnabled != (mode == .rgba16f) {
        cancel("armedTargetChanged"); return
      }
    }
    if let epoch, transition.new.epoch != epoch || transition.new.floatEnabled != (mode == .rgba16f) {
      // A gap cannot be trusted as a stable boundary, but a known actual edge
      // already invalidates an armed run. Keep its reason explicitly pending.
      append(["event": "armedTransitionPendingSequence", "sequence": transition.sequence,
        "reason": transition.reason, "old": Self.targetJSON(transition.old), "new": Self.targetJSON(transition.new)])
      cancel("armedTargetChanged"); return
    }
    if !transitions.isEmpty && epoch == nil { clearEligibility() }
  }
  private func observe(_ target: Target) -> Bool {
    guard alive() else { return false }
    if let epoch, target.epoch != epoch || target.floatEnabled != (mode == .rgba16f) {
      cancel("armedTargetChanged"); return false
    }
    guard let candidate, let lastTransition else { return false }
    guard target.transitionSequence == lastTransition, transitions.isEmpty,
          sameGeneration(target, candidate) else {
      if epoch == nil { clearEligibility() }
      return false
    }
    guard target.floatEnabled == (mode == .rgba16f) else { return false }
    return true
  }

  /// Terminal/sequence gates precede all diagnostic GL reads. The render caller
  /// also matches this coherent snapshot to its actual selected target.
  func prepareAttachmentQuery(target: Target) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return observe(target) && attemptID < maximumAttempts
  }
  func begin(target: Target, slot: String, actualDepth: UInt32,
             poolBefore: [String: Any]) -> Attempt? {
    lock.lock(); defer { lock.unlock() }
    guard observe(target) else { return nil }
    guard actualDepth == (mode == .bgra8 ? 8 : 16) else {
      cancel("unexpectedActualAttachmentDepth"); return nil
    }
    guard attemptID < maximumAttempts else { return nil }
    attemptID += 1
    let inject = injectedAttempt == nil && state == "armed"
    if inject { injectedAttempt = attemptID; state = "injected" }
    if failureAttempt != nil && nextNormalAttempt == nil { nextNormalAttempt = attemptID }
    let attempt = Attempt(id: attemptID, epoch: target.epoch, mode: mode, slot: slot,
      actualDepth: actualDepth, requestedDepth: actualDepth + (inject ? 1 : 0), injected: inject)
    append(["event": "attempt", "attempt": attempt.id, "epoch": target.epoch, "mode": mode.rawValue,
      "slot": slot, "actualDepth": actualDepth, "requestedDepth": attempt.requestedDepth,
      "injected": inject, "poolBefore": poolBefore])
    guard terminalReason == nil else { return nil }
    return attempt
  }

  /// Raw status is the actual mpv return. Effective status includes the existing
  /// shared diagnostic/epoch gate. A failed attempt must remain unpublished.
  func finish(_ attempt: Attempt?, rawStatus: Int32, effectiveStatus: Int32,
              target: Target, produced: Bool, pushed: Bool,
              token: CompletedRenderToken?, poolAfter: [String: Any]) {
    guard let attempt else { return }
    lock.lock(); defer { lock.unlock() }
    guard alive() else { return }
    let targetChanged = target.epoch != attempt.epoch || target.floatEnabled != (attempt.mode == .rgba16f)
    let violatesPublication = (rawStatus < 0 || effectiveStatus < 0) && (produced || pushed || token != nil)
    if violatesPublication { publicationViolations += 1 }
    if attempt.injected && rawStatus < 0 { failureAttempt = attempt.id; state = "awaitingRecovery" }
    let successful = rawStatus >= 0 && effectiveStatus >= 0 && produced && pushed &&
      token?.failureAttemptID == attempt.id && token?.failureSlotID == attempt.slot && token?.epoch == attempt.epoch
    if failureAttempt != nil && !attempt.injected && successful && state == "awaitingRecovery" {
      recoveredAttempt = attempt.id; state = "recovered"
    }
    var row: [String: Any] = ["event": "result", "attempt": attempt.id, "rawMpvStatus": rawStatus,
      "effectiveStatus": effectiveStatus, "currentTarget": Self.targetJSON(target),
      "markProducedExecuted": produced, "pushExecuted": pushed,
      "token": Self.tokenJSON(token), "poolAfter": poolAfter]
    if attempt.id >= maximumAttempts { row["terminalReason"] = "attemptLimitWithoutConsumerRecovery" }
    append(row)
    guard terminalReason == nil else { return }
    if violatesPublication {
      end(state: "invalid", result: "invalid", reason: "publicationViolation")
    } else if attempt.injected && rawStatus >= 0 {
      end(state: "unexpectedAcceptance", result: "invalid", reason: "injectedContractAccepted")
    } else if targetChanged {
      if epoch != nil { cancel("armedTargetChangedDuringRender") }
      else { clearEligibility() }
    } else if successful, let token, observe(target) {
      updateEvidence(token, target: target, event: "producerConfirmed") { $0.produced = true }
    }
    if terminalReason == nil && attempt.id >= maximumAttempts {
      // The last result itself records the limit; avoid an extra event forcing
      // overflow when the default 128 rows contain exactly 64 attempt/results.
      state = "attemptLimit"; result = "incomplete"
      terminalReason = "attemptLimitWithoutConsumerRecovery"
    }
  }

  func flutterCopy(slot: String?, token: CompletedRenderToken?, target: Target) {
    lock.lock(); defer { lock.unlock() }
    guard observe(target), mode == .bgra8 else { return }
    guard let token, let slot, token.failureSlotID == slot else { return }
    updateEvidence(token, target: target, event: "flutterCopy") { $0.copied = true }
  }
  /// This is the immutable token captured while retaining the exact buffer.
  /// A recycled buffer's later token can never replace the captured lease token.
  func leased(buffer: String, slot: String, token: CompletedRenderToken?) {
    lock.lock(); defer { lock.unlock() }
    guard alive() else { return }
    guard let token, token.failureAttemptID == nil || token.failureSlotID == slot else {
      missingLeaseToken += 1
      end(state: "invalid", result: "invalid", reason: "missingLeaseToken"); return
    }
    if pendingLeases[buffer] != nil {
      end(state: "invalid", result: "invalid", reason: "untransferredLeaseCollision"); return
    }
    guard leaseEvidence.count < capacity else {
      end(state: "invalid", result: "invalid", reason: "leaseCapacity"); return
    }
    leaseID += 1
    let lease = Lease(id: leaseID, buffer: buffer, slot: slot, token: token)
    pendingLeases[buffer] = lease
    leaseEvidence[leaseID] = LeaseEvidence(lease: lease)
    append(["event": "nativeLease", "lease": leaseID, "buffer": buffer, "slot": slot, "token": Self.tokenJSON(token)])
  }
  func takeLease(buffer: String) -> Lease? {
    lock.lock(); defer { lock.unlock() }
    return pendingLeases.removeValue(forKey: buffer)
  }
  func native(_ event: String, lease: Lease?, succeeded: Bool? = nil,
              presentedTime: Double? = nil, target: Target) {
    lock.lock(); defer { lock.unlock() }
    guard observe(target), mode == .rgba16f else { return }
    guard let lease, let token = lease.token else {
      missingLeaseToken += 1
      end(state: "invalid", result: "invalid", reason: "missingLeaseSnapshot"); return
    }
    guard token.epoch == target.epoch else { staleConsumerEvents += 1; return }
    guard var record = leaseEvidence[lease.id], record.lease == lease else {
      end(state: "invalid", result: "invalid", reason: "conflictingLeaseIdentity"); return
    }
    // Normal frames outside the diagnostic contiguous-sequence/mode window
    // still carry their real retained token. They cannot establish eligibility.
    guard token.failureAttemptID != nil else { return }
    guard token.failureSlotID == lease.slot else {
      missingLeaseToken += 1
      end(state: "invalid", result: "invalid", reason: "leaseSlotMismatch"); return
    }
    var changed = false
    if event == "nativeCompletion", let succeeded {
      if let previous = record.completion, previous != succeeded {
        end(state: "invalid", result: "invalid", reason: "conflictingLeaseCompletion"); return
      }
      changed = record.completion == nil
      record.completion = succeeded
    } else if event == "nativePresented", let presentedTime, presentedTime.isFinite, presentedTime > 0 {
      if let previous = record.presentedTime, previous != presentedTime {
        end(state: "invalid", result: "invalid", reason: "conflictingLeasePresentation"); return
      }
      changed = record.presentedTime == nil
      record.presentedTime = presentedTime
    } else {
      // Enqueue, returned lease, invalid time and failed enqueue remain audit
      // facts; they never synthesize either half of a successful pair.
      append(["event": event, "lease": lease.id, "slot": lease.slot, "token": Self.tokenJSON(token),
        "succeeded": succeeded as Any? ?? NSNull(), "presentedTimeValid": false,
        "currentTarget": Self.targetJSON(target)])
      return
    }
    leaseEvidence[lease.id] = record
    if changed {
      append(["event": event, "lease": lease.id, "slot": lease.slot, "token": Self.tokenJSON(token),
        "succeeded": record.completion as Any? ?? NSNull(),
        "presentedTime": record.presentedTime as Any? ?? NSNull(), "currentTarget": Self.targetJSON(target)])
    } else { repeatedConsumerEvents += 1 }
    guard terminalReason == nil, record.completion == true, let presentedTime = record.presentedTime else { return }
    // Both callbacks belong to this same immutable lease. Token-level dedup
    // happens only after a complete successful lease pair exists.
    updateEvidence(token, target: target, event: "nativeLeasePaired",
      metadata: ["lease": lease.id, "succeeded": true, "presentedTime": presentedTime]) {
      if $0.nativeLeaseID == nil { $0.nativeLeaseID = lease.id }
    }
  }
  private func updateEvidence(_ token: CompletedRenderToken, target: Target, event: String,
                              metadata: [String: Any] = [:], update: (inout Evidence) -> Void) {
    guard token.epoch == target.epoch, token.failureAttemptID != nil, token.failureSlotID != nil else {
      staleConsumerEvents += 1; return
    }
    let key = TokenKey(token)
    if let existing = evidence[key], existing.token != token {
      end(state: "invalid", result: "invalid", reason: "conflictingTokenIdentity"); return
    }
    guard evidence[key] != nil || evidence.count < Int(maximumAttempts) else {
      end(state: "invalid", result: "invalid", reason: "tokenCapacity"); return
    }
    var item = evidence[key] ?? Evidence(token: token)
    let previous = item
    update(&item)
    if previous.produced == item.produced && previous.copied == item.copied &&
       previous.nativeLeaseID == item.nativeLeaseID {
      repeatedConsumerEvents += 1
    } else {
      var row = metadata
      row["event"] = event; row["token"] = Self.tokenJSON(token); row["currentTarget"] = Self.targetJSON(target)
      append(row)
    }
    evidence[key] = item
    guard terminalReason == nil else { return }
    let headroomValid = target.currentHeadroom.map { $0.isFinite && $0 >= 1 } ?? false
    let consumed = mode == .bgra8 ? item.copied : (item.nativeLeaseID != nil && target.surfaceActive)
    guard item.produced, consumed, headroomValid else { return }
    if epoch == nil && !item.eligible {
      item.eligible = true; evidence[key] = item; stableSuccesses += 1
      if stableSuccesses >= 3 {
        epoch = target.epoch; state = "armed"
        append(["event": "armed", "epoch": target.epoch, "mode": mode.rawValue,
          "distinctConsumedTokens": stableSuccesses, "transitionSequence": target.transitionSequence])
      }
    }
    guard state == "recovered", let recoveredAttempt, let consumedAttempt = token.failureAttemptID,
          consumedAttempt >= recoveredAttempt, overflow == 0, publicationViolations == 0,
          missingLeaseToken == 0 else { return }
    append(["event": "observationComplete", "consumedRecoveryAttempt": consumedAttempt,
      "nativeLease": item.nativeLeaseID as Any? ?? NSNull(), "currentTarget": Self.targetJSON(target),
      "note": "render/consumer evidence only; physical output acceptance remains separate"])
    guard terminalReason == nil else { return }
    observationComplete = true; result = "observedRecovery"; terminalReason = "consumerRecoveryObserved"
  }
  private static func targetJSON(_ target: Target) -> [String: Any] {
    ["epoch": target.epoch, "mode": target.floatEnabled ? "RGBA16F" : "BGRA8",
      "headroom": target.currentHeadroom as Any? ?? NSNull(), "surfaceActive": target.surfaceActive,
      "transitionSequence": target.transitionSequence]
  }
  private static func tokenJSON(_ token: CompletedRenderToken?) -> Any {
    guard let token else { return NSNull() }
    return ["session": token.session, "sequence": token.sequence, "epoch": token.epoch,
      "attempt": token.failureAttemptID as Any? ?? NSNull(),
      "slot": token.failureSlotID as Any? ?? NSNull()] as [String: Any]
  }
  func snapshot() -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    _ = alive()
    return ["kind": "shared-render-one-shot-failure", "session": session,
      "pid": ProcessInfo.processInfo.processIdentifier, "mode": mode.rawValue,
      "state": state, "result": result, "terminalReason": terminalReason as Any? ?? NSNull(),
      "maximumAttempts": maximumAttempts, "attempts": attemptID, "epoch": epoch as Any? ?? NSNull(), "stableSuccesses": stableSuccesses,
      "injectedAttempt": injectedAttempt as Any? ?? NSNull(),
      "failureAttempt": failureAttempt as Any? ?? NSNull(),
      "nextNormalAttempt": nextNormalAttempt as Any? ?? NSNull(),
      "recoveredAttempt": recoveredAttempt as Any? ?? NSNull(),
      "lastTransitionSequence": lastTransition as Any? ?? NSNull(), "pendingTransitions": transitions.count,
      "repeatedConsumerEvents": repeatedConsumerEvents, "staleConsumerEvents": staleConsumerEvents,
      "candidateTarget": candidate.map(Self.targetJSON) as Any? ?? NSNull(),
      "leaseEvidenceCount": leaseEvidence.count,
      "capacity": capacity, "overflow": overflow, "droppedEvents": overflow,
      "publicationViolations": publicationViolations, "missingLeaseToken": missingLeaseToken,
      "observationComplete": observationComplete,
      "recordingExpired": clock() - began >= duration,
      "events": rows, "elapsed": max(0, clock() - began)]
  }
  func writeSummary() {
    guard let fileURL, summaries < 181 else { timer?.cancel(); return }
    let row = snapshot()
    do {
      var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      data.append(0x0a); output.append(data); summaries += 1
      try output.write(to: fileURL, options: [.atomic])
    } catch { /* IO failure never changes the render path. */ }
    if row["recordingExpired"] as? Bool == true { timer?.cancel() }
  }
}
