import Foundation

enum NativeSurfaceViewRegistry {
  private static var views = [Int64: ( [String: Any] ) -> Void]()
  private static let lock = NSLock()

  static func register(handle: Int64, configure: @escaping ([String: Any]) -> Void) {
    lock.lock(); defer { lock.unlock() }
    views[handle] = configure
  }

  static func unregister(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    views.removeValue(forKey: handle)
  }

  static func configure(handle: Int64, configuration: [String: Any]) {
    lock.lock(); let configure = views[handle]; lock.unlock()
    configure?(configuration)
  }
}
