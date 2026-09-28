import XCTest
import HearthdayCore
@testable import Hearthday

/// Records what the app asked iOS to schedule, standing in for UNUserNotificationCenter.
final class RecordingNotifications: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var _batches: [[ReminderSpec]] = []
    var permissionToReport: ReminderPermission = .allowed

    var batches: [[ReminderSpec]] { lock.withLock { _batches } }
    var pending: [ReminderSpec] { batches.last ?? [] }

    func requestAuthorizationIfNeeded() async -> ReminderPermission { permissionToReport }
    func permission() async -> ReminderPermission { permissionToReport }
    func replaceAll(with specs: [ReminderSpec], now: Date) {
        lock.withLock { _batches.append(specs.filter { $0.fireAt > now }) }
    }
}

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date { lock.withLock { _now } }
    func set(_ date: Date) { lock.withLock { _now = date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }
}

@MainActor
final class AppModelTests: XCTestCase {
    var dir: URL!
    var store: JSONFileStore!
    var notifications: RecordingNotifications!
    var clock: TestClock!
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = JSONFileStore(url: dir.appendingPathComponent("state.json"))
        notifications = RecordingNotifications()
        // Friday 2026-10-09 07:15 UTC.
        clock = TestClock(utc.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 7, minute: 15))!)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeModel() -> AppModel {
        let clock = self.clock!
        let model = AppModel.load(from: store, notifications: notifications, clock: { clock.now })
        model.calendar = utc
        model.followsSystemCalendar = false
        return model
    }

    func onboardedModel() -> AppModel {
        let model = makeModel()
        model.update { $0.settings.hasCompletedOnboarding = true }
        return model
    }

    func saturday10() -> Date { utc.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 10))! }

    func startBake(_ model: AppModel) async throws -> BakePlan {
        let result = await model.plan(readyBy: saturday10(), formula: .countryLoaf, tempC: 21, starterNeedsFeed: true)
        let plan = try XCTUnwrap(result.primary, "\(result)")
        model.start(plan)
        return plan
    }

    func completeNext(_ model: AppModel, at date: Date? = nil) throws -> BakeStep {
        let step = try XCTUnwrap(model.state.activeSession?.nextAttendedStep)
        clock.set(date ?? step.end)
        model.complete(step)
        return step
    }

    /// plan → start → check in → re-plan → finish → journal, through the same model the UI uses.
    func testCompleteLoopPersistsEveryStepAndKeepsRemindersInSync() async throws {
        let model = onboardedModel()
        let plan = try await startBake(model)
        XCTAssertEqual(notifications.pending, Reminders.specs(for: model.state.activeSession!, now: clock.now, availability: model.state.settings.availability, calendar: utc))
        XCTAssertFalse(notifications.pending.isEmpty)

        while model.state.activeSession?.isInBulk == false { _ = try completeNext(model) }
        while model.state.activeSession?.nextAttendedStep?.kind == .fold { _ = try completeNext(model) }

        // Dough racing ahead on a Friday evening: 3 h after mixing it's already up 60%.
        clock.set(model.state.activeSession!.bulkClockStart.addingTimeInterval(3 * 3600))
        let before = notifications.pending
        let result = try XCTUnwrap(model.checkIn(risePercent: 60, tempC: 23))
        XCTAssertTrue(result.problems.isEmpty)
        let option = try XCTUnwrap(result.options.first { $0.recommended } ?? result.options.first)
        model.apply(option, checkIn: CheckIn(at: clock.now, risePercent: 60, tempC: 23))

        let session = try XCTUnwrap(model.state.activeSession)
        XCTAssertEqual(session.replanCount, 1)
        XCTAssertEqual(session.checkIns.count, 1)
        XCTAssertNotEqual(notifications.pending, before, "Re-planning reschedules reminders")
        XCTAssertEqual(notifications.pending, Reminders.specs(for: session, now: clock.now, availability: model.state.settings.availability, calendar: utc))
        XCTAssertEqual(try store.load().activeSession, session, "Every change is on disk immediately")

        let shape = try completeNext(model)
        XCTAssertEqual(shape.kind, .shape)
        model.setShapeReadiness(.justRight)
        while model.state.activeSession?.isBaked == false { _ = try completeNext(model) }
        model.finish(rating: 5, notes: "Good oven spring")

        XCTAssertNil(model.state.activeSession)
        XCTAssertEqual(notifications.pending, [], "Finishing cancels every reminder")
        let record = try XCTUnwrap(model.state.history.first)
        XCTAssertEqual(record.replanCount, 1)
        XCTAssertEqual(record.rating, 5)
        XCTAssertEqual(record.originalReadyAt, plan.readyAt)
        XCTAssertEqual(try store.load().history, model.state.history)
    }

    func testReopeningMidBakeRestoresTheSessionAndRebuildsReminders() async throws {
        let first = onboardedModel()
        _ = try await startBake(first)
        _ = try completeNext(first)
        let saved = try XCTUnwrap(first.state.activeSession)

        clock.advance(2 * 3600)
        let reopenedNotifications = RecordingNotifications()
        notifications = reopenedNotifications
        let reopened = makeModel()
        XCTAssertNil(reopened.loadProblem)
        XCTAssertEqual(reopened.state.activeSession, saved)
        XCTAssertTrue(reopenedNotifications.batches.isEmpty)

        await reopened.resume()
        XCTAssertEqual(reopenedNotifications.pending, Reminders.specs(for: saved, now: clock.now, availability: reopened.state.settings.availability, calendar: utc))
        XCTAssertTrue(reopenedNotifications.pending.allSatisfy { $0.fireAt > clock.now }, "Nothing scheduled in the past")
        XCTAssertEqual(reopened.reminderPermission, .allowed)
    }

    func testReopeningAfterMissingAStepShowsItAsOverdue() async throws {
        let model = onboardedModel()
        _ = try await startBake(model)
        let next = try XCTUnwrap(model.state.activeSession?.nextAttendedStep)
        clock.set(next.start.addingTimeInterval(2 * 3600))
        let reopened = makeModel()
        await reopened.resume()
        XCTAssertEqual(reopened.state.activeSession?.status(now: reopened.now), .overdue(next, minutesLate: 120))
    }

    func testDeniedNotificationsAreReported() async {
        notifications.permissionToReport = .denied
        let model = onboardedModel()
        await model.resume()
        XCTAssertEqual(model.reminderPermission, .denied)
    }

    func testAbandonCancelsRemindersAndKeepsNothingInTheJournal() async throws {
        let model = onboardedModel()
        _ = try await startBake(model)
        model.abandon()
        XCTAssertEqual(notifications.pending, [])
        XCTAssertTrue(model.state.history.isEmpty)
        XCTAssertNil(try store.load().activeSession)
    }

    func testInvalidRequestsAndReadingsAreRejected() async throws {
        let model = onboardedModel()
        let past = await model.plan(readyBy: clock.now.addingTimeInterval(-60), formula: .countryLoaf, tempC: 21, starterNeedsFeed: true)
        guard case .invalid(let problems) = past else { return XCTFail("\(past)") }
        XCTAssertEqual(problems, [.readyTimeInPast])
        XCTAssertNil(model.state.activeSession)

        _ = try await startBake(model)
        let bad = try XCTUnwrap(model.checkIn(risePercent: -10, tempC: 21))
        XCTAssertTrue(bad.options.isEmpty)
        XCTAssertEqual(bad.problems.map(\.code), ["riseOutOfRange"])
    }

    func testCorruptFileIsKeptAndReported() throws {
        try Data("{broken".utf8).write(to: store.url)
        let model = makeModel()
        XCTAssertNotNil(model.loadProblem)
        XCTAssertEqual(model.state, AppState())
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("unreadable") }
        XCTAssertEqual(backups.count, 1)
    }

    func testFileFromNewerVersionIsKeptWithASpecificMessage() throws {
        try Data(#"{"schemaVersion": 42}"#.utf8).write(to: store.url)
        let model = makeModel()
        XCTAssertTrue(model.loadProblem?.contains("newer version") ?? false, model.loadProblem ?? "nil")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("unreadable") }
        XCTAssertEqual(backups.count, 1)
    }

    func testFreeAndProBoundaries() async throws {
        let model = onboardedModel()
        XCTAssertFalse(model.state.isPro)
        XCTAssertTrue(model.state.canAddFormula)
        model.update { $0.formulas.append(.countryLoaf) }
        XCTAssertFalse(model.state.canAddFormula, "Free: \(AppState.freeFormulaLimit) formulas")
        XCTAssertEqual(model.state.planningModel.speedFactor, 1, "Free plans use the textbook model")

        model.setPro(true)
        XCTAssertTrue(model.state.canAddFormula)
        XCTAssertTrue(try store.load().isPro, "Entitlement is cached for offline launches")

        model.resetEverything()
        XCTAssertTrue(model.state.isPro, "Erasing data doesn't forfeit a purchase")
        XCTAssertEqual(model.state.formulas.count, 1)
    }
}
