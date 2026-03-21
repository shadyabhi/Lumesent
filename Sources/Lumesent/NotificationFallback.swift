import Foundation
import UserNotifications

enum NotificationFallback {
    private static var didRequestAuth = false

    static func requestAuthorizationIfNeeded() {
        guard !didRequestAuth else { return }
        didRequestAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postEcho(for record: NotificationRecord) {
        let content = UNMutableNotificationContent()
        content.title = record.title.isEmpty ? record.appName : record.title
        let bodyText = record.body.isEmpty ? " " : record.body
        content.body = bodyText
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lumesent.echo.\(record.id).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.shared.debug("UN notification echo failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
