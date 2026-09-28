import XCTest
@testable import HearthdayCore

final class LiveSessionTests: XCTestCase {
    let cal = TestClock.calendar
    let worker = Availability.typicalWeekdayWorker
    let model = FermentationModel()

    /// Saturday: mix 10:00, loaf out Sunday 11:00.
    func startedSession() -> BakeSession {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var s = BakeSession(plan: plan, startedAt: TestClock.date(10, 9, 55))
        s.complete("mix", at: plan.step("mix")!.end)
        for i in 1...4 { s.complete("fold-\(i)", at: plan.step("fold-\(i)")!.end) }
        return s
    }

    func checkIn(_ s: BakeSession, at now: Date, rise: Double, temp: Double = 21) -> CheckInResult {
        LiveReplanner.checkIn(session: s, now: now, risePercent: rise, tempC: temp, availability: worker, calendar: cal, model: model)
    }

    func testOnTrackDoughKeepsTheFinishTime() throws {
        let s = startedSession()
        // 4 h in at 21 °C: 4/7 of a 75% target ≈ 43%.
        let result = checkIn(s, at: TestClock.date(10, 14), rise: 43)
        let option = try XCTUnwrap(result.options.first)
        XCTAssertEqual(option.kind, .shapeWhenReady)
        XCTAssertTrue(option.recommended)
        XCTAssertEqual(option.readyAt, s.originalReadyAt)
        XCTAssertEqual(result.estimatedReadyAt.timeIntervalSince(TestClock.date(10, 17)), 0, accuracy: 15 * 60)
    }

    func testReadyDoughSaysShapeNow() throws {
        let s = startedSession()
        let result = checkIn(s, at: TestClock.date(10, 16, 30), rise: 76)
        XCTAssertEqual(result.options.first?.kind, .shapeNow)
    }

    func testSlowDoughThatWouldPeakOvernightOffersTheFridge() throws {
        let s = startedSession()
        // 6 h in with only 30% of a 75% target → progress 0.4 → ready ≈ 15 h after mixing = Sunday 01:00 (asleep).
        let now = TestClock.date(10, 16)
        let result = checkIn(s, at: now, rise: 30)
        XCTAssertEqual(result.estimatedReadyAt.timeIntervalSince(TestClock.date(11, 1)), 0, accuracy: 60)

        let fridge = try XCTUnwrap(result.options.first { $0.kind == .fridgeNow })
        XCTAssertTrue(fridge.recommended)
        XCTAssertEqual(fridge.shapeAt, TestClock.date(11, 7), "Shape as soon as sleep ends")
        XCTAssertEqual(fridge.bulkEndsAt, TestClock.date(10, 22, 50), "Into the fridge just before bed")
        XCTAssertGreaterThan(fridge.readyAt, s.originalReadyAt, "Honest: the loaf comes out later")

        let stayUp = try XCTUnwrap(result.options.first { $0.kind == .stayUp })
        XCTAssertEqual(stayUp.conflictLabel, "Sleep")
        XCTAssertFalse(stayUp.recommended)

        var applied = s
        applied.apply(fridge)
        XCTAssertNotNil(applied.plan.step("cold-bulk"))
        XCTAssertEqual(applied.plan.step("bulk")?.end, fridge.bulkEndsAt)
        XCTAssertEqual(applied.plan.attendedConflicts(worker), [])
        XCTAssertEqual(applied.replanCount, 1)
    }

    func testVeryYoungDoughIsNotSentToTheFridge() {
        let s = startedSession()
        // Barely moving 2 h in: projected far into the night; too early for a cold bulk.
        let result = checkIn(s, at: TestClock.date(10, 12, 5), rise: 5)
        XCTAssertFalse(result.options.contains { $0.kind == .fridgeNow })
        XCTAssertFalse(result.options.isEmpty, "Always offer something")
    }

    func testRoomProofPlanFallsBackToFridgeRatherThanOfferingNothing() throws {
        // Friday-evening overnight bulk planned for a Saturday-morning room proof; the dough runs fast and
        // would be ready at ~01:00, too young to fridge at bedtime and too early to bake before sleep ends.
        let r = PlanRequest(now: TestClock.date(9, 7, 15), readyBy: TestClock.date(10, 10), kitchenTempC: 21, availability: worker)
        let plan = try XCTUnwrap(Planner.plan(r, calendar: cal).primary)
        XCTAssertEqual(plan.proofMode, .room)
        var s = BakeSession(plan: plan, startedAt: plan.firstStepAt)
        for step in plan.steps where step.attended && step.kind != .shape && step.end <= plan.mixAt.addingTimeInterval(2.5 * 3600) {
            s.complete(step.id, at: step.end)
        }
        let now = s.bulkClockStart.addingTimeInterval(2 * 3600)
        let result = checkIn(s, at: now, rise: 30, temp: 22)
        XCTAssertFalse(result.options.isEmpty)
        XCTAssertEqual(result.options.filter(\.recommended).count, 1, "Exactly one recommendation")
        for option in result.options {
            var applied = s
            applied.apply(option)
            let conflicts = applied.plan.attendedConflicts(worker).filter { !$0.hasPrefix("shape") }
            XCTAssertEqual(conflicts, [], "\(option.kind): only the shape step may knowingly sit in a busy block")
        }
    }

    func testFinishingTheMixLateSlidesFoldsAndShaping() {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var s = BakeSession(plan: plan, startedAt: TestClock.date(10, 9, 55))
        let late: TimeInterval = 25 * 60
        s.complete("mix", at: plan.step("mix")!.end.addingTimeInterval(late))
        XCTAssertEqual(s.plan.step("fold-1")!.start, plan.step("fold-1")!.start.addingTimeInterval(late))
        XCTAssertEqual(s.plan.step("shape")!.start, plan.step("shape")!.start.addingTimeInterval(late))
        XCTAssertEqual(s.plan.step("bake")!.start, plan.step("bake")!.start, "Fridge proof absorbs the delay")
        XCTAssertEqual(s.bulkClockStart, TestClock.date(10, 10, 25))
    }

    func testConflictBannerWhenStepsDriftIntoBusyTime() {
        // Friday evening mix finished 2 h late pushes shaping toward midnight.
        let plan = makeFridgePlan(mixAt: TestClock.date(9, 15, 30), readyAt: TestClock.date(10, 17))
        var s = BakeSession(plan: plan, startedAt: TestClock.date(9, 15))
        s.complete("mix", at: plan.step("mix")!.end.addingTimeInterval(2 * 3600))
        let conflicts = s.upcomingConflicts(now: TestClock.date(9, 18), availability: worker, calendar: cal)
        XCTAssertTrue(conflicts.contains { $0.step.id == "shape" && $0.busyLabel == "Sleep" })
    }

    func testCalibrationSampleRequiresJustRight() throws {
        var s = startedSession()
        s.complete("shape", at: TestClock.date(10, 16, 20))
        XCTAssertNil(s.calibrationSample())
        s.shapeReadiness = .over
        XCTAssertNil(s.calibrationSample())
        s.shapeReadiness = .justRight
        let sample = try XCTUnwrap(s.calibrationSample())
        XCTAssertEqual(sample.actualHours, 6, accuracy: 1e-9)
        XCTAssertEqual(sample.modelHours, 7, accuracy: 1e-9)
        XCTAssertGreaterThan(sample.observedSpeed, 1)
    }

    func testRemindersCoverPendingHandsOnSteps() {
        let s = startedSession()
        let specs = Reminders.specs(for: s, now: TestClock.date(10, 12, 30))
        XCTAssertEqual(specs.map(\.title), ["Check your dough", "Shape", "Preheat oven", "Bake"])
        XCTAssertEqual(specs, specs.sorted { $0.fireAt < $1.fireAt })
    }
}
