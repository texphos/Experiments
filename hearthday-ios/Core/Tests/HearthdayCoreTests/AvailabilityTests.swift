import XCTest
@testable import HearthdayCore

final class AvailabilityTests: XCTestCase {
    let availability = Availability.typicalWeekdayWorker
    let cal = TestClock.calendar

    func testOvernightSleepBlockWrapsPastMidnight() {
        let timeline = availability.timeline(from: TestClock.date(5, 0), to: TestClock.date(7, 0), calendar: cal)
        XCTAssertEqual(timeline.conflict(start: TestClock.date(6, 2), duration: 600)?.label, "Sleep")
        XCTAssertEqual(timeline.conflict(start: TestClock.date(5, 22, 50), duration: 20 * 60)?.label, "Sleep", "Overlapping the start of sleep counts")
        XCTAssertTrue(timeline.isFree(start: TestClock.date(6, 7), duration: 60 * 60))
        XCTAssertTrue(timeline.isFree(start: TestClock.date(5, 22, 40), duration: 20 * 60), "Ending exactly at 23:00 is fine")
    }

    func testWorkBlockOnlyOnWeekdays() {
        let timeline = availability.timeline(from: TestClock.date(9, 0), to: TestClock.date(12, 0), calendar: cal)
        XCTAssertEqual(timeline.conflict(start: TestClock.date(9, 12), duration: 600)?.label, "Work", "Friday")
        XCTAssertTrue(timeline.isFree(start: TestClock.date(10, 12), duration: 600), "Saturday")
        XCTAssertTrue(timeline.isFree(start: TestClock.date(11, 12), duration: 600), "Sunday")
    }

    func testEarliestFreeStartJumpsPastConsecutiveBlocks() {
        let timeline = availability.timeline(from: TestClock.date(5, 0), to: TestClock.date(8, 0), calendar: cal)
        // Monday 22:50, 30 min task: runs into sleep → next free is Tuesday 07:00, 30 min fits before work at 08:30.
        let t = timeline.earliestFreeStart(atOrAfter: TestClock.date(5, 22, 50), duration: 30 * 60, limit: TestClock.date(8, 0))
        XCTAssertEqual(t, TestClock.date(6, 7))
        // A 2 h task on Tuesday morning cannot fit 07:00–08:30, so it moves to after work.
        let long = timeline.earliestFreeStart(atOrAfter: TestClock.date(6, 7), duration: 2 * 3600, limit: TestClock.date(8, 0))
        XCTAssertEqual(long, TestClock.date(6, 17, 30))
    }

    func testBlockDuration() {
        XCTAssertEqual(availability.blocks[0].durationMinutes, 8 * 60)
        XCTAssertEqual(availability.blocks[1].durationMinutes, 9 * 60)
    }
}
