import AppKit

struct NotificationRecord: Identifiable {
    let id: Int64  // rec_id from DB
    let appIdentifier: String
    let title: String
    let body: String
    let deliveredDate: Date

    var appName: String {
        AppNameCache.shared.name(for: appIdentifier)
    }
}

final class AppNameCache {
    static let shared = AppNameCache()
    private var cache: [String: String] = [:]

    private init() {}

    func name(for bundleIdentifier: String) -> String {
        if let cached = cache[bundleIdentifier] {
            return cached
        }

        let name = resolveName(bundleIdentifier)
        cache[bundleIdentifier] = name
        return name
    }

    private func resolveName(_ bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let bundle = Bundle(url: url),
              let name = bundle.infoDictionary?["CFBundleName"] as? String
        else {
            // Fall back to last component of bundle ID
            return bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier
        }
        return name
    }
}
