import Foundation

enum MatchOperator: String, Codable, CaseIterable, Equatable {
    case contains = "contains"
    case regex = "regex"
    case equals = "equals"

    func matches(_ haystack: String, _ needle: String) -> Bool {
        switch self {
        case .contains:
            return haystack.localizedCaseInsensitiveContains(needle)
        case .equals:
            return haystack.caseInsensitiveCompare(needle) == .orderedSame
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: needle, options: .caseInsensitive) else {
                return false
            }
            let range = NSRange(haystack.startIndex..., in: haystack)
            return regex.firstMatch(in: haystack, range: range) != nil
        }
    }
}

enum AlertDisplayMode: Codable, Equatable {
    case timed(seconds: Double)
    case sticky

    static let defaultTimed = AlertDisplayMode.timed(seconds: 8)

    var isSticky: Bool {
        if case .sticky = self { return true }
        return false
    }

    var timeoutSeconds: Double? {
        if case .timed(let seconds) = self { return seconds }
        return nil
    }
}

struct FilterRule: Identifiable, Codable, Equatable {
    let id: UUID
    var appIdentifier: String  // empty = match any app
    var titleContains: String  // empty = match any title
    var titleOperator: MatchOperator
    var bodyContains: String   // empty = match any body
    var bodyOperator: MatchOperator
    var isEnabled: Bool
    var label: String  // empty = no label
    var displayMode: AlertDisplayMode

    init(id: UUID = UUID(), appIdentifier: String = "", titleContains: String = "", titleOperator: MatchOperator = .contains, bodyContains: String = "", bodyOperator: MatchOperator = .contains, isEnabled: Bool = true, label: String = "", displayMode: AlertDisplayMode = .defaultTimed) {
        self.id = id
        self.appIdentifier = appIdentifier
        self.titleContains = titleContains
        self.titleOperator = titleOperator
        self.bodyContains = bodyContains
        self.bodyOperator = bodyOperator
        self.isEnabled = isEnabled
        self.label = label
        self.displayMode = displayMode
    }

    var isValid: Bool {
        !appIdentifier.isEmpty || !titleContains.isEmpty || !bodyContains.isEmpty
    }

    /// Sample notification for “Test this rule” previews.
    func previewNotificationRecord() -> NotificationRecord {
        let app = appIdentifier.isEmpty ? "com.apple.Terminal" : appIdentifier
        let t = titleContains.isEmpty ? "Preview: matched title" : titleContains
        let b = bodyContains.isEmpty ? "This is sample body text for your rule preview." : bodyContains
        return NotificationRecord(id: -42, appIdentifier: app, title: t, body: b, deliveredDate: Date())
    }
}
