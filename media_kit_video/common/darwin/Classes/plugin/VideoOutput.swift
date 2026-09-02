import CoreGraphics
import Foundation

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

// This class creates and manipulates the different types of FlutterTexture,
// handles resizing, rendering calls, and notify Flutter when a new frame is
// available to render.
//
// To improve the user experience, a worker is used to execute heavy tasks on a
// dedicated thread.
public class VideoOutput: NSObject {
  // Will be called on the main thread
  public typealias TextureUpdateCallback = (Int64, CGSize) -> Void

  private static let isSimulator: Bool = {
    let isSim: Bool
    #if targetEnvironment(simulator)
      isSim = true
    #else
      isSim = false
    #endif
    return isSim
  }()

  private let handle: OpaquePointer
  private let enableHardwareAcceleration: Bool
  private let registry: FlutterTextureRegistry
  private let textureUpdateCallback: TextureUpdateCallback
  private let worker: Worker = .init()
  private var width: Int64?
  private var height: Int64?
  private var texture: ResizableTextureProtocol!
  private var textureId: Int64 = -1
  private var currentSize: CGSize = CGSize.zero
  private enum DisposalState {
    case active
    case disposing
    case disposed
  }
  private let disposalLock = NSLock()
  private var disposalState: DisposalState = .active
  private var disposalCompletions: [() -> Void] = []

  init(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    registry: FlutterTextureRegistry,
    textureUpdateCallback: @escaping TextureUpdateCallback
  ) {
    let handle = OpaquePointer(bitPattern: Int(handle))
    assert(handle != nil, "handle casting")

    self.handle = handle!
    width = configuration.width
    height = configuration.height
    enableHardwareAcceleration = configuration.enableHardwareAcceleration
    self.registry = registry
    self.textureUpdateCallback = textureUpdateCallback

    super.init()

    worker.enqueue {
      self._init()
    }
  }

  deinit {
    worker.cancel()

    if !isDisposalRequested {
      disposeTextureId()
    }
  }

  public func setSize(width: Int64?, height: Int64?) {
    if isDisposalRequested {
      return
    }
    worker.enqueue {
      if self.isDisposalRequested {
        return
      }
      self.width = width
      self.height = height
    }
  }

  private func _init() {
    if isDisposalRequested {
      return
    }

    let enableHardwareAcceleration =
      VideoOutput.isSimulator ? false : enableHardwareAcceleration

    NSLog(
      "VideoOutput: enableHardwareAcceleration: \(enableHardwareAcceleration)"
    )

    if VideoOutput.isSimulator {
      NSLog(
        "VideoOutput: warning: hardware rendering is disabled in the iOS simulator, due to an incompatibility with OpenGL ES"
      )
    }

    if enableHardwareAcceleration {
      texture = SafeResizableTexture(
        TextureHW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    } else {
      texture = SafeResizableTexture(
        TextureSW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    }

    DispatchQueue.main.sync { [weak self]() in
      guard let that = self else {
        return
      }
      that.registerTextureId()
    }
  }

  // Must be run on the main thread
  private func registerTextureId() {
    // Textures must be registered on the platform thread.
    textureId = registry.register(texture)
    // textureUpdateCallback must run on the main thread
    textureUpdateCallback(textureId, CGSize(width: 0, height: 0))
  }

  private func disposeTextureId() {
    let registry_ = self.registry
    let textureId_ = self.textureId
    textureId = -1
    DispatchQueue.main.async {
      // Textures must be unregistered on the platform thread
      if textureId_ >= 0 {
        registry_.unregisterTexture(textureId_)
      }
    }
  }

  public func updateCallback() {
    if isDisposalRequested {
      return
    }
    worker.enqueue {
      self._updateCallback()
    }
  }

  private func _updateCallback() {
    if isDisposalRequested {
      return
    }

    let size = videoSize

    if size.width == 0 || size.height == 0 {
      return
    }

    if currentSize != size {
      currentSize = size

      texture.resize(size)
      DispatchQueue.main.sync { [weak self] in
        guard let that = self else { return }
        // textureUpdateCallback must run on the main thread
        that.textureUpdateCallback(that.textureId, size)
      }
    }

    texture.render(size)
    DispatchQueue.main.sync { [weak self] in
      guard let that = self else { return }
      // Textures must be marked as available from the main thread
      that.registry.textureFrameAvailable(that.textureId)
    }
  }

  // Dispose in the worker's queue order, then synchronously unregister the
  // Flutter texture on the platform thread. The completion is invoked only
  // after both the worker and texture registry have stopped referring to this
  // output, so a replacement using the same handle cannot race the old one.
  public func dispose(completion: @escaping () -> Void) {
    let shouldStart = disposalLock.synchronized { () -> Bool in
      switch disposalState {
      case .active:
        disposalState = .disposing
        disposalCompletions.append(completion)
        return true
      case .disposing:
        disposalCompletions.append(completion)
        return false
      case .disposed:
        DispatchQueue.main.async {
          completion()
        }
        return false
      }
    }

    guard shouldStart else {
      return
    }

    worker.enqueue {
      let that = self

      let registry = that.registry
      let textureId = that.textureId
      that.textureId = -1

      DispatchQueue.main.sync {
        if textureId >= 0 {
          registry.unregisterTexture(textureId)
        }
      }

      // Release the native texture only after unregistering it from Flutter.
      that.texture = nil
      let completions = that.disposalLock.synchronized { () -> [() -> Void] in
        that.disposalState = .disposed
        let completions = that.disposalCompletions
        that.disposalCompletions.removeAll()
        return completions
      }
      DispatchQueue.main.async {
        completions.forEach { $0() }
      }
    }
  }

  private var isDisposalRequested: Bool {
    disposalLock.synchronized {
      disposalState != .active
    }
  }

    private var videoSize: CGSize {
        // fixed size
        if width != nil && height != nil {
            return CGSize(
                width: Double(width!),
                height: Double(height!)
            )
        }
        
        let params = MPVHelpers.getVideoOutParams(handle)
        return CGSize(
            width: Double(width ?? (params.rotate == 0 || params.rotate == 180
                                    ? params.dw
                                    : params.dh)),
            height: Double(height ?? (params.rotate == 0 || params.rotate == 180
                                      ? params.dh
                                      : params.dw))
        )
  }
}

private extension NSLock {
  func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
