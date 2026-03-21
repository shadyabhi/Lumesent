import AppKit
import Combine
import UserNotifications

final class PermissionChecker: ObservableObject {
    @Published var hasFullDiskAccess: Bool = false
    @Published var hasAccessibility: Bool = false
    @Published var hasNotifications: Bool = false

    private var timer: Timer?
    private let dbPath: String

    var allGranted: Bool { hasFullDiskAccess && hasAccessibility }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        dbPath = "\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"
        AppLog.shared.info("permission checker init — dbPath=\(self.dbPath, privacy: .public)")
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func check() {
        let fda = FileManager.default.isReadableFile(atPath: dbPath)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        let ax = AXIsProcessTrustedWithOptions(opts)
        checkNotificationPermission()
        DispatchQueue.main.async {
            if self.hasFullDiskAccess != fda {
                AppLog.shared.info("permission change: FDA \(self.hasFullDiskAccess, privacy: .public) → \(fda, privacy: .public)")
                self.hasFullDiskAccess = fda
            }
            if self.hasAccessibility != ax {
                AppLog.shared.info("permission change: AX \(self.hasAccessibility, privacy: .public) → \(ax, privacy: .public)")
                self.hasAccessibility = ax
            }
            if fda && ax && self.hasNotifications {
                AppLog.shared.info("all permissions granted, stopping permission poll timer")
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                if self.hasNotifications != granted {
                    AppLog.shared.info("permission change: Notifications \(self.hasNotifications, privacy: .public) → \(granted, privacy: .public)")
                    self.hasNotifications = granted
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
