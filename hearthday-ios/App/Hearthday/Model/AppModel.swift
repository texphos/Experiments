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
    /// Set when iOS rejected some reminders for the current plan; cleared by the next fully successful sync.
    private(set) var reminderProblem: String?

    private var store: JSONFileStore?
    /// An unreadable file that couldn't be moved aside. Nothing is written until a copy is safe
    /// (see `recoverUnreadableFileIfPossible`), so the only original is never overwritten.
    @ObservationIgnored private var heldStore: JSONFileStore?
    @ObservationIgnored private var quarantine: (JSONFileStore) throws -> URL = { try $0.quarantineCorruptFile() }
    private let notifications: NotificationScheduling
    let clock: @Sendable () -> Date
    @ObservationIgnored var calendar = Calendar.current
    /// Picks up time-zone changes on resume. Tests turn this off to pin a calendar.
    @ObservationIgnored var followsSystemCalendar = true
    /// Where resume reads the device calendar from. `TimeZone.current` is cached by Foundation, so the cache is
    /// reset first; otherwise a time-zone change while the app was suspended would be missed.
    @ObservationIgnored var systemCalendar: () -> Calendar = {
        NSTimeZone.resetSystemTimeZone()
        return Calendar.current
    }

    /// Reminder syncs run one at a time. While one is in flight, newer requests replace each other, so only the
    /// latest state is ever sent next and an older plan can't be re-added after a re-plan, abandon or reset.
    @ObservationIgnored private var queuedReminders: [ReminderSpec]?
    @ObservationIgnored private var reminderWorker: Task<Void, Never>?

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

    /// Opens saved state. An unreadable file is moved aside (never deleted) and the app starts fresh. If it can't
    /// be moved, the app runs without saving so the original stays untouched, and retries on every resume.
    static func load(
        from store: JSONFileStore,
        notifications: NotificationScheduling,
        clock: @escaping @Sendable () -> Date = { Date() },
        quarantine: @escaping (JSONFileStore) throws -> URL = { try $0.quarantineCorruptFile() }
    ) -> AppModel {
        do {
            return AppModel(state: try store.load(), store: store, notifications: notifications, clock: clock)
        } catch {
            let newer = error is AppState.NewerFileError
            let model = AppModel(store: nil, notifications: notifications, clock: clock)
            model.quarantine = quarantine
            if let backup = try? quarantine(store) {
                model.store = store
                model.loadProblem = Self.freshStartMessage(newer: newer, keptAs: backup)
            } else {
                model.heldStore = store
                model.loadProblem = newer
                    ? "Your bakes were saved by a newer version of Hearthday. They couldn’t be set aside safely, so this version won’t save anything until they can. Update the app to see them again."
                    : "Your saved bakes couldn’t be read or set aside safely, so Hearthday won’t save changes for now. That keeps the original file untouched. Restart the app or free up storage to try again."
            }
            return model
        }
    }

    private static func freshStartMessage(newer: Bool, keptAs backup: URL) -> String {
        let kept = " The old file was kept as \(backup.lastPathComponent)."
        return newer
            ? "Your bakes were saved by a newer version of Hearthday, so this version started fresh.\(kept) Update the app to see them again."
            : "Your saved bakes couldn’t be read, so Hearthday started fresh.\(kept)"
    }

    /// True while an unreadable file is being protected and nothing is being saved.
    var isHoldingUnreadableFile: Bool { heldStore != nil }

    /// Tries again to set the unreadable file aside. Only once that succeeds is the store attached and the
    /// current state saved. If the file has become readable in the meantime, nothing is overwritten either:
    /// the app keeps protecting it and asks for a restart, which loads it normally.
    private func recoverUnreadableFileIfPossible() {
        guard let held = heldStore else { return }
        if !FileManager.default.fileExists(atPath: held.url.path) {
            heldStore = nil
            store = held
            loadProblem = nil
            persist()
            return
        }
        if (try? held.load()) != nil {
            loadProblem = "Your saved bakes can be read again. Close and reopen Hearthday to load them; nothing has been overwritten."
            return
        }
        guard let backup = try? quarantine(held) else { return }
        heldStore = nil
        store = held
        loadProblem = Self.freshStartMessage(newer: false, keptAs: backup)
        persist()
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

    /// Call on launch, whenever the app becomes active, and when the time zone or clock changes: the clock, time
    /// zone or notification permission may have changed, so reminders are rebuilt from the saved plan.
    func resume() async {
        if followsSystemCalendar { calendar = systemCalendar() }
        refreshClock()
        recoverUnreadableFileIfPossible()
        reminderPermission = await notifications.permission()
        syncReminders()
        await remindersSettled()
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
        queuedReminders = state.activeSession.map {
            Reminders.specs(for: $0, now: t, availability: state.settings.availability, calendar: calendar)
        } ?? []
        guard reminderWorker == nil else { return }
        reminderWorker = Task { [weak self] in
            await self?.drainReminderQueue()
        }
    }

    private func drainReminderQueue() async {
        while let specs = queuedReminders {
            queuedReminders = nil
            do {
                reminderPermission = try await notifications.replaceAll(with: specs, now: clock())
                if queuedReminders == nil { reminderProblem = nil }
            } catch let error as ReminderSchedulingError {
                if queuedReminders == nil {
                    reminderProblem = "\(error.failedCount) of \(error.totalCount) reminders couldn’t be scheduled. Keep an eye on this screen for the next step."
                }
            } catch {
                if queuedReminders == nil {
                    reminderProblem = "Reminders couldn’t be scheduled. Keep an eye on this screen for the next step."
                }
            }
        }
        reminderWorker = nil
    }

    /// Waits until every queued reminder change has reached the scheduler.
    func remindersSettled() async {
        while let worker = reminderWorker {
            await worker.value
        }
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

    /// Starts the bake straight away, then asks for notification permission (the first time only) and schedules
    /// reminders once the answer is known, so a fresh grant doesn't miss the plan's reminders.
    func start(_ plan: BakePlan) async {
        update { $0.start(plan, now: clock()) }
        reminderPermission = await notifications.requestAuthorizationIfNeeded()
        syncReminders()
        await remindersSettled()
    }

    func complete(_ step: BakeStep) {
        let calendar = self.calendar
        update { $0.completeStep(step.id, at: clock(), calendar: calendar) }
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

    /// Erases bakes, formulas and settings. The cached Pro flag is kept so an offline reset doesn't lock a paid
    /// feature; callers then re-check StoreKit (`ProStore.refreshEntitlement`), which is the only source of truth.
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
    static let darkAppearance = "-hearthday-dark"
    static let lightAppearance = "-hearthday-light"
}
