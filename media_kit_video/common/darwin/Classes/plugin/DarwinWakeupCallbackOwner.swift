import Foundation
#if SWIFT_PACKAGE
import Mpv
#endif

#if os(macOS)
/// Lifecycle-only, opt-in diagnostics. No mpv queries and no frame/event-pump
/// instrumentation. The diagnostic mutex is never held across registry work.
final class DarwinWakeupShutdownDiagnostics {
  static let shared = DarwinWakeupShutdownDiagnostics(
    enabled: ProcessInfo.processInfo.environment["PILIPLUSX_FRAME_PACING_DIAGNOSTICS"] == "1",
    fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "media-kit-wakeup-shutdown-\(ProcessInfo.processInfo.processIdentifier).jsonl"
    )
  )
  private let enabled: Bool
  private let fileURL: URL
  private let lock = NSLock()
  private var count = 0
  private var boundedData = Data()

  init(enabled: Bool, fileURL: URL) {
    self.enabled = enabled
    self.fileURL = fileURL
  }

  // Only integer counters/flags are accepted; never URLs or media metadata.
  func record(_ event: String, fields: [String: Int] = [:]) {
    guard enabled else { return }
    lock.lock(); defer { lock.unlock() }
    guard count < 128 else { return }
    count += 1
    let row: [String: Any] = [
      "event": event, "sequence": count,
      "pid": ProcessInfo.processInfo.processIdentifier,
      "timestamp": Date().timeIntervalSince1970, "fields": fields,
    ]
    do {
      var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      data.append(0x0a)
      // Legacy FileHandle write/seek/close can raise Objective-C exceptions,
      // which Swift catch cannot contain. Only throwing Data IO is used here.
      // Rewriting at most 128 lifecycle rows keeps memory and IO bounded.
      boundedData.append(data)
      try boundedData.write(to: fileURL, options: [.atomic])
    } catch {
      // Diagnostics cannot affect callback admission or shutdown correctness.
    }
  }
}

typealias DarwinWakeupFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void

/// Serializes callback publication/removal with the host's pre-engine-shutdown
/// barrier. It deliberately does not destroy players or render contexts.
final class DarwinWakeupCallbackRegistry {
  static let shared = DarwinWakeupCallbackRegistry()
  typealias Setter = (OpaquePointer, DarwinWakeupFunction?, UnsafeMutableRawPointer?) -> Void
  private let lock = NSLock()
  private var nextOwner: UInt64 = 0
  private var owners: [UInt64: Set<OpaquePointer>] = [:]
  private var handleOwners: [OpaquePointer: UInt64] = [:]
  private let setter: Setter

  init(setter: @escaping Setter = { mpv_set_wakeup_callback($0, $1, $2) }) {
    self.setter = setter
  }

  static func binding(owner: UInt64) -> [String: Any] {
    let install: @convention(c) (UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = mediaKitDarwinWakeupInstall
    let remove: @convention(c) (UInt64, UnsafeMutableRawPointer?) -> Int32 = mediaKitDarwinWakeupRemove
    return ["owner": owner, "install": unsafeBitCast(install, to: UInt.self),
            "remove": unsafeBitCast(remove, to: UInt.self)]
  }

  func createOwner() -> UInt64 {
    lock.lock(); defer { lock.unlock() }
    precondition(nextOwner < UInt64.max)
    nextOwner += 1
    owners[nextOwner] = []
    return nextOwner
  }

  func install(owner: UInt64, handle: OpaquePointer,
               callback: DarwinWakeupFunction, userdata: UnsafeMutableRawPointer?) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard owners[owner] != nil, handleOwners[handle] == nil else { return false }
    owners[owner]!.insert(handle)
    handleOwners[handle] = owner
    // mpv synchronously invokes the listener once here. The listener only
    // posts into Dart; it must not reenter this registry synchronously.
    setter(handle, callback, userdata)
    return true
  }

  func remove(owner: UInt64, handle: OpaquePointer) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard let registeredOwner = handleOwners[handle] else {
      // Already cleared by shutdown or a previous remove. Never dereference a
      // raw handle that may have been destroyed after that successful clear.
      return true
    }
    guard registeredOwner == owner else { return false }
    setter(handle, nil, nil)
    handleOwners.removeValue(forKey: handle)
    owners[owner]?.remove(handle)
    return true
  }

  func prepareForEngineShutdown(owner: UInt64) {
    DarwinWakeupShutdownDiagnostics.shared.record("owner.prepare.called", fields: ["owner": Int(owner)])
    var clearedCount: Int?
    lock.lock()
    defer {
      lock.unlock()
      // Record only after releasing the safety barrier's mutex.
      DarwinWakeupShutdownDiagnostics.shared.record(
        clearedCount == nil ? "owner.prepare.alreadyClosed" : "owner.prepare.cleared",
        fields: ["owner": Int(owner), "clearedCount": clearedCount ?? 0]
      )
    }
    // Removing the admission entry rejects every late install, forever: owner
    // tokens are monotonic and never reused. remove remains idempotent.
    guard let handles = owners.removeValue(forKey: owner) else { return }
    NSLog("media_kit wakeup shutdown begin owner=%llu handles=%lu", owner, handles.count)
    for handle in handles {
      setter(handle, nil, nil)
      handleOwners.removeValue(forKey: handle)
    }
    NSLog("media_kit wakeup shutdown end owner=%llu cleared=%lu", owner, handles.count)
    clearedCount = handles.count
  }
}

@_cdecl("media_kit_darwin_wakeup_install")
public func mediaKitDarwinWakeupInstall(
  _ owner: UInt64, _ handle: UnsafeMutableRawPointer?,
  _ callback: UnsafeMutableRawPointer?, _ userdata: UnsafeMutableRawPointer?
) -> Int32 {
  guard let handle, let callback else { return 0 }
  let function = unsafeBitCast(callback, to: DarwinWakeupFunction.self)
  return DarwinWakeupCallbackRegistry.shared.install(
    owner: owner, handle: OpaquePointer(handle), callback: function, userdata: userdata
  ) ? 1 : 0
}

@_cdecl("media_kit_darwin_wakeup_remove")
public func mediaKitDarwinWakeupRemove(
  _ owner: UInt64, _ handle: UnsafeMutableRawPointer?
) -> Int32 {
  guard let handle else { return 0 }
  return DarwinWakeupCallbackRegistry.shared.remove(
    owner: owner, handle: OpaquePointer(handle)
  ) ? 1 : 0
}
#endif
