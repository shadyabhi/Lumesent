import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    let appIdentifier: String
    let appName: String
    let title: String
    let body: String
    let date: Date
    var matched: Bool = false
}

class NotificationHistory: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lumesent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func record(_ notification: NotificationRecord, matched: Bool) {
        let entry = HistoryEntry(
            appIdentifier: notification.appIdentifier,
            appName: notification.appName,
            title: notification.title,
            body: notification.body,
            date: notification.deliveredDate,
            matched: matched
        )
        entries.append(entry)

        // Cap at 500 entries
        if entries.count > 500 {
            entries = Array(entries.suffix(500))
        }

        save()
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
    case appIdentifier, title, body

    func value(from entry: HistoryEntry) -> String {
        switch self {
        case .appIdentifier: return entry.appIdentifier
        case .title: return entry.title
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
            print("Failed to save notification history: \(error)")
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
