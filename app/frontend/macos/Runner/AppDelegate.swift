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

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Launch in full screen mode like a game
    DispatchQueue.main.async {
      if let window = NSApplication.shared.windows.first, !window.styleMask.contains(.fullScreen) {
        window.toggleFullScreen(nil)
      }
    }
  }
}
