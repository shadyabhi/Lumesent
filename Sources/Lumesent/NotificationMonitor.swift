import AppKit
import SQLite3

final class NotificationMonitor {
    private let onNewNotification: (NotificationRecord) -> Void
    private var db: OpaquePointer?
    private var lastSeenRecId: Int64 = 0
    private var fallbackTimer: Timer?
    private var axObserver: AXObserver?

    init(onNewNotification: @escaping (NotificationRecord) -> Void) {
        self.onNewNotification = onNewNotification
    }

    func start() {
        guard openDatabase() else {
            showPermissionAlert()
            return
        }
        initializeLastSeenId()
        startAccessibilityObserver()
        startFallbackTimer()
    }

    // MARK: - SQLite

    private func openDatabase() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)

        guard result == SQLITE_OK else {
            NSLog("Lumesent: Failed to open notification DB: %d", result)
            return false
        }

        // Use WAL mode for non-blocking reads
        sqlite3_exec(db, "PRAGMA journal_mode=wal", nil, nil, nil)
        return true
    }

    private func initializeLastSeenId() {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT MAX(rec_id) FROM record", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW
        else { return }

        lastSeenRecId = sqlite3_column_int64(stmt, 0)
        NSLog("Lumesent: initialized, last rec_id = %lld", lastSeenRecId)
    }

    func fetchNewNotifications() {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let query = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r
            JOIN app a ON r.app_id = a.app_id
            WHERE r.rec_id > ?
            ORDER BY r.rec_id ASC
            """

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("Lumesent: Failed to prepare query: %@", String(cString: sqlite3_errmsg(db!)))
            return
        }

        sqlite3_bind_int64(stmt, 1, lastSeenRecId)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let recId = sqlite3_column_int64(stmt, 0)

            let appIdentifier: String
            if let cStr = sqlite3_column_text(stmt, 1) {
                appIdentifier = String(cString: cStr)
            } else {
                appIdentifier = "unknown"
            }

            var title = ""
            var body = ""

            if let dataBlob = sqlite3_column_blob(stmt, 2) {
                let dataLen = sqlite3_column_bytes(stmt, 2)
                let data = Data(bytes: dataBlob, count: Int(dataLen))
                (title, body) = parsePlist(data)
            }

            let deliveredDate: Date
            let timestamp = sqlite3_column_double(stmt, 3)
            if timestamp > 0 {
                // Core Data timestamp (seconds since 2001-01-01)
                deliveredDate = Date(timeIntervalSinceReferenceDate: timestamp)
            } else {
                deliveredDate = Date()
            }

            let record = NotificationRecord(
                id: recId,
                appIdentifier: appIdentifier,
                title: title,
                body: body,
                deliveredDate: deliveredDate
            )

            lastSeenRecId = recId
            NSLog("Lumesent: new notification from %@: %@ — %@", appIdentifier, title, body)
            onNewNotification(record)
        }
    }

    private func parsePlist(_ data: Data) -> (title: String, body: String) {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let req = plist["req"] as? [String: Any]
        else {
            return ("", "")
        }

        let title = req["titl"] as? String ?? ""
        let body = req["body"] as? String ?? ""
        return (title, body)
    }

    // MARK: - Accessibility Observer

    private func startAccessibilityObserver() {
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            return
        }

        guard let ncPid = findNotificationCenterPID() else {
            NSLog("Lumesent: could not find NotificationCenter process")
            return
        }

        let element = AXUIElementCreateApplication(ncPid)
        var observer: AXObserver?

        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<NotificationMonitor>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.fetchNewNotifications()
            }
        }

        guard AXObserverCreate(ncPid, callback, &observer) == .success,
              let observer = observer
        else {
            NSLog("Lumesent: failed to create AXObserver")
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.axObserver = observer

        NSLog("Lumesent: accessibility observer started for NotificationCenter (pid %d)", ncPid)
    }

    private func findNotificationCenterPID() -> pid_t? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first { $0.bundleIdentifier == "com.apple.notificationcenterui" }?.processIdentifier
    }

    private func promptForAccessibility() {
        NSLog("Lumesent: accessibility not granted, requesting...")
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Fallback Timer

    private func startFallbackTimer() {
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.fetchNewNotifications()
        }
    }

    // MARK: - Permission Alert

    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Full Disk Access Required"
            alert.informativeText = "Lumesent needs Full Disk Access to read system notifications. Please grant it in System Settings > Privacy & Security > Full Disk Access."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            NSApp.terminate(nil)
        }
    }
}
