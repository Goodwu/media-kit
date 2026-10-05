import Foundation
import CoreVideo

@main
struct CompletedRenderDiagnosticsTests {
  final class Slot {
    let id: Int
    var token: CompletedRenderToken?
    init(_ id: Int) { self.id = id }
  }
  static func main() throws {
    var now: Double = 0
    let trace = CompletedRenderDiagnostics(active: true, session: "test", capacity: 3,
      duration: 10, clock: { now }, automaticSampling: false)
    func render(_ epoch: Int64 = 1) -> CompletedRenderToken {
      trace.completeRender(epoch: epoch, start: now, end: now + 0.001,
        fenceEnd: now + 0.002, succeeded: true)!
    }
    let pool = SwappableObjectManager(objects: [Slot(1), Slot(2)])
    let firstSlot = pool.nextAvailable()!
    firstSlot.token = render()
    pool.pushAsReady(firstSlot)
    let first = pool.withCurrentSnapshot { current in (current!.id, current!.token!) }
    now = 0.01
    trace.consume(token: first.1, hasCurrent: true, hasBuffer: true)
    trace.consume(token: first.1, hasCurrent: true, hasBuffer: true)
    let secondSlot = pool.nextAvailable()!
    secondSlot.token = render(2)
    pool.pushAsReady(secondSlot)
    now = 0.02
    let reused = pool.nextAvailable()!
    precondition(reused === firstSlot)
    reused.token = render(3)
    pool.pushAsReady(reused)
    let newest = pool.withCurrentSnapshot { current in (current!.id, current!.token!) }
    precondition(first.0 == newest.0 && first.1.sequence == 1 && newest.1.sequence == 3)
    trace.consume(token: newest.1, hasCurrent: true, hasBuffer: true)
    // An immutable snapshot remains its original seq despite slot reuse.
    trace.consume(token: first.1, hasCurrent: true, hasBuffer: true)
    var snapshot = trace.snapshot()
    precondition(snapshot["firstCopies"] as! Int == 2)
    precondition(snapshot["repeatedCopies"] as! Int == 2)
    trace.consume(token: nil, hasCurrent: false, hasBuffer: false)
    trace.consume(token: nil, hasCurrent: true, hasBuffer: true)
    trace.noteNoWritableSlot()
    now = 0.03
    _ = render()
    trace.consume(token: first.1, hasCurrent: true, hasBuffer: true)
    snapshot = trace.snapshot()
    precondition(snapshot["recordOverflow"] as! Int == 1)
    precondition(snapshot["missingRecord"] as! Int == 1)
    precondition(snapshot["missingToken"] as! Int == 1)
    precondition(snapshot["noCurrent"] as! Int == 1 && snapshot["noBuffer"] as! Int == 1)
    precondition(snapshot["noWritableSlot"] as! Int == 1)
    precondition((snapshot["recentTokens"] as! [[String: Any]]).count == 3)
    precondition((snapshot["uniqueCopyIntervalMs"] as! [String: Any])["count"] as! Int == 1)
    precondition(trace.completeRender(epoch: 4, start: now, end: now + 0.001,
      fenceEnd: now + 0.002, succeeded: false) == nil)
    precondition(trace.snapshot()["renderFailures"] as! Int == 1)
    let rowsWithTimes = trace.snapshot()["recentTokens"] as! [[String: Any]]
    let copiedRow = rowsWithTimes.first { ($0["sequence"] as! UInt64) == newest.1.sequence }!
    precondition(copiedRow["firstCopyTime"] as! Double == 0.02)
    now = 10
    precondition(trace.beginRender() == nil)
    trace.consume(token: newest.1, hasCurrent: true, hasBuffer: true)
    precondition(trace.snapshot()["copies"] as! Int == snapshot["copies"] as! Int)
    precondition(trace.snapshot()["stopped"] as! Bool)
    print("PASS same-lock snapshot survives slot reuse; duplicate/missing/no-slot counters; ring capacity and elapsed stop")

    now = 0
    let phases = CompletedRenderDiagnostics(active: true, session: "phase", capacity: 3,
      duration: 10, clock: { now }, automaticSampling: false)
    let request = phases.makeRequest(source: .mpv)!
    now = 0.001; phases.notePhase(request, .mainArrival)
    now = 0.002; phases.notePhase(request, .enqueue)
    now = 0.003; phases.notePhase(request, .workerStart)
    now = 0.004; phases.notePhase(request, .resizeBegin)
    now = 0.005; phases.notePhase(request, .resizeEnd)
    let token = phases.completeRender(epoch: 9, start: 0.006, end: 0.007,
      fenceEnd: 0.008, succeeded: true, request: request)!
    precondition(token.requestID == request.identifier)
    now = 0.009; phases.notePhase(request, .published, token: token)
    now = 0.010; phases.notePhase(request, .notifyWait, token: token)
    now = 0.011; phases.notePhase(request, .notifyMain, token: token)
    // An already pending raster copy can observe the published token before
    // this exact request's notification returns. Preserve signed ordering.
    now = 0.012; phases.consume(token: token, hasCurrent: true, hasBuffer: true)
    now = 0.013; phases.notePhase(request, .notifyEnd, token: token)
    now = 0.014; phases.notePhase(request, .workerEnd, token: token)
    var phaseSnapshot = phases.snapshot()
    let timing = phaseSnapshot["phaseMs"] as! [String: [String: Any]]
    precondition(abs(timing["callbackToMainMs"]!["max"] as! Double - 1) < 0.00001)
    precondition(abs(timing["enqueueToWorkerMs"]!["max"] as! Double - 1) < 0.00001)
    precondition((timing["signedNotifyEndToFirstCopyMs"]!["max"] as! Double) < 0)
    let requestsBefore = phaseSnapshot["recentRequests"] as! [[String: Any]]
    precondition(requestsBefore[0]["tokenSequence"] as! UInt64 == token.sequence)
    let skipped = phases.makeRequest(source: .videoOutput)!
    phases.notePhase(skipped, .workerStart)
    phases.notePhase(skipped, .workerEnd, skip: .zeroSize)
    // Neither the last global sequence nor recycled token is rebound to a
    // request that did not actually render.
    phases.notePhase(skipped, .notifyEnd, token: token)
    phaseSnapshot = phases.snapshot()
    let skippedRow = (phaseSnapshot["recentRequests"] as! [[String: Any]])[1]
    precondition(skippedRow["tokenSequence"] is NSNull)
    precondition(skippedRow["skip"] as! String == "zeroSize")
    precondition(phaseSnapshot["tokenRequestMismatch"] as! Int == 1)
    let failed = phases.makeRequest(source: .floatOutput)!
    precondition(phases.completeRender(epoch: 9, start: now, end: now,
      fenceEnd: now, succeeded: false, request: failed) == nil)
    phases.notePhase(failed, .workerEnd, skip: .noCompletedRender)
    _ = phases.makeRequest(source: .surfaceActive)
    phases.notePhase(request, .workerEnd, token: token)
    phaseSnapshot = phases.snapshot()
    precondition(phaseSnapshot["requestOverflow"] as! Int == 1)
    precondition(phaseSnapshot["missingRequest"] as! Int == 1)
    now = 10
    precondition(phases.makeRequest(source: .mpv) == nil)
    print("PASS request phase binding, resize/skip/failure origins, signed asynchronous copy order, mismatch rejection and bounded stale requests")

    now = 0
    let fidelity = CompletedRenderDiagnostics(active: true, session: "fbo-fidelity", capacity: 3,
      duration: 10, clock: { now }, automaticSampling: false)
    var pixelBuffer: CVPixelBuffer?
    precondition(CVPixelBufferCreate(kCFAllocatorDefault, 113, 57, kCVPixelFormatType_32BGRA,
      nil, &pixelBuffer) == kCVReturnSuccess)
    let buffer = pixelBuffer!
    let measured = fidelity.completeRender(epoch: 17, start: 0, end: 0.001,
      fenceEnd: 0.002, succeeded: true,
      actualFboWidth: CVPixelBufferGetWidth(buffer), actualFboHeight: CVPixelBufferGetHeight(buffer),
      pixelFormatCode: CVPixelBufferGetPixelFormatType(buffer),
      renderParameterWidth: 3840, renderParameterHeight: 2160)!
    precondition(measured.actualFboWidth == 113 && measured.actualFboHeight == 57)
    precondition(measured.pixelFormatCode == kCVPixelFormatType_32BGRA)
    precondition(measured.renderParameterWidth == 3840 && measured.renderParameterHeight == 2160)
    let legacyConstructed = CompletedRenderToken(session: "legacy", sequence: 1, epoch: 1,
      renderStart: 0, renderEnd: 0.001, fenceEnd: 0.002, requestID: nil)
    precondition(legacyConstructed.actualFboWidth == nil && legacyConstructed.pixelFormatCode == nil)
    let legacy = fidelity.completeRender(epoch: 18, start: 0, end: 0.001,
      fenceEnd: 0.002, succeeded: true)!
    precondition(legacy.actualFboWidth == nil && legacy.actualFboHeight == nil && legacy.pixelFormatCode == nil)
    // A later resize/render cannot mutate a previously copied token.
    _ = fidelity.completeRender(epoch: 19, start: 0, end: 0.001, fenceEnd: 0.002,
      succeeded: true, actualFboWidth: 1920, actualFboHeight: 1080,
      pixelFormatCode: kCVPixelFormatType_64RGBAHalf)
    precondition(measured.actualFboWidth == 113 && measured.pixelFormatCode == kCVPixelFormatType_32BGRA)
    let encoded = try JSONSerialization.data(withJSONObject: fidelity.snapshot())
    let decoded = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    let fidelityRows = decoded["recentTokens"] as! [[String: Any]]
    let measuredRow = fidelityRows.first { ($0["sequence"] as! NSNumber).uint64Value == measured.sequence }!
    precondition(measuredRow["actualFboWidth"] as! Int == 113)
    precondition(measuredRow["actualFboHeight"] as! Int == 57)
    precondition((measuredRow["pixelFormatCode"] as! NSNumber).uint32Value == kCVPixelFormatType_32BGRA)
    precondition(measuredRow["renderParameterWidth"] as! Int == 3840)
    let legacyRow = fidelityRows.first { ($0["sequence"] as! NSNumber).uint64Value == legacy.sequence }!
    precondition(legacyRow["actualFboWidth"] is NSNull && legacyRow["pixelFormatCode"] is NSNull)
    print("PASS actual CVPixelBuffer dimensions/format distinct from requested render parameters, immutable token and JSON fidelity, legacy nil compatibility")

    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("on.jsonl")
    now = 0
    let output = CompletedRenderDiagnostics(active: true, capacity: 2, duration: 10,
      fileURL: file, clock: { now }, automaticSampling: false)
    _ = output.completeRender(epoch: 7, start: 0, end: 0.001, fenceEnd: 0.002, succeeded: true)
    for _ in 0..<200 { output.writeSummary() }
    let rows = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
    precondition(rows.count == 181)
    let offFile = dir.appendingPathComponent("off.jsonl")
    let disabled = CompletedRenderDiagnostics(active: false, fileURL: offFile, automaticSampling: false)
    precondition(disabled.beginRender() == nil)
    precondition(disabled.makeRequest(source: .mpv) == nil)
    disabled.notePhase(request, .workerStart)
    precondition(disabled.completeRender(epoch: 1, start: 0, end: 1, fenceEnd: 2, succeeded: true) == nil)
    disabled.consume(token: nil, hasCurrent: false, hasBuffer: false)
    disabled.writeSummary()
    precondition(disabled.snapshot()["copies"] as! Int == 0)
    precondition(!FileManager.default.fileExists(atPath: offFile.path))
    let unwritable = CompletedRenderDiagnostics(active: true, fileURL: dir, automaticSampling: false)
    unwritable.writeSummary()
    precondition(unwritable.beginRender() != nil)
    // Hold the real pool snapshot mutex on another thread while sampling.
    // The sampler must not acquire it or wait for the render wrapper/pool.
    let held = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      pool.withCurrentSnapshot { _ in
        held.signal()
        release.wait()
      }
      finished.signal()
    }
    precondition(held.wait(timeout: .now() + 1) == .success)
    _ = output.snapshot()
    output.writeSummary()
    release.signal()
    precondition(finished.wait(timeout: .now() + 1) == .success)
    print("PASS sampler has no pool-lock dependency; snapshot/IO finish while real pool mutex is held")
    print("PASS bounded summary output, default off no IO, failed atomic write isolated")
  }
}
