import Foundation

enum FileLocations {
    static let appSupportDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lumesent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let defaultSocketPath: String = appSupportDirectory.appendingPathComponent("notify.sock").path

    static func saveJSON<T: Encodable>(_ value: T, to url: URL, label: String) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(value)
                try data.write(to: url, options: .atomic)
            } catch {
                AppLog.shared.error("Failed to save \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
