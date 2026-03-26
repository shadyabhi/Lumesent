import Foundation

struct DismissKeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: UInt  // NSEvent.ModifierFlags.rawValue
    var displayName: String

    static func from(event: NSEventShim) -> DismissKeyShortcut {
        DismissKeyShortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierRawValue,
            displayName: event.displayName
        )
    }

    func matches(keyCode: UInt16, modifierFlags: UInt) -> Bool {
        let mask: UInt = 0x00F_E0000
        return self.keyCode == keyCode && (self.modifierFlags & mask) == (modifierFlags & mask)
    }
}

struct NSEventShim {
    let keyCode: UInt16
    let modifierRawValue: UInt
    let displayName: String
}

enum UpdateChannel: String, Codable, CaseIterable {
    case stable
    case head

    var displayName: String {
        switch self {
        case .stable: "Stable"
        case .head: "Head (latest main)"
        }
    }

    var feedURL: URL {
        switch self {
        case .stable: URL(string: "https://github.com/shadyabhi/lumesent/releases/latest/download/appcast.xml")!
        case .head: URL(string: "https://github.com/shadyabhi/lumesent/releases/download/head/appcast-head.xml")!
        }
    }

    /// Head builds have CFBundleVersion set to "head" by CI.
    static var defaultForCurrentBuild: UpdateChannel {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return version.hasPrefix("head") ? .head : .stable
    }
}

enum UpdateCheckInterval: Int, Codable, CaseIterable {
    case every30Minutes = 1800
    case everyHour = 3600
    case every4Hours = 14400
    case everyDay = 86400

    var displayName: String {
        switch self {
        case .every30Minutes: "Every 30 minutes"
        case .everyHour: "Every hour"
        case .every4Hours: "Every 4 hours"
        case .everyDay: "Every day"
        }
    }
}

class AppSettings: ObservableObject {
    @Published var dismissKey: DismissKeyShortcut?
    @Published var showInDock: Bool = false
    @Published var alertPresentation: AlertPresentation = .default
    /// When non-nil and in the future, matched alerts are suppressed.
    @Published var pauseAlertsUntil: Date?
    @Published var socketPath: String = FileLocations.defaultSocketPath
    @Published var updateChannel: UpdateChannel = UpdateChannel.defaultForCurrentBuild
    @Published var updateCheckInterval: UpdateCheckInterval = .everyHour
    @Published var suppressWhenSourceVisible: Bool = true

    private let fileURL: URL

    init() {
        fileURL = FileLocations.appSupportDirectory.appendingPathComponent("settings.json")
        load()
    }

    var isPauseActive: Bool {
        guard let until = pauseAlertsUntil else { return false }
        return Date() < until
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(SettingsData(
                dismissKey: dismissKey,
                showInDock: showInDock,
                alertPresentation: alertPresentation,
                pauseAlertsUntil: pauseAlertsUntil,
                socketPath: socketPath == FileLocations.defaultSocketPath ? nil : socketPath,
                updateChannel: updateChannel == .stable ? nil : updateChannel,
                updateCheckInterval: updateCheckInterval == .everyHour ? nil : updateCheckInterval,
                suppressWhenSourceVisible: suppressWhenSourceVisible ? nil : suppressWhenSourceVisible
            ))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.shared.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLog.shared.info("no settings file at \(self.fileURL.path, privacy: .public), using defaults")
            return
        }
        guard let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else {
            AppLog.shared.error("failed to decode settings from \(self.fileURL.path, privacy: .public) (\(data.count, privacy: .public) bytes)")
            return
        }
        dismissKey = decoded.dismissKey
        showInDock = decoded.showInDock
        alertPresentation = decoded.alertPresentation
        pauseAlertsUntil = decoded.pauseAlertsUntil
        socketPath = decoded.socketPath ?? FileLocations.defaultSocketPath
        updateChannel = decoded.updateChannel ?? UpdateChannel.defaultForCurrentBuild
        updateCheckInterval = decoded.updateCheckInterval ?? .everyHour
        suppressWhenSourceVisible = decoded.suppressWhenSourceVisible ?? true
        AppLog.shared.info("settings loaded — dock=\(self.showInDock, privacy: .public) layout=\(String(describing: self.alertPresentation.layout), privacy: .public) paused=\(self.isPauseActive, privacy: .public)")
    }

    private struct SettingsData: Codable {
        var dismissKey: DismissKeyShortcut?
        var showInDock: Bool = false
        var alertPresentation: AlertPresentation = .default
        var pauseAlertsUntil: Date?
        var socketPath: String?
        var updateChannel: UpdateChannel?
        var updateCheckInterval: UpdateCheckInterval?
        var suppressWhenSourceVisible: Bool?
    }
}
