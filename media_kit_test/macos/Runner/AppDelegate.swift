import Cocoa
import FlutterMacOS
import media_kit_video

@main
class AppDelegate: FlutterAppDelegate {
  private let mediaKitEngines = NSHashTable<FlutterEngine>.weakObjects()

  func registerMediaKitEngine(_ engine: FlutterEngine) {
    mediaKitEngines.add(engine)
    MediaKitVideoPlugin.recordWakeupShutdownDiagnostic("host.engine.registered", fields: [
      "engineCount": mediaKitEngines.allObjects.count,
    ])
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let reply = super.applicationShouldTerminate(sender)
    if reply == .terminateNow {
      for engine in mediaKitEngines.allObjects {
        MediaKitVideoPlugin.prepareForEngineShutdown(engine)
      }
    }
    return reply
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // The diagnostic host does not persist a restorable Flutter window. Keeping
  // the default AppKit restoration path can recreate a stale className=nil
  // window with windowID=0 and prevent the test page from being shown.
  func applicationShouldRestoreState(_ app: NSApplication) -> Bool {
    return false
  }

  func applicationShouldSaveState(_ app: NSApplication) -> Bool {
    return false
  }
}
