import Foundation
import UserNotifications
import HearthdayCore

enum ReminderPermission: Equatable, Sendable {
    case unknown
    case allowed
    case denied
}

protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async -> ReminderPermission
    func permission() async -> ReminderPermission
    /// Replaces every pending Hearthday reminder with `specs`. Called after every state change.
    func replaceAll(with specs: [ReminderSpec], now: Date)
}

struct NoopNotifications: NotificationScheduling {
    func requestAuthorizationIfNeeded() async -> ReminderPermission { .unknown }
    func permission() async -> ReminderPermission { .unknown }
    func replaceAll(with specs: [ReminderSpec], now: Date) {}
}

/// Local notifications only. Nothing leaves the device.
///
/// Removal and additions are issued synchronously and in order, with no completion-handler round trip, so two
/// quick plan changes can't interleave and leave the older plan's reminders behind. Triggers are time
/// intervals from now rather than calendar components: a plan is a sequence of absolute instants, and a
/// time-zone change must not move "shape in 3 hours" to a different moment.
struct NotificationScheduler: NotificationScheduling {
    static let categoryID = "hearthday.step"

    func requestAuthorizationIfNeeded() async -> ReminderPermission {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        return await permission()
    }

    func permission() async -> ReminderPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    func replaceAll(with specs: [ReminderSpec], now: Date) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        if specs.isEmpty { center.removeAllDeliveredNotifications() }
        for spec in specs {
            let seconds = spec.fireAt.timeIntervalSince(now)
            guard seconds >= 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = spec.title
            content.body = spec.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.threadIdentifier = "hearthday.bake"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            center.add(UNNotificationRequest(identifier: "hearthday.\(spec.id)", content: content, trigger: trigger))
        }
    }
}
