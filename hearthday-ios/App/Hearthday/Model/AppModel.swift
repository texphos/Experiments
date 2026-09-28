import Foundation
import Observation
import HearthdayCore

/// Thin observable shell around `AppState`. Every mutation goes through `update`, which persists and
/// re-syncs reminders, so no view can change state without it being saved.
@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState
    /// Set when the saved file could not be read; the file is moved aside, never deleted.
    var loadProblem: String?
    var saveProblem: String?
    private(set) var now = Date()

    @ObservationIgnored private let store: JSONFileStore?
    @ObservationIgnored private let notifications: NotificationScheduling
    @ObservationIgnored var calendar = Calendar.current

    init(state: AppState = AppState(), store: JSONFileStore? = nil, notifications: NotificationScheduling = NoopNotifications()) {
        self.state = state
        self.store = store
        self.notifications = notifications
    }

    static func live() -> AppModel {
        let notifications = NotificationScheduler()
        guard let store = try? JSONFileStore.defaultLocation() else {
            let model = AppModel(notifications: notifications)
            model.saveProblem = "Hearthday couldn’t open its storage folder, so changes won’t be kept after you close the app."
            return model
        }
        do {
            return AppModel(state: try store.load(), store: store, notifications: notifications)
        } catch {
            let model = AppModel(store: store, notifications: notifications)
            if let backup = try? store.quarantineCorruptFile() {
                model.loadProblem = "Your saved bakes couldn’t be read, so Hearthday started fresh. The old file was kept as \(backup.lastPathComponent)."
            } else {
                model.loadProblem = "Your saved bakes couldn’t be read. Hearthday started fresh for now."
            }
            return model
        }
    }

    static func preview(_ configure: (inout AppState) -> Void = { _ in }) -> AppModel {
        var s = AppState()
        s.settings.hasCompletedOnboarding = true
        configure(&s)
        return AppModel(state: s)
    }

    func refreshClock() { now = Date() }

    func update(_ mutate: (inout AppState) -> Void) {
        mutate(&state)
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
        let specs = state.activeSession.map { Reminders.specs(for: $0, now: Date()) } ?? []
        notifications.replaceAll(with: specs)
    }

    // MARK: Planning

    func plan(readyBy: Date, formula: Formula, tempC: Double, starterNeedsFeed: Bool) async -> PlanResult {
        let request = state.request(readyBy: readyBy, now: Date(), formula: formula, tempC: tempC, starterNeedsFeed: starterNeedsFeed)
        let calendar = self.calendar
        return await Task.detached(priority: .userInitiated) {
            Planner.plan(request, calendar: calendar)
        }.value
    }

    func checkIn(risePercent: Double, tempC: Double) -> CheckInResult? {
        guard let session = state.activeSession else { return nil }
        return LiveReplanner.checkIn(
            session: session,
            now: Date(),
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
        Task { await notifications.requestAuthorizationIfNeeded() }
        update { $0.start(plan, now: Date()) }
    }

    func complete(_ step: BakeStep) {
        update { $0.completeStep(step.id, at: Date()) }
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
        update { $0.finishActiveBake(rating: rating, notes: notes, at: Date()) }
    }

    func abandon() {
        update { $0.abandonActiveBake() }
    }

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
