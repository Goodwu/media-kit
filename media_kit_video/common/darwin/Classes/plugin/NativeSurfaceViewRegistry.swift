import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum NativeSurfaceViewRegistry {
  private static var views = [Int64: ( [String: Any] ) -> Void]()
  private static var displayMetrics = [Int64: () -> [String: Double]]()
  private static let lock = NSLock()

  static func register(
    handle: Int64,
    configure: @escaping ([String: Any]) -> Void,
    displayMetrics: @escaping () -> [String: Double] = { [:] }
  ) {
    lock.lock(); defer { lock.unlock() }
    views[handle] = configure
    self.displayMetrics[handle] = displayMetrics
  }

  static func unregister(handle: Int64) {
    lock.lock(); defer { lock.unlock() }
    views.removeValue(forKey: handle)
    displayMetrics.removeValue(forKey: handle)
  }

  static func configure(handle: Int64, configuration: [String: Any]) {
    lock.lock(); let configure = views[handle]; lock.unlock()
    configure?(configuration)
  }

  static func metrics(handle: Int64) -> [String: Double] {
    lock.lock(); let provider = displayMetrics[handle]; lock.unlock()
    return provider?() ?? [:]
  }
}

#if canImport(AppKit)
/// A native-owned identity for a Cocoa view.
///
/// This is intentionally not an NSView pointer and is not exposed to Dart. The
/// future mpv-owned-window backend can resolve it only while the matching
/// handle/generation is alive, which prevents stale Flutter callbacks from
/// binding mpv to a recycled view.
final class DarwinViewTokenRegistry {
  struct Token: Hashable {
    let rawValue: UInt64
    fileprivate let handle: Int64
    fileprivate let generation: Int
  }

  private struct Entry {
    weak var view: NSView?
    let handle: Int64
    let generation: Int
  }

  private static let lock = NSLock()
  private static var nextRawValue: UInt64 = 1
  private static var entries = [UInt64: Entry]()

  static func register(view: NSView, handle: Int64, generation: Int) -> Token {
    lock.lock(); defer { lock.unlock() }
    let rawValue = nextRawValue
    nextRawValue &+= 1
    let token = Token(rawValue: rawValue, handle: handle, generation: generation)
    entries[rawValue] = Entry(view: view, handle: handle, generation: generation)
    return token
  }

  static func resolve(_ token: Token, handle: Int64, generation: Int) -> NSView? {
    lock.lock(); defer { lock.unlock() }
    guard token.handle == handle, token.generation == generation,
          let entry = entries[token.rawValue],
          entry.handle == handle, entry.generation == generation
    else { return nil }
    return entry.view
  }

  static func unregister(_ token: Token, handle: Int64, generation: Int) {
    lock.lock(); defer { lock.unlock() }
    guard token.handle == handle, token.generation == generation,
          let entry = entries[token.rawValue],
          entry.handle == handle, entry.generation == generation
    else { return }
    entries.removeValue(forKey: token.rawValue)
  }

  static func attach(handle: Int64, generation: Int) -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    guard let match = entries.first(where: {
      $0.value.handle == handle && $0.value.generation == generation
    }), let view = match.value.view else {
      return [
        "capable": false,
        "attached": false,
        "failureReason": "native view token not found",
        "generation": generation,
      ]
    }
    return [
      "capable": true,
      "attached": true,
      "token": String(match.key),
      // W1 experimental bridge only. The value is valid only while this
      // generation's view remains attached; Dart must consume it immediately
      // and never persist it as an identity or lifecycle token.
      "nativeViewHandle": Int64(Int(bitPattern: Unmanaged.passUnretained(view).toOpaque())),
      "handle": handle,
      "generation": generation,
      "frame": [
        "x": Double(view.frame.origin.x),
        "y": Double(view.frame.origin.y),
        "width": Double(view.frame.size.width),
        "height": Double(view.frame.size.height),
      ],
    ]
  }

  static func state(handle: Int64, generation: Int) -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    guard let match = entries.first(where: {
      $0.value.handle == handle && $0.value.generation == generation
    }), let view = match.value.view else {
      return [
        "capable": false,
        "attached": false,
        "generation": generation,
        "handle": handle,
        "failureReason": "native view token not found",
      ]
    }
    return [
      "capable": true,
      "attached": true,
      "token": String(match.key),
      "handle": handle,
      "generation": generation,
      "frame": [
        "x": Double(view.frame.origin.x),
        "y": Double(view.frame.origin.y),
        "width": Double(view.frame.size.width),
        "height": Double(view.frame.size.height),
      ],
    ]
  }

  static func detach(handle: Int64, generation: Int) -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    let matchingKeys = entries.compactMap { key, entry in
      entry.handle == handle && entry.generation == generation ? key : nil
    }
    matchingKeys.forEach { entries.removeValue(forKey: $0) }
    return [
      "capable": true,
      "detached": !matchingKeys.isEmpty,
      "generation": generation,
      "handle": handle,
    ]
  }

  static var liveEntryCount: Int {
    lock.lock(); defer { lock.unlock() }
    entries = entries.filter { $0.value.view != nil }
    return entries.count
  }
}
#endif
