import Foundation

class FilterEngine {
    var rules: [FilterRule]

    init(rules: [FilterRule]) {
        self.rules = rules
    }

    func matchingRule(for notification: NotificationRecord) -> FilterRule? {
        let enabledRules = rules.filter { $0.isEnabled && $0.isValid }
        AppLog.shared.debug("evaluating \(enabledRules.count, privacy: .public) enabled rules against app=\(notification.appIdentifier, privacy: .public)")
        for rule in enabledRules {
            if matchesRule(notification, rule) {
                return rule
            }
        }
        return nil
    }

    private func matchesRule(_ n: NotificationRecord, _ r: FilterRule) -> Bool {
        // All non-empty fields must match (AND logic)
        if !r.appIdentifier.isEmpty {
            guard r.appOperator.matches(n.appIdentifier, r.appIdentifier) else {
                AppLog.shared.debug("rule \(r.label, privacy: .public) (\(r.id.uuidString.prefix(8), privacy: .public)): app mismatch — op=\(r.appOperator.rawValue, privacy: .public) pattern=\(r.appIdentifier, privacy: .public) got=\(n.appIdentifier, privacy: .public)")
                return false
            }
        }
        if !r.titleContains.isEmpty {
            guard r.titleOperator.matches(n.title, r.titleContains) else {
                AppLog.shared.debug("rule \(r.label, privacy: .public) (\(r.id.uuidString.prefix(8), privacy: .public)): title mismatch — op=\(r.titleOperator.rawValue, privacy: .public) pattern=\(r.titleContains, privacy: .public) actual=\(n.title, privacy: .public)")
                return false
            }
        }
        if !r.bodyContains.isEmpty {
            guard r.bodyOperator.matches(n.body, r.bodyContains) else {
                AppLog.shared.debug("rule \(r.label, privacy: .public) (\(r.id.uuidString.prefix(8), privacy: .public)): body mismatch — op=\(r.bodyOperator.rawValue, privacy: .public) pattern=\(r.bodyContains, privacy: .public)")
                return false
            }
        }
        return true
    }
}
