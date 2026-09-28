import XCTest
@testable import HearthdayCore

/// What happens when the baker closes the app mid-bake (or iOS terminates it) and opens it again later.
final class RecoveryTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var store: JSONFileStore { JSONFileStore(url: dir.appendingPathComponent("state.json")) }

    /// Saturday mix 10:00, slow dough checked at 16:00 and moved to the fridge before bed.
    func midBakeState() throws -> (AppState, ReplanOption) {
        var state = AppState()
        state.settings.hasCompletedOnboarding = true
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        state.start(plan, now: TestClock.date(10, 9, 55))
        state.completeStep("mix", at: plan.step("mix")!.end.addingTimeInterval(0.375))
        for i in 1...4 { state.completeStep("fold-\(i)", at: plan.step("fold-\(i)")!.end) }
        let session = try XCTUnwrap(state.activeSession)
        let now = TestClock.date(10, 16)
        let result = LiveReplanner.checkIn(session: session, now: now, risePercent: 30, tempC: 21,
                                           availability: state.settings.availability, calendar: TestClock.calendar, model: state.planningModel)
        let fridge = try XCTUnwrap(result.options.first { $0.kind == .fridgeNow })
        state.recordCheckIn(CheckIn(at: now, risePercent: 30, tempC: 21))
        state.apply(fridge)
        return (state, fridge)
    }

    func testMidBakeStateSurvivesCloseAndReopenExactly() throws {
        let (state, _) = try midBakeState()
        try store.save(state)
        let reopened = try JSONFileStore(url: store.url).load()
        XCTAssertEqual(reopened, state, "Including sub-second completion times")
        XCTAssertEqual(reopened.activeSession?.replanCount, 1)
        XCTAssertNotNil(reopened.activeSession?.plan.step("cold-bulk"))
    }

    func testReopenedBakeProducesTheSameRemindersAndDropsOnesThatPassed() throws {
        let (state, _) = try midBakeState()
        try store.save(state)
        let reopened = try store.load()
        let beforeClose = Reminders.specs(for: state.activeSession!, now: TestClock.date(10, 16, 5))
        XCTAssertEqual(Reminders.specs(for: reopened.activeSession!, now: TestClock.date(10, 16, 5)), beforeClose)

        let nextMorning = TestClock.date(11, 7, 30)
        let later = Reminders.specs(for: reopened.activeSession!, now: nextMorning)
        XCTAssertTrue(later.allSatisfy { $0.fireAt > nextMorning })
        XCTAssertLessThan(later.count, beforeClose.count)
    }

    func testStatusAfterReopeningDistinguishesDueOverdueAndStale() throws {
        let (state, _) = try midBakeState()
        let session = try XCTUnwrap(state.activeSession)
        let shape = try XCTUnwrap(session.nextAttendedStep)
        XCTAssertEqual(shape.kind, .shape)

        XCTAssertEqual(session.status(now: shape.start.addingTimeInterval(-3600)), .upcoming(shape))
        XCTAssertEqual(session.status(now: shape.start.addingTimeInterval(-60)), .due(shape))
        XCTAssertEqual(session.status(now: shape.start.addingTimeInterval(10 * 60)), .due(shape), "Within the grace period")
        XCTAssertEqual(session.status(now: shape.start.addingTimeInterval(3 * 3600)), .overdue(shape, minutesLate: 180))
        XCTAssertEqual(session.status(now: session.plan.readyAt.addingTimeInterval(13 * 3600)), .stale)

        var baked = session
        for step in baked.plan.steps where step.attended { baked.complete(step.id, at: step.end) }
        XCTAssertEqual(baked.status(now: session.plan.readyAt.addingTimeInterval(30 * 3600)), .baked, "Baked wins over stale")
    }

    func testFileFromOlderBuildWithMissingKeysStillOpens() throws {
        try Data(#"{"settings":{"hasCompletedOnboarding":true,"kitchenTempC":23}}"#.utf8).write(to: store.url)
        let state = try store.load()
        XCTAssertTrue(state.settings.hasCompletedOnboarding)
        XCTAssertEqual(state.settings.kitchenTempC, 23)
        XCTAssertEqual(state.settings.availability, .typicalWeekdayWorker)
        XCTAssertEqual(state.formulas, [.countryLoaf])
        XCTAssertNil(state.activeSession)
    }

    func testFileFromNewerBuildIsNotSilentlyOverwritten() throws {
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? AppState.NewerFileError, AppState.NewerFileError(version: 99))
        }
    }

    func testDamagedValuesInTheFileAreRepairedOnLoad() throws {
        var state = AppState()
        state.settings.kitchenTempC = 80
        try store.save(state)
        XCTAssertEqual(try store.load().settings.kitchenTempC, Limits.tempC.upperBound)
    }

    func testISO8601DatesFromHandEditedFilesStillDecode() throws {
        let json = #"{"history":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","finishedAt":"2026-10-11T11:00:00Z","formulaName":"Loaf","proofMode":"fridge","inoculationPercent":20,"tempC":21,"originalReadyAt":"2026-10-11T11:00:00.250Z","actualReadyAt":"2026-10-11T11:00:00Z","replanCount":0,"checkInCount":0,"rating":4,"notes":"","modelBulkHours":7}]}"#
        try Data(json.utf8).write(to: store.url)
        let record = try XCTUnwrap(try store.load().history.first)
        XCTAssertEqual(record.finishedAt, TestClock.date(11, 11))
        XCTAssertEqual(record.originalReadyAt, TestClock.date(11, 11).addingTimeInterval(0.25))
        XCTAssertNil(record.actualBulkHours)
    }

    func testUnreadableDateMakesTheLoadFailSoTheFileIsQuarantinedNotWiped() throws {
        try Data(#"{"history":[{"finishedAt":"yesterday"}]}"#.utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }
}
