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
        NotificationCenter.default.postOnMain(name: .lumesentDidPersistUserSettings, object: feedbackMessage)
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
        guard let loaded: [FilterRule] = FileLocations.loadJSONArray(from: fileURL, label: "rules") else { return }
        rules = loaded
        AppLog.shared.info("loaded \(loaded.count, privacy: .public) rules from \(self.fileURL.path, privacy: .public)")
    }
}
