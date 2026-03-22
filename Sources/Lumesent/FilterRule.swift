import Foundation

enum MatchOperator: String, Codable, CaseIterable, Equatable {
    case contains = "contains"
    case startsWith = "starts_with"
    case equals = "equals"
    case regex = "regex"

    func matches(_ haystack: String, _ needle: String) -> Bool {
        switch self {
        case .contains:
            return haystack.localizedCaseInsensitiveContains(needle)
        case .startsWith:
            return haystack.range(of: needle, options: [.anchored, .caseInsensitive], range: nil, locale: .current) != nil
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
    var appOperator: MatchOperator
    var titleContains: String  // empty = match any title
    var titleOperator: MatchOperator
    var bodyContains: String   // empty = match any body
    var bodyOperator: MatchOperator
    var isEnabled: Bool
    var label: String  // empty = no label
    var ruleDescription: String  // empty = no description
    var displayMode: AlertDisplayMode
    var focusSourceOnDismiss: Bool

    init(id: UUID = UUID(), appIdentifier: String = "", appOperator: MatchOperator = .contains, titleContains: String = "", titleOperator: MatchOperator = .contains, bodyContains: String = "", bodyOperator: MatchOperator = .contains, isEnabled: Bool = true, label: String = "", ruleDescription: String = "", displayMode: AlertDisplayMode = .defaultTimed, focusSourceOnDismiss: Bool = true) {
        self.id = id
        self.appIdentifier = appIdentifier
        self.appOperator = appOperator
        self.titleContains = titleContains
        self.titleOperator = titleOperator
        self.bodyContains = bodyContains
        self.bodyOperator = bodyOperator
        self.isEnabled = isEnabled
        self.label = label
        self.ruleDescription = ruleDescription
        self.displayMode = displayMode
        self.focusSourceOnDismiss = focusSourceOnDismiss
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appIdentifier = try c.decode(String.self, forKey: .appIdentifier)
        appOperator = try c.decodeIfPresent(MatchOperator.self, forKey: .appOperator) ?? .contains
        titleContains = try c.decode(String.self, forKey: .titleContains)
        titleOperator = try c.decode(MatchOperator.self, forKey: .titleOperator)
        bodyContains = try c.decode(String.self, forKey: .bodyContains)
        bodyOperator = try c.decode(MatchOperator.self, forKey: .bodyOperator)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        label = try c.decode(String.self, forKey: .label)
        ruleDescription = try c.decodeIfPresent(String.self, forKey: .ruleDescription) ?? ""
        displayMode = try c.decode(AlertDisplayMode.self, forKey: .displayMode)
        focusSourceOnDismiss = try c.decodeIfPresent(Bool.self, forKey: .focusSourceOnDismiss) ?? true
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

    /// AND logic for non-empty filter fields. Does not check `isEnabled` or `isValid` (for previews).
    func matchesFields(of notification: NotificationRecord) -> Bool {
        if !appIdentifier.isEmpty {
            guard appOperator.matches(notification.appIdentifier, appIdentifier) else { return false }
        }
        if !titleContains.isEmpty {
            guard titleOperator.matches(notification.title, titleContains) else { return false }
        }
        if !bodyContains.isEmpty {
            guard bodyOperator.matches(notification.body, bodyContains) else { return false }
        }
        return true
    }
}
