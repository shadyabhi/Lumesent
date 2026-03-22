import AppKit
import Foundation

extension Notification.Name {
    static let lumesentOpenSettings = Notification.Name("com.shadyabhi.Lumesent.openSettings")
    static let lumesentNavigateToTab = Notification.Name("com.shadyabhi.Lumesent.navigateToTab")
}

// ── CLI: --help ──
if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    let help = """
    Lumesent — macOS notification monitor with full-screen alerts

    USAGE
      Lumesent                      Launch the menu bar app
      Lumesent --send [options]     Send an external notification to the running app

    SEND OPTIONS
      --title <text>        (required) Notification title
      --body <text>         Notification body
      --app-name <text>     App name shown in the alert (default: "External")
      --display-mode <mode> "sticky" (stays until dismissed) or "timed" (auto-dismiss)
      --alert-type <type>   "fullscreen" (default) or "notification" (native macOS notification)
      --no-focus-source     Don't focus the source terminal after alert dismiss (default: focus)

    EXAMPLES
      Lumesent --send --title "Build failed" --body "exit code 1"
      Lumesent --send --title "Deploy complete" --app-name "CI" --display-mode sticky
      Lumesent --send --title "Done!" --alert-type notification

    External notifications bypass filter rules and are always displayed (unless paused).
    The app must already be running for --send to work.
    """
    print(help)
    exit(0)
}

// ── CLI: --send --title "…" [--body "…"] [--app-name "…"] [--display-mode sticky|timed] [--alert-type fullscreen|notification] ──
if CommandLine.arguments.contains("--send") {
    let args = CommandLine.arguments

    func flagValue(_ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    guard let title = flagValue("--title") else {
        fputs("error: --title is required\n", stderr)
        fputs("usage: Lumesent --send --title \"…\" [--body \"…\"] [--app-name \"…\"] [--display-mode sticky|timed] [--alert-type fullscreen|notification]\n", stderr)
        exit(1)
    }

    let noFocusSource = args.contains("--no-focus-source")

    let payload = ExternalNotification(
        title: title,
        body: flagValue("--body"),
        appName: flagValue("--app-name"),
        displayMode: flagValue("--display-mode"),
        alertType: flagValue("--alert-type"),
        sourceContext: SourceContext.detect(),
        focusSource: noFocusSource ? false : nil
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
