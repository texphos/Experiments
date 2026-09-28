import XCTest
@testable import HearthdayCore

/// Recurring busy blocks are wall-clock commitments. Across a daylight-saving change the real length of
/// "Sleep 23:00–07:00" changes, and the block must still end at 07:00 local time.
final class DSTTests: XCTestCase {
    func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    lazy var newYork = calendar("America/New_York")

    func ny(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    let sleep = BusyBlock(label: "Sleep", kind: .sleep, weekdays: BusyBlock.everyDay, startMinute: 23 * 60, endMinute: 7 * 60)

    func sleepInterval(startingOn month: Int, _ day: Int) throws -> BusyInterval {
        let intervals = Availability(blocks: [sleep]).intervals(from: ny(month, day, 12), to: ny(month, day + 1, 12), calendar: newYork)
        return try XCTUnwrap(intervals.first { newYork.component(.day, from: $0.start) == day })
    }

    func testSpringForwardNightIsSevenRealHoursAndEndsAtSevenLocal() throws {
        // 2026-03-08 02:00 EST → 03:00 EDT.
        let night = try sleepInterval(startingOn: 3, 7)
        XCTAssertEqual(night.start, ny(3, 7, 23))
        XCTAssertEqual(night.end, ny(3, 8, 7))
        XCTAssertEqual(night.end.timeIntervalSince(night.start), 7 * 3600)
    }

    func testFallBackNightIsNineRealHoursAndEndsAtSevenLocal() throws {
        // 2026-11-01 02:00 EDT → 01:00 EST.
        let night = try sleepInterval(startingOn: 10, 31)
        XCTAssertEqual(night.start, ny(10, 31, 23))
        XCTAssertEqual(night.end, ny(11, 1, 7))
        XCTAssertEqual(night.end.timeIntervalSince(night.start), 9 * 3600)
    }

    func testTimeFreedBySpringForwardIsFreeAndTimeAddedByFallBackIsBusy() {
        let timeline = Availability(blocks: [sleep]).timeline(from: ny(3, 7, 0), to: ny(11, 2, 0), calendar: newYork)
        // A fixed 8 h duration would wrongly keep 07:00–08:00 EDT busy on 8 March.
        XCTAssertTrue(timeline.isFree(start: ny(3, 8, 7, 15), duration: 20 * 60))
        // …and would wrongly free 06:00–07:00 EST on 1 November.
        XCTAssertFalse(timeline.isFree(start: ny(11, 1, 6, 15), duration: 20 * 60))
    }

    func testBlockStartingInTheSkippedHourMovesForwardByTheGap() throws {
        let early = BusyBlock(label: "Early", kind: .other, weekdays: [1], startMinute: 2 * 60 + 30, endMinute: 4 * 60)
        let interval = try XCTUnwrap(Availability(blocks: [early]).intervals(from: ny(3, 8, 0), to: ny(3, 8, 12), calendar: newYork).first)
        XCTAssertEqual(interval.start, ny(3, 8, 3, 30))
        XCTAssertEqual(interval.end, ny(3, 8, 4))
    }

    func testBlockStartingInTheRepeatedHourUsesTheFirstOccurrence() throws {
        let early = BusyBlock(label: "Early", kind: .other, weekdays: [1], startMinute: 90, endMinute: 3 * 60)
        let interval = try XCTUnwrap(Availability(blocks: [early]).intervals(from: ny(11, 1, 0), to: ny(11, 1, 12), calendar: newYork).first)
        XCTAssertEqual(interval.start, Date(timeIntervalSince1970: 1_793_511_000), "01:30 EDT (05:30 UTC)")
        XCTAssertEqual(interval.end, ny(11, 1, 3), "03:00 EST")
        XCTAssertEqual(interval.end.timeIntervalSince(interval.start), 2.5 * 3600)
    }

    /// Every night of 2026, in zones with northern, southern and no DST, starts at 23:00 and ends at 07:00 local.
    func testEveryNightOfTheYearKeepsWallClockTimesInSeveralZones() {
        for zone in ["America/New_York", "Europe/London", "Australia/Sydney", "Asia/Tokyo", "Asia/Kolkata"] {
            let cal = calendar(zone)
            let from = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
            let to = cal.date(from: DateComponents(year: 2027, month: 1, day: 1))!
            let nights = Availability(blocks: [sleep]).intervals(from: from, to: to, calendar: cal)
            XCTAssertGreaterThanOrEqual(nights.count, 365, zone)
            for night in nights {
                let s = cal.dateComponents([.hour, .minute], from: night.start)
                let e = cal.dateComponents([.hour, .minute], from: night.end)
                XCTAssertEqual([s.hour, s.minute, e.hour, e.minute], [23, 0, 7, 0], "\(zone) \(night.start)")
                XCTAssertEqual(cal.dateComponents([.day], from: cal.startOfDay(for: night.start), to: cal.startOfDay(for: night.end)).day, 1)
            }
        }
    }

    func testPlanAcrossSpringForwardKeepsHandsOnStepsOutOfLocalBusyTime() throws {
        let request = PlanRequest(now: ny(3, 6, 18), readyBy: ny(3, 8, 11), kitchenTempC: 21)
        let plan = try XCTUnwrap(Planner.plan(request, calendar: newYork).primary)
        XCTAssertEqual(plan.readyAt, ny(3, 8, 11), "Fridge plans finish on the requested local time")
        XCTAssertEqual(plan.attendedConflicts(.typicalWeekdayWorker, calendar: newYork), [])
    }

    func testPlanAcrossFallBackKeepsHandsOnStepsOutOfLocalBusyTime() throws {
        let request = PlanRequest(now: ny(10, 30, 18), readyBy: ny(11, 1, 11), kitchenTempC: 21)
        let plan = try XCTUnwrap(Planner.plan(request, calendar: newYork).primary)
        XCTAssertEqual(plan.attendedConflicts(.typicalWeekdayWorker, calendar: newYork), [])
    }

    /// Plans store absolute instants; the same plan read in a new time zone is re-checked against the
    /// baker's busy times *in that zone*, so travel surfaces real conflicts instead of hiding them.
    func testChangingTimeZoneReevaluatesConflictsAgainstLocalBusyTimes() throws {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var session = BakeSession(plan: plan, startedAt: TestClock.date(10, 9))
        session.complete("mix", at: plan.step("mix")!.end)
        let now = TestClock.date(10, 11)
        XCTAssertEqual(session.upcomingConflicts(now: now, availability: .typicalWeekdayWorker, calendar: TestClock.calendar), [])
        let tokyo = session.upcomingConflicts(now: now, availability: .typicalWeekdayWorker, calendar: calendar("Asia/Tokyo"))
        XCTAssertFalse(tokyo.isEmpty, "Saturday 10:00 UTC folds land at 19:00+ Tokyo time; shaping lands during Tokyo sleep")
        XCTAssertTrue(tokyo.contains { $0.busyLabel == "Sleep" })
    }
}
