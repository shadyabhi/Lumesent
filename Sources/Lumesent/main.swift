import AppKit
import Foundation

extension Notification.Name {
    static let lumesentOpenSettings = Notification.Name("com.shadyabhi.Lumesent.openSettings")
}

// ── CLI: --help ──
if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    let help = """
    Lumesent — macOS notification monitor with full-screen alerts

    USAGE
      Lumesent                      Launch the menu bar app

    EXTERNAL ALERTS (AppleScript)
      With Lumesent running, use osascript or Script Editor. Automation permission may be required
      for the calling app (Terminal, iTerm, etc.).

      Example:
        osascript -e 'tell application "Lumesent" to send external alert "Build failed" body text "exit 1"'

      Optional labeled parameters: application name, display mode (sticky|timed),
      alert type (fullscreen|notification), focus source terminal (true|false).

    External alerts bypass filter rules and are shown unless Lumesent is paused.
    """
    print(help)
    exit(0)
}

// Single-instance check: if already running, signal existing instance to open settings
let bundleId = "com.shadyabhi.Lumesent"
let myPID = ProcessInfo.processInfo.processIdentifier
let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    .filter { $0.processIdentifier != myPID }

if runningInstances.first != nil {
    DistributedNotificationCenter.default().postNotificationName(
        .lumesentOpenSettings,
        object: nil)
    usleep(500_000)

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Lumesent is already running"
    alert.informativeText =
        "Another copy is open in the menu bar. Settings was opened there. This duplicate will quit when you click OK."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    _ = alert.runModal()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
