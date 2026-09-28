import XCTest
@testable import HearthdayCore

/// Reminders are derived from the active plan, so every plan change must change what gets scheduled.
final class RemindersTests: XCTestCase {
    let cal = TestClock.calendar

    func started() -> BakeSession {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var s = BakeSession(plan: plan, startedAt: TestClock.date(10, 9, 55))
        s.complete("mix", at: plan.step("mix")!.end)
        return s
    }

    func testOneReminderPerPendingHandsOnStepAtItsStart() {
        let s = started()
        let now = TestClock.date(10, 10, 20)
        let specs = Reminders.specs(for: s, now: now)
        let expected = s.plan.steps.filter { $0.attended && !s.isDone($0) && $0.start > now }
        XCTAssertEqual(specs.filter { !$0.id.hasSuffix("-check") }.map(\.fireAt), expected.map(\.start))
        XCTAssertTrue(specs.allSatisfy { $0.id.hasPrefix(s.id.uuidString) })
        XCTAssertEqual(specs.map(\.fireAt), specs.map(\.fireAt).sorted())
    }

    func testApplyingAReplanMovesTheShapeAndBakeReminders() throws {
        var s = started()
        for i in 1...4 { s.complete("fold-\(i)", at: s.plan.step("fold-\(i)")!.end) }
        let now = TestClock.date(10, 16)
        let before = Reminders.specs(for: s, now: now)
        let result = LiveReplanner.checkIn(session: s, now: now, risePercent: 30, tempC: 21,
                                           availability: .typicalWeekdayWorker, calendar: cal, model: FermentationModel())
        let fridge = try XCTUnwrap(result.options.first { $0.kind == .fridgeNow })
        s.apply(fridge)
        let after = Reminders.specs(for: s, now: now)

        XCTAssertNotEqual(before, after)
        let shape = try XCTUnwrap(after.first { $0.id.hasSuffix("-shape") })
        XCTAssertEqual(shape.fireAt, fridge.shapeAt)
        XCTAssertFalse(after.contains { $0.fireAt == before.first { $0.id.hasSuffix("-shape") }?.fireAt },
                       "The old shape time is no longer scheduled")
        let bake = try XCTUnwrap(after.first { $0.id.hasSuffix("-bake") })
        XCTAssertEqual(bake.fireAt, s.plan.step("bake")!.start)
    }

    func testMixingLateSlidesTheDoughReminders() {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var onTime = BakeSession(plan: plan, startedAt: TestClock.date(10, 9))
        var late = onTime
        onTime.complete("mix", at: plan.step("mix")!.end)
        late.complete("mix", at: plan.step("mix")!.end.addingTimeInterval(45 * 60))
        let a = Reminders.specs(for: onTime, now: TestClock.date(10, 10))
        let b = Reminders.specs(for: late, now: TestClock.date(10, 10))
        let foldA = a.first { $0.id.hasSuffix("-fold-1") }!.fireAt
        let foldB = b.first { $0.id.hasSuffix("-fold-1") }!.fireAt
        XCTAssertEqual(foldB.timeIntervalSince(foldA), 45 * 60)
    }

    func testCompletingAStepRemovesItsReminderAndFinishingRemovesAll() {
        var state = AppState()
        state.start(makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11)), now: TestClock.date(10, 9))
        let now = TestClock.date(10, 9, 30)
        XCTAssertTrue(Reminders.specs(for: state.activeSession!, now: now).contains { $0.id.hasSuffix("-mix") })
        state.completeStep("mix", at: now)
        XCTAssertFalse(Reminders.specs(for: state.activeSession!, now: now).contains { $0.id.hasSuffix("-mix") })
        state.finishActiveBake(rating: nil, notes: "", at: TestClock.date(11, 11))
        XCTAssertNil(state.activeSession, "No session means the app schedules nothing")
    }

    func testEarlyCheckNudgeOnlyWhenTheLikelyWindowOpensWellBeforeShaping() {
        let s = started()
        let specs = Reminders.specs(for: s, now: TestClock.date(10, 10, 20))
        let check = specs.first { $0.id.hasSuffix("-check") }
        XCTAssertNotNil(check)
        XCTAssertEqual(check?.fireAt, s.plan.step("shape")?.likelyStart)
        XCTAssertFalse(check!.body.lowercased().contains("ready now"), "The nudge says 'could be', not 'is'")
    }
}
