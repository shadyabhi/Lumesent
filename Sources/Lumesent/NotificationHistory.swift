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
    /// Optional UI/persistence label (e.g. `speedy_dismiss` when the system removed the notification before we read it).
    var historyLabel: String?

    var displayAppName: String { appName.isEmpty ? appIdentifier : appName }

    /// First matched rule ID, for backwards compatibility.
    var matchedRuleId: UUID? { matchedRuleIds.first }

    /// True when matched and a visible alert was actually shown (not cooldown- or source-suppressed).
    var isDisplayableMatch: Bool {
        matched && !cooldownSuppressed && !sourceVisibleSuppressed
    }

    init(appIdentifier: String, appName: String, title: String, subtitle: String = "", body: String, date: Date, matched: Bool = false, matchedRuleIds: [UUID] = [], cooldownSuppressed: Bool = false, sourceVisibleSuppressed: Bool = false, historyLabel: String? = nil) {
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
        self.historyLabel = historyLabel
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
        if let ids = try c.decodeIfPresent([UUID].self, forKey: .matchedRuleIds) {
            matchedRuleIds = ids
        } else {
            // Migrate from legacy single-rule format
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            if let legacyId = try legacy.decodeIfPresent(UUID.self, forKey: .matchedRuleId) {
                matchedRuleIds = [legacyId]
            } else {
                matchedRuleIds = []
            }
        }
        cooldownSuppressed = try c.decodeIfPresent(Bool.self, forKey: .cooldownSuppressed) ?? false
        sourceVisibleSuppressed = try c.decodeIfPresent(Bool.self, forKey: .sourceVisibleSuppressed) ?? false
        historyLabel = try c.decodeIfPresent(String.self, forKey: .historyLabel)
    }

    private enum CodingKeys: String, CodingKey {
        case id, appIdentifier, appName, title, subtitle, body, date, matched
        case matchedRuleIds
        case cooldownSuppressed, sourceVisibleSuppressed
        case historyLabel
    }

    /// Legacy key used only for migration from single-rule format.
    private enum LegacyCodingKeys: String, CodingKey {
        case matchedRuleId
    }
}

/// Quick filter chips in Settings → History (same buckets as row badges in `HistoryRow`).
enum HistoryQuickFilter: Int, CaseIterable, Identifiable {
    case all
    case matched
    case cooldown
    case downgraded
    case paused
    case speedyDismiss
    case unmatched

    var id: Int { rawValue }

    var chipTitle: String {
        switch self {
        case .all: return "All"
        case .matched: return "Matched"
        case .cooldown: return "Cooldown"
        case .downgraded: return "Downgraded"
        case .paused: return "Paused"
        case .speedyDismiss: return "Speedy dismiss"
        case .unmatched: return "Unmatched"
        }
    }

    var chipIcon: String? {
        switch self {
        case .all: return nil
        case .matched: return "bell.fill"
        case .cooldown: return "clock.arrow.circlepath"
        case .downgraded: return "arrow.down.right.circle"
        case .paused: return "pause.circle"
        case .speedyDismiss: return "bolt.fill"
        case .unmatched: return "bell.slash"
        }
    }

    /// Shown as the hover tooltip for the filter chip (Settings → History).
    var chipHelp: String {
        switch self {
        case .all:
            return "Show every stored notification, newest first."
        case .matched:
            return "Only entries where a rule matched and an alert was shown (not cooldown- or source-suppressed)."
        case .cooldown:
            return "Only entries that matched a rule but were skipped because that rule’s cooldown had not elapsed."
        case .downgraded:
            return "Only entries where a full-screen alert was downgraded or suppressed because the source window or pane was already visible."
        case .paused:
            return "Only entries that matched a rule but arrived while alerts were paused. These are replayed when alerts resume."
        case .speedyDismiss:
            return "Only placeholder entries for notifications the system removed from the database before Lumesent could read them."
        case .unmatched:
            return "Only notifications that did not match any enabled rule."
        }
    }
}

extension HistoryEntry {
    /// Mutually exclusive category for quick filters (priority matches `HistoryRow` badge order).
    var quickFilterCategory: HistoryQuickFilter {
        if historyLabel == "speedy_dismiss" { return .speedyDismiss }
        if historyLabel == "paused" { return .paused }
        if sourceVisibleSuppressed { return .downgraded }
        if cooldownSuppressed { return .cooldown }
        if isDisplayableMatch { return .matched }
        return .unmatched
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

    func record(_ notification: NotificationRecord, matched: Bool, matchedRuleIds: [UUID] = [], cooldownSuppressed: Bool = false, sourceVisibleSuppressed: Bool = false, historyLabel: String? = nil) {
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
            sourceVisibleSuppressed: sourceVisibleSuppressed,
            historyLabel: historyLabel
        )
        entries.append(entry)

        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }

        debouncedSave()
    }

    /// Skip extra rows when Notification Center fires multiple AX callbacks for one user action (window created + destroyed, etc.).
    private static let speedyDismissCoalesceInterval: TimeInterval = 3.0

    /// Logged when AX indicated Notification Center activity but no `record` row was read after burst retries (often dismissed before read).
    /// `axNotificationName` / `axElementLabel` come from the Accessibility callback (e.g. window created vs destroyed; optional UI string).
    func recordSpeedyDismissPlaceholder(axNotificationName: String, axElementLabel: String?) {
        if let last = entries.last,
           last.historyLabel == "speedy_dismiss",
           Date().timeIntervalSince(last.date) < Self.speedyDismissCoalesceInterval {
            return
        }
        let ncBundle = "com.apple.notificationcenterui"
        let appName = AppNameCache.shared.name(for: ncBundle)
        let subtitle = "Trigger: \(Self.humanizeAXNotificationName(axNotificationName))"
        var body = "The system removed this notification from the database before Lumesent could capture it."
        if let hint = axElementLabel, !hint.isEmpty {
            body = "Accessibility: \(hint)\n\n\(body)"
        }
        let entry = HistoryEntry(
            appIdentifier: ncBundle,
            appName: appName,
            title: "Notification dismissed before read",
            subtitle: subtitle,
            body: body,
            date: Date(),
            matched: false,
            matchedRuleIds: [],
            historyLabel: "speedy_dismiss"
        )
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }
        debouncedSave()
    }

    private static func humanizeAXNotificationName(_ raw: String) -> String {
        switch raw {
        case "AXWindowCreated": return "Window created"
        case "AXUIElementDestroyed": return "UI element removed"
        default: return raw
        }
    }

    func clearAll() {
        entries.removeAll()
        saveTimer?.invalidate()
        saveTimer = nil
        save()
        NotificationCenter.default.postOnMain(name: .lumesentDidPersistUserSettings, object: "History cleared")
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
            guard let decoded: [HistoryEntry] = FileLocations.loadJSONArray(from: url, label: "history") else { return }
            let trimmed = decoded.count > Self.maxEntries ? Array(decoded.suffix(Self.maxEntries)) : decoded
            let needsSave = decoded.count > Self.maxEntries
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
