import Foundation

class FilterEngine {
    var rules: [FilterRule]

    init(rules: [FilterRule]) {
        self.rules = rules
    }

    func matchingRules(for notification: NotificationRecord) -> [FilterRule] {
        let enabledRules = rules.filter { $0.isEnabled && $0.isValid }
        AppLog.shared.debug("evaluating \(enabledRules.count, privacy: .public) enabled rules against app=\(notification.appIdentifier, privacy: .public)")
        return enabledRules.filter { matchesRule(notification, $0) }
    }

    func matchingRule(for notification: NotificationRecord) -> FilterRule? {
        matchingRules(for: notification).first
    }

    private func matchesRule(_ n: NotificationRecord, _ r: FilterRule) -> Bool {
        guard r.matchesFields(of: n) else {
            AppLog.shared.debug("rule \(r.label, privacy: .public) (\(r.id.uuidString.prefix(8), privacy: .public)): no match for app=\(n.appIdentifier, privacy: .public) title=\(n.title, privacy: .public)")
            return false
        }
        return true
    }
}
