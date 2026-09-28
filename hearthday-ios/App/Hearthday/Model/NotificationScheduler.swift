import Foundation
import UserNotifications
import HearthdayCore

enum ReminderPermission: Equatable, Sendable {
    case unknown
    case allowed
    case denied
}

/// Some reminders were rejected by iOS. The rest were scheduled.
struct ReminderSchedulingError: Error, Equatable {
    var failedCount: Int
    var totalCount: Int
}

protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async -> ReminderPermission
    func permission() async -> ReminderPermission
    /// Replaces every pending Hearthday reminder with `specs` and returns the permission it saw. Nothing is added
    /// unless notifications are allowed. Throws `ReminderSchedulingError` when iOS rejects any request.
    /// Callers must not overlap calls; `AppModel` runs them one at a time and only ever sends the latest state.
    func replaceAll(with specs: [ReminderSpec], now: Date) async throws -> ReminderPermission
}

struct NoopNotifications: NotificationScheduling {
    func requestAuthorizationIfNeeded() async -> ReminderPermission { .unknown }
    func permission() async -> ReminderPermission { .unknown }
    func replaceAll(with specs: [ReminderSpec], now: Date) async throws -> ReminderPermission { .unknown }
}

/// Local notifications only. Nothing leaves the device.
///
/// Triggers are time intervals from now rather than calendar components: a plan is a sequence of absolute
/// instants, and a time-zone change must not move "shape in 3 hours" to a different moment.
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
        Self.permission(for: await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    static func permission(for status: UNAuthorizationStatus) -> ReminderPermission {
        switch status {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    func replaceAll(with specs: [ReminderSpec], now: Date) async throws -> ReminderPermission {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        if specs.isEmpty { center.removeAllDeliveredNotifications() }
        let permission = await permission()
        guard permission == .allowed else { return permission }

        var failed = 0
        var total = 0
        for spec in specs {
            let seconds = spec.fireAt.timeIntervalSince(now)
            guard seconds >= 1 else { continue }
            total += 1
            let content = UNMutableNotificationContent()
            content.title = spec.title
            content.body = spec.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.threadIdentifier = "hearthday.bake"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: "hearthday.\(spec.id)", content: content, trigger: trigger))
            } catch {
                failed += 1
            }
        }
        if failed > 0 { throw ReminderSchedulingError(failedCount: failed, totalCount: total) }
        return permission
    }
}
