import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.title = "Archangel"
    // Open at 1280x720 (same as Windows/Linux), centered; don't allow it
    // smaller than the desktop layout's breakpoint can handle.
    self.setContentSize(NSSize(width: 1280, height: 720))
    self.contentMinSize = NSSize(width: 800, height: 560)
    self.center()
    self.collectionBehavior.insert([.fullScreenPrimary, .fullScreenAllowsTiling])

    RegisterGeneratedPlugins(registry: flutterViewController)
    WireGuardMacOS.register(with: flutterViewController.engine.binaryMessenger)

    let windowChannel = FlutterMethodChannel(name: "archangel/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else {
        result(FlutterError(code: "NO_WINDOW", message: "Window not available", details: nil))
        return
      }
      switch call.method {
      case "toggleFullScreen":
        self.toggleFullScreen(nil)
        result(true)
      case "setFullScreen":
        if let args = call.arguments as? [String: Any], let full = args["fullScreen"] as? Bool {
          let isFull = self.styleMask.contains(.fullScreen)
          if isFull != full {
            self.toggleFullScreen(nil)
          }
        }
        result(true)
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
