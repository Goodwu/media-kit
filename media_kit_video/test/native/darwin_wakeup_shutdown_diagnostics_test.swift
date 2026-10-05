import Foundation

@main
struct DarwinWakeupShutdownDiagnosticsTests {
  static func main() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let offURL = directory.appendingPathComponent("off.jsonl")
    DarwinWakeupShutdownDiagnostics(enabled: false, fileURL: offURL).record("default.off")
    precondition(!FileManager.default.fileExists(atPath: offURL.path))

    let onURL = directory.appendingPathComponent("enabled.jsonl")
    let recorder = DarwinWakeupShutdownDiagnostics(enabled: true, fileURL: onURL)
    recorder.record("host.engine.registrationAttempt", fields: ["delegateMatched": 1])
    recorder.record("host.applicationShouldTerminate", fields: ["reply": 1, "engineCount": 1])
    recorder.record("plugin.prepare.lookup", fields: ["hit": 1])
    recorder.record("owner.prepare.called", fields: ["owner": 1])
    recorder.record("owner.prepare.cleared", fields: ["owner": 1, "clearedCount": 2])
    DispatchQueue.concurrentPerform(iterations: 200) { value in
      recorder.record("bounded.concurrent", fields: ["value": value])
    }
    let lines = try String(contentsOf: onURL, encoding: .utf8).split(separator: "\n")
    precondition(lines.count == 128)
    let rows = try lines.map { line in
      try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    }
    precondition(rows.enumerated().allSatisfy { ($0.element["sequence"] as! Int) == $0.offset + 1 })
    precondition(rows[0]["event"] as! String == "host.engine.registrationAttempt")
    precondition((rows[4]["fields"] as! [String: Int])["clearedCount"] == 2)
    precondition(rows.allSatisfy { ($0["pid"] as! Int) == Int(ProcessInfo.processInfo.processIdentifier) })
    print("PASS default off creates no file; JSONL captures lifecycle fields; 200 concurrent writes capped at 128 ordered events")

    // Invoke the actual production prepare entry to verify its diagnostic
    // events, without testing/replacing the already-reviewed safety barrier.
    let registry = DarwinWakeupCallbackRegistry { _, _, _ in }
    let owner = registry.createOwner()
    registry.prepareForEngineShutdown(owner: owner)
    registry.prepareForEngineShutdown(owner: owner)
    let sharedURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "media-kit-wakeup-shutdown-\(ProcessInfo.processInfo.processIdentifier).jsonl"
    )
    if ProcessInfo.processInfo.environment["PILIPLUSX_FRAME_PACING_DIAGNOSTICS"] == "1" {
      let captured = try String(contentsOf: sharedURL, encoding: .utf8).split(separator: "\n")
      let events = try captured.map { line in
        (try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any])["event"] as! String
      }
      precondition(events == ["owner.prepare.called", "owner.prepare.cleared", "owner.prepare.called", "owner.prepare.alreadyClosed"])
      print("PASS opt-in shared recorder captures actual prepare/cleared/alreadyClosed path: \(sharedURL.path)")

      // A directory at the destination is a real unwritable file target. All
      // throwing Data writes now fail, but callback clearing must continue.
      try FileManager.default.removeItem(at: sharedURL)
      try FileManager.default.createDirectory(at: sharedURL, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: sharedURL) }
      var clears = 0
      let failureRegistry = DarwinWakeupCallbackRegistry { _, callback, _ in
        if callback == nil { clears += 1 }
      }
      let failureOwner = failureRegistry.createOwner()
      let fakeHandle = OpaquePointer(bitPattern: 1)!
      let callback: DarwinWakeupFunction = { _ in }
      precondition(failureRegistry.install(owner: failureOwner, handle: fakeHandle,
                                          callback: callback, userdata: nil))
      failureRegistry.prepareForEngineShutdown(owner: failureOwner)
      precondition(clears == 1)
      precondition(failureRegistry.remove(owner: failureOwner, handle: fakeHandle))
      failureRegistry.prepareForEngineShutdown(owner: failureOwner)
      precondition(clears == 1)
      print("PASS real unwritable diagnostic destination does not prevent production prepare clearing")
    } else {
      precondition(!FileManager.default.fileExists(atPath: sharedURL.path))
      print("PASS production prepare default off creates no diagnostic file")
    }
  }
}
