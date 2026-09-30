import Foundation

// This class was created to prevent a frameBuffer read by Flutter from being
// concurrently modified by a write method (mpv's renderer).
//
// To do this, two pools are set up, one for frameBuffers available for writing,
// the other for frameBuffers ready to be read by Flutter.
//
// When a frameBuffer has finished being modified and is "pushed", the oldest
// ready frameBuffer is marked as the current frameBuffer, and the oldest
// current frameBuffer is placed in the pool of frameBuffers available for
// writing.
//
// The use of at least three frameBuffers ensures that the read and write phases
// do not overlap, thus eliminating flicker.
public class SwappableObjectManager<T> {
  private let lock: NSRecursiveLock = NSRecursiveLock()
  private var available: [T]
  private var ready: [T] = []
  private var held: [T] = []
  private var _current: T?

  init(objects: [T], skipCheckArgs: Bool = false) {
    if !skipCheckArgs {
      SwappableObjectManager.checkArgs(objects)
    }

    available = objects
  }

  public func reinit(objects: [T], skipCheckArgs: Bool = false) {
    if !skipCheckArgs {
      SwappableObjectManager.checkArgs(objects)
    }

    lock.lock()
    defer {
      lock.unlock()
    }

    available = objects
    ready = []
    held = []
    _current = nil
  }

  public func nextAvailable() -> T? {
    lock.lock()
    defer {
      lock.unlock()
    }

    let object: T? =
      available.count > 0
      ? available.removeFirst()
      : nil

    return object
  }

  /// Pushes a freshly written object as ready.
  ///
  /// When the previous current object is rotated out, `hold` decides whether
  /// it may return to the writable pool immediately. A held object (still
  /// being read by an async consumer, e.g. an in-flight Metal blit) stays
  /// parked until `releaseHeld(where:)` observes the hold clearing.
  public func pushAsReady(_ object: T, hold: ((T) -> Bool)? = nil) {
    lock.lock()
    defer {
      lock.unlock()
    }

    ready.append(object)
    updateCurrent(hold: hold)
  }

  /// Returns held objects whose hold predicate has cleared to the writable
  /// pool. Idempotent; cheap to call speculatively.
  public func releaseHeld(where predicate: (T) -> Bool) {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard !held.isEmpty else { return }
    var stillHeld = [T]()
    for object in held {
      if predicate(object) {
        stillHeld.append(object)
      } else {
        available.append(object)
      }
    }
    held = stillHeld
  }

  public var current: T? {
    lock.lock()
    defer {
      lock.unlock()
    }

    return _current
  }

  private func updateCurrent(hold: ((T) -> Bool)? = nil) {
    lock.lock()
    defer {
      lock.unlock()
    }

    let next: T? =
      ready.count > 0
      ? ready.removeFirst()
      : nil

    if next == nil {
      return
    }

    let old: T? = _current
    _current = next

    if old == nil {
      return
    }

    if let old, hold?(old) == true {
      held.append(old)
    } else {
      available.append(old!)
    }
  }

  static private func checkArgs(_ objects: [T]) {
    if objects.count < 2 {
      NSLog("SwappableObjectManager: require at least two objects to work")
    }
  }
}
