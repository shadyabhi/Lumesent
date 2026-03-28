import Foundation

class FilterEngine {
    var rules: [FilterRule]

    init(rules: [FilterRule]) {
        self.rules = rules
    }

    func matchingRules(for notification: NotificationRecord) -> [FilterRule] {
        rules.filter { $0.isEnabled && $0.isValid && $0.matchesFields(of: notification) }
    }
}
