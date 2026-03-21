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
            print("Failed to save rules: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FilterRule].self, from: data)
        else { return }
        rules = decoded
    }
}
