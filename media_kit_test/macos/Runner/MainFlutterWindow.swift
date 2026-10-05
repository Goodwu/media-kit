import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowTestChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    isRestorable = false
    restorationClass = nil
    identifier = nil
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    (NSApp.delegate as? AppDelegate)?.registerMediaKitEngine(flutterViewController.engine)

    let channel = FlutterMethodChannel(
      name: "media_kit_test/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setFrame",
            let args = call.arguments as? [String: Any],
            let width = args["width"] as? Double,
            let height = args["height"] as? Double else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        guard let self else {
          result(FlutterError(code: "NO_WINDOW", message: "Flutter window not found", details: nil))
          return
        }
        self.minSize = NSSize(width: 0, height: 0)
        self.contentMinSize = NSSize(width: 0, height: 0)
        self.setContentSize(NSSize(width: width, height: height))
        self.displayIfNeeded()
        result(["width": self.frame.width, "height": self.frame.height])
      }
    }
    windowTestChannel = channel

    super.awakeFromNib()
  }
}
