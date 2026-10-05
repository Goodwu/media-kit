import CoreGraphics
import Foundation

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

#if os(macOS)
private typealias VideoOutputDiagnosticRequest = CompletedRenderRequest
#else
private typealias VideoOutputDiagnosticRequest = Never
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
  private let useNativeSurface: Bool
  private let registry: FlutterTextureRegistry
  private let textureUpdateCallback: TextureUpdateCallback
  private let worker: Worker = .init()
  private var width: Int64?
  private var height: Int64?
  private var texture: ResizableTextureProtocol!
  private var textureId: Int64 = -1
  private var currentSize: CGSize = CGSize.zero
  #if os(macOS)
  private let completedRenderDiagnostics: CompletedRenderDiagnostics?
  #endif
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
    useNativeSurface = configuration.useNativeSurface
    self.registry = registry
    self.textureUpdateCallback = textureUpdateCallback
    #if os(macOS)
    if CompletedRenderDiagnostics.enabled && configuration.enableHardwareAcceleration {
      let session = UUID().uuidString
      let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "media-kit-flutter-consumption-\(ProcessInfo.processInfo.processIdentifier)-\(Int(bitPattern: handle!))-\(session).jsonl"
      )
      completedRenderDiagnostics = CompletedRenderDiagnostics(active: true, session: session, fileURL: file)
    } else {
      completedRenderDiagnostics = nil
    }
    #endif

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
      let update: () -> Void = { [weak self] in self?.updateCallback() }
      #if os(macOS)
      let hardware = TextureHW(
        handle: handle, nativeSurface: useNativeSurface,
        completedRenderDiagnostics: completedRenderDiagnostics,
        diagnosticUpdateCallback: { [weak self] request in self?.updateCallback(diagnosticRequest: request) },
        updateCallback: update
      )
      #else
      let hardware = TextureHW(handle: handle, nativeSurface: useNativeSurface, updateCallback: update)
      #endif
      texture = SafeResizableTexture(hardware)
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
    #if os(macOS)
    if completedRenderDiagnostics != nil {
      updateCallback(diagnosticRequest: nil)
      return
    }
    #endif
    if isDisposalRequested {
      return
    }
    worker.enqueue {
      self._updateCallback()
    }
  }

  #if os(macOS)
  private func updateCallback(diagnosticRequest: CompletedRenderRequest?) {
    let request = diagnosticRequest ?? completedRenderDiagnostics?.makeRequest(source: .videoOutput)
    if isDisposalRequested {
      completedRenderDiagnostics?.notePhase(request, .workerEnd, skip: .disposedBeforeEnqueue)
      return
    }
    completedRenderDiagnostics?.notePhase(request, .enqueue)
    worker.enqueue { self._updateCallback(diagnosticRequest: request) }
  }
  #endif

  private func _updateCallback(diagnosticRequest: VideoOutputDiagnosticRequest? = nil) {
    #if os(macOS)
    completedRenderDiagnostics?.notePhase(diagnosticRequest, .workerStart)
    #endif
    if isDisposalRequested {
      #if os(macOS)
      completedRenderDiagnostics?.notePhase(diagnosticRequest, .workerEnd, skip: .disposedInWorker)
      #endif
      return
    }

    let size = videoSize

    if size.width == 0 || size.height == 0 {
      #if os(macOS)
      completedRenderDiagnostics?.notePhase(diagnosticRequest, .workerEnd, skip: .zeroSize)
      #endif
      return
    }

    if currentSize != size {
      currentSize = size

      #if os(macOS)
      completedRenderDiagnostics?.notePhase(diagnosticRequest, .resizeBegin)
      #endif
      texture.resize(size)
      #if os(macOS)
      completedRenderDiagnostics?.notePhase(diagnosticRequest, .resizeEnd)
      completedRenderDiagnostics?.notePhase(diagnosticRequest, .resizeNotifyWait)
      #endif
      DispatchQueue.main.sync { [weak self] in
        guard let that = self else { return }
        #if os(macOS)
        that.completedRenderDiagnostics?.notePhase(diagnosticRequest, .resizeNotifyMain)
        #endif
        // textureUpdateCallback must run on the main thread
        that.textureUpdateCallback(that.textureId, size)
        #if os(macOS)
        that.completedRenderDiagnostics?.notePhase(diagnosticRequest, .resizeNotifyEnd)
        #endif
      }
    }

    #if os(macOS)
    var completedToken: CompletedRenderToken?
    if completedRenderDiagnostics != nil, let safeTexture = texture as? SafeResizableTexture {
      completedToken = safeTexture.render(size, diagnosticRequest: diagnosticRequest)
    } else {
      texture.render(size)
    }
    completedRenderDiagnostics?.notePhase(diagnosticRequest, .notifyWait, token: completedToken)
    #else
    texture.render(size)
    #endif
    DispatchQueue.main.sync { [weak self] in
      guard let that = self else { return }
      #if os(macOS)
      that.completedRenderDiagnostics?.notePhase(diagnosticRequest, .notifyMain, token: completedToken)
      #endif
      // Textures must be marked as available from the main thread
      that.registry.textureFrameAvailable(that.textureId)
      #if os(macOS)
      that.completedRenderDiagnostics?.notePhase(diagnosticRequest, .notifyEnd, token: completedToken)
      #endif
    }
    #if os(macOS)
    completedRenderDiagnostics?.notePhase(diagnosticRequest, .workerEnd, token: completedToken,
      skip: completedToken == nil ? .noCompletedRender : nil)
    #endif
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
