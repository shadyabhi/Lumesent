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
            guard let regex = Self.cachedRegex(needle) else { return false }
            let range = NSRange(haystack.startIndex..., in: haystack)
            return regex.firstMatch(in: haystack, range: range) != nil
        }
    }

    private static var regexCache: [String: NSRegularExpression] = [:]
    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        regexCache[pattern] = regex
        return regex
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
    var subtitleContains: String  // empty = match any subtitle
    var subtitleOperator: MatchOperator
    var bodyContains: String   // empty = match any body
    var bodyOperator: MatchOperator
    var isEnabled: Bool
    var label: String  // empty = no label
    var ruleDescription: String  // empty = no description
    var displayMode: AlertDisplayMode
    var focusSourceOnDismiss: Bool
    var cooldownSeconds: Double
    /// If the full-screen alert is still showing after this many seconds, send a mobile notification (when configured in Settings). `0` disables for this rule. JSON key unchanged for compatibility.
    var pushoverUnattendedAfterSeconds: Double

    /// Returns a copy with a new `id`, suitable for cloning.
    func cloned() -> FilterRule {
        FilterRule(appIdentifier: appIdentifier, appOperator: appOperator, titleContains: titleContains, titleOperator: titleOperator, subtitleContains: subtitleContains, subtitleOperator: subtitleOperator, bodyContains: bodyContains, bodyOperator: bodyOperator, isEnabled: isEnabled, label: label, ruleDescription: ruleDescription, displayMode: displayMode, focusSourceOnDismiss: focusSourceOnDismiss, cooldownSeconds: cooldownSeconds, pushoverUnattendedAfterSeconds: pushoverUnattendedAfterSeconds)
    }

    init(id: UUID = UUID(), appIdentifier: String = "", appOperator: MatchOperator = .contains, titleContains: String = "", titleOperator: MatchOperator = .contains, subtitleContains: String = "", subtitleOperator: MatchOperator = .contains, bodyContains: String = "", bodyOperator: MatchOperator = .contains, isEnabled: Bool = true, label: String = "", ruleDescription: String = "", displayMode: AlertDisplayMode = .defaultTimed, focusSourceOnDismiss: Bool = true, cooldownSeconds: Double = 60, pushoverUnattendedAfterSeconds: Double = 300) {
        self.id = id
        self.appIdentifier = appIdentifier
        self.appOperator = appOperator
        self.titleContains = titleContains
        self.titleOperator = titleOperator
        self.subtitleContains = subtitleContains
        self.subtitleOperator = subtitleOperator
        self.bodyContains = bodyContains
        self.bodyOperator = bodyOperator
        self.isEnabled = isEnabled
        self.label = label
        self.ruleDescription = ruleDescription
        self.displayMode = displayMode
        self.focusSourceOnDismiss = focusSourceOnDismiss
        self.cooldownSeconds = cooldownSeconds
        self.pushoverUnattendedAfterSeconds = pushoverUnattendedAfterSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appIdentifier = try c.decode(String.self, forKey: .appIdentifier)
        appOperator = try c.decodeIfPresent(MatchOperator.self, forKey: .appOperator) ?? .contains
        titleContains = try c.decodeIfPresent(String.self, forKey: .titleContains) ?? ""
        titleOperator = try c.decodeIfPresent(MatchOperator.self, forKey: .titleOperator) ?? .contains
        subtitleContains = try c.decodeIfPresent(String.self, forKey: .subtitleContains) ?? ""
        subtitleOperator = try c.decodeIfPresent(MatchOperator.self, forKey: .subtitleOperator) ?? .contains
        bodyContains = try c.decodeIfPresent(String.self, forKey: .bodyContains) ?? ""
        bodyOperator = try c.decodeIfPresent(MatchOperator.self, forKey: .bodyOperator) ?? .contains
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        ruleDescription = try c.decodeIfPresent(String.self, forKey: .ruleDescription) ?? ""
        displayMode = try c.decodeIfPresent(AlertDisplayMode.self, forKey: .displayMode) ?? .defaultTimed
        focusSourceOnDismiss = try c.decodeIfPresent(Bool.self, forKey: .focusSourceOnDismiss) ?? true
        cooldownSeconds = try c.decodeIfPresent(Double.self, forKey: .cooldownSeconds) ?? 60
        pushoverUnattendedAfterSeconds = try c.decodeIfPresent(Double.self, forKey: .pushoverUnattendedAfterSeconds) ?? 300
    }

    var isValid: Bool {
        !appIdentifier.isEmpty || !titleContains.isEmpty || !subtitleContains.isEmpty || !bodyContains.isEmpty
    }

    /// Sample notification for “Test this rule” previews.
    func previewNotificationRecord() -> NotificationRecord {
        let app = appIdentifier.isEmpty ? "com.apple.Terminal" : appIdentifier
        let t = titleContains.isEmpty ? "Preview: matched title" : titleContains
        let b = bodyContains.isEmpty ? "This is sample body text for your rule preview." : bodyContains
        return NotificationRecord(id: -42, appIdentifier: app, title: t, subtitle: "", body: b, deliveredDate: Date())
    }

    /// AND logic for non-empty filter fields. Does not check `isEnabled` or `isValid` (for previews).
    func matchesFields(of notification: NotificationRecord) -> Bool {
        if !appIdentifier.isEmpty {
            guard appOperator.matches(notification.appIdentifier, appIdentifier) else { return false }
        }
        if !titleContains.isEmpty {
            guard titleOperator.matches(notification.title, titleContains) else { return false }
        }
        if !subtitleContains.isEmpty {
            guard subtitleOperator.matches(notification.subtitle, subtitleContains) else { return false }
        }
        if !bodyContains.isEmpty {
            guard bodyOperator.matches(notification.body, bodyContains) else { return false }
        }
        return true
    }
}
