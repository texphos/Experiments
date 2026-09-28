import XCTest
@testable import HearthdayCore

final class ValidationTests: XCTestCase {
    let now = TestClock.date(9, 7)

    func request(temp: Double = 21, readyBy: Date? = nil, formula: Formula = .countryLoaf) -> PlanRequest {
        PlanRequest(now: now, readyBy: readyBy ?? TestClock.date(10, 10), kitchenTempC: temp, formula: formula)
    }

    func problems(_ r: PlanRequest) -> [InputProblem] {
        if case let .invalid(p) = Planner.plan(r, calendar: TestClock.calendar) { return p }
        return []
    }

    func testDefaultRequestIsValidAndPlans() {
        XCTAssertEqual(request().problems, [])
        XCTAssertNotNil(Planner.plan(request(), calendar: TestClock.calendar).primary)
    }

    func testTemperaturesOutsideTheModelRangeAreRejectedNotExtrapolated() {
        for t in [45.0, 5, -3, .nan, .infinity] {
            XCTAssertEqual(problems(request(temp: t)).map(\.code), ["temperatureOutOfRange"], "\(t)")
        }
        XCTAssertEqual(problems(request(temp: Limits.tempC.lowerBound)), [])
        XCTAssertEqual(problems(request(temp: Limits.tempC.upperBound)), [])
    }

    func testReadyTimesInThePastOrTooFarAheadAreRejected() {
        XCTAssertEqual(problems(request(readyBy: now)).map(\.code), ["readyTimeInPast"])
        XCTAssertEqual(problems(request(readyBy: now.addingTimeInterval(-3600))).map(\.code), ["readyTimeInPast"])
        XCTAssertEqual(problems(request(readyBy: now.addingTimeInterval(8 * 86_400 + 7200))).map(\.code), ["readyTimeTooFar"])
    }

    func testBrokenFormulaIsRejectedBeforeItCanDivideByZero() {
        var f = Formula.countryLoaf
        f.name = "  "
        f.starterPercent = 0
        f.flourGrams = -10
        f.hydrationPercent = 200
        f.saltPercent = .nan
        XCTAssertEqual(
            Set(problems(request(formula: f)).map(\.code)),
            ["formulaNameEmpty", "starterOutOfRange", "flourOutOfRange", "hydrationOutOfRange", "saltOutOfRange"]
        )
    }

    func testEveryProblemHasAPlainMessage() {
        let all: [InputProblem] = [
            .temperatureOutOfRange(0), .riseOutOfRange(0), .readyTimeInPast, .readyTimeTooFar, .formulaNameEmpty,
            .flourOutOfRange(0), .hydrationOutOfRange(0), .starterOutOfRange(0), .saltOutOfRange(0),
            .busyLabelEmpty, .busyNoDays, .busyTimeInvalid, .busyZeroLength,
        ]
        XCTAssertEqual(Set(all.map(\.code)).count, all.count)
        for p in all { XCTAssertTrue(p.message.hasSuffix("."), p.code) }
    }

    func testBusyBlockProblemsAndInvalidBlocksAreIgnoredByPlanning() {
        let zero = BusyBlock(label: "Nap", kind: .other, weekdays: [7], startMinute: 600, endMinute: 600)
        let noDays = BusyBlock(label: "Gym", kind: .other, weekdays: [], startMinute: 600, endMinute: 660)
        let badTime = BusyBlock(label: "", kind: .other, weekdays: [1, 9], startMinute: 1500, endMinute: 60)
        XCTAssertEqual(zero.problems, [.busyZeroLength])
        XCTAssertEqual(noDays.problems, [.busyNoDays])
        XCTAssertEqual(Set(badTime.problems), [.busyLabelEmpty, .busyNoDays, .busyTimeInvalid])
        XCTAssertEqual(BusyBlock(label: "Sleep", kind: .sleep, weekdays: [1], startMinute: 1380, endMinute: 420).problems, [])

        let availability = Availability(blocks: [zero, noDays, badTime])
        XCTAssertTrue(availability.intervals(from: TestClock.date(5, 0), to: TestClock.date(12, 0), calendar: TestClock.calendar).isEmpty)
    }

    func testInvalidCheckInReadingsGiveNoOptionsAndSayWhy() {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var s = BakeSession(plan: plan, startedAt: TestClock.date(10, 10))
        s.complete("mix", at: plan.step("mix")!.end)
        for (rise, temp, code) in [(-5.0, 21.0, "riseOutOfRange"), (500, 21, "riseOutOfRange"), (.nan, 21, "riseOutOfRange"), (40, 60, "temperatureOutOfRange")] {
            let r = LiveReplanner.checkIn(session: s, now: TestClock.date(10, 14), risePercent: rise, tempC: temp,
                                          availability: .typicalWeekdayWorker, calendar: TestClock.calendar, model: FermentationModel())
            XCTAssertTrue(r.options.isEmpty)
            XCTAssertEqual(r.problems.map(\.code), [code])
            XCTAssertFalse(r.summary.isEmpty)
        }
    }

    func testRepairBringsDamagedValuesBackInRangeSoTheStateCanBeSaved() throws {
        var state = AppState()
        state.settings.kitchenTempC = .nan
        state.formulas = []
        XCTAssertTrue(state.repair())
        XCTAssertEqual(state.settings.kitchenTempC, 21)
        XCTAssertEqual(state.formulas.count, 1)

        var f = Formula.countryLoaf
        f.name = ""
        f.starterPercent = 90
        f.hydrationPercent = .infinity
        state.formulas = [f]
        state.repair()
        XCTAssertEqual(state.formulas[0].problems, [])
        XCTAssertEqual(state.formulas[0].starterPercent, Limits.starterPercent.upperBound)
        XCTAssertFalse(state.repair(), "Repair is idempotent")
        XCTAssertNoThrow(try JSONFileStore.encoder.encode(state))
    }
}
