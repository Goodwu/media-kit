import Foundation
import Mpv

private final class WakeupCallbackCounter {
  private let lock = NSLock()
  private var value = 0

  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
  }

  func snapshot() -> Int {
    lock.lock()
    let current = value
    lock.unlock()
    return current
  }
}

private func stage(_ message: String) {
  FileHandle.standardError.write(Data("[wakeup-owner-fixture] \(message)\n".utf8))
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
  guard condition() else {
    stage("FAIL \(message)")
    fatalError(message)
  }
}

private let callback: DarwinWakeupFunction = { pointer in
  guard let pointer else { return }
  Unmanaged<WakeupCallbackCounter>.fromOpaque(pointer)
    .takeUnretainedValue()
    .increment()
}

private func drainEvents(_ mpv: OpaquePointer, stage label: String) {
  let started = DispatchTime.now().uptimeNanoseconds
  let timeoutNanoseconds: UInt64 = 2_000_000_000
  let maximumIterations = 100_000
  stage("drain \(label) begin")
  for iteration in 0..<maximumIterations {
    guard let event = mpv_wait_event(mpv, 0) else {
      fatalError("drain \(label): mpv_wait_event returned nil")
    }
    switch event.pointee.event_id {
    case MPV_EVENT_NONE:
      guard DispatchTime.now().uptimeNanoseconds - started < timeoutNanoseconds else {
        fatalError("drain \(label): exceeded 2 second bound before MPV_EVENT_NONE")
      }
      stage("drain \(label) reached MPV_EVENT_NONE after \(iteration) events")
      return
    case MPV_EVENT_SHUTDOWN:
      fatalError("drain \(label): unexpected MPV_EVENT_SHUTDOWN")
    case MPV_EVENT_QUEUE_OVERFLOW:
      fatalError("drain \(label): MPV_EVENT_QUEUE_OVERFLOW")
    default:
      break
    }
    if DispatchTime.now().uptimeNanoseconds - started >= timeoutNanoseconds {
      fatalError("drain \(label): exceeded 2 second bound")
    }
  }
  fatalError("drain \(label): exceeded \(maximumIterations) event bound")
}

@main
struct DarwinWakeupCallbackOwnerTests {
  static func main() {
    let handle = OpaquePointer(bitPattern: 1)!
    var writes: [String] = []
    let registry = DarwinWakeupCallbackRegistry { h, callback, _ in
      writes.append("\(h):\(callback == nil ? "clear" : "install")")
    }
    let a = registry.createOwner(), b = registry.createOwner()
    let h2 = OpaquePointer(bitPattern: 2)!
    require(registry.install(owner: a, handle: handle, callback: callback, userdata: nil), "mock owner A install")
    require(registry.install(owner: b, handle: h2, callback: callback, userdata: nil), "mock owner B install")
    require(!registry.remove(owner: b, handle: handle), "mock wrong-owner remove rejection")
    require(writes.count == 2, "mock ownership isolation writes")
    registry.prepareForEngineShutdown(owner: a)
    require(writes.count == 3 && writes.last!.hasSuffix("clear"), "mock shutdown clears owner A")
    require(!registry.install(owner: a, handle: handle, callback: callback, userdata: nil), "mock closed owner rejects install")
    require(registry.remove(owner: a, handle: handle), "mock repeated owner A remove")
    require(writes.count == 3, "mock repeated remove does not call setter")
    require(registry.remove(owner: b, handle: h2), "mock owner B remove")
    registry.prepareForEngineShutdown(owner: b)
    require(writes.count == 4, "mock owner B shutdown clear")
    require(registry.createOwner() > b, "mock owner tokens are monotonic")
    print("PASS owners isolated, mismatch rejected, shutdown admission closed, repeated remove/close harmless")

    // Concurrent dispose and shutdown must never pass a cleared/free handle
    // back to mpv; both operations use the same production registry mutex.
    for _ in 0..<200 {
      let concurrent = DarwinWakeupCallbackRegistry { _, function, _ in
        if function == nil { Thread.sleep(forTimeInterval: 0.0001) }
      }
      let owner = concurrent.createOwner()
      require(concurrent.install(owner: owner, handle: handle, callback: callback, userdata: nil), "race owner install")
      let group = DispatchGroup()
      group.enter()
      DispatchQueue.global().async {
        require(concurrent.remove(owner: owner, handle: handle), "race remove")
        group.leave()
      }
      group.enter()
      DispatchQueue.global().async {
        concurrent.prepareForEngineShutdown(owner: owner)
        group.leave()
      }
      group.wait()
      require(concurrent.remove(owner: owner, handle: handle), "race repeated remove")
    }
    print("PASS 200 concurrent remove/shutdown races")

    // The actual exported ABI uses actual mpv, not a replacement state machine.
    stage("actual mpv create begin")
    guard let mpv = mpv_create() else {
      fatalError("actual mpv create returned nil")
    }
    stage("actual mpv initialize begin")
    require(mpv_initialize(mpv) == 0, "actual mpv initialize")
    let counter = WakeupCallbackCounter()
    let owner = DarwinWakeupCallbackRegistry.shared.createOwner()
    let binding = DarwinWakeupCallbackRegistry.binding(owner: owner)
    typealias Install = @convention(c) (UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32
    typealias Remove = @convention(c) (UInt64, UnsafeMutableRawPointer?) -> Int32
    stage("actual ABI address resolution begin")
    guard let installAddress = binding["install"] as? UInt,
          let removeAddress = binding["remove"] as? UInt else {
      fatalError("actual ABI address resolution failed")
    }
    let nativeInstall = unsafeBitCast(installAddress, to: Install.self)
    let remove = unsafeBitCast(removeAddress, to: Remove.self)
    stage("actual ABI install begin")
    require(nativeInstall(owner, UnsafeMutableRawPointer(mpv), unsafeBitCast(callback, to: UnsafeMutableRawPointer.self), Unmanaged.passUnretained(counter).toOpaque()) == 1, "actual ABI install returns one")
    require(counter.snapshot() > 0, "actual ABI install invokes the callback synchronously")
    stage("actual ABI install callback count=\(counter.snapshot())")

    // Drain all coalesced events before each wake so mpv can re-arm its callback.
    drainEvents(mpv, stage: "live-1")
    let liveBaseline1 = counter.snapshot()
    stage("live-1 wake baseline=\(liveBaseline1)")
    mpv_wakeup(mpv)
    let liveAfter1 = counter.snapshot()
    require(liveAfter1 > liveBaseline1, "live wake 1 increases callback count")
    stage("live-1 callback count=\(liveAfter1)")
    drainEvents(mpv, stage: "live-2")
    let liveBaseline2 = counter.snapshot()
    stage("live-2 wake baseline=\(liveBaseline2)")
    mpv_wakeup(mpv)
    let liveAfter2 = counter.snapshot()
    require(liveAfter2 > liveBaseline2, "live wake 2 increases callback count")
    stage("live-2 callback count=\(liveAfter2)")

    stage("prepare shutdown barrier begin")
    DarwinWakeupCallbackRegistry.shared.prepareForEngineShutdown(owner: owner)
    stage("prepare shutdown barrier returned")
    drainEvents(mpv, stage: "cleared-1")
    let clearedBaseline1 = counter.snapshot()
    stage("cleared-1 wake baseline=\(clearedBaseline1)")
    mpv_wakeup(mpv)
    let clearedAfter1 = counter.snapshot()
    require(clearedAfter1 == clearedBaseline1, "cleared wake 1 does not increase callback count")
    stage("cleared-1 callback count=\(clearedAfter1)")
    drainEvents(mpv, stage: "cleared-2")
    let clearedBaseline2 = counter.snapshot()
    stage("cleared-2 wake baseline=\(clearedBaseline2)")
    mpv_wakeup(mpv)
    let clearedAfter2 = counter.snapshot()
    require(clearedAfter2 == clearedBaseline2, "cleared wake 2 does not increase callback count")
    stage("cleared-2 callback count=\(clearedAfter2)")

    stage("remove before destroy")
    require(remove(owner, UnsafeMutableRawPointer(mpv)) == 1, "remove before destroy returns one")
    stage("destroy begin")
    mpv_terminate_destroy(mpv)
    stage("destroy returned")
    // Late/repeated remove does not touch the freed mpv pointer.
    require(remove(owner, UnsafeMutableRawPointer(mpv)) == 1, "late remove after destroy returns one")
    stage("late remove after destroy returned")
    print("PASS actual function-address ABI, actual mpv callback live before barrier and cleared before destroy")
  }
}
