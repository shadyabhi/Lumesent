import AppKit

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

        if let pane = env["TMUX_PANE"] {
            ctx.tmuxPane = pane
            ctx.tmuxSession = shellOutput("tmux display-message -p -t \(pane) \"#S\"")
            ctx.tmuxWindow = shellOutput("tmux display-message -p -t \(pane) \"#I\"")
        }

        if let iterm = env["ITERM_SESSION_ID"] {
            ctx.itermSessionId = iterm
        }

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

    /// Returns true if the terminal app is frontmost AND the tmux pane is active in its active window.
    /// Must be called from a background thread (runs shell commands synchronously).
    func isSourcePaneVisible() -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))

        guard let bundleId = terminalAppBundleId else { return false }

        let isFrontmost: Bool = DispatchQueue.main.sync {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId
        }
        guard isFrontmost else { return false }

        guard hasTmux, let pane = tmuxPane else {
            return true
        }

        let output = SourceContext.shellOutput("tmux display-message -p -t \(pane) '#{pane_active} #{window_active}'")
        let parts = output?.split(separator: " ")
        return parts?.count == 2 && parts?[0] == "1" && parts?[1] == "1"
    }

    static func shellOutput(_ command: String) -> String? {
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

    /// Runs a shell command, discarding output. Returns the exit status.
    @discardableResult
    static func shellRun(_ command: String) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            return -1
        }
    }
}

enum ExternalAlertType: String, Codable {
    case fullscreen
    case notification
}

struct ExternalNotification: Codable {
    let title: String
    var subtitle: String?
    var body: String?
    var appName: String?
    var displayMode: String?
    var alertType: String?
    var sourceContext: SourceContext?
    var focusSource: Bool?
    var sourceApp: String?

    var resolvedSubtitle: String { subtitle ?? "" }
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
