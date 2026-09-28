import XCTest
@testable import HearthdayCore

final class PlannerTests: XCTestCase {
    let cal = TestClock.calendar
    let worker = Availability.typicalWeekdayWorker

    func request(now: Date, readyBy: Date, temp: Double = 21) -> PlanRequest {
        PlanRequest(now: now, readyBy: readyBy, kitchenTempC: temp, availability: worker)
    }

    func testFridayMorningToSaturdayBreakfastFitsAroundWorkAndSleep() throws {
        // Friday 07:15 → loaf out Saturday 10:00.
        let result = Planner.plan(request(now: TestClock.date(9, 7, 15), readyBy: TestClock.date(10, 10)), calendar: cal)
        let plan = try XCTUnwrap(result.primary, "Expected a plan, got \(result)")
        XCTAssertEqual(plan.readyAt, TestClock.date(10, 10))
        XCTAssertEqual(plan.attendedConflicts(worker), [])
        XCTAssertNotNil(plan.step("feed"))
        XCTAssertNotNil(plan.step("shape"))
    }

    /// Property check across a week of requested times: every feasible plan must keep hands-on work out of
    /// busy blocks and respect the process rules; every infeasible answer must come with a reason.
    func testInvariantsAcrossAWeekOfRequests() throws {
        let now = TestClock.date(5, 6, 0)
        var feasible = 0
        var feasibleWhenOvenSlotFree = 0
        var ovenSlotFree = 0
        let timeline = worker.timeline(from: now, to: now.addingTimeInterval(140 * 3600), calendar: cal)
        for hoursAhead in stride(from: 24, through: 132, by: 3) {
            for temp in [19.0, 23.0] {
                let readyBy = now.addingTimeInterval(TimeInterval(hoursAhead) * 3600)
                let r = request(now: now, readyBy: readyBy, temp: temp)
                let slotFree = timeline.isFree(start: readyBy.addingTimeInterval(-90 * 60), duration: 90 * 60)
                if slotFree { ovenSlotFree += 1 }
                switch Planner.plan(r, calendar: cal) {
                case let .feasible(plan, alternatives):
                    feasible += 1
                    if slotFree { feasibleWhenOvenSlotFree += 1 }
                    for p in [plan] + alternatives {
                        try assertValid(p, request: r)
                    }
                case let .infeasible(info):
                    XCTAssertFalse(info.message.isEmpty)
                    let earliest = try XCTUnwrap(info.earliestFeasibleReadyAt, "Always suggest a workable time within 3 days")
                    XCTAssertGreaterThan(earliest, readyBy)
                    if !slotFree {
                        XCTAssertEqual(info.reason, .bakeConflict, "A busy oven slot should be named as the blocker")
                    }
                case let .invalid(problems):
                    XCTFail("Valid request reported as invalid: \(problems)")
                }
            }
        }
        XCTAssertGreaterThan(feasible, 0)
        // When the baker is free to bake at the requested time, the planner should almost always find a way.
        XCTAssertGreaterThanOrEqual(Double(feasibleWhenOvenSlotFree) / Double(ovenSlotFree), 0.8,
                                    "\(feasibleWhenOvenSlotFree)/\(ovenSlotFree) free oven slots were plannable")
    }

    func assertValid(_ plan: BakePlan, request r: PlanRequest, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(plan.attendedConflicts(worker), [], file: file, line: line)
        XCTAssertGreaterThanOrEqual(plan.firstStepAt, r.now, file: file, line: line)
        XCTAssertLessThanOrEqual(plan.readyAt, r.readyBy, file: file, line: line)
        XCTAssertEqual(plan.steps, plan.steps.sorted { $0.start < $1.start || ($0.start == $1.start) }, file: file, line: line)
        let mix = try XCTUnwrap(plan.step("mix"))
        let shape = try XCTUnwrap(plan.step("shape"))
        let bake = try XCTUnwrap(plan.step("bake"))
        if let feed = plan.step("feed") { XCTAssertLessThan(feed.start, mix.start, file: file, line: line) }
        XCTAssertGreaterThanOrEqual(shape.start, try XCTUnwrap(shape.likelyStart), file: file, line: line)
        XCTAssertLessThanOrEqual(shape.start, try XCTUnwrap(shape.likelyEnd), file: file, line: line)
        if plan.proofMode == .fridge {
            let retard = bake.start.timeIntervalSince(shape.end) / 3600
            XCTAssert((r.process.retardMinHours...r.process.retardMaxHours).contains(retard), "retard \(retard) h", file: file, line: line)
            XCTAssertEqual(plan.readyAt, r.readyBy, file: file, line: line)
        } else {
            XCTAssertGreaterThanOrEqual(plan.readyAt, r.readyBy.addingTimeInterval(-TimeInterval(r.process.roomFinishSlackMinutes * 60)), file: file, line: line)
        }
    }

    func testTooSoonIsExplainedWithEarliestWorkableTime() throws {
        let r = request(now: TestClock.date(5, 18), readyBy: TestClock.date(5, 21))
        guard case let .infeasible(info) = Planner.plan(r, calendar: cal) else {
            return XCTFail("3 hours is not enough for sourdough")
        }
        XCTAssertEqual(info.reason, .notEnoughTime)
        let earliest = try XCTUnwrap(info.earliestFeasibleReadyAt)
        var retry = r
        retry.readyBy = earliest
        XCTAssertNotNil(Planner.plan(retry, calendar: cal).primary, "The suggested time must itself be plannable")
    }

    func testBakingDuringWorkNamesTheBlock() {
        let r = request(now: TestClock.date(5, 7), readyBy: TestClock.date(7, 12))
        guard case let .infeasible(info) = Planner.plan(r, calendar: cal) else {
            return XCTFail("Loaf out at noon Wednesday needs someone home to bake")
        }
        XCTAssertEqual(info.reason, .bakeConflict)
        XCTAssertEqual(info.blockingLabel, "Work")
        XCTAssertTrue(info.message.contains("Work"))
    }

    func testSamePlanEveryTime() {
        let r = request(now: TestClock.date(9, 7, 15), readyBy: TestClock.date(10, 10))
        XCTAssertEqual(Planner.plan(r, calendar: cal), Planner.plan(r, calendar: cal))
    }

    func testLeversAreOnlyUsedWhenAllowed() throws {
        // Same-day Saturday loaf with an active starter, room proof only, usual starter percentage.
        var r = request(now: TestClock.date(10, 7), readyBy: TestClock.date(10, 20))
        r.starterNeedsFeed = false
        r.allowInoculationAdjustment = false
        r.proofModes = [.room]
        let plan = try XCTUnwrap(Planner.plan(r, calendar: cal).primary)
        XCTAssertEqual(plan.inoculationPercent, r.formula.starterPercent)
        XCTAssertEqual(plan.proofMode, .room)
        XCTAssertNil(plan.step("cold-proof"))

        var fixedFeed = request(now: TestClock.date(10, 7), readyBy: TestClock.date(11, 12))
        fixedFeed.allowFeedRatioAdjustment = false
        fixedFeed.preferredFeedRatio = .oneFiveFive
        XCTAssertEqual(try XCTUnwrap(Planner.plan(fixedFeed, calendar: cal).primary).feedRatio, .oneFiveFive)
    }

    func testSameDayFromAColdStarterIsHonestlyImpossible() {
        // Feeding alone takes ~8½ h at 21 °C, so an 8 pm loaf from a 7 am start cannot work.
        var r = request(now: TestClock.date(10, 7), readyBy: TestClock.date(10, 20))
        r.proofModes = [.room]
        guard case let .infeasible(info) = Planner.plan(r, calendar: cal) else {
            return XCTFail("Should not squeeze fermentation to fit")
        }
        XCTAssertNotNil(info.earliestFeasibleReadyAt)
    }

    func testActiveStarterSkipsFeeding() throws {
        var r = request(now: TestClock.date(10, 8), readyBy: TestClock.date(11, 11))
        r.starterNeedsFeed = false
        let plan = try XCTUnwrap(Planner.plan(r, calendar: cal).primary)
        XCTAssertNil(plan.step("feed"))
        XCTAssertNil(plan.feedRatio)
    }

    func testFasterPersonalDoughShortensExpectedBulk() throws {
        var slow = request(now: TestClock.date(10, 7), readyBy: TestClock.date(11, 11))
        slow.allowInoculationAdjustment = false
        var fast = slow
        fast.model.speedFactor = 1.3
        let a = try XCTUnwrap(Planner.plan(slow, calendar: cal).primary)
        let b = try XCTUnwrap(Planner.plan(fast, calendar: cal).primary)
        XCTAssertLessThan(b.expectedBulkHours, a.expectedBulkHours)
        XCTAssertEqual(b.modelBulkHours, a.modelBulkHours, accuracy: 1e-9, "Calibration must not leak into the textbook baseline")
    }

    func testAlternativesDifferFromPrimary() throws {
        let result = Planner.plan(request(now: TestClock.date(10, 7), readyBy: TestClock.date(11, 17)), calendar: cal)
        guard case let .feasible(primary, alternatives) = result else { return XCTFail() }
        let signatures = Set(([primary] + alternatives).map(Planner.signature))
        XCTAssertEqual(signatures.count, alternatives.count + 1)
    }

    func testWiderUncertaintyNeverMakesPlanningEasier() {
        // With a narrower window the shape slot is easier to fit; a wider one should not create plans out of nothing.
        var narrow = request(now: TestClock.date(5, 6), readyBy: TestClock.date(6, 19))
        narrow.model.uncertainty = 0.1
        var wide = narrow
        wide.model.uncertainty = 0.3
        if Planner.plan(wide, calendar: cal).primary != nil {
            XCTAssertNotNil(Planner.plan(narrow, calendar: cal).primary)
        }
    }
}
