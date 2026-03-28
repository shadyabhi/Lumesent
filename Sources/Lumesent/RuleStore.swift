import Foundation

class RuleStore: ObservableObject {
    @Published var rules: [FilterRule] = []

    private let fileURL: URL

    init() {
        fileURL = FileLocations.appSupportDirectory.appendingPathComponent("rules.json")
        load()
    }

    var sortedLabels: [String] {
        Set(rules.compactMap { $0.label.isEmpty ? nil : $0.label }).sorted()
    }

    func save(feedbackMessage: String = "Saved") {
        FileLocations.saveJSON(rules, to: fileURL, label: "rules")
        let notify = {
            NotificationCenter.default.post(name: .lumesentDidPersistUserSettings, object: feedbackMessage)
        }
        if Thread.isMainThread {
            notify()
        } else {
            DispatchQueue.main.async(execute: notify)
        }
    }

    func exportRulesJSON() throws -> Data {
        try JSONEncoder().encode(rules)
    }

    func importRules(from data: Data) throws {
        let imported = try JSONDecoder().decode([FilterRule].self, from: data)
        AppLog.shared.info("imported \(imported.count, privacy: .public) rules")
        rules = imported
        save(feedbackMessage: "Rules imported")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLog.shared.info("no rules file at \(self.fileURL.path, privacy: .public), starting with empty rules")
            return
        }
        // Try decoding the full array first (fast path).
        if let decoded = try? JSONDecoder().decode([FilterRule].self, from: data) {
            rules = decoded
            AppLog.shared.info("loaded \(decoded.count, privacy: .public) rules from \(self.fileURL.path, privacy: .public)")
            return
        }
        // Fall back to per-element decoding so one corrupt rule doesn't lose all rules.
        guard let jsonArray = try? JSONDecoder().decode([LossyCodableArray<FilterRule>.Element].self, from: data) else {
            AppLog.shared.error("failed to decode rules from \(self.fileURL.path, privacy: .public) (\(data.count, privacy: .public) bytes)")
            return
        }
        var recovered: [FilterRule] = []
        var failed = 0
        for element in jsonArray {
            if let rule = element.value {
                recovered.append(rule)
            } else {
                failed += 1
            }
        }
        rules = recovered
        AppLog.shared.error("loaded \(recovered.count, privacy: .public) rules, skipped \(failed, privacy: .public) corrupt entries from \(self.fileURL.path, privacy: .public)")
        if !recovered.isEmpty {
            save(feedbackMessage: "Rules recovered")
        }
    }
}
