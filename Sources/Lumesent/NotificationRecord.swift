import AppKit

struct NotificationRecord: Identifiable {
    let id: Int64  // rec_id from DB (negative for external notifications)
    let appIdentifier: String
    let title: String
    let body: String
    let deliveredDate: Date
    private let overrideAppName: String?

    init(id: Int64, appIdentifier: String, title: String, body: String, deliveredDate: Date) {
        self.id = id
        self.appIdentifier = appIdentifier
        self.title = title
        self.body = body
        self.deliveredDate = deliveredDate
        self.overrideAppName = nil
    }

    var appName: String {
        overrideAppName ?? AppNameCache.shared.name(for: appIdentifier)
    }

    private static var externalIdCounter: Int64 = 0

    static func fromExternal(_ ext: ExternalNotification) -> NotificationRecord {
        externalIdCounter -= 1
        return NotificationRecord(
            id: externalIdCounter,
            appIdentifier: "external",
            title: ext.title,
            body: ext.resolvedBody,
            deliveredDate: Date(),
            overrideAppName: ext.resolvedAppName
        )
    }

    private init(id: Int64, appIdentifier: String, title: String, body: String, deliveredDate: Date, overrideAppName: String?) {
        self.id = id
        self.appIdentifier = appIdentifier
        self.title = title
        self.body = body
        self.deliveredDate = deliveredDate
        self.overrideAppName = overrideAppName
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
