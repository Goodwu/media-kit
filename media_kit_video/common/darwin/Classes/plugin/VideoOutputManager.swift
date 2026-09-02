#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public class VideoOutputManager: NSObject {
  private typealias HandleOperation = (@escaping () -> Void) -> Void

  private let registry: FlutterTextureRegistry
  private var videoOutputs = [Int64: VideoOutput]()
  private var operationQueues = [Int64: [HandleOperation]]()
  private var runningHandles = Set<Int64>()

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
  }

  public func create(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    textureUpdateCallback: @escaping VideoOutput.TextureUpdateCallback,
    completion: @escaping () -> Void
  ) {
    enqueue(handle: handle) { [weak self] finish in
      guard let self = self else {
        completion()
        finish()
        return
      }
      let createReplacement = {
        self.createNow(
          handle: handle,
          configuration: configuration,
          textureUpdateCallback: textureUpdateCallback
        )
        completion()
        finish()
      }
      if let oldVideoOutput = self.videoOutputs.removeValue(forKey: handle) {
        oldVideoOutput.dispose {
          createReplacement()
        }
      } else {
        createReplacement()
      }
    }
  }

  private func createNow(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    textureUpdateCallback: @escaping VideoOutput.TextureUpdateCallback
  ) {
    let videoOutput = VideoOutput(
      handle: handle,
      configuration: configuration,
      registry: self.registry,
      textureUpdateCallback: textureUpdateCallback
    )

    self.videoOutputs[handle] = videoOutput
  }

  public func setSize(
    handle: Int64,
    width: Int64?,
    height: Int64?
  ) {
    let videoOutput = self.videoOutputs[handle]
    if videoOutput == nil {
      return
    }

    videoOutput!.setSize(
      width: width,
      height: height
    )
  }

  public func destroy(
    handle: Int64,
    completion: @escaping () -> Void
  ) {
    enqueue(handle: handle) { [weak self] finish in
      guard let self = self,
        let videoOutput = self.videoOutputs.removeValue(forKey: handle)
      else {
        completion()
        finish()
        return
      }

      videoOutput.dispose {
        completion()
        finish()
      }
    }
  }

  private func enqueue(
    handle: Int64,
    operation: @escaping HandleOperation
  ) {
    operationQueues[handle, default: []].append(operation)
    runNext(handle: handle)
  }

  private func runNext(handle: Int64) {
    guard !runningHandles.contains(handle),
      var queue = operationQueues[handle],
      !queue.isEmpty
    else {
      return
    }

    let operation = queue.removeFirst()
    operationQueues[handle] = queue.isEmpty ? nil : queue
    runningHandles.insert(handle)
    operation { [weak self] in
      guard let self = self else { return }
      self.runningHandles.remove(handle)
      self.runNext(handle: handle)
    }
  }
}
