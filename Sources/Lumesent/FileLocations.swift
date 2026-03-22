import Foundation

enum FileLocations {
    static let appSupportDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lumesent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let defaultSocketPath: String = appSupportDirectory.appendingPathComponent("notify.sock").path
}
