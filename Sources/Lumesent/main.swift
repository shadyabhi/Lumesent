import AppKit
import Foundation

extension Notification.Name {
    static let lumesentOpenSettings = Notification.Name("com.shadyabhi.Lumesent.openSettings")
    static let lumesentNavigateToTab = Notification.Name("com.shadyabhi.Lumesent.navigateToTab")
}

// ── CLI routing ──
let args = CommandLine.arguments
let subcommand = args.count > 1 ? args[1] : nil

// ── Lumesent --help / Lumesent -h ──
if subcommand == "--help" || subcommand == "-h" {
    let help = """
    Lumesent — macOS notification monitor with full-screen alerts

    USAGE
      Lumesent                Launch the menu bar app
      Lumesent send [options] Send a notification to the running app
      Lumesent logs [options] Stream or show recent app logs

    Run 'Lumesent <command> --help' for command options.
    """
    print(help)
    exit(0)
}

// ── Lumesent logs ──
if subcommand == "logs" {
    if args.contains("--help") || args.contains("-h") {
        let help = """
        Show Lumesent app logs via the unified macOS log system.

        USAGE
          Lumesent logs [options]

        OPTIONS
          --follow              Stream logs in real time (like tail -f)
          --last <duration>     How far back to show (default: 1h). Examples: 30m, 2h, 1d

        EXAMPLES
          Lumesent logs
          Lumesent logs --follow
          Lumesent logs --last 30m
          Lumesent logs --follow --last 5m
        """
        print(help)
        exit(0)
    }

    func flagValue(_ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    let last = flagValue("--last") ?? "1h"
    let follow = args.contains("--follow")

    var logArgs = [String]()
    if follow {
        logArgs += ["stream", "--predicate", "process == \"Lumesent\""]
    } else {
        logArgs += ["show", "--predicate", "process == \"Lumesent\"", "--last", last]
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    task.arguments = logArgs
    task.standardOutput = FileHandle.standardOutput
    task.standardError = FileHandle.standardError

    signal(SIGINT, SIG_IGN)
    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSource.setEventHandler { task.terminate() }
    sigintSource.resume()

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        fputs("error: failed to run log command — \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    exit(task.terminationStatus)
}

// ── Lumesent send ──
if subcommand == "send" {
    // Lumesent send --help / Lumesent send -h
    if args.contains("--help") || args.contains("-h") {
        let help = """
        Send a notification to the running Lumesent app.

        USAGE
          Lumesent send --title <text> [options]

        OPTIONS
          --title <text>        (required) Notification title
          --subtitle <text>     Notification subtitle
          --body <text>         Notification body
          --app-name <text>     App name shown in the alert (default: "External")
          --display-mode <mode> "sticky" (stays until dismissed) or "timed" (auto-dismiss)
          --alert-type <type>   "fullscreen" (default) or "notification" (native macOS notification)
          --no-focus-source     Don't focus the source terminal after alert dismiss

        EXAMPLES
          Lumesent send --title "Build failed" --body "exit code 1"
          Lumesent send --title "Deploy complete" --app-name "CI" --display-mode sticky
          Lumesent send --title "Done!" --alert-type notification

        Bypasses filter rules — always displayed (unless paused).
        The app must already be running.
        """
        print(help)
        exit(0)
    }

    func flagValue(_ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    guard let title = flagValue("--title") else {
        fputs("error: --title is required\n", stderr)
        fputs("usage: Lumesent send --title \"…\" [--subtitle \"…\"] [--body \"…\"] [--app-name \"…\"] [--display-mode sticky|timed] [--alert-type fullscreen|notification]\n", stderr)
        exit(1)
    }

    let noFocusSource = args.contains("--no-focus-source")

    let payload = ExternalNotification(
        title: title,
        subtitle: flagValue("--subtitle"),
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

    let socketPath = AppSettings().socketPath
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
