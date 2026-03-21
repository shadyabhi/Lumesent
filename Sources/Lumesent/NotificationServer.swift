import Foundation

struct SourceContext: Codable {
    var tmuxSession: String?
    var tmuxWindow: String?
    var tmuxPane: String?
    var itermSessionId: String?
    var terminalAppBundleId: String?

    var hasTmux: Bool { tmuxPane != nil }

    /// Auto-detect from current process environment.
    static func detect() -> SourceContext? {
        let env = ProcessInfo.processInfo.environment
        var ctx = SourceContext()

        // Tmux detection
        if let pane = env["TMUX_PANE"] {
            ctx.tmuxPane = pane
            // $TMUX is like /tmp/tmux-501/default,12345,0 — not the session name.
            // Ask tmux for session and window index.
            ctx.tmuxSession = shellOutput("tmux display-message -p -t \(pane) \"#S\"")
            ctx.tmuxWindow = shellOutput("tmux display-message -p -t \(pane) \"#I\"")
        }

        // iTerm2 detection
        if let iterm = env["ITERM_SESSION_ID"] {
            ctx.itermSessionId = iterm
        }

        // Detect which terminal app we're inside.
        // Inside tmux, TERM_PROGRAM=tmux, so check LC_TERMINAL and
        // __CFBundleIdentifier which survive tmux sessions.
        if let bundleId = env["__CFBundleIdentifier"], !bundleId.isEmpty {
            ctx.terminalAppBundleId = bundleId
        } else if let lcTerminal = env["LC_TERMINAL"]?.lowercased() {
            switch lcTerminal {
            case "iterm2": ctx.terminalAppBundleId = "com.googlecode.iterm2"
            default: break
            }
        } else if let termProgram = env["TERM_PROGRAM"]?.lowercased() {
            switch termProgram {
            case "iterm.app": ctx.terminalAppBundleId = "com.googlecode.iterm2"
            case "apple_terminal": ctx.terminalAppBundleId = "com.apple.Terminal"
            case "wezterm": ctx.terminalAppBundleId = "com.github.wez.wezterm"
            case "alacritty": ctx.terminalAppBundleId = "org.alacritty"
            default: break
            }
        }

        let hasAnything = ctx.tmuxPane != nil || ctx.itermSessionId != nil || ctx.terminalAppBundleId != nil
        return hasAnything ? ctx : nil
    }

    private static func shellOutput(_ command: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (str?.isEmpty == false) ? str : nil
        } catch {
            return nil
        }
    }
}

enum ExternalAlertType: String, Codable {
    case fullscreen
    case notification
}

struct ExternalNotification: Codable {
    let title: String
    var body: String?
    var appName: String?
    var displayMode: String?
    var alertType: String?
    var sourceContext: SourceContext?
    var focusSource: Bool?

    var resolvedBody: String { body ?? "" }
    var resolvedAppName: String { appName ?? "External" }
    var resolvedDisplayMode: AlertDisplayMode {
        displayMode == "sticky" ? .sticky : .defaultTimed
    }
    var resolvedAlertType: ExternalAlertType {
        ExternalAlertType(rawValue: alertType ?? "") ?? .fullscreen
    }
    var resolvedFocusSource: Bool { focusSource ?? true }
}

final class NotificationServer {
    private let socketPath: String
    private var serverFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "com.shadyabhi.Lumesent.notificationServer.accept")
    private let onNotification: (ExternalNotification) -> Void

    init(onNotification: @escaping (ExternalNotification) -> Void) {
        self.socketPath = FileLocations.appSupportDirectory.appendingPathComponent("notify.sock").path
        self.onNotification = onNotification
    }

    func start() {
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            AppLog.shared.error("failed to create socket: \(errno, privacy: .public)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathFieldLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathMaxCopy = pathFieldLen - 1
        guard socketPath.utf8.count <= pathMaxCopy else {
            AppLog.shared.error("socket path too long for sockaddr_un")
            close(serverFD)
            serverFD = -1
            return
        }
        socketPath.withCString { ptr in
            withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
                let pathBuf = rawBuf.baseAddress!.assumingMemoryBound(to: CChar.self)
                strncpy(pathBuf, ptr, pathMaxCopy)
            }
        }
        // BSD: address length is prefix + pathname bytes (SUN_LEN), not sizeof(sockaddr_un).
        let sunPathOffset = Int(MemoryLayout.offset(of: \sockaddr_un.sun_path)!)
        let addrLen = socklen_t(sunPathOffset + socketPath.utf8.count)
        addr.sun_len = UInt8(addrLen)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            AppLog.shared.error("failed to bind socket: \(errno, privacy: .public)")
            close(serverFD)
            serverFD = -1
            return
        }

        chmod(socketPath, 0o777)

        guard Darwin.listen(serverFD, 16) == 0 else {
            AppLog.shared.error("failed to listen on socket: \(errno, privacy: .public)")
            close(serverFD)
            serverFD = -1
            return
        }

        let listenFD = serverFD
        acceptQueue.async { [weak self] in
            self?.acceptLoop(listenFD: listenFD)
        }

        AppLog.shared.info("notification server listening at \(self.socketPath, privacy: .public)")
    }

    func stop() {
        let fd = serverFD
        serverFD = -1
        if fd >= 0 {
            close(fd)
        }
        unlink(socketPath)
    }

    deinit {
        stop()
    }

    /// Blocking `accept` on a background queue; `stop()` closes `listenFD` to unblock.
    private func acceptLoop(listenFD: Int32) {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                if errno == EBADF || errno == EINVAL { break }
                AppLog.shared.notice("accept failed: \(errno, privacy: .public)")
                break
            }
            handleClient(clientFD)
            close(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            data.append(contentsOf: buffer[..<bytesRead])
        }

        guard !data.isEmpty else { return }

        do {
            let notification = try JSONDecoder().decode(ExternalNotification.self, from: data)
            AppLog.shared.notice("received external notification: \(notification.title, privacy: .public) sourceContext: tmux=\(notification.sourceContext?.tmuxSession ?? "nil", privacy: .public):\(notification.sourceContext?.tmuxWindow ?? "nil", privacy: .public):\(notification.sourceContext?.tmuxPane ?? "nil", privacy: .public) terminal=\(notification.sourceContext?.terminalAppBundleId ?? "nil", privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                self?.onNotification(notification)
            }
        } catch {
            AppLog.shared.notice("failed to parse external notification: \(error.localizedDescription, privacy: .public)")
        }
    }
}
