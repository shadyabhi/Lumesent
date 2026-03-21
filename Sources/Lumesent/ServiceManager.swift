import Foundation

struct ServiceManager {
    static let label = "com.shadyabhi.Lumesent"

    static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    static func install() throws {
        guard let appPath = appBundlePath else {
            throw ServiceError.notRunningFromBundle
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["\(appPath)/Contents/MacOS/Lumesent"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": "/tmp/lumesent.stdout.log",
            "StandardErrorPath": "/tmp/lumesent.stderr.log",
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)

        let agentsDir = agentPlistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try data.write(to: agentPlistURL, options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", "gui/\(getuid())", agentPlistURL.path]
        try process.run()
        process.waitUntilExit()
    }

    static func uninstall() throws {
        guard isInstalled else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try process.run()
        process.waitUntilExit()

        try FileManager.default.removeItem(at: agentPlistURL)
    }

    static var appBundlePath: String? {
        let execPath = ProcessInfo.processInfo.arguments[0]
        let url = URL(fileURLWithPath: execPath).resolvingSymlinksInPath()
        let components = url.pathComponents
        // Expect: /path/to/Lumesent.app/Contents/MacOS/Lumesent
        if let macosIndex = components.firstIndex(of: "MacOS"),
           macosIndex >= 2,
           components[macosIndex - 1] == "Contents" {
            let appComponents = Array(components[0..<(macosIndex - 1)])
            return appComponents.joined(separator: "/")
        }
        return nil
    }

    enum ServiceError: LocalizedError {
        case notRunningFromBundle

        var errorDescription: String? {
            switch self {
            case .notRunningFromBundle:
                return "Lumesent must be running from a .app bundle to install as a login service. Build with: swift build -c release && bash scripts/bundle.sh"
            }
        }
    }
}
