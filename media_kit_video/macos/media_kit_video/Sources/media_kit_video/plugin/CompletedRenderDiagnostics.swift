import Foundation

enum RenderRequestSource: String { case mpv, floatOutput, surfaceActive, videoOutput }
enum RenderRequestPhase: String {
  case mainArrival, enqueue, workerStart, resizeBegin, resizeEnd
  case resizeNotifyWait, resizeNotifyMain, resizeNotifyEnd
  case published, notifyWait, notifyMain, notifyEnd, workerEnd
}
enum RenderRequestSkip: String { case disposedBeforeEnqueue, disposedInWorker, zeroSize, noCompletedRender }
struct CompletedRenderRequest: Equatable {
  let session: String
  let identifier: UInt64
  let callbackTime: Double
  let source: RenderRequestSource
}

/// Identifies a completed OpenGL render, not a decoded or presented frame.
struct CompletedRenderToken: Equatable {
  let session: String
  let sequence: UInt64
  let epoch: Int64
  let renderStart: Double
  let renderEnd: Double
  let fenceEnd: Double
  let requestID: UInt64?
  // Actual allocated color attachment properties, distinct from the render
  // parameter dimensions passed to mpv. Unknown for legacy/test callers.
  let actualFboWidth: Int?
  let actualFboHeight: Int?
  let pixelFormatCode: UInt32?
  let renderParameterWidth: Int?
  let renderParameterHeight: Int?
  let failureAttemptID: UInt64?
  let failureSlotID: String?

  init(session: String, sequence: UInt64, epoch: Int64, renderStart: Double,
       renderEnd: Double, fenceEnd: Double, requestID: UInt64?,
       actualFboWidth: Int? = nil, actualFboHeight: Int? = nil,
       pixelFormatCode: UInt32? = nil, renderParameterWidth: Int? = nil,
       renderParameterHeight: Int? = nil, failureAttemptID: UInt64? = nil,
       failureSlotID: String? = nil) {
    self.session = session
    self.sequence = sequence
    self.epoch = epoch
    self.renderStart = renderStart
    self.renderEnd = renderEnd
    self.fenceEnd = fenceEnd
    self.requestID = requestID
    self.actualFboWidth = actualFboWidth
    self.actualFboHeight = actualFboHeight
    self.pixelFormatCode = pixelFormatCode
    self.renderParameterWidth = renderParameterWidth
    self.renderParameterHeight = renderParameterHeight
    self.failureAttemptID = failureAttemptID
    self.failureSlotID = failureSlotID
  }
}

private struct DiagnosticMetricRing {
  private var values: [Double]
  private var next = 0
  private var size = 0
  private(set) var overflow = 0
  init(capacity: Int) { values = Array(repeating: 0, count: capacity) }
  mutating func append(_ value: Double) {
    if size == values.count { overflow += 1 } else { size += 1 }
    values[next] = value
    next = (next + 1) % values.count
  }
  func snapshot() -> [Double] { Array(values.prefix(size)) }
}

/// Opt-in, bounded observation of production and Flutter copyPixelBuffer calls.
/// Hot paths only update in-memory counters/rings. No mpv queries or tasks are
/// posted per frame. Serialization and throwing atomic IO run at most 1 Hz.
final class CompletedRenderDiagnostics {
  static let enabled = ProcessInfo.processInfo.environment["PILIPLUSX_FRAME_PACING_DIAGNOSTICS"] == "1"
  let session: String
  private struct Record {
    let token: CompletedRenderToken
    var copies: Int = 0
    var firstCopyTime: Double?
    var lastCopyTime: Double?
  }
  private struct RequestRecord {
    let request: CompletedRenderRequest
    var phases: [RenderRequestPhase: Double] = [:]
    var skip: RenderRequestSkip?
    var tokenSequence: UInt64?
  }
  private let lock = NSLock()
  private let active: Bool
  private let clock: () -> Double
  private let began: Double
  private let duration: Double
  private let fileURL: URL?
  private let outputQueue = DispatchQueue(label: "media_kit.completed_render_diagnostics")
  private var timer: DispatchSourceTimer?
  private var stopped = false
  private var sequence: UInt64 = 0
  private var records: [Record?]
  private var recordOverflow = 0
  private var requestSequence: UInt64 = 0
  private var requests: [RequestRecord?]
  private var requestOverflow = 0
  private var missingRequest = 0
  private var tokenRequestMismatch = 0
  private var repeatedPhases = 0
  private var renderFailures = 0
  private var noWritableSlot = 0
  private var noCurrent = 0
  private var noBuffer = 0
  private var missingToken = 0
  private var missingRecord = 0
  private var copies = 0
  private var firstCopies = 0
  private var repeatedCopies = 0
  private var lastCopyTime: Double?
  private var lastUniqueCopyTime: Double?
  private var renderTimes: DiagnosticMetricRing
  private var fenceTimes: DiagnosticMetricRing
  private var copyAges: DiagnosticMetricRing
  private var copyIntervals: DiagnosticMetricRing
  private var uniqueCopyIntervals: DiagnosticMetricRing
  private var firstCopyAges: DiagnosticMetricRing
  private var output = Data()
  private var summaries = 0

  init(active: Bool, session: String = UUID().uuidString, capacity: Int = 4096,
       duration: Double = 180, fileURL: URL? = nil,
       clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
       automaticSampling: Bool = true) {
    precondition(capacity > 0 && duration > 0)
    self.active = active
    self.session = session
    self.clock = clock
    self.began = clock()
    self.duration = duration
    self.fileURL = fileURL
    records = Array(repeating: nil, count: capacity)
    requests = Array(repeating: nil, count: capacity)
    renderTimes = DiagnosticMetricRing(capacity: capacity)
    fenceTimes = DiagnosticMetricRing(capacity: capacity)
    copyAges = DiagnosticMetricRing(capacity: capacity)
    copyIntervals = DiagnosticMetricRing(capacity: capacity)
    uniqueCopyIntervals = DiagnosticMetricRing(capacity: capacity)
    firstCopyAges = DiagnosticMetricRing(capacity: capacity)
    if active && automaticSampling && fileURL != nil {
      let source = DispatchSource.makeTimerSource(queue: outputQueue)
      source.schedule(deadline: .now() + 1, repeating: 1)
      source.setEventHandler { [weak self] in self?.writeSummary() }
      timer = source
      source.resume()
    }
  }

  deinit { timer?.cancel() }

  private func recording(_ now: Double) -> Bool {
    guard active && !stopped else { return false }
    if now - began >= duration { stopped = true; return false }
    return true
  }

  func makeRequest(source: RenderRequestSource) -> CompletedRenderRequest? {
    guard active else { return nil }
    let now = clock()
    lock.lock(); defer { lock.unlock() }
    guard recording(now) else { return nil }
    requestSequence += 1
    let request = CompletedRenderRequest(session: session, identifier: requestSequence,
      callbackTime: now, source: source)
    let index = Int((requestSequence - 1) % UInt64(requests.count))
    if requests[index] != nil { requestOverflow += 1 }
    requests[index] = RequestRecord(request: request)
    return request
  }

  func notePhase(_ request: CompletedRenderRequest?, _ phase: RenderRequestPhase,
                 token: CompletedRenderToken? = nil, skip: RenderRequestSkip? = nil) {
    guard active, let request else { return }
    let now = clock()
    lock.lock(); defer { lock.unlock() }
    guard recording(now) else { return }
    guard request.session == session, request.identifier > 0 else { missingRequest += 1; return }
    let index = Int((request.identifier - 1) % UInt64(requests.count))
    guard var record = requests[index], record.request == request else { missingRequest += 1; return }
    if record.phases[phase] != nil { repeatedPhases += 1 }
    record.phases[phase] = now
    if let skip { record.skip = skip }
    if let token {
      if token.session == session, token.requestID == request.identifier {
        record.tokenSequence = token.sequence
      } else {
        tokenRequestMismatch += 1
      }
    }
    requests[index] = record
  }

  func beginRender() -> Double? {
    guard active else { return nil }
    let now = clock()
    lock.lock(); defer { lock.unlock() }
    return recording(now) ? now : nil
  }

  func completeRender(epoch: Int64, start: Double, end: Double,
                      fenceEnd: Double, succeeded: Bool,
                      request: CompletedRenderRequest? = nil,
                      actualFboWidth: Int? = nil, actualFboHeight: Int? = nil,
                      pixelFormatCode: UInt32? = nil,
                      renderParameterWidth: Int? = nil,
                      renderParameterHeight: Int? = nil,
                      failureAttemptID: UInt64? = nil, failureSlotID: String? = nil) -> CompletedRenderToken? {
    guard active else { return nil }
    lock.lock(); defer { lock.unlock() }
    guard recording(fenceEnd) else { return nil }
    guard succeeded else { renderFailures += 1; return nil }
    sequence += 1
    var requestID: UInt64?
    if let request, request.session == session, request.identifier > 0 {
      let index = Int((request.identifier - 1) % UInt64(requests.count))
      if requests[index]?.request == request { requestID = request.identifier }
      else { missingRequest += 1 }
    }
    let token = CompletedRenderToken(session: session, sequence: sequence,
      epoch: epoch, renderStart: start, renderEnd: end, fenceEnd: fenceEnd, requestID: requestID,
      actualFboWidth: actualFboWidth, actualFboHeight: actualFboHeight,
      pixelFormatCode: pixelFormatCode, renderParameterWidth: renderParameterWidth,
      renderParameterHeight: renderParameterHeight,
      failureAttemptID: failureAttemptID, failureSlotID: failureSlotID)
    let index = Int((sequence - 1) % UInt64(records.count))
    if records[index] != nil { recordOverflow += 1 }
    records[index] = Record(token: token)
    renderTimes.append(max(0, end - start))
    fenceTimes.append(max(0, fenceEnd - end))
    return token
  }

  func noteNoWritableSlot() {
    guard active else { return }
    let now = clock()
    lock.lock(); defer { lock.unlock() }
    if recording(now) { noWritableSlot += 1 }
  }

  /// Called outside the pool mutex, using the retained buffer's copied token.
  func consume(token: CompletedRenderToken?, hasCurrent: Bool, hasBuffer: Bool) {
    guard active else { return }
    let now = clock()
    lock.lock(); defer { lock.unlock() }
    guard recording(now) else { return }
    if !hasCurrent { noCurrent += 1 }
    guard hasBuffer else { noBuffer += 1; return }
    copies += 1
    if let last = lastCopyTime { copyIntervals.append(max(0, now - last)) }
    lastCopyTime = now
    guard let token else { missingToken += 1; return }
    guard token.session == session, token.sequence > 0 else { missingRecord += 1; return }
    let index = Int((token.sequence - 1) % UInt64(records.count))
    guard var record = records[index], record.token == token else { missingRecord += 1; return }
    if record.copies == 0 {
      firstCopies += 1
      record.firstCopyTime = now
      firstCopyAges.append(max(0, now - token.fenceEnd))
      if let last = lastUniqueCopyTime { uniqueCopyIntervals.append(max(0, now - last)) }
      lastUniqueCopyTime = now
    } else {
      repeatedCopies += 1
    }
    record.copies += 1
    record.lastCopyTime = now
    records[index] = record
    copyAges.append(max(0, now - token.fenceEnd))
  }

  /// Copies bounded observations under the lock; sorting/serialization/IO is
  /// outside it. The pool mutex is never acquired by this class.
  func snapshot() -> [String: Any] {
    let now = clock()
    lock.lock()
    _ = recording(now)
    let copiedRecords = records.compactMap { $0 }
    let copiedRequests = requests.compactMap { $0 }
    var result: [String: Any] = [
      "kind": "completed-render-to-flutter-copy", "session": session,
      "pid": ProcessInfo.processInfo.processIdentifier,
      "monotonicTime": now, "elapsed": max(0, now - began),
      "stopped": stopped, "capacity": records.count, "completedRenders": sequence,
      "renderFailures": renderFailures, "noWritableSlot": noWritableSlot,
      "noCurrent": noCurrent, "noBuffer": noBuffer, "missingToken": missingToken,
      "missingRecord": missingRecord, "copies": copies, "firstCopies": firstCopies,
      "repeatedCopies": repeatedCopies, "recordOverflow": recordOverflow,
      "requests": requestSequence, "requestOverflow": requestOverflow, "missingRequest": missingRequest,
      "tokenRequestMismatch": tokenRequestMismatch, "repeatedPhases": repeatedPhases,
      "metricOverflow": renderTimes.overflow + fenceTimes.overflow + copyAges.overflow + copyIntervals.overflow + uniqueCopyIntervals.overflow + firstCopyAges.overflow,
    ]
    let render = renderTimes.snapshot(), fence = fenceTimes.snapshot()
    let age = copyAges.snapshot(), interval = copyIntervals.snapshot()
    let firstAge = firstCopyAges.snapshot(), uniqueInterval = uniqueCopyIntervals.snapshot()
    lock.unlock()
    result["recentTokens"] = copiedRecords.sorted { $0.token.sequence < $1.token.sequence }
      .suffix(64).map { record -> [String: Any] in
        let t = record.token
        return ["sequence": t.sequence, "epoch": t.epoch, "renderStart": t.renderStart,
                "renderEnd": t.renderEnd, "fenceEnd": t.fenceEnd, "copies": record.copies,
                "firstCopyTime": record.firstCopyTime as Any? ?? NSNull(),
                "lastCopyTime": record.lastCopyTime as Any? ?? NSNull(),
                "requestID": t.requestID as Any? ?? NSNull(),
                "actualFboWidth": t.actualFboWidth as Any? ?? NSNull(),
                "actualFboHeight": t.actualFboHeight as Any? ?? NSNull(),
                "pixelFormatCode": t.pixelFormatCode as Any? ?? NSNull(),
                "renderParameterWidth": t.renderParameterWidth as Any? ?? NSNull(),
                "renderParameterHeight": t.renderParameterHeight as Any? ?? NSNull(),
                "failureAttemptID": t.failureAttemptID as Any? ?? NSNull(),
                "failureSlotID": t.failureSlotID as Any? ?? NSNull()]
      }
    result["recentRequests"] = copiedRequests.sorted { $0.request.identifier < $1.request.identifier }
      .suffix(64).map { record -> [String: Any] in
        ["requestID": record.request.identifier, "callbackTime": record.request.callbackTime,
         "source": record.request.source.rawValue,
         "phases": Dictionary(uniqueKeysWithValues: record.phases.map { ($0.key.rawValue, $0.value) }),
         "skip": record.skip?.rawValue as Any? ?? NSNull(),
         "tokenSequence": record.tokenSequence as Any? ?? NSNull()]
      }
    var phaseSamples: [String: [Double]] = [:]
    func sample(_ key: String, _ end: Double?, _ start: Double?) {
      if let end, let start { phaseSamples[key, default: []].append(end - start) }
    }
    let tokensBySequence = Dictionary(uniqueKeysWithValues: copiedRecords.map { ($0.token.sequence, $0) })
    for r in copiedRequests {
      let p = r.phases
      sample("callbackToMainMs", p[.mainArrival], r.request.callbackTime)
      sample("enqueueToWorkerMs", p[.workerStart], p[.enqueue])
      sample("resizeMs", p[.resizeEnd], p[.resizeBegin])
      sample("resizeMainWaitMs", p[.resizeNotifyMain], p[.resizeNotifyWait])
      sample("notifyMainWaitMs", p[.notifyMain], p[.notifyWait])
      sample("notifyCallMs", p[.notifyEnd], p[.notifyMain])
      sample("workerMs", p[.workerEnd], p[.workerStart])
      if let seq = r.tokenSequence, let record = tokensBySequence[seq], record.token.requestID == r.request.identifier {
        sample("workerToRenderMs", record.token.renderStart, p[.workerStart])
        sample("fenceToPublishMs", p[.published], record.token.fenceEnd)
        sample("publishToNotifyWaitMs", p[.notifyWait], p[.published])
        // This is signed correlation: Flutter may copy the published token
        // before this request's notification returns. It is not causal proof.
        sample("signedNotifyEndToFirstCopyMs", record.firstCopyTime, p[.notifyEnd])
      }
    }
    result["phaseMs"] = phaseSamples.mapValues { Self.distribution($0) }
    result["renderMs"] = Self.distribution(render)
    result["fenceMs"] = Self.distribution(fence)
    result["fenceToCopyMs"] = Self.distribution(age)
    result["copyIntervalMs"] = Self.distribution(interval)
    result["uniqueCopyIntervalMs"] = Self.distribution(uniqueInterval)
    result["fenceToFirstCopyMs"] = Self.distribution(firstAge)
    return result
  }

  private static func distribution(_ values: [Double]) -> [String: Any] {
    guard !values.isEmpty else { return ["count": 0] }
    let sorted = values.sorted()
    func percentile(_ fraction: Double) -> Double {
      sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))] * 1000
    }
    return ["count": sorted.count, "p50": percentile(0.5), "p95": percentile(0.95),
            "max": sorted.last! * 1000]
  }

  /// Production calls this only from the 1 Hz serial output queue. Public to
  /// the module so tests can deterministically verify bounded throwing IO.
  func writeSummary() {
    guard active, let fileURL else { return }
    guard summaries < 181 else { timer?.cancel(); return }
    let row = snapshot()
    do {
      var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      data.append(0x0a)
      output.append(data)
      summaries += 1
      try output.write(to: fileURL, options: [.atomic])
    } catch { /* Diagnostic IO cannot change rendering or consumption. */ }
    if row["stopped"] as? Bool == true { timer?.cancel() }
  }
}
