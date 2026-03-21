import AppKit

// Single-instance check: if already running, signal existing instance to open settings
let bundleId = "com.shadyabhi.Lumesent"
let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    .filter { $0 != .current }

if let _ = runningInstances.first {
    DistributedNotificationCenter.default().postNotificationName(
        .init("\(bundleId).openSettings"),
        object: nil)
    usleep(500_000)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
