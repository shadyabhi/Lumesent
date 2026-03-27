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

    func save() {
        FileLocations.saveJSON(rules, to: fileURL, label: "rules")
    }

    func exportRulesJSON() throws -> Data {
        try JSONEncoder().encode(rules)
    }

    func importRules(from data: Data) throws {
        let imported = try JSONDecoder().decode([FilterRule].self, from: data)
        AppLog.shared.info("imported \(imported.count, privacy: .public) rules")
        rules = imported
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLog.shared.info("no rules file at \(self.fileURL.path, privacy: .public), starting with empty rules")
            return
        }
        guard let decoded = try? JSONDecoder().decode([FilterRule].self, from: data) else {
            AppLog.shared.error("failed to decode rules from \(self.fileURL.path, privacy: .public) (\(data.count, privacy: .public) bytes)")
            return
        }
        rules = decoded
        AppLog.shared.info("loaded \(decoded.count, privacy: .public) rules from \(self.fileURL.path, privacy: .public)")
    }
}
