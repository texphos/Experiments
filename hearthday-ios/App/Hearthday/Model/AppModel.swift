import Foundation
import Observation
import HearthdayCore

/// Thin observable shell around `AppState`. Every mutation goes through `update`, which persists and
/// re-syncs reminders, so no view can change state without it being saved and rescheduled.
@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState
    /// Set when the saved file could not be read; the file is moved aside, never deleted.
    var loadProblem: String?
    var saveProblem: String?
    private(set) var now: Date
    private(set) var reminderPermission: ReminderPermission = .unknown

    private let store: JSONFileStore?
    private let notifications: NotificationScheduling
    let clock: @Sendable () -> Date
    @ObservationIgnored var calendar = Calendar.current
    /// Picks up time-zone changes on resume. Tests turn this off to pin a calendar.
    @ObservationIgnored var followsSystemCalendar = true

    init(
        state: AppState = AppState(),
        store: JSONFileStore? = nil,
        notifications: NotificationScheduling = NoopNotifications(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.state = state
        self.store = store
        self.notifications = notifications
        self.clock = clock
        self.now = clock()
    }

    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        if arguments.contains(LaunchArgument.uiTesting) {
            return uiTesting(arguments: arguments)
        }
        guard let store = try? JSONFileStore.defaultLocation() else {
            let model = AppModel(notifications: NotificationScheduler())
            model.saveProblem = "Hearthday couldn’t open its storage folder, so changes won’t be kept after you close the app."
            return model
        }
        return load(from: store, notifications: NotificationScheduler())
    }

    /// Opens saved state. An unreadable file is moved aside (never deleted) and the app starts fresh.
    static func load(from store: JSONFileStore, notifications: NotificationScheduling, clock: @escaping @Sendable () -> Date = { Date() }) -> AppModel {
        do {
            return AppModel(state: try store.load(), store: store, notifications: notifications, clock: clock)
        } catch {
            let model = AppModel(store: store, notifications: notifications, clock: clock)
            let backup = try? store.quarantineCorruptFile()
            let kept = backup.map { " The old file was kept as \($0.lastPathComponent)." } ?? ""
            if error is AppState.NewerFileError {
                model.loadProblem = "Your bakes were saved by a newer version of Hearthday, so this version started fresh.\(kept) Update the app to see them again."
            } else {
                model.loadProblem = "Your saved bakes couldn’t be read, so Hearthday started fresh.\(kept)"
            }
            return model
        }
    }

    /// A clean, throwaway store for UI tests; nothing touches the real journal or schedules real reminders.
    private static func uiTesting(arguments: [String]) -> AppModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hearthday-uitest-state.json")
        if arguments.contains(LaunchArgument.resetState) {
            try? FileManager.default.removeItem(at: url)
        }
        return load(from: JSONFileStore(url: url), notifications: NoopNotifications())
    }

    static func preview(_ configure: (inout AppState) -> Void = { _ in }) -> AppModel {
        var s = AppState()
        s.settings.hasCompletedOnboarding = true
        configure(&s)
        return AppModel(state: s)
    }

    func refreshClock() { now = clock() }

    /// Call on launch and whenever the app returns to the foreground: the clock, time zone or notification
    /// permission may have changed while it was closed, so reminders are rebuilt from the saved plan.
    func resume() async {
        if followsSystemCalendar { calendar = Calendar.current }
        refreshClock()
        syncReminders()
        reminderPermission = await notifications.permission()
    }

    func update(_ mutate: (inout AppState) -> Void) {
        mutate(&state)
        refreshClock()
        persist()
        syncReminders()
    }

    private func persist() {
        guard let store else { return }
        do {
            try store.save(state)
            saveProblem = nil
        } catch {
            saveProblem = "Your latest change couldn’t be saved. Check that your iPhone has free storage."
        }
    }

    private func syncReminders() {
        let t = clock()
        let specs = state.activeSession.map {
            Reminders.specs(for: $0, now: t, availability: state.settings.availability, calendar: calendar)
        } ?? []
        notifications.replaceAll(with: specs, now: t)
    }

    // MARK: Planning

    func plan(readyBy: Date, formula: Formula, tempC: Double, starterNeedsFeed: Bool) async -> PlanResult {
        let request = state.request(readyBy: readyBy, now: clock(), formula: formula, tempC: tempC, starterNeedsFeed: starterNeedsFeed)
        let calendar = self.calendar
        return await Task.detached(priority: .userInitiated) {
            Planner.plan(request, calendar: calendar)
        }.value
    }

    func checkIn(risePercent: Double, tempC: Double) -> CheckInResult? {
        guard let session = state.activeSession else { return nil }
        return LiveReplanner.checkIn(
            session: session,
            now: clock(),
            risePercent: risePercent,
            tempC: tempC,
            availability: state.settings.availability,
            calendar: calendar,
            model: state.planningModel
        )
    }

    func upcomingConflicts() -> [StepConflict] {
        state.activeSession?.upcomingConflicts(now: now, availability: state.settings.availability, calendar: calendar) ?? []
    }

    // MARK: Intents

    func start(_ plan: BakePlan) {
        update { $0.start(plan, now: clock()) }
        Task { reminderPermission = await notifications.requestAuthorizationIfNeeded() }
    }

    func complete(_ step: BakeStep) {
        update { $0.completeStep(step.id, at: clock()) }
    }

    func apply(_ option: ReplanOption, checkIn: CheckIn) {
        update {
            $0.recordCheckIn(checkIn)
            $0.apply(option)
        }
    }

    func logCheckInOnly(_ checkIn: CheckIn) {
        update { $0.recordCheckIn(checkIn) }
    }

    func setShapeReadiness(_ readiness: ShapeReadiness) {
        update { $0.setShapeReadiness(readiness) }
    }

    func finish(rating: Int?, notes: String) {
        update { $0.finishActiveBake(rating: rating, notes: notes, at: clock()) }
    }

    func abandon() {
        update { $0.abandonActiveBake() }
    }

    /// Only StoreKit's verified entitlements call this (see `ProStore`); nothing in the UI can set Pro directly.
    func setPro(_ isPro: Bool) {
        guard state.isPro != isPro else { return }
        update { $0.isPro = isPro }
    }

    func resetEverything() {
        update { s in
            let isPro = s.isPro
            s = AppState()
            s.isPro = isPro
        }
    }
}

enum LaunchArgument {
    static let uiTesting = "-hearthday-ui-testing"
    static let resetState = "-hearthday-reset-state"
}
