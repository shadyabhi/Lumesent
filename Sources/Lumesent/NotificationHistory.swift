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
    var matchedRuleId: UUID? = nil
    var cooldownSuppressed: Bool = false
    var sourceVisibleSuppressed: Bool = false

    /// True when matched and a visible alert was actually shown (not cooldown- or source-suppressed).
    var isDisplayableMatch: Bool {
        matched && !cooldownSuppressed && !sourceVisibleSuppressed
    }

    init(appIdentifier: String, appName: String, title: String, subtitle: String = "", body: String, date: Date, matched: Bool = false, matchedRuleId: UUID? = nil, cooldownSuppressed: Bool = false, sourceVisibleSuppressed: Bool = false) {
        self.id = UUID()
        self.appIdentifier = appIdentifier
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.date = date
        self.matched = matched
        self.matchedRuleId = matchedRuleId
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
        matchedRuleId = try c.decodeIfPresent(UUID.self, forKey: .matchedRuleId)
        cooldownSuppressed = try c.decodeIfPresent(Bool.self, forKey: .cooldownSuppressed) ?? false
        sourceVisibleSuppressed = try c.decodeIfPresent(Bool.self, forKey: .sourceVisibleSuppressed) ?? false
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

    func record(_ notification: NotificationRecord, matched: Bool, matchedRuleId: UUID? = nil, cooldownSuppressed: Bool = false, sourceVisibleSuppressed: Bool = false) {
        let entry = HistoryEntry(
            appIdentifier: notification.appIdentifier,
            appName: notification.appName,
            title: notification.title,
            subtitle: notification.subtitle,
            body: notification.body,
            date: min(notification.deliveredDate, Date()),
            matched: matched,
            matchedRuleId: matchedRuleId,
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

    /// Most recent matched notifications (any rule), for menu previews.
    func recentMatches(count: Int) -> [HistoryEntry] {
        Array(entries.filter(\.matched).sorted { $0.date > $1.date }.prefix(count))
    }

    /// Returns matched entries for a specific rule, most recent first.
    func matchedEntries(for ruleId: UUID) -> [HistoryEntry] {
        entries.filter { $0.matchedRuleId == ruleId }.reversed()
    }

    /// Returns suggestions for a given field, deduplicated by value, most recent first.
    /// Each suggestion carries the most recent full entry for preview.
    func suggestions(for field: SuggestionField, matching query: String) -> [Suggestion] {
        // Group entries by the target field value, keep most recent per unique value
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

        var results = latest.values.map { entry in
            Suggestion(displayValue: field.value(from: entry), entry: entry)
        }

        // Filter by query
        if !query.isEmpty {
            let q = query.lowercased()
            results = results.filter { $0.displayValue.lowercased().contains(q) && $0.displayValue != query }
        }

        // Sort most recent first
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
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.shared.error("Failed to save notification history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLog.shared.info("no history file at \(self.fileURL.path, privacy: .public), starting empty")
            return
        }
        guard let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            AppLog.shared.error("failed to decode history from \(self.fileURL.path, privacy: .public) (\(data.count, privacy: .public) bytes)")
            return
        }
        entries = decoded.count > Self.maxEntries ? Array(decoded.suffix(Self.maxEntries)) : decoded
        AppLog.shared.info("loaded \(self.entries.count, privacy: .public) history entries (\(self.entries.filter(\.matched).count, privacy: .public) matched)")
        if decoded.count > Self.maxEntries {
            AppLog.shared.info("history trimmed from \(decoded.count, privacy: .public) to \(Self.maxEntries, privacy: .public)")
            save()
        }
    }
}
