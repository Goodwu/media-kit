#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public class MediaKitVideoPlugin: NSObject, FlutterPlugin {
  #if os(macOS)
  private static let wakeupPlugins = NSMapTable<AnyObject, MediaKitVideoPlugin>(
    keyOptions: .weakMemory, valueOptions: .weakMemory
  )
  private let wakeupOwner = DarwinWakeupCallbackRegistry.shared.createOwner()

  /// The host calls this synchronously before engine.shutdown()/Dart teardown.
  /// FlutterPlugin has no pre-detach callback; direct shutdown without this
  /// explicit host barrier is not covered by normal application Quit handling.
  public static func prepareForEngineShutdown(_ engine: FlutterEngine) {
    let messenger = engine.binaryMessenger as AnyObject
    let plugin = wakeupPlugins.object(forKey: messenger)
    recordWakeupShutdownDiagnostic("plugin.prepare.lookup", fields: ["hit": plugin == nil ? 0 : 1])
    guard let plugin else { return }
    DarwinWakeupCallbackRegistry.shared.prepareForEngineShutdown(owner: plugin.wakeupOwner)
  }
  #endif

  #if os(macOS)
  /// Opt-in lifecycle diagnostics shared with the host. Integer counters/flags
  /// only; default execution performs no diagnostic file IO.
  public static func recordWakeupShutdownDiagnostic(_ event: String, fields: [String: Int] = [:]) {
    DarwinWakeupShutdownDiagnostics.shared.record(event, fields: fields)
  }
  #endif

  private static let CHANNEL_NAME = "com.alexmercerind/media_kit_video"

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if canImport(Flutter)
      let binaryMessenger = registrar.messenger()
      let registry = registrar.textures()
      let utils: UtilsProtocol? = nil
    #elseif canImport(FlutterMacOS)
      let binaryMessenger = registrar.messenger
      let registry = registrar.textures
      let utils: UtilsProtocol? = Utils(registrar)
    #endif

    let channel = FlutterMethodChannel(
      name: CHANNEL_NAME,
      binaryMessenger: binaryMessenger
    )
    let instance = MediaKitVideoPlugin(
      registry: registry,
      channel: channel,
      utils: utils
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    #if os(macOS)
    wakeupPlugins.setObject(instance, forKey: binaryMessenger as AnyObject)
    recordWakeupShutdownDiagnostic("plugin.registered", fields: ["owner": Int(instance.wakeupOwner)])
    #endif
    #if canImport(Flutter)
      let nativeSurfaceViewFactory = NativeSurfaceViewFactory(onLayerReady: { handle, generation, rendererReady in
        let report = instance.nativeSurfaceOutput.attachLayer(handle: handle, generation: generation, rendererReady: rendererReady)
        var event: [String: Any] = report
        event["handle"] = handle
        event["generation"] = generation
        event["rendererReady"] = rendererReady
        instance.channel.invokeMethod("NativeSurface.Ready", arguments: event)
      })
      instance.nativeSurfaceViewFactory = nativeSurfaceViewFactory
      registrar.register(nativeSurfaceViewFactory, withId: "com.alexmercerind/media_kit_video/native_surface")
    #elseif canImport(FlutterMacOS)
      let nativeSurfaceViewFactory = NativeSurfaceViewFactory(
        onLayerReady: { handle, generation, rendererReady in
          let report = instance.nativeSurfaceOutput.attachLayer(handle: handle, generation: generation, rendererReady: rendererReady)
          var event: [String: Any] = report
          event["handle"] = handle
          event["generation"] = generation
          event["rendererReady"] = rendererReady
          instance.channel.invokeMethod("NativeSurface.Ready", arguments: event)
        },
        onFrameChanged: { handle, generation, frame in
          instance.channel.invokeMethod(
            "NativeWindow.Frame",
            arguments: [
              "handle": handle,
              "generation": generation,
              "frame": [
                "x": Double(frame.origin.x),
                "y": Double(frame.origin.y),
                "width": Double(frame.size.width),
                "height": Double(frame.size.height),
              ],
            ] as [String: Any]
          )
        }
      )
      instance.nativeSurfaceViewFactory = nativeSurfaceViewFactory
      registrar.register(nativeSurfaceViewFactory, withId: "com.alexmercerind/media_kit_video/native_surface")
    #endif
  }

  private let channel: FlutterMethodChannel
  private let videoOutputManager: VideoOutputManager
  private let nativeSurfaceOutput = NativeSurfaceOutput()
  private let utils: UtilsProtocol?
  private var nativeSurfaceViewFactory: NativeSurfaceViewFactory?

  init(
    registry: FlutterTextureRegistry,
    channel: FlutterMethodChannel,
    utils: UtilsProtocol?
  ) {
    self.channel = channel
    videoOutputManager = VideoOutputManager(
      registry: registry
    )
    self.utils = utils
    super.init()
    nativeSurfaceOutput.onStateChanged = { [weak self] report in
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.channel.invokeMethod("NativeSurface.Ready", arguments: report)
      }
    }
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    #if os(macOS)
    case "WakeupCallback.Owner":
      result(DarwinWakeupCallbackRegistry.binding(owner: wakeupOwner))
    #endif
    case "NativeWindow.Attach":
      #if canImport(AppKit)
        let args = call.arguments as? [String: Any]
        let handle = Int64((args?["handle"] as? String) ?? "") ?? -1
        let generation = args?["generation"] as? Int ?? 0
        let attachment = DarwinViewTokenRegistry.attach(handle: handle, generation: generation)
        NSLog("NativeWindow.Attach handle=\(handle) generation=\(generation) result=\(attachment)")
        result(attachment)
      #else
        result(["capable": false, "attached": false, "failureReason": "Cocoa window backend unavailable"])
      #endif
    case "NativeWindow.Detach":
      #if canImport(AppKit)
        let args = call.arguments as? [String: Any]
        let handle = Int64((args?["handle"] as? String) ?? "") ?? -1
        let generation = args?["generation"] as? Int ?? 0
        let detachment = DarwinViewTokenRegistry.detach(handle: handle, generation: generation)
        self.nativeSurfaceViewFactory?.release(handle: handle)
        NSLog("NativeWindow.Detach handle=\(handle) generation=\(generation) result=\(detachment)")
        result(detachment)
      #else
        result(["capable": false, "detached": false, "failureReason": "Cocoa window backend unavailable"])
      #endif
    case "NativeWindow.State":
      #if canImport(AppKit)
        let args = call.arguments as? [String: Any]
        let handle = Int64((args?["handle"] as? String) ?? "") ?? -1
        let generation = args?["generation"] as? Int ?? 0
        result(DarwinViewTokenRegistry.state(handle: handle, generation: generation))
      #else
        result(["capable": false, "attached": false, "failureReason": "Cocoa window backend unavailable"])
      #endif
    case "createNativeOutput":
      handleNativeOutput(call.arguments, result: result) { handle, generation, _ in
        return self.nativeSurfaceOutput.create(handle: handle, generation: generation)
      }
    case "configureHdrOutput":
      handleNativeOutput(call.arguments, result: result) { handle, generation, configuration in
        return self.nativeSurfaceOutput.configure(handle: handle, generation: generation, configuration: configuration)
      }
    case "resetHdrOutput":
      handleNativeOutput(call.arguments, result: result) { handle, generation, _ in
        return self.nativeSurfaceOutput.reset(handle: handle, generation: generation)
      }
    case "disposeNativeOutput":
      let args = call.arguments as? [String: Any]
      let handle = Int64((args?["handle"] as? String) ?? "") ?? -1
      let generation = args?["generation"] as? Int
      nativeSurfaceOutput.dispose(handle: handle, generation: generation)
      result(nil)
    case "VideoOutputManager.Create":
      handleCreateMethodCall(call.arguments, result)
    case "VideoOutputManager.SetSize":
      handleSetSizeMethodCall(call.arguments, result)
    case "VideoOutputManager.Dispose":
      handleDisposeMethodCall(call.arguments, result)
    case "Utils.EnterNativeFullscreen":
      handleEnterNativeFullscreenMethodCall(call.arguments, result)
    case "Utils.ExitNativeFullscreen":
      handleExitNativeFullscreenMethodCall(call.arguments, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleNativeOutput(
    _ arguments: Any?,
    result: @escaping FlutterResult,
    operation: (Int64, Int, [String: Any]) -> [String: Any]
  ) {
    let args = arguments as? [String: Any]
    let handle = Int64((args?["handle"] as? String) ?? "") ?? -1
    let generation = args?["generation"] as? Int ?? 0
    let configuration = args?["configuration"] as? [String: Any] ?? [:]
    result(operation(handle, generation, configuration))
  }

  private func handleCreateMethodCall(
    _ arguments: Any?,
    _ result: @escaping FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let handle: Int64? = Int64(handleStr)
    let configDict = args?["configuration"] as! [String: Any]
    let configuration = VideoOutputConfiguration.fromDict(configDict)

    assert(handle != nil, "handle must be an Int64")

    videoOutputManager.create(
      handle: handle!,
      configuration: configuration,
      textureUpdateCallback: { (_ textureId: Int64, _ size: CGSize) in
        self.channel.invokeMethod(
          "VideoOutput.Resize",
          arguments: [
            "handle": handle!,
            "id": textureId,
            "rect": [
              "top": 0,
              "left": 0,
              "width": size.width,
              "height": size.height,
            ],
          ] as [String: Any]
        )
      },
      completion: {
        result(nil)
      }
    )
  }

  private func handleSetSizeMethodCall(
    _ arguments: Any?,
    _ result: FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let widthStr = args?["width"] as! String
    let heightStr = args?["height"] as! String

    let handle: Int64? = Int64(handleStr)
    let width: Int64? = Int64(widthStr)
    let height: Int64? = Int64(heightStr)

    assert(handle != nil, "handle must be an Int64")

    self.videoOutputManager.setSize(
      handle: handle!,
      width: width,
      height: height
    )

    result(nil)
  }

  private func handleDisposeMethodCall(
    _ arguments: Any?,
    _ result: @escaping FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let handle: Int64? = Int64(handleStr)

    assert(handle != nil, "handle must be an Int64")

    videoOutputManager.destroy(
      handle: handle!,
      completion: {
        result(nil)
      }
    )
  }

  private func handleEnterNativeFullscreenMethodCall(
    _: Any?,
    _ result: FlutterResult
  ) {
    if utils == nil {
      return result(FlutterMethodNotImplemented)
    }

    utils?.enterNativeFullscreen()
    result(nil)
  }

  private func handleExitNativeFullscreenMethodCall(
    _: Any?,
    _ result: FlutterResult
  ) {
    if utils == nil {
      return result(FlutterMethodNotImplemented)
    }

    utils?.exitNativeFullscreen()
    result(nil)
  }
}
