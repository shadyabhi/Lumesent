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

    /// Loads a JSON array with lossy per-element decoding: tries a fast full-array decode first,
    /// then falls back to per-element recovery so one corrupt entry doesn't discard the entire file.
    static func loadJSONArray<T: Decodable>(from url: URL, label: String) -> [T]? {
        guard let data = try? Data(contentsOf: url) else {
            AppLog.shared.info("no \(label, privacy: .public) file at \(url.path, privacy: .public), starting empty")
            return nil
        }
        if let full = try? JSONDecoder().decode([T].self, from: data) {
            return full
        }
        guard let elements = try? JSONDecoder().decode([LossyCodableArray<T>.Element].self, from: data) else {
            AppLog.shared.error("failed to decode \(label, privacy: .public) from \(url.path, privacy: .public) (\(data.count, privacy: .public) bytes)")
            return nil
        }
        let recovered = elements.compactMap(\.value)
        let failed = elements.count - recovered.count
        AppLog.shared.error("\(label, privacy: .public): recovered \(recovered.count, privacy: .public) entries, skipped \(failed, privacy: .public) corrupt")
        return recovered
    }
}
