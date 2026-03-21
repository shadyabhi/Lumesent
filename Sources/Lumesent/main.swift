import AppKit

extension Notification.Name {
    static let lumesentOpenSettings = Notification.Name("com.shadyabhi.Lumesent.openSettings")
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
