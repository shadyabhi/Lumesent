import AppKit
import Combine
import SQLite3

enum NotificationDatabaseStatus: Equatable {
    /// Cannot read the DB path (typically missing Full Disk Access).
    case noAccess
    /// Path is readable but SQLite could not open (locked, corrupt, etc.).
    case temporarilyUnavailable
    case connected
}

final class NotificationMonitor: ObservableObject {
    @Published private(set) var databaseStatus: NotificationDatabaseStatus = .noAccess

    /// `AXIsProcessTrustedWithOptions(prompt: true)` may show a system dialog; only once per launch.
    private static var didPromptForAccessibilityThisSession = false

    private let onNewNotification: (NotificationRecord) -> Void
    private var db: OpaquePointer?
    private var lastSeenRecId: Int64 = 0
    private var didPrimeLastSeenId = false
    private var fallbackTimer: Timer?
    private var axObserver: AXObserver?
    private let dbPath: String

    init(onNewNotification: @escaping (NotificationRecord) -> Void) {
        self.onNewNotification = onNewNotification
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }

    func start() {
        AppLog.shared.info("NotificationMonitor starting — dbPath=\(self.dbPath, privacy: .public)")
        tryOpenDatabase()
        if db != nil {
            initializeLastSeenIdIfNeeded()
        }
        startAccessibilityObserver()
        startFallbackTimer()
    }

    // MARK: - SQLite

    private func tryOpenDatabase() {
        if db != nil { return }

        guard FileManager.default.isReadableFile(atPath: dbPath) else {
            DispatchQueue.main.async { self.databaseStatus = .noAccess }
            return
        }

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(dbPath, &handle, flags, nil)

        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            AppLog.shared.notice("Failed to open notification DB: code \(result, privacy: .public)")
            DispatchQueue.main.async { self.databaseStatus = .temporarilyUnavailable }
            return
        }

        db = handle
        sqlite3_exec(db, "PRAGMA journal_mode=wal", nil, nil, nil)
        DispatchQueue.main.async { self.databaseStatus = .connected }
        AppLog.shared.info("Notification DB opened")
    }

    private func closeDatabase() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
        didPrimeLastSeenId = false
    }

    private func initializeLastSeenIdIfNeeded() {
        guard let db, !didPrimeLastSeenId else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT MAX(rec_id) FROM record", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW
        else { return }

        lastSeenRecId = sqlite3_column_int64(stmt, 0)
        didPrimeLastSeenId = true
        AppLog.shared.info("initialized, last rec_id = \(self.lastSeenRecId, privacy: .public)")
    }

    /// Returns `true` if at least one new notification was found.
    @discardableResult
    func fetchNewNotifications() -> Bool {
        guard let db else { return false }

        // Ensure we see the latest WAL frames by resetting the read transaction.
        sqlite3_exec(db, "BEGIN; END;", nil, nil, nil)

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
            let msg = String(cString: sqlite3_errmsg(db))
            AppLog.shared.notice("Failed to prepare query: \(msg, privacy: .public)")
            DispatchQueue.main.async { self.databaseStatus = .temporarilyUnavailable }
            closeDatabase()
            return false
        }

        sqlite3_bind_int64(stmt, 1, lastSeenRecId)
        var foundAny = false

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

            foundAny = true
            lastSeenRecId = recId
            AppLog.shared.debug("new notification from \(appIdentifier, privacy: .public): \(title, privacy: .public)")
            onNewNotification(record)
        }
        return foundAny
    }

    private func parsePlist(_ data: Data) -> (title: String, body: String) {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let req = plist["req"] as? [String: Any]
        else {
            AppLog.shared.debug("parsePlist failed — could not decode plist blob (\(data.count, privacy: .public) bytes)")
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
            AppLog.shared.notice("could not find NotificationCenter process")
            return
        }

        let element = AXUIElementCreateApplication(ncPid)
        var observer: AXObserver?

        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<NotificationMonitor>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                let found = monitor.fetchNewNotifications()
                if !found {
                    // DB row may not be committed yet; retry once after a short delay.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        monitor.fetchNewNotifications()
                    }
                }
            }
        }

        guard AXObserverCreate(ncPid, callback, &observer) == .success,
              let observer
        else {
            AppLog.shared.notice("failed to create AXObserver")
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.axObserver = observer

        AppLog.shared.info("accessibility observer started for NotificationCenter (pid \(ncPid, privacy: .public))")
    }

    private func findNotificationCenterPID() -> pid_t? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first { $0.bundleIdentifier == "com.apple.notificationcenterui" }?.processIdentifier
    }

    private func promptForAccessibility() {
        guard !Self.didPromptForAccessibilityThisSession else { return }
        Self.didPromptForAccessibilityThisSession = true
        AppLog.shared.info("accessibility not granted, requesting...")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Fallback Timer

    private func startFallbackTimer() {
        AppLog.shared.info("fallback poll timer started (2s interval)")
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.axObserver == nil && AXIsProcessTrusted() {
                AppLog.shared.info("fallback timer: AX now trusted, retrying observer setup")
                self.startAccessibilityObserver()
            }
            if self.db == nil {
                AppLog.shared.debug("fallback timer: DB not open, attempting reconnect")
                self.tryOpenDatabase()
                if self.db != nil {
                    self.initializeLastSeenIdIfNeeded()
                }
            }
            self.fetchNewNotifications()
        }
    }
}
