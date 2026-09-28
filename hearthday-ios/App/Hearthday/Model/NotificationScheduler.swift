import Foundation
import UserNotifications
import HearthdayCore

protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async
    func replaceAll(with specs: [ReminderSpec])
}

struct NoopNotifications: NotificationScheduling {
    func requestAuthorizationIfNeeded() async {}
    func replaceAll(with specs: [ReminderSpec]) {}
}

/// Local notifications only. Nothing leaves the device.
struct NotificationScheduler: NotificationScheduling {
    private static let prefix = "hearthday."

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func replaceAll(with specs: [ReminderSpec]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for spec in specs where spec.fireAt > Date() {
                let content = UNMutableNotificationContent()
                content.title = spec.title
                content.body = spec.body
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: spec.fireAt)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: Self.prefix + spec.id, content: content, trigger: trigger))
            }
        }
    }
}
