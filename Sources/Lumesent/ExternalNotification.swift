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
