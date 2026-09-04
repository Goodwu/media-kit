import CoreVideo
import Foundation

/// Process-local bridge from the mpv renderer to a native platform view.
/// The callback never exposes an engine or platform pointer to Dart.
public enum NativeFrameRegistry {
  private static var callbacks = [Int64: () -> CVPixelBuffer?]()
  private static var floatFormats = Set<Int64>()
  private static var formatObservers = [Int64: (Int64) -> Void]()
  private static var activeSurfaces = Set<Int64>()
  private static var activeObservers = [Int64: (Int64) -> Void]()
  private static let lock = NSLock()

  public static func register(handle: Int64, callback: @escaping () -> CVPixelBuffer?) {
    lock.lock(); defer { lock.unlock() }
    callbacks[handle] = callback
  }

  public static func unregister(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    callbacks.removeValue(forKey: handle)
    floatFormats.remove(handle)
    formatObservers.removeValue(forKey: handle)
    activeSurfaces.remove(handle)
    activeObservers.removeValue(forKey: handle)
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

  public static func setSurfaceActive(handle: Int64, enabled: Bool) {
    lock.lock()
    if enabled { activeSurfaces.insert(handle) } else { activeSurfaces.remove(handle) }
    let observer = activeObservers[handle]
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

  public static func hasFloatProvider(handle: Int64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return callbacks[handle] != nil && floatFormats.contains(handle)
  }
}
