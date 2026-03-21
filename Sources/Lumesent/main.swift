import AppKit
import Foundation

extension Notification.Name {
    static let lumesentOpenSettings = Notification.Name("com.shadyabhi.Lumesent.openSettings")
}

// ── CLI: --send --title "…" [--body "…"] [--app-name "…"] [--display-mode sticky|timed] ──
if CommandLine.arguments.contains("--send") {
    let args = CommandLine.arguments

    func flagValue(_ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    guard let title = flagValue("--title") else {
        fputs("error: --title is required\n", stderr)
        fputs("usage: Lumesent --send --title \"…\" [--body \"…\"] [--app-name \"…\"] [--display-mode sticky|timed]\n", stderr)
        exit(1)
    }

    let payload = ExternalNotification(
        title: title,
        body: flagValue("--body"),
        appName: flagValue("--app-name"),
        displayMode: flagValue("--display-mode")
    )

    let data: Data
    do {
        data = try JSONEncoder().encode(payload)
    } catch {
        fputs("error: failed to encode JSON — \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    let socketPath = FileLocations.appSupportDirectory.appendingPathComponent("notify.sock").path
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { fputs("error: cannot create socket\n", stderr); exit(1) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathMaxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
    withUnsafeMutablePointer(to: &addr) { addrPtr in
        socketPath.withCString { cstr in
            let sunPath = UnsafeMutableRawPointer(addrPtr).advanced(by: MemoryLayout.offset(of: \sockaddr_un.sun_path)!)
            strncpy(sunPath.assumingMemoryBound(to: CChar.self), cstr, pathMaxLen)
        }
    }
    let sunPathOffset = Int(MemoryLayout.offset(of: \sockaddr_un.sun_path)!)
    let addrLen = socklen_t(sunPathOffset + socketPath.utf8.count)
    addr.sun_len = UInt8(addrLen)

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(fd, sockPtr, addrLen)
        }
    }
    guard connectResult == 0 else {
        fputs("error: cannot connect to Lumesent — is it running?\n", stderr)
        close(fd)
        exit(1)
    }

    data.withUnsafeBytes { buf in
        _ = write(fd, buf.baseAddress!, buf.count)
    }
    close(fd)
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
