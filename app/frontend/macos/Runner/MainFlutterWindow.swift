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

    RegisterGeneratedPlugins(registry: flutterViewController)
    WireGuardMacOS.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
