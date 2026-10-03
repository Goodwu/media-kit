import Foundation

@main
struct SwappableObjectManagerTests {
  final class Buffer {
    let id: Int
    var inFlight = false
    init(_ id: Int) { self.id = id }
  }
  static var failures = 0
  static func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
  }
  static func parkedPool() -> (SwappableObjectManager<Buffer>, [Buffer]) {
    let objects = (0..<3).map(Buffer.init)
    let pool = SwappableObjectManager(objects: objects)
    for object in objects {
      check(pool.nextAvailable() === object, "initial FIFO")
      object.inFlight = true
      pool.pushAsReady(object, hold: { $0.inFlight })
    }
    return (pool, objects)
  }
  static func main() {
    do {
      let (pool, objects) = parkedPool()
      pool.releaseHeld(where: { !$0.inFlight })
      check(pool.nextAvailable() == nil, "busy held buffers must not be writable")
      check(pool.current === objects[2], "current buffer must remain published")
    }
    do {
      let (pool, objects) = parkedPool()
      objects[0].inFlight = false
      pool.releaseHeld(where: { !$0.inFlight })
      pool.releaseHeld(where: { !$0.inFlight })
      check(pool.nextAvailable() === objects[0], "completed held buffer must return exactly once")
      check(pool.nextAvailable() == nil, "busy buffer and current must stay unavailable")
      objects[1].inFlight = false
      pool.releaseHeld(where: { !$0.inFlight })
      check(pool.nextAvailable() === objects[1], "second completed buffer must return")
      check(pool.nextAvailable() == nil, "repeat release must not duplicate objects")
    }
    do {
      let objects = (0..<3).map(Buffer.init)
      let pool = SwappableObjectManager(objects: objects)
      for frame in 0..<1000 {
        guard let next = pool.nextAvailable() else {
          check(false, "pool exhausted at frame \(frame)")
          break
        }
        let previous = pool.current
        next.inFlight = true
        pool.pushAsReady(next, hold: { $0.inFlight })
        previous?.inFlight = false
        pool.releaseHeld(where: { !$0.inFlight })
        pool.releaseHeld(where: { !$0.inFlight })
        check(pool.current === next, "latest frame remains current")
      }
    }
    if failures > 0 { print("\(failures) failures"); exit(1) }
    print("PASS: busy protection, completion, idempotence and 1000-frame rotation")
  }
}
