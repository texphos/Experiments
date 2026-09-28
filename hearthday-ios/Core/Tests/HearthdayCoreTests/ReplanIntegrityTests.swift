import XCTest
@testable import HearthdayCore

/// Regression tests for re-planning and late completions: the fridge transfer is a real hands-on step, chilled
/// bulks never feed calibration or room-temperature check-ins, cold proofs stay workable, and plans stay in order
/// through repeated check-ins.
final class ReplanIntegrityTests: XCTestCase {
    let cal = TestClock.calendar
    let worker = Availability.typicalWeekdayWorker
    let model = FermentationModel()
    let process = ProcessSettings()

    /// Saturday 10 October: mix 10:00, loaf out Sunday 11:00; mix and folds done on time.
    func startedSession(readyAt: Date = TestClock.date(11, 11), foldsDone: Int = 4) -> BakeSession {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: readyAt)
        var s = BakeSession(plan: plan, startedAt: TestClock.date(10, 9, 55))
        s.complete("mix", at: plan.step("mix")!.end)
        if foldsDone > 0 {
            for i in 1...foldsDone { s.complete("fold-\(i)", at: plan.step("fold-\(i)")!.end) }
        }
        return s
    }

    func checkIn(_ s: BakeSession, at now: Date, rise: Double, availability: Availability? = nil) -> CheckInResult {
        LiveReplanner.checkIn(session: s, now: now, risePercent: rise, tempC: 21, availability: availability ?? worker, calendar: cal, model: model)
    }

    /// Every step runs forwards, pending folds end before bulk does, the fridge transfer precedes the cold bulk,
    /// cold bulk ends before shaping, and a pending cold proof is within its workable range and ends at the bake.
    func assertChronology(_ s: BakeSession, file: StaticString = #filePath, line: UInt = #line) {
        for step in s.plan.steps {
            XCTAssertLessThanOrEqual(step.start, step.end, "\(step.id) runs backwards", file: file, line: line)
        }
        let bulkEnd = s.plan.step("bulk")?.end
        for fold in s.plan.steps where fold.kind == .fold && s.completed[fold.id] == nil {
            if let bulkEnd { XCTAssertLessThanOrEqual(fold.end, bulkEnd, "\(fold.id) after the end of bulk", file: file, line: line) }
        }
        if let shape = s.plan.step("shape"), s.completed["shape"] == nil {
            for fold in s.plan.steps where fold.kind == .fold && s.completed[fold.id] == nil {
                XCTAssertLessThanOrEqual(fold.end, shape.start, "\(fold.id) after shaping", file: file, line: line)
            }
            if let cold = s.plan.step("cold-bulk") {
                XCTAssertLessThanOrEqual(cold.end, shape.start, file: file, line: line)
            }
        }
        if let transfer = s.plan.step("fridge"), let cold = s.plan.step("cold-bulk") {
            XCTAssertLessThanOrEqual(transfer.end, cold.start, file: file, line: line)
            XCTAssertEqual(transfer.start, bulkEnd, "Bulk at room temperature ends when the dough goes in", file: file, line: line)
        }
        if let retard = s.plan.step("cold-proof"), let bake = s.plan.step("bake"), let preheat = s.plan.step("preheat"),
           s.completed["bake"] == nil {
            let hours = retard.end.timeIntervalSince(retard.start) / 3600
            XCTAssertGreaterThanOrEqual(hours, process.retardMinHours - 1e-9, "cold proof too short", file: file, line: line)
            XCTAssertLessThanOrEqual(hours, process.retardMaxHours + 1e-9, "cold proof too long", file: file, line: line)
            XCTAssertEqual(retard.end, bake.start, file: file, line: line)
            XCTAssertEqual(preheat.end, bake.start, file: file, line: line)
        }
    }

    // MARK: Fridge transfer is a real, scheduled, hands-on step

    func testFridgeOptionStartsWithAHandsOnTransferInFreeTime() throws {
        let s = startedSession()
        let fridge = try XCTUnwrap(checkIn(s, at: TestClock.date(10, 16), rise: 30).options.first { $0.kind == .fridgeNow })
        let transfer = try XCTUnwrap(fridge.steps.first)
        XCTAssertEqual(transfer.kind, .fridgeDough)
        XCTAssertTrue(transfer.attended)
        XCTAssertEqual(transfer.start, TestClock.date(10, 22, 50), "Ten minutes before bed")
        XCTAssertEqual(transfer.duration, TimeInterval(LiveReplanner.fridgeTransferMinutes * 60))
        XCTAssertEqual(fridge.steps[1].kind, .coldBulk)
        XCTAssertEqual(fridge.steps[1].start, transfer.end)
        XCTAssertFalse(fridge.steps[1].attended)

        var applied = s
        applied.apply(fridge)
        XCTAssertEqual(applied.plan.attendedConflicts(worker), [], "Nothing hands-on lands in busy time, including the transfer")
        assertChronology(applied)
    }

    func testFridgeTransferGetsAReminderAndNoEarlyCheckNudge() throws {
        var s = startedSession()
        let fridge = try XCTUnwrap(checkIn(s, at: TestClock.date(10, 16), rise: 30).options.first { $0.kind == .fridgeNow })
        s.apply(fridge)
        let specs = Reminders.specs(for: s, now: TestClock.date(10, 16, 1), availability: worker, calendar: cal)
        let first = try XCTUnwrap(specs.first)
        XCTAssertEqual(first.title, "Put the dough in the fridge")
        XCTAssertEqual(first.fireAt, TestClock.date(10, 22, 50))
        XCTAssertFalse(specs.contains { $0.title == "Check your dough" })

        s.complete("fridge", at: TestClock.date(10, 22, 55))
        let after = Reminders.specs(for: s, now: TestClock.date(10, 22, 56), availability: worker, calendar: cal)
        XCTAssertFalse(after.contains { $0.title == "Put the dough in the fridge" })
        XCTAssertEqual(after.first?.title, "Shape")
    }

    func testTransferMovesToNowWhenTheSlotBeforeTheBusyBlockIsTaken() throws {
        var blocks = worker.blocks
        blocks.append(BusyBlock(label: "Walk the dog", kind: .other, weekdays: BusyBlock.everyDay, startMinute: 22 * 60 + 45, endMinute: 22 * 60 + 55))
        let busyEvening = Availability(blocks: blocks)
        let s = startedSession()
        let now = TestClock.date(10, 16)
        let fridge = try XCTUnwrap(checkIn(s, at: now, rise: 30, availability: busyEvening).options.first { $0.kind == .fridgeNow })
        XCTAssertEqual(fridge.steps.first?.start, now)
        var applied = s
        applied.apply(fridge)
        XCTAssertEqual(applied.plan.attendedConflicts(busyEvening), [])
    }

    // MARK: Chilled bulks never teach calibration or re-enter the room-temperature model

    func testChilledBakeIsExcludedFromCalibrationEvenAfterTheFridgeStepIsGone() throws {
        var s = startedSession()
        let result = checkIn(s, at: TestClock.date(10, 16), rise: 30)
        let fridge = try XCTUnwrap(result.options.first { $0.kind == .fridgeNow })
        let stayUp = try XCTUnwrap(result.options.first { $0.kind == .stayUp })
        s.apply(fridge)
        s.complete("fridge", at: TestClock.date(10, 22, 55))
        XCTAssertTrue(s.isChilled)
        XCTAssertFalse(s.canCheckIn)

        s.apply(stayUp)
        XCTAssertNotNil(s.plan.step("cold-bulk"), "A stale option can't wipe out the fridge time")
        XCTAssertEqual(s.replanCount, 1)

        s.plan.steps.removeAll { $0.kind == .coldBulk || $0.kind == .fridgeDough }
        XCTAssertTrue(s.isChilled, "Completion of the transfer is remembered even if the plan loses the steps")

        s.complete("shape", at: TestClock.date(11, 7, 20))
        s.shapeReadiness = .justRight
        XCTAssertNil(s.calibrationSample())
        let roomHours = try XCTUnwrap(s.actualBulkHours)
        XCTAssertEqual(roomHours, TestClock.date(10, 22, 50).timeIntervalSince(s.bulkClockStart) / 3600, accuracy: 1e-9,
                       "Journal bulk time counts room temperature only, not the night in the fridge")
    }

    func testCheckInsAreRefusedOnceTheDoughIsChilled() throws {
        var s = startedSession()
        s.apply(try XCTUnwrap(checkIn(s, at: TestClock.date(10, 16), rise: 30).options.first { $0.kind == .fridgeNow }))
        XCTAssertTrue(s.canCheckIn, "Until the dough actually goes in, the baker can still re-plan")
        s.complete("fridge", at: TestClock.date(10, 22, 55))
        let late = checkIn(s, at: TestClock.date(11, 6), rise: 60)
        XCTAssertEqual(late.problems, [.doughIsChilled])
        XCTAssertTrue(late.options.isEmpty)
    }

    func testBakeSavedBeforeTheTransferStepExistedCountsAsChilled() throws {
        var s = startedSession()
        s.apply(try XCTUnwrap(checkIn(s, at: TestClock.date(10, 16), rise: 30).options.first { $0.kind == .fridgeNow }))
        s.plan.steps.removeAll { $0.kind == .fridgeDough }
        XCTAssertTrue(s.isChilled)
        XCTAssertEqual(checkIn(s, at: TestClock.date(11, 6), rise: 60).problems, [.doughIsChilled])
    }

    func testCheckInOutsideBulkIsRefused() {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        let notMixed = BakeSession(plan: plan, startedAt: TestClock.date(10, 9))
        XCTAssertEqual(checkIn(notMixed, at: TestClock.date(10, 9, 30), rise: 10).problems, [.notInBulk])
    }

    // MARK: Late or early completions never leave an impossible cold proof

    func testShapingLateMovesTheBakeToKeepTheMinimumColdProof() throws {
        var s = startedSession()
        s.complete("shape", at: TestClock.date(11, 3), availability: worker, calendar: cal)
        assertChronology(s)
        XCTAssertEqual(s.plan.step("bake")?.start, TestClock.date(11, 11), "03:00 + 8 h, on the 15-minute grid")
        XCTAssertNotNil(s.adjustmentNote)
        XCTAssertEqual(s.plan.attendedConflicts(worker).filter { !$0.hasPrefix("shape") }, [])
    }

    func testShapingAfterThePlannedBakeTimeNeverLeavesANegativeProof() throws {
        var s = startedSession()
        s.complete("shape", at: TestClock.date(11, 12), availability: worker, calendar: cal)
        assertChronology(s)
        let retard = try XCTUnwrap(s.plan.step("cold-proof"))
        XCTAssertEqual(retard.start, TestClock.date(11, 12))
        XCTAssertGreaterThanOrEqual(s.plan.step("bake")!.start, TestClock.date(11, 20))
    }

    func testMixingVeryLateMovesTheBakeAndPrefersFreeOvenTime() throws {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var s = BakeSession(plan: plan, startedAt: TestClock.date(10, 9, 55))
        s.complete("mix", at: plan.step("mix")!.end.addingTimeInterval(14 * 3600), availability: worker, calendar: cal)
        assertChronology(s)
        XCTAssertNotNil(s.adjustmentNote)
        let bake = try XCTUnwrap(s.plan.step("bake"))
        let preheat = try XCTUnwrap(s.plan.step("preheat"))
        let timeline = worker.timeline(from: preheat.start.addingTimeInterval(-3600), to: bake.end.addingTimeInterval(3600), calendar: cal)
        XCTAssertTrue(timeline.isFree(start: preheat.start, duration: bake.end.timeIntervalSince(preheat.start)))
    }

    func testShapingEarlyNeverStretchesTheColdProofPastItsMaximum() throws {
        var s = startedSession(readyAt: TestClock.date(12, 5))
        XCTAssertGreaterThan(s.plan.step("cold-proof")!.duration / 3600, 34)
        s.complete("shape", at: TestClock.date(10, 15, 20), availability: worker, calendar: cal)
        assertChronology(s)
        XCTAssertNotNil(s.adjustmentNote)
        let bake = try XCTUnwrap(s.plan.step("bake"))
        let preheat = try XCTUnwrap(s.plan.step("preheat"))
        let timeline = worker.timeline(from: preheat.start.addingTimeInterval(-3600), to: bake.end.addingTimeInterval(3600), calendar: cal)
        XCTAssertTrue(timeline.isFree(start: preheat.start, duration: bake.end.timeIntervalSince(preheat.start)), "Not at 3 AM")
    }

    func testOnTimeCompletionsLeaveTheBakeAlone() {
        var s = startedSession()
        let bakeBefore = s.plan.step("bake")!.start
        s.complete("shape", at: s.plan.step("shape")!.end.addingTimeInterval(20 * 60), availability: worker, calendar: cal)
        XCTAssertEqual(s.plan.step("bake")?.start, bakeBefore)
        XCTAssertNil(s.adjustmentNote)
        assertChronology(s)
    }

    // MARK: Chronology through early and repeated check-ins

    func testEarlyShapeDropsFoldsThatWouldComeAfterIt() throws {
        var s = startedSession(foldsDone: 2)
        let now = TestClock.date(10, 11, 10)
        let result = checkIn(s, at: now, rise: 80)
        let shapeNow = try XCTUnwrap(result.options.first { $0.kind == .shapeNow })
        s.apply(shapeNow)
        XCTAssertNil(s.plan.step("fold-3"))
        XCTAssertNil(s.plan.step("fold-4"))
        XCTAssertNotNil(s.plan.step("fold-1"), "Completed folds stay in the record")
        assertChronology(s)
        let specs = Reminders.specs(for: s, now: now, availability: worker, calendar: cal)
        XCTAssertFalse(specs.contains { $0.title.hasPrefix("Fold") })
    }

    func testRepeatedCheckInsReplaceAnUnexecutedFridgeOptionAndStayInOrder() throws {
        var s = startedSession()
        s.apply(try XCTUnwrap(checkIn(s, at: TestClock.date(10, 16), rise: 30).options.first { $0.kind == .fridgeNow }))
        assertChronology(s)

        let second = checkIn(s, at: TestClock.date(10, 17), rise: 76)
        XCTAssertTrue(second.problems.isEmpty)
        let option = try XCTUnwrap(second.options.first)
        XCTAssertEqual(option.kind, .shapeNow)
        s.apply(option)
        XCTAssertNil(s.plan.step("fridge"), "The fridge plan that never happened is gone")
        XCTAssertNil(s.plan.step("cold-bulk"))
        XCTAssertEqual(s.replanCount, 2)
        assertChronology(s)

        let specs = Reminders.specs(for: s, now: TestClock.date(10, 17), availability: worker, calendar: cal)
        XCTAssertEqual(specs, specs.sorted { $0.fireAt < $1.fireAt })
        XCTAssertFalse(specs.contains { $0.title == "Put the dough in the fridge" })

        s.complete("shape", at: s.plan.step("shape")!.end)
        s.shapeReadiness = .justRight
        XCTAssertNotNil(s.calibrationSample(), "Never chilled, so this bake can calibrate")
    }

    func testChronologyHoldsForEveryOptionAcrossADayOfCheckIns() throws {
        for hour in [11, 12, 14, 16, 18, 20, 22] {
            for rise in stride(from: 10.0, through: 90.0, by: 20) {
                let s = startedSession(foldsDone: hour >= 12 ? 4 : 1)
                for option in checkIn(s, at: TestClock.date(10, hour), rise: rise).options {
                    var applied = s
                    applied.apply(option)
                    assertChronology(applied)
                    var later = applied
                    for step in later.plan.steps where step.attended && later.completed[step.id] == nil {
                        later.complete(step.id, at: step.end.addingTimeInterval(90 * 60), availability: worker, calendar: cal)
                        assertChronology(later)
                    }
                }
            }
        }
    }
}
