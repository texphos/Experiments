import XCTest
import HearthdayCore
@testable import Hearthday

/// Records what the app asked iOS to schedule, standing in for UNUserNotificationCenter. Like the real
/// scheduler it removes everything first and only adds reminders while notifications are allowed.
final class RecordingNotifications: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var _batches: [[ReminderSpec]] = []
    private var _events: [String] = []
    private var _permission: ReminderPermission = .allowed
    private var _inFlight = 0
    private var _maxInFlight = 0
    private var _failNext: ReminderSchedulingError?
    /// When set, the permission `requestAuthorizationIfNeeded` grants if it hasn't been decided yet.
    var grantOnRequest: ReminderPermission? = .allowed
    /// Makes each replace take a while, so overlapping callers would show up.
    var replaceDelay: Duration?

    var batches: [[ReminderSpec]] { lock.withLock { _batches } }
    var pending: [ReminderSpec] { batches.last ?? [] }
    var events: [String] { lock.withLock { _events } }
    var maxConcurrentReplaces: Int { lock.withLock { _maxInFlight } }
    var permissionToReport: ReminderPermission {
        get { lock.withLock { _permission } }
        set { lock.withLock { _permission = newValue } }
    }
    func failNextReplace(_ error: ReminderSchedulingError) { lock.withLock { _failNext = error } }

    func requestAuthorizationIfNeeded() async -> ReminderPermission {
        lock.withLock {
            _events.append("request")
            if _permission == .unknown, let grant = grantOnRequest { _permission = grant }
            return _permission
        }
    }
    func permission() async -> ReminderPermission { permissionToReport }
    func replaceAll(with specs: [ReminderSpec], now: Date) async throws -> ReminderPermission {
        let permission: ReminderPermission = lock.withLock {
            _inFlight += 1
            _maxInFlight = max(_maxInFlight, _inFlight)
            _events.append("replace:\(_permission)")
            return _permission
        }
        defer { lock.withLock { _inFlight -= 1 } }
        if let replaceDelay { try? await Task.sleep(for: replaceDelay) }
        return try lock.withLock {
            let allowed = permission == .allowed
            _batches.append(allowed ? specs.filter { $0.fireAt > now } : [])
            if let error = _failNext {
                _failNext = nil
                throw error
            }
            return permission
        }
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
        await model.start(plan)
        return plan
    }

    func completeNext(_ model: AppModel, at date: Date? = nil) async throws -> BakeStep {
        let step = try XCTUnwrap(model.state.activeSession?.nextAttendedStep)
        clock.set(date ?? step.end)
        model.complete(step)
        await model.remindersSettled()
        return step
    }

    /// plan → start → check in → re-plan → finish → journal, through the same model the UI uses.
    func testCompleteLoopPersistsEveryStepAndKeepsRemindersInSync() async throws {
        let model = onboardedModel()
        let plan = try await startBake(model)
        XCTAssertEqual(notifications.pending, Reminders.specs(for: model.state.activeSession!, now: clock.now, availability: model.state.settings.availability, calendar: utc))
        XCTAssertFalse(notifications.pending.isEmpty)

        while model.state.activeSession?.isInBulk == false { _ = try await completeNext(model) }
        while model.state.activeSession?.nextAttendedStep?.kind == .fold { _ = try await completeNext(model) }

        // Dough racing ahead on a Friday evening: 3 h after mixing it's already up 60%.
        clock.set(model.state.activeSession!.bulkClockStart.addingTimeInterval(3 * 3600))
        let before = notifications.pending
        let result = try XCTUnwrap(model.checkIn(risePercent: 60, tempC: 23))
        XCTAssertTrue(result.problems.isEmpty)
        let option = try XCTUnwrap(result.options.first { $0.recommended } ?? result.options.first)
        model.apply(option, checkIn: CheckIn(at: clock.now, risePercent: 60, tempC: 23))
        await model.remindersSettled()

        let session = try XCTUnwrap(model.state.activeSession)
        XCTAssertEqual(session.replanCount, 1)
        XCTAssertEqual(session.checkIns.count, 1)
        XCTAssertNotEqual(notifications.pending, before, "Re-planning reschedules reminders")
        XCTAssertEqual(notifications.pending, Reminders.specs(for: session, now: clock.now, availability: model.state.settings.availability, calendar: utc))
        XCTAssertEqual(try store.load().activeSession, session, "Every change is on disk immediately")

        if model.state.activeSession?.nextAttendedStep?.kind == .fridgeDough {
            _ = try await completeNext(model)
            XCTAssertEqual(model.state.activeSession?.isChilled, true)
        }
        let shape = try await completeNext(model)
        XCTAssertEqual(shape.kind, .shape)
        model.setShapeReadiness(.justRight)
        while model.state.activeSession?.isBaked == false { _ = try await completeNext(model) }
        model.finish(rating: 5, notes: "Good oven spring")
        await model.remindersSettled()

        XCTAssertNil(model.state.activeSession)
        XCTAssertEqual(notifications.pending, [], "Finishing cancels every reminder")
        let record = try XCTUnwrap(model.state.history.first)
        XCTAssertEqual(record.replanCount, 1)
        XCTAssertEqual(record.rating, 5)
        XCTAssertEqual(record.originalReadyAt, plan.readyAt)
        XCTAssertEqual(try store.load().history, model.state.history)
    }

    func testShapingLateMovesTheBakeAndItsReminderAndSaysWhy() async throws {
        let model = onboardedModel()
        let sunday10 = utc.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 10))!
        let result = await model.plan(readyBy: sunday10, formula: .countryLoaf, tempC: 21, starterNeedsFeed: true)
        let plan = try XCTUnwrap(result.primary, "\(result)")
        XCTAssertEqual(plan.proofMode, .fridge, "Friday morning to Sunday 10:00 plans an overnight cold proof")
        await model.start(plan)
        while model.state.activeSession?.nextAttendedStep?.kind != .shape { _ = try await completeNext(model) }
        let bakeBefore = try XCTUnwrap(model.state.activeSession?.plan.step("bake")?.start)
        let shape = try XCTUnwrap(model.state.activeSession?.nextAttendedStep)
        _ = try await completeNext(model, at: shape.end.addingTimeInterval(12 * 3600))

        let session = try XCTUnwrap(model.state.activeSession)
        let retard = try XCTUnwrap(session.plan.step("cold-proof"))
        let bake = try XCTUnwrap(session.plan.step("bake"))
        XCTAssertGreaterThanOrEqual(retard.end.timeIntervalSince(retard.start), 8 * 3600, "Never a negative or too-short cold proof")
        XCTAssertEqual(retard.end, bake.start)
        XCTAssertGreaterThan(bake.start, bakeBefore)
        XCTAssertNotNil(session.adjustmentNote)
        XCTAssertEqual(notifications.pending, Reminders.specs(for: session, now: clock.now, availability: model.state.settings.availability, calendar: utc))
        XCTAssertEqual(notifications.pending.first { $0.title == "Bake" }?.fireAt, bake.start)
        XCTAssertEqual(try store.load().activeSession, session)
    }

    func testReopeningMidBakeRestoresTheSessionAndRebuildsReminders() async throws {
        let first = onboardedModel()
        _ = try await startBake(first)
        _ = try await completeNext(first)
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
        await model.remindersSettled()
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
        let beforeMix = try XCTUnwrap(model.checkIn(risePercent: 20, tempC: 21))
        XCTAssertEqual(beforeMix.problems.map(\.code), ["notInBulk"], "Check-ins are refused before mixing")
        XCTAssertTrue(beforeMix.options.isEmpty)

        while let step = model.state.activeSession?.nextAttendedStep, model.state.activeSession?.isInBulk == false {
            model.complete(step)
        }
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

    // MARK: Reminder scheduling around permission, overlap and failure

    func testStartWaitsForThePermissionAnswerThenSchedulesReminders() async throws {
        notifications.permissionToReport = .unknown
        let model = onboardedModel()
        _ = try await startBake(model)
        let events = notifications.events
        let request = try XCTUnwrap(events.firstIndex(of: "request"), "\(events)")
        XCTAssertEqual(events.last, "replace:allowed", "The last sync runs after the grant: \(events)")
        XCTAssertGreaterThan(try XCTUnwrap(events.lastIndex(of: "replace:allowed")), request)
        XCTAssertEqual(model.reminderPermission, .allowed)
        XCTAssertFalse(notifications.pending.isEmpty)
        XCTAssertEqual(notifications.pending, Reminders.specs(for: model.state.activeSession!, now: clock.now, availability: model.state.settings.availability, calendar: utc))
    }

    func testDeniedPermissionAtStartIsReportedAndNothingIsScheduled() async throws {
        notifications.permissionToReport = .unknown
        notifications.grantOnRequest = .denied
        let model = onboardedModel()
        _ = try await startBake(model)
        XCTAssertEqual(model.reminderPermission, .denied)
        XCTAssertEqual(notifications.pending, [])
        XCTAssertNotNil(model.state.activeSession, "The bake still starts; the live screen shows the reminders-off banner")
    }

    func testPermissionTurnedOffLaterIsPickedUpByTheNextSync() async throws {
        let model = onboardedModel()
        _ = try await startBake(model)
        XCTAssertEqual(model.reminderPermission, .allowed)
        notifications.permissionToReport = .denied
        _ = try await completeNext(model)
        XCTAssertEqual(model.reminderPermission, .denied)
        XCTAssertEqual(notifications.pending, [])
    }

    func testRapidChangesNeverOverlapAndAnAbandonedBakeLeavesNoReminders() async throws {
        let model = onboardedModel()
        _ = try await startBake(model)
        notifications.replaceDelay = .milliseconds(80)
        let batchesBefore = notifications.batches.count
        for _ in 0..<3 {
            guard let step = model.state.activeSession?.nextAttendedStep else { break }
            clock.set(step.end)
            model.complete(step)
        }
        model.abandon()
        await model.remindersSettled()
        XCTAssertEqual(notifications.maxConcurrentReplaces, 1, "One replace at a time")
        XCTAssertEqual(notifications.pending, [], "An older plan can't be re-added after abandoning")
        XCTAssertLessThanOrEqual(notifications.batches.count - batchesBefore, 2, "Changes made while a replace is running collapse into one")
    }

    func testRapidReplansEndOnTheLatestPlan() async throws {
        let model = onboardedModel()
        _ = try await startBake(model)
        notifications.replaceDelay = .milliseconds(50)
        while model.state.activeSession?.isInBulk == false {
            let step = model.state.activeSession!.nextAttendedStep!
            clock.set(step.end)
            model.complete(step)
        }
        await model.remindersSettled()
        XCTAssertEqual(notifications.pending, Reminders.specs(for: model.state.activeSession!, now: clock.now, availability: model.state.settings.availability, calendar: utc))
        XCTAssertEqual(notifications.maxConcurrentReplaces, 1)
    }

    func testSchedulingFailuresAreShownUntilASyncSucceeds() async throws {
        let model = onboardedModel()
        _ = try await startBake(model)
        XCTAssertNil(model.reminderProblem)
        notifications.failNextReplace(ReminderSchedulingError(failedCount: 2, totalCount: 7))
        _ = try await completeNext(model)
        XCTAssertEqual(model.reminderProblem, "2 of 7 reminders couldn’t be scheduled. Keep an eye on this screen for the next step.")
        _ = try await completeNext(model)
        XCTAssertNil(model.reminderProblem)
    }

    // MARK: Activation

    func testResumePicksUpATimeZoneChangeAndReschedules() async throws {
        let model = onboardedModel()
        _ = try await startBake(model)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        model.followsSystemCalendar = true
        model.systemCalendar = { newYork }
        let batches = notifications.batches.count
        clock.advance(3600)
        await model.resume()
        XCTAssertEqual(model.calendar.timeZone.identifier, "America/New_York")
        XCTAssertEqual(notifications.batches.count, batches + 1, "Reminders are rebuilt on activation")
        XCTAssertEqual(notifications.pending, Reminders.specs(for: model.state.activeSession!, now: clock.now, availability: model.state.settings.availability, calendar: newYork))
    }

    // MARK: Unreadable file that can't be set aside

    func testUnreadableFileThatCannotBeSetAsideIsNeverOverwritten() async throws {
        let original = Data("{broken".utf8)
        try original.write(to: store.url)
        let gate = QuarantineGate()
        let model = AppModel.load(from: store, notifications: notifications, clock: { [testClock = clock!] in testClock.now }, quarantine: { store in
            if gate.blocked { throw CocoaError(.fileWriteNoPermission) }
            return try store.quarantineCorruptFile()
        })
        model.calendar = utc
        model.followsSystemCalendar = false
        XCTAssertTrue(model.isHoldingUnreadableFile)
        XCTAssertTrue(model.loadProblem?.contains("won’t save changes") ?? false, model.loadProblem ?? "nil")

        model.update { $0.settings.hasCompletedOnboarding = true }
        _ = try await startBake(model)
        await model.resume()
        XCTAssertEqual(try Data(contentsOf: store.url), original, "The only copy is untouched while it can't be backed up")
        XCTAssertTrue(model.isHoldingUnreadableFile)

        gate.blocked = false
        await model.resume()
        XCTAssertFalse(model.isHoldingUnreadableFile)
        let backups = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("unreadable") }
        XCTAssertEqual(backups.count, 1)
        let backup = try XCTUnwrap(backups.first)
        XCTAssertEqual(try Data(contentsOf: backup), original, "The original is kept as a backup")
        XCTAssertEqual(try store.load().activeSession, model.state.activeSession, "Only now is the current state saved")
    }

    func testUnreadableFileThatBecomesReadableIsNotOverwritten() async throws {
        try Data("{broken".utf8).write(to: store.url)
        let gate = QuarantineGate()
        let model = AppModel.load(from: store, notifications: notifications, clock: { [testClock = clock!] in testClock.now }, quarantine: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        _ = gate
        var saved = AppState()
        saved.settings.hasCompletedOnboarding = true
        saved.settings.kitchenTempC = 19
        try JSONFileStore(url: store.url).save(saved)
        model.update { $0.settings.kitchenTempC = 25 }
        await model.resume()
        XCTAssertTrue(model.isHoldingUnreadableFile)
        XCTAssertTrue(model.loadProblem?.contains("can be read again") ?? false, model.loadProblem ?? "nil")
        XCTAssertEqual(try store.load().settings.kitchenTempC, 19, "A file that became readable again is left for the next launch to load")
    }
}

final class QuarantineGate: @unchecked Sendable {
    var blocked = true
}
