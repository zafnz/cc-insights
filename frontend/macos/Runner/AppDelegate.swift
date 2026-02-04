import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var channel: FlutterMethodChannel?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    channel = FlutterMethodChannel(
      name: "com.nickclifford.ccinsights/window",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel?.setMethodCallHandler { (call, result) in
      if call.method == "bringToFront" {
        NSApp.activate(ignoringOtherApps: true)
        self.mainFlutterWindow?.makeKeyAndOrderFront(nil)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @IBAction func openSettings(_ sender: Any) {
    channel?.invokeMethod("openSettings", arguments: nil)
  }
}
