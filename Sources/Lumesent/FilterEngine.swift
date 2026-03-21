import Foundation

class FilterEngine {
    var rules: [FilterRule]

    init(rules: [FilterRule]) {
        self.rules = rules
    }

    func shouldAlert(for notification: NotificationRecord) -> Bool {
        matchingRule(for: notification) != nil
    }

    func matchingRule(for notification: NotificationRecord) -> FilterRule? {
        rules.filter(\.isEnabled).filter(\.isValid).first { rule in
            matchesRule(notification, rule)
        }
    }

    private func matchesRule(_ n: NotificationRecord, _ r: FilterRule) -> Bool {
        // All non-empty fields must match (AND logic)
        if !r.appIdentifier.isEmpty {
            guard n.appIdentifier.localizedCaseInsensitiveContains(r.appIdentifier) else { return false }
        }
        if !r.titleContains.isEmpty {
            guard r.titleOperator.matches(n.title, r.titleContains) else { return false }
        }
        if !r.bodyContains.isEmpty {
            guard r.bodyOperator.matches(n.body, r.bodyContains) else { return false }
        }
        return true
    }
}
