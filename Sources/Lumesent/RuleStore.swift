import Foundation

class RuleStore: ObservableObject {
    @Published var rules: [FilterRule] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lumesent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("rules.json")
        load()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(rules)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.shared.error("Failed to save rules: \(error.localizedDescription, privacy: .public)")
        }
    }

    func exportRulesJSON() throws -> Data {
        try JSONEncoder().encode(rules)
    }

    func importRules(from data: Data) throws {
        let imported = try JSONDecoder().decode([FilterRule].self, from: data)
        rules = imported
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FilterRule].self, from: data)
        else { return }
        rules = decoded
    }
}
