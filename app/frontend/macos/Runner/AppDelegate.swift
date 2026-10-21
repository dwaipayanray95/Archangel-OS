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
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      let win = NSApplication.shared.windows.first(where: { $0 is MainFlutterWindow }) ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first
      if let window = win, !window.styleMask.contains(.fullScreen) {
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
      }
    }
  }
}
