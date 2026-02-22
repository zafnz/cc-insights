import Cocoa
import FlutterMacOS
import Darwin

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
    if ProcessInfo.processInfo.environment["CCI_DISABLE_SIGPIPE_IGNORE"] != "1" {
      signal(SIGPIPE, SIG_IGN)
    }
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    channel = FlutterMethodChannel(
      name: "com.nickclifford.ccinsights/window",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel?.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "bringToFront":
        NSApp.activate(ignoringOtherApps: true)
        self?.mainFlutterWindow?.makeKeyAndOrderFront(nil)
        result(nil)

      case "pickDirectory":
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"

        // Try sheet modal first, fall back to app-modal
        if let window = self?.mainFlutterWindow {
          panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
              result(url.path)
            } else {
              result(nil)
            }
          }
        } else {
          let response = panel.runModal()
          if response == .OK, let url = panel.url {
            result(url.path)
          } else {
            result(nil)
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @IBAction func openSettings(_ sender: Any) {
    channel?.invokeMethod("openSettings", arguments: nil)
  }
}
