import Foundation
import Darwin

@main
struct SharedRenderFailureDiagnosticsTests {
  typealias Trace = SharedRenderFailureDiagnostics
  typealias Target = Trace.Target
  final class Clock { var now: Double = 0 }
  final class Slot { let id: String; var token: CompletedRenderToken?; init(_ id: String) { self.id = id } }
  static func target(_ epoch: Int64 = 0, _ mode: Trace.Mode = .bgra8,
                     sequence: UInt64 = 0, headroom: Double? = 2, active: Bool = true) -> Target {
    Target(epoch: epoch, floatEnabled: mode == .rgba16f, currentHeadroom: headroom,
      surfaceActive: active, transitionSequence: sequence)
  }
  static func token(_ a: Trace.Attempt, session: String = "fixture") -> CompletedRenderToken {
    CompletedRenderToken(session: session, sequence: a.id, epoch: a.epoch,
      renderStart: 0, renderEnd: 0, fenceEnd: 0, requestID: nil,
      failureAttemptID: a.id, failureSlotID: a.slot)
  }
  static func initial(_ trace: Trace, _ t: Target) {
    trace.transition(Trace.Transition(sequence: 0, reason: "registered-prior-reason-unknown", old: t, new: t))
  }
  static func move(_ trace: Trace, _ old: Target, _ new: Target) {
    trace.transition(Trace.Transition(sequence: new.transitionSequence, reason: "fixture-generation-change", old: old, new: new))
  }
  @discardableResult
  static func produce(_ trace: Trace, _ t: Target, consume: Bool = false,
                      consumerFirst: Bool = false) -> (Trace.Attempt, CompletedRenderToken) {
    let a = trace.begin(target: t, slot: "slot", actualDepth: t.floatEnabled ? 16 : 8, poolBefore: [:])!
    let tok = token(a)
    if consume && consumerFirst { consumption(trace, tok, t) }
    trace.finish(a, rawStatus: 0, effectiveStatus: 0, target: t,
      produced: true, pushed: true, token: tok, poolAfter: [:])
    if consume && !consumerFirst { consumption(trace, tok, t) }
    return (a, tok)
  }
  static func consumption(_ trace: Trace, _ tok: CompletedRenderToken, _ t: Target, presentedFirst: Bool = false) {
    if !t.floatEnabled { trace.flutterCopy(slot: tok.failureSlotID, token: tok, target: t); return }
    trace.leased(buffer: "buffer", slot: tok.failureSlotID!, token: tok)
    guard let lease = trace.takeLease(buffer: "buffer") else { return }
    if presentedFirst { trace.native("nativePresented", lease: lease, presentedTime: 1, target: t) }
    trace.native("nativeCompletion", lease: lease, succeeded: true, target: t)
    if !presentedFirst { trace.native("nativePresented", lease: lease, presentedTime: 1, target: t) }
  }
  static func assertResult(_ trace: Trace, _ result: String, _ reason: String? = nil) {
    let s = trace.snapshot(); precondition(s["result"] as! String == result, "\(s)")
    if let reason { precondition(s["terminalReason"] as? String == reason, "\(s)") }
  }
  static func main() throws {
    setbuf(stdout, nil)
    for mode in [Trace.Mode.bgra8, .rgba16f] {
      precondition(Trace.configuredMode(bundleMarked: true, sharedRenderer: true, explicitMode: mode.rawValue) == mode)
      precondition(Trace.configuredMode(bundleMarked: false, sharedRenderer: true, explicitMode: mode.rawValue) == nil)
      precondition(Trace.configuredMode(bundleMarked: true, sharedRenderer: false, explicitMode: mode.rawValue) == nil)
    }
    for name in [nil, "", "1", "bgra8", "RGBA16", "BGRA8 "] {
      precondition(Trace.configuredMode(bundleMarked: true, sharedRenderer: true, explicitMode: name) == nil)
    }
    var gateReads = 0
    func actual(_ value: Bool) -> Bool { gateReads += 1; return value }
    precondition(!Trace.registryLookupAllowed(mode: nil, sharedRenderer: actual(true)) && gateReads == 0)
    precondition(!Trace.registryLookupAllowed(mode: .bgra8, sharedRenderer: actual(false)) && gateReads == 1)
    precondition(Trace.registryLookupAllowed(mode: .bgra8, sharedRenderer: actual(true)) && gateReads == 2)
    print("PASS default-off lazy gates; actual create failure bypasses diagnostic lookup")

    for mode in [Trace.Mode.bgra8, .rgba16f] {
      let trace = Trace(mode: mode, automaticSampling: false)
      let t = target(0, mode); initial(trace, t) // epoch zero is a legitimate stable generation.
      let pool = SwappableObjectManager(objects: [Slot("a"), Slot("b"), Slot("c")])
      func run(_ raw: Int32) -> (Trace.Attempt, CompletedRenderToken?) {
        let before = pool.auditSnapshot { $0.id }; let slot = pool.nextAvailable()!
        let a = trace.begin(target: t, slot: slot.id, actualDepth: mode == .bgra8 ? 8 : 16, poolBefore: before)!
        let tok = raw >= 0 ? token(a) : nil; slot.token = tok
        if raw >= 0 { pool.pushAsReady(slot) } else { pool.returnUnpublished(slot) }
        trace.finish(a, rawStatus: raw, effectiveStatus: raw, target: t,
          produced: raw >= 0, pushed: raw >= 0, token: tok, poolAfter: pool.auditSnapshot { $0.id })
        return (a, tok)
      }
      for n in 0..<3 {
        let (a, tok) = run(0); precondition(!a.injected)
        consumption(trace, tok!, t, presentedFirst: n % 2 == 1)
        consumption(trace, tok!, t) // duplicates do not count a new distinct frame.
      }
      precondition(trace.snapshot()["stableSuccesses"] as! Int == 3)
      let retained = pool.withCurrentSnapshot { ($0!.id, $0!.token!) }
      let before = pool.auditSnapshot { $0.id }
      let (failed, noToken) = run(-4) // CPU input only: no actual mpv or GL execution.
      precondition(failed.injected && failed.requestedDepth == failed.actualDepth + 1 && noToken == nil)
      let after = pool.auditSnapshot { $0.id }
      precondition(before["current"] as! String == after["current"] as! String)
      precondition((after["available"] as! [String]).contains(failed.slot))
      precondition(pool.withCurrentSnapshot { $0!.token! } == retained.1)
      consumption(trace, retained.1, t); assertResult(trace, "pending")
      let (normal, recovered) = run(0)
      precondition(!normal.injected && normal.requestedDepth == normal.actualDepth)
      assertResult(trace, "pending")
      consumption(trace, recovered!, t, presentedFirst: true)
      assertResult(trace, "observedRecovery", "consumerRecoveryObserved")
      let s = trace.snapshot(); precondition(s["observationComplete"] as! Bool)
      precondition(s["nextNormalAttempt"] as! UInt64 == normal.id)
      let failedRow = (s["events"] as! [[String: Any]]).first { $0["event"] as? String == "result" && $0["attempt"] as? UInt64 == failed.id }!
      precondition(failedRow["rawMpvStatus"] as! Int32 == -4 && failedRow["token"] is NSNull)
      precondition(failedRow["markProducedExecuted"] as! Bool == false && failedRow["pushExecuted"] as! Bool == false)
      let count = (s["events"] as! [[String: Any]]).count
      move(trace, t, target(1, mode, sequence: 1)); trace.cancelBeforeRender("late")
      for _ in 0..<1000 { precondition(!trace.prepareAttachmentQuery(target: t)); consumption(trace, recovered!, t) }
      assertResult(trace, "observedRecovery"); precondition((trace.snapshot()["events"] as! [[String: Any]]).count == count)
      _ = try JSONSerialization.data(withJSONObject: s)
    }
    print("PASS both modes: real-consumer arming, fixture failure slot return, old copy, normal publish and paired recovery; immutable terminal")

    let producerOnly = Trace(mode: .bgra8, automaticSampling: false); let zero = target(); initial(producerOnly, zero)
    for _ in 0..<5 { precondition(!produce(producerOnly, zero).0.injected) }
    precondition(producerOnly.snapshot()["stableSuccesses"] as! Int == 0)
    let noHeadroom = Trace(mode: .bgra8, automaticSampling: false); let unknown = target(headroom: nil); initial(noHeadroom, unknown)
    for _ in 0..<3 { produce(noHeadroom, unknown, consume: true) }
    precondition(noHeadroom.snapshot()["stableSuccesses"] as! Int == 0)
    let known = target(1, sequence: 1); move(noHeadroom, unknown, known)
    for _ in 0..<3 { produce(noHeadroom, known, consume: true, consumerFirst: true) }
    precondition(noHeadroom.snapshot()["state"] as! String == "armed")
    print("PASS producer-only and unknown headroom cannot arm; consumer-before-finish merges exact token")

    let changes = Trace(mode: .bgra8, automaticSampling: false); initial(changes, zero)
    let old = produce(changes, zero, consume: true).1
    produce(changes, zero, consume: true)
    let one = target(1, sequence: 1); move(changes, zero, one)
    precondition(changes.snapshot()["stableSuccesses"] as! Int == 0)
    consumption(changes, old, one); precondition(changes.snapshot()["stableSuccesses"] as! Int == 0)
    for _ in 0..<3 { produce(changes, one, consume: true) }
    precondition(changes.snapshot()["attempts"] as! UInt64 == 5)
    move(changes, one, target(2, sequence: 2)); assertResult(changes, "incomplete", "armedTargetChanged")
    precondition(!changes.prepareAttachmentQuery(target: one))
    print("PASS prearm transition clears old tokens without resetting attempts; armed transition permanently cancels")

    let ordered = Trace(mode: .bgra8, automaticSampling: false)
    let two = target(2, sequence: 2)
    let tr1 = Trace.Transition(sequence: 1, reason: "one", old: zero, new: one)
    let tr2 = Trace.Transition(sequence: 2, reason: "two", old: one, new: two)
    ordered.transition(tr2); ordered.transition(tr2)
    initial(ordered, zero)
    precondition(!ordered.prepareAttachmentQuery(target: two))
    ordered.transition(tr1)
    for _ in 0..<3 { produce(ordered, two, consume: true) }
    let rows = ordered.snapshot()["events"] as! [[String: Any]]
    precondition(rows.filter { $0["event"] as? String == "outputTransition" }.map { $0["sequence"] as! UInt64 } == [0, 1, 2])
    let conflict = Trace(mode: .bgra8, automaticSampling: false); initial(conflict, zero)
    conflict.transition(Trace.Transition(sequence: 0, reason: "different", old: zero, new: zero))
    assertResult(conflict, "invalid", "conflictingTransition")
    print("PASS out-of-order/baseline-late transitions merge contiguously; gap blocks arming, duplicates dedup, conflicts invalid")

    for presentedFirst in [false, true] {
      let trace = Trace(mode: .rgba16f, automaticSampling: false); let t = target(4, .rgba16f); initial(trace, t)
      for _ in 0..<3 {
        let tok = produce(trace, t).1
        trace.leased(buffer: "same-recycled-buffer", slot: "slot", token: tok)
        let lease = trace.takeLease(buffer: "same-recycled-buffer")!
        let later = CompletedRenderToken(session: "later", sequence: 1, epoch: 4, renderStart: 0, renderEnd: 0, fenceEnd: 0, requestID: nil, failureAttemptID: 1, failureSlotID: "later-slot")
        trace.leased(buffer: "same-recycled-buffer", slot: "later-slot", token: later)
        _ = trace.takeLease(buffer: "same-recycled-buffer")
        if presentedFirst { trace.native("nativePresented", lease: lease, presentedTime: 2, target: t) }
        else { trace.native("nativeCompletion", lease: lease, succeeded: true, target: t) }
        precondition(trace.snapshot()["state"] as! String != "armed")
        trace.native("nativePresented", lease: lease, presentedTime: .nan, target: t)
        if presentedFirst { trace.native("nativeCompletion", lease: lease, succeeded: true, target: t) }
        else { trace.native("nativePresented", lease: lease, presentedTime: 2, target: t) }
        trace.native("nativeCompletion", lease: lease, succeeded: true, target: t)
        trace.native("nativePresented", lease: lease, presentedTime: 2, target: t)
        precondition(lease.token == tok)
      }
      precondition(trace.snapshot()["stableSuccesses"] as! Int == 3)
    }
    func acquire(_ trace: Trace, _ tok: CompletedRenderToken, buffer: String) -> Trace.Lease {
      trace.leased(buffer: buffer, slot: tok.failureSlotID!, token: tok)
      return trace.takeLease(buffer: buffer)!
    }
    for presentedFirst in [false, true] {
      for testingRecovery in [false, true] {
        let trace = Trace(mode: .rgba16f, automaticSampling: false)
        let t = target(0, .rgba16f); initial(trace, t)
        for _ in 0..<(testingRecovery ? 3 : 2) { produce(trace, t, consume: true) }
        if testingRecovery {
          let injected = trace.begin(target: t, slot: "slot", actualDepth: 16, poolBefore: [:])!
          precondition(injected.injected)
          trace.finish(injected, rawStatus: -4, effectiveStatus: -4, target: t,
            produced: false, pushed: false, token: nil, poolAfter: [:])
        }
        let tok = produce(trace, t).1
        let a = acquire(trace, tok, buffer: "recycled")
        let b = acquire(trace, tok, buffer: "recycled")
        precondition(a.id != b.id && a.token == b.token && a.slot == b.slot)
        if presentedFirst { trace.native("nativePresented", lease: b, presentedTime: 1, target: t) }
        trace.native("nativeCompletion", lease: a, succeeded: true, target: t)
        trace.native("nativeCompletion", lease: a, succeeded: true, target: t) // duplicate
        if !presentedFirst { trace.native("nativePresented", lease: b, presentedTime: 1, target: t) }
        // This callback arrives after B presentation; it cannot borrow A success.
        trace.native("nativeCompletion", lease: b, succeeded: false, target: t)
        trace.native("nativePresented", lease: b, presentedTime: 1, target: t) // duplicate
        assertResult(trace, "pending")
        precondition(trace.snapshot()["stableSuccesses"] as! Int == (testingRecovery ? 3 : 2))
        precondition(trace.snapshot()["observationComplete"] as! Bool == false)
        if !testingRecovery { precondition(trace.snapshot()["state"] as! String != "armed") }
        // A third lease supplies a genuine pair for the same distinct token.
        let c = acquire(trace, tok, buffer: "recycled")
        if presentedFirst { trace.native("nativePresented", lease: c, presentedTime: 2, target: t) }
        trace.native("nativeCompletion", lease: c, succeeded: true, target: t)
        if !presentedFirst { trace.native("nativePresented", lease: c, presentedTime: 2, target: t) }
        if testingRecovery {
          assertResult(trace, "observedRecovery")
          let completed = (trace.snapshot()["events"] as! [[String: Any]]).first { $0["event"] as? String == "observationComplete" }!
          precondition(completed["nativeLease"] as! UInt64 == c.id)
        } else {
          precondition(trace.snapshot()["state"] as! String == "armed")
          precondition(trace.snapshot()["stableSuccesses"] as! Int == 3)
          trace.native("nativePresented", lease: a, presentedTime: 2, target: t)
          precondition(trace.snapshot()["stableSuccesses"] as! Int == 3) // same token, another valid lease.
        }
      }
    }
    for failureFirst in [false, true] {
      let trace = Trace(mode: .rgba16f, automaticSampling: false)
      let t = target(0, .rgba16f); initial(trace, t)
      let tok = produce(trace, t).1; let lease = acquire(trace, tok, buffer: "b")
      if !failureFirst { trace.native("nativePresented", lease: lease, presentedTime: 1, target: t) }
      trace.native("nativeCompletion", lease: lease, succeeded: false, target: t)
      if failureFirst { trace.native("nativePresented", lease: lease, presentedTime: 1, target: t) }
      assertResult(trace, "pending"); precondition(trace.snapshot()["stableSuccesses"] as! Int == 0)
      trace.native("nativeCompletion", lease: lease, succeeded: true, target: t)
      assertResult(trace, "invalid", "conflictingLeaseCompletion")
    }
    for conflictingSlot in [false, true] {
      let trace = Trace(mode: .rgba16f, automaticSampling: false)
      let t = target(0, .rgba16f); initial(trace, t)
      let a = produce(trace, t).0; let original = token(a)
      let lease = acquire(trace, original, buffer: "b")
      let forged = Trace.Lease(id: lease.id, buffer: lease.buffer,
        slot: conflictingSlot ? "other-slot" : lease.slot,
        token: conflictingSlot ? original : token(a, session: "other-session"))
      trace.native("nativeCompletion", lease: forged, succeeded: true, target: t)
      assertResult(trace, "invalid", "conflictingLeaseIdentity")
    }
    let boundedLeases = Trace(mode: .rgba16f, capacity: 4, automaticSampling: false)
    let ordinary = CompletedRenderToken(session: "ordinary", sequence: 1, epoch: 0,
      renderStart: 0, renderEnd: 0, fenceEnd: 0, requestID: nil)
    for n in 0..<8 {
      boundedLeases.leased(buffer: "b", slot: "slot", token: ordinary)
      _ = boundedLeases.takeLease(buffer: "b")
      precondition((boundedLeases.snapshot()["leaseEvidenceCount"] as! Int) <= 4)
      if n >= 4 { assertResult(boundedLeases, "invalid") }
    }
    print("PASS same-token cross-lease callbacks cannot arm/recover; same-lease pairs in both orders, failed completion/identity conflicts and bounded lease audit")
    let untagged = Trace(mode: .rgba16f, automaticSampling: false)
    let normalOutsideWindow = CompletedRenderToken(session: "ordinary", sequence: 1, epoch: 0,
      renderStart: 0, renderEnd: 0, fenceEnd: 0, requestID: nil)
    untagged.leased(buffer: "ordinary", slot: "actual-slot", token: normalOutsideWindow)
    let ordinaryLease = untagged.takeLease(buffer: "ordinary")!
    let ordinaryTarget = target(0, .rgba16f)
    initial(untagged, ordinaryTarget)
    untagged.native("nativeCompletion", lease: ordinaryLease, succeeded: true, target: ordinaryTarget)
    untagged.native("nativePresented", lease: ordinaryLease, presentedTime: 1, target: ordinaryTarget)
    assertResult(untagged, "pending")
    precondition(untagged.snapshot()["stableSuccesses"] as! Int == 0 && ordinaryLease.token == normalOutsideWindow)
    let inactive = Trace(mode: .rgba16f, automaticSampling: false); let off = target(4, .rgba16f, active: false); initial(inactive, off)
    for _ in 0..<3 { produce(inactive, off, consume: true) }
    precondition(inactive.snapshot()["stableSuccesses"] as! Int == 0)
    let pairOld = Trace(mode: .rgba16f, automaticSampling: false); let f0 = target(0, .rgba16f); initial(pairOld, f0)
    let tok = produce(pairOld, f0).1; pairOld.leased(buffer: "b", slot: "slot", token: tok)
    let lease = pairOld.takeLease(buffer: "b")!
    pairOld.native("nativeCompletion", lease: lease, succeeded: true, target: f0)
    let f1 = target(1, .rgba16f, sequence: 1); move(pairOld, f0, f1)
    pairOld.native("nativePresented", lease: lease, presentedTime: 1, target: f1)
    precondition(pairOld.snapshot()["stableSuccesses"] as! Int == 0)
    print("PASS float requires same-token completion/presentation, valid time, current active surface; cross-epoch pair rejected")

    for mode in [Trace.Mode.bgra8, .rgba16f] {
      let trace = Trace(mode: mode, automaticSampling: false); let t = target(0, mode); initial(trace, t)
      for _ in 0..<3 { produce(trace, t, consume: true) }
      let a = trace.begin(target: t, slot: "slot", actualDepth: mode == .bgra8 ? 8 : 16, poolBefore: [:])!
      trace.finish(a, rawStatus: -4, effectiveStatus: -4, target: t, produced: false, pushed: false, token: nil, poolAfter: [:])
      let recovered = produce(trace, t).1
      // Current target is E+1 even though ordered observer has not arrived yet.
      consumption(trace, recovered, target(1, mode, sequence: 1))
      assertResult(trace, "incomplete", "armedTargetChanged")
    }
    let accepted = Trace(mode: .bgra8, automaticSampling: false); initial(accepted, zero)
    for _ in 0..<3 { produce(accepted, zero, consume: true) }; produce(accepted, zero)
    assertResult(accepted, "invalid", "injectedContractAccepted")
    let violation = Trace(mode: .bgra8, automaticSampling: false); initial(violation, zero)
    let a = violation.begin(target: zero, slot: "slot", actualDepth: 8, poolBefore: [:])!
    violation.finish(a, rawStatus: -4, effectiveStatus: -4, target: zero, produced: true, pushed: true, token: token(a), poolAfter: [:])
    for _ in 0..<3 { consumption(violation, token(a), zero) }; assertResult(violation, "invalid", "publicationViolation")
    let missing = Trace(mode: .rgba16f, automaticSampling: false); let f = target(0, .rgba16f); initial(missing, f)
    missing.native("nativeCompletion", lease: nil, succeeded: true, target: f)
    assertResult(missing, "invalid", "missingLeaseSnapshot")
    let overflow = Trace(mode: .bgra8, capacity: 4, automaticSampling: false); initial(overflow, zero)
    produce(overflow, zero, consume: true); assertResult(overflow, "invalid", "eventOverflow")
    overflow.cancelBeforeRender("late"); assertResult(overflow, "invalid", "eventOverflow")
    let beginOverflow = Trace(mode: .bgra8, capacity: 1, automaticSampling: false)
    initial(beginOverflow, zero)
    precondition(beginOverflow.begin(target: zero, slot: "slot", actualDepth: 8, poolBefore: [:]) == nil)
    assertResult(beginOverflow, "invalid", "eventOverflow")
    let nilToken = Trace(mode: .rgba16f, automaticSampling: false)
    nilToken.leased(buffer: "b", slot: "slot", token: nil)
    assertResult(nilToken, "invalid", "missingLeaseToken")
    let depth = Trace(mode: .bgra8, automaticSampling: false); initial(depth, zero)
    precondition(depth.begin(target: zero, slot: "slot", actualDepth: 16, poolBefore: [:]) == nil)
    assertResult(depth, "incomplete", "unexpectedActualAttachmentDepth")
    let query = Trace(mode: .bgra8, automaticSampling: false); initial(query, zero)
    query.cancelBeforeRender("attachmentDepthQueryFailed")
    precondition(!query.prepareAttachmentQuery(target: zero))
    assertResult(query, "incomplete", "attachmentDepthQueryFailed")
    print("PASS old-E recovery callback, accepted mismatch, publication violation/missing lease/overflow followed by consumption cannot pass")

    let clock = Clock(); let expired = Trace(mode: .bgra8, duration: 10, automaticSampling: false, clock: { clock.now })
    initial(expired, zero); produce(expired, zero, consume: true)
    clock.now = 9; move(expired, zero, one); produce(expired, one, consume: true)
    clock.now = 10; precondition(!expired.prepareAttachmentQuery(target: one))
    assertResult(expired, "incomplete", "expiredBeforeConsumerRecovery")
    let capped = Trace(mode: .bgra8, capacity: 1024, automaticSampling: false); initial(capped, zero)
    var previous = zero
    for i in 0..<64 {
      let t = target(Int64(i), sequence: UInt64(i))
      if i > 0 { move(capped, previous, t) }
      produce(capped, t); previous = t
    }
    assertResult(capped, "incomplete", "attemptLimitWithoutConsumerRecovery")
    precondition(!capped.prepareAttachmentQuery(target: previous))
    move(capped, previous, target(65, sequence: 64)); capped.cancelBeforeRender("lateGLfailure")
    assertResult(capped, "incomplete", "attemptLimitWithoutConsumerRecovery")
    print("PASS prearm changes do not renew total deadline or 64-attempt budget; terminal suppresses GL queries")

    let handle: Int64 = 910034
    NativeFrameRegistry.unregister(handle: handle)
    NativeFrameRegistry.register(handle: handle) { nil }
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: true)
    precondition(NativeFrameRegistry.diagnosticOutputSnapshot(handle: handle).transitionSequence == 0)
    var transitions: [Trace.Transition] = []
    NativeFrameRegistry.observeOutputTransitions(handle: handle) { t in
      _ = NativeFrameRegistry.diagnosticOutputSnapshot(handle: handle) // proves registry mutex already released.
      transitions.append(t)
    }
    NativeFrameRegistry.publishDisplayHeadroom(handle: handle, value: 2)
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: false)
    _ = NativeFrameRegistry.advanceOutputEpoch(handle: handle, diagnosticReason: "native-output-reset")
    precondition(transitions.map(\.sequence) == [0, 1, 2, 3])
    precondition(transitions.map(\.reason) == ["registered-prior-reason-unknown", "display-headroom-change", "float-output-mode-change", "native-output-reset"])
    for i in 1..<transitions.count {
      precondition(transitions[i].new.epoch == transitions[i].old.epoch + 1)
      precondition(transitions[i].old.transitionSequence == UInt64(i - 1))
    }
    NativeFrameRegistry.unregister(handle: handle)
    _ = NativeFrameRegistry.advanceOutputEpoch(handle: handle)
    precondition(NativeFrameRegistry.diagnosticOutputSnapshot(handle: handle).transitionSequence == 0)
    NativeFrameRegistry.unregister(handle: handle)
    print("PASS registry three mutation sources capture coherent epochs/reasons/sequence outside-lock observer; unobserved transitions allocate no sequence")
    print("CPU fixture only: no GL/mpv, App, GPU or physical output acceptance")
  }
}
