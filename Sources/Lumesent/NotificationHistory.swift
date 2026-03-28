import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    let appIdentifier: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    var matched: Bool = false
    /// All rule IDs that matched this notification (may be multiple).
    var matchedRuleIds: [UUID] = []
    var cooldownSuppressed: Bool = false
    var sourceVisibleSuppressed: Bool = false

    /// First matched rule ID, for backwards compatibility.
    var matchedRuleId: UUID? { matchedRuleIds.first }

    /// True when matched and a visible alert was actually shown (not cooldown- or source-suppressed).
    var isDisplayableMatch: Bool {
        matched && !cooldownSuppressed && !sourceVisibleSuppressed
    }

    init(appIdentifier: String, appName: String, title: String, subtitle: String = "", body: String, date: Date, matched: Bool = false, matchedRuleIds: [UUID] = [], cooldownSuppressed: Bool = false, sourceVisibleSuppressed: Bool = false) {
        self.id = UUID()
        self.appIdentifier = appIdentifier
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.date = date
        self.matched = matched
        self.matchedRuleIds = matchedRuleIds
        self.cooldownSuppressed = cooldownSuppressed
        self.sourceVisibleSuppressed = sourceVisibleSuppressed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appIdentifier, forKey: .appIdentifier)
        try container.encode(appName, forKey: .appName)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(body, forKey: .body)
        try container.encode(date, forKey: .date)
        try container.encode(matched, forKey: .matched)
        try container.encode(matchedRuleIds, forKey: .matchedRuleIds)
        try container.encode(cooldownSuppressed, forKey: .cooldownSuppressed)
        try container.encode(sourceVisibleSuppressed, forKey: .sourceVisibleSuppressed)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appIdentifier = try c.decode(String.self, forKey: .appIdentifier)
        appName = try c.decode(String.self, forKey: .appName)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        body = try c.decode(String.self, forKey: .body)
        date = try c.decode(Date.self, forKey: .date)
        matched = try c.decodeIfPresent(Bool.self, forKey: .matched) ?? false
        // Migrate: prefer new matchedRuleIds array, fall back to legacy matchedRuleId scalar
        if let ids = try c.decodeIfPresent([UUID].self, forKey: .matchedRuleIds) {
            matchedRuleIds = ids
        } else if let legacyId = try c.decodeIfPresent(UUID.self, forKey: .matchedRuleId) {
            matchedRuleIds = [legacyId]
        } else {
            matchedRuleIds = []
        }
        cooldownSuppressed = try c.decodeIfPresent(Bool.self, forKey: .cooldownSuppressed) ?? false
        sourceVisibleSuppressed = try c.decodeIfPresent(Bool.self, forKey: .sourceVisibleSuppressed) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, appIdentifier, appName, title, subtitle, body, date, matched
        case matchedRuleIds, matchedRuleId
        case cooldownSuppressed, sourceVisibleSuppressed
    }
}

class NotificationHistory: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    static let maxEntries = 1000
    private let fileURL: URL
    private var saveTimer: Timer?

    init() {
        fileURL = FileLocations.appSupportDirectory.appendingPathComponent("history.json")
        load()
    }

    func record(_ notification: NotificationRecord, matched: Bool, matchedRuleIds: [UUID] = [], cooldownSuppressed: Bool = false, sourceVisibleSuppressed: Bool = false) {
        let entry = HistoryEntry(
            appIdentifier: notification.appIdentifier,
            appName: notification.appName,
            title: notification.title,
            subtitle: notification.subtitle,
            body: notification.body,
            date: min(notification.deliveredDate, Date()),
            matched: matched,
            matchedRuleIds: matchedRuleIds,
            cooldownSuppressed: cooldownSuppressed,
            sourceVisibleSuppressed: sourceVisibleSuppressed
        )
        AppLog.shared.info("history: recording app=\(notification.appName, privacy: .public) (\(notification.appIdentifier, privacy: .public)) title=\(notification.title, privacy: .public) subtitle=\(notification.subtitle, privacy: .public) time=\(notification.deliveredDate.description, privacy: .public) matched=\(matched, privacy: .public)")
        entries.append(entry)

        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }

        debouncedSave()
    }

    func clearAll() {
        entries.removeAll()
        saveTimer?.invalidate()
        saveTimer = nil
        save()
        let notify = {
            NotificationCenter.default.post(name: .lumesentDidPersistUserSettings, object: "History cleared")
        }
        if Thread.isMainThread {
            notify()
        } else {
            DispatchQueue.main.async(execute: notify)
        }
    }

    /// Coalesces rapid save calls into a single write after 0.5s of inactivity.
    private func debouncedSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.save()
        }
    }

    /// Returns matched entries for a specific rule, most recent first.
    func matchedEntries(for ruleId: UUID) -> [HistoryEntry] {
        entries.filter { $0.matchedRuleIds.contains(ruleId) }.reversed()
    }

    /// Returns suggestions for a given field, deduplicated by value, most recent first.
    /// Each suggestion carries the most recent full entry for preview.
    func suggestions(for field: SuggestionField, matching query: String) -> [Suggestion] {
        Self.computeSuggestions(entries: entries, field: field, matching: query)
    }

    /// Pure computation on a snapshot — safe to call from any thread.
    static func computeSuggestions(entries: [HistoryEntry], field: SuggestionField, matching query: String) -> [Suggestion] {
        var latest: [String: HistoryEntry] = [:]
        for entry in entries {
            let value = field.value(from: entry)
            if value.isEmpty { continue }
            if let existing = latest[value] {
                if entry.date > existing.date { latest[value] = entry }
            } else {
                latest[value] = entry
            }
        }

        var results = latest.values.map { Suggestion(displayValue: field.value(from: $0), entry: $0) }

        if !query.isEmpty {
            let q = query.lowercased()
            results = results.filter { $0.displayValue.lowercased().contains(q) && $0.displayValue != query }
        }

        results.sort { $0.entry.date > $1.entry.date }
        return results
    }
}

enum SuggestionField {
    case appIdentifier, title, subtitle, body

    func value(from entry: HistoryEntry) -> String {
        switch self {
        case .appIdentifier: return entry.appIdentifier
        case .title: return entry.title
        case .subtitle: return entry.subtitle
        case .body: return entry.body
        }
    }
}

struct Suggestion: Identifiable {
    var id: String { displayValue }
    let displayValue: String
    let entry: HistoryEntry
}

// MARK: - Persistence

private extension NotificationHistory {
    func save() {
        FileLocations.saveJSON(entries, to: fileURL, label: "notification history")
    }

    func load() {
        let url = fileURL
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let data = try? Data(contentsOf: url) else {
                AppLog.shared.info("no history file at \(url.path, privacy: .public), starting empty")
                return
            }
            // Try fast-path full-array decode, fall back to per-element lossy decode.
            let decoded: [HistoryEntry]
            if let full = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
                decoded = full
            } else if let elements = try? JSONDecoder().decode([LossyCodableArray<HistoryEntry>.Element].self, from: data) {
                let recovered = elements.compactMap(\.value)
                let failed = elements.count - recovered.count
                AppLog.shared.error("history: recovered \(recovered.count, privacy: .public) entries, skipped \(failed, privacy: .public) corrupt")
                decoded = recovered
            } else {
                AppLog.shared.error("failed to decode history from \(url.path, privacy: .public) (\(data.count, privacy: .public) bytes)")
                return
            }
            let trimmed = decoded.count > Self.maxEntries ? Array(decoded.suffix(Self.maxEntries)) : decoded
            let needsSave = decoded.count > Self.maxEntries || decoded.count != trimmed.count
            AppLog.shared.info("loaded \(trimmed.count, privacy: .public) history entries (\(trimmed.filter(\.matched).count, privacy: .public) matched)")
            DispatchQueue.main.async {
                self.entries = trimmed
                if needsSave {
                    AppLog.shared.info("history trimmed from \(decoded.count, privacy: .public) to \(Self.maxEntries, privacy: .public)")
                    self.save()
                }
            }
        }
    }
}
