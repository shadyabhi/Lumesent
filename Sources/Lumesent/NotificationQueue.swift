import Foundation

/// A notification that was queued while alerts were paused.
struct QueuedNotification: Codable, Identifiable {
    var id: UUID = UUID()
    let appIdentifier: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    /// Matched rule IDs at the time of queuing (empty for external notifications).
    let matchedRuleIds: [UUID]
    /// Non-nil when the notification came from the external socket (CLI).
    let externalNotification: ExternalNotification?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appIdentifier = try c.decode(String.self, forKey: .appIdentifier)
        appName = try c.decode(String.self, forKey: .appName)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        date = try c.decode(Date.self, forKey: .date)
        matchedRuleIds = try c.decodeIfPresent([UUID].self, forKey: .matchedRuleIds) ?? []
        externalNotification = try c.decodeIfPresent(ExternalNotification.self, forKey: .externalNotification)
    }
}

/// Durable queue for notifications received while alerts are paused.
/// Persisted to `queue.json` in the app support directory.
class NotificationQueue: ObservableObject {
    @Published private(set) var entries: [QueuedNotification] = []

    private let fileURL: URL
    private var saveTimer: Timer?

    init() {
        fileURL = FileLocations.appSupportDirectory.appendingPathComponent("queue.json")
        load()
    }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    func enqueue(record: NotificationRecord, matchedRuleIds: [UUID], externalNotification: ExternalNotification? = nil) {
        let entry = QueuedNotification(
            appIdentifier: record.appIdentifier,
            appName: record.appName,
            title: record.title,
            subtitle: record.subtitle,
            body: record.body,
            date: record.deliveredDate,
            matchedRuleIds: matchedRuleIds,
            externalNotification: externalNotification
        )
        entries.append(entry)
        debouncedSave()
        AppLog.shared.info("queued notification (paused): \(record.title, privacy: .public) (\(self.entries.count, privacy: .public) in queue)")
    }

    /// Removes and returns all queued notifications, clearing the persisted file.
    func drainAll() -> [QueuedNotification] {
        let drained = entries
        entries.removeAll()
        saveTimer?.invalidate()
        saveTimer = nil
        save()
        return drained
    }

    private func debouncedSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.save()
        }
    }

    private func save() {
        FileLocations.saveJSON(entries, to: fileURL, label: "notification queue")
    }

    private func load() {
        guard let decoded: [QueuedNotification] = FileLocations.loadJSONArray(from: fileURL, label: "queue") else { return }
        entries = decoded
        if !entries.isEmpty {
            AppLog.shared.info("loaded \(self.entries.count, privacy: .public) queued notifications from disk")
        }
    }
}

// MARK: - Memberwise init (kept out of the auto-generated Codable path)

extension QueuedNotification {
    init(appIdentifier: String, appName: String, title: String, subtitle: String, body: String, date: Date, matchedRuleIds: [UUID], externalNotification: ExternalNotification?) {
        self.id = UUID()
        self.appIdentifier = appIdentifier
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.date = date
        self.matchedRuleIds = matchedRuleIds
        self.externalNotification = externalNotification
    }
}
