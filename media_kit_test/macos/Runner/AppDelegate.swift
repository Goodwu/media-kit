import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
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
