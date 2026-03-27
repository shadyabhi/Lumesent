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

    /// How many entries are retained on disk (UI may reference this in copy).
    static let storedEntryLimit = 1000
    private static let maxEntries = storedEntryLimit
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
        let snapshot = entries
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                AppLog.shared.error("Failed to save notification history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func load() {
        let url = fileURL
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let data = try? Data(contentsOf: url) else {
                AppLog.shared.info("no history file at \(url.path, privacy: .public), starting empty")
                return
            }
            guard let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
                AppLog.shared.error("failed to decode history from \(url.path, privacy: .public) (\(data.count, privacy: .public) bytes)")
                return
            }
            let trimmed = decoded.count > Self.maxEntries ? Array(decoded.suffix(Self.maxEntries)) : decoded
            AppLog.shared.info("loaded \(trimmed.count, privacy: .public) history entries (\(trimmed.filter(\.matched).count, privacy: .public) matched)")
            DispatchQueue.main.async {
                self.entries = trimmed
                if decoded.count > Self.maxEntries {
                    AppLog.shared.info("history trimmed from \(decoded.count, privacy: .public) to \(Self.maxEntries, privacy: .public)")
                    self.save()
                }
            }
        }
    }
}
