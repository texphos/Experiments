import XCTest
@testable import HearthdayCore

/// Fermentation is variable. Everything Hearthday says about timing must read as an estimate.
final class CopyTests: XCTestCase {
    let banned = ["guarantee", "will be ready", "perfect", "exactly", "definitely", "certain", "always ready", "foolproof", "never fail"]

    func allGeneratedText() throws -> [String] {
        var text: [String] = []
        let worker = Availability.typicalWeekdayWorker
        let requests = [
            PlanRequest(now: TestClock.date(9, 7, 15), readyBy: TestClock.date(10, 10), kitchenTempC: 21),
            PlanRequest(now: TestClock.date(10, 7), readyBy: TestClock.date(10, 20), kitchenTempC: 23, starterNeedsFeed: false, proofModes: [.room]),
            PlanRequest(now: TestClock.date(5, 18), readyBy: TestClock.date(5, 21), kitchenTempC: 21),
        ]
        for r in requests {
            switch Planner.plan(r, calendar: TestClock.calendar) {
            case let .feasible(primary, alternatives):
                for p in [primary] + alternatives {
                    text += p.steps.flatMap { [$0.title, $0.detail] } + p.leverSummary
                }
            case let .infeasible(info):
                text.append(info.message)
            case let .invalid(problems):
                text += problems.map(\.message)
            }
        }
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var s = BakeSession(plan: plan, startedAt: TestClock.date(10, 10))
        s.complete("mix", at: plan.step("mix")!.end)
        for (hours, rise) in [(4.0, 43.0), (6, 30), (6.5, 76), (3, 60), (8, 20)] {
            let r = LiveReplanner.checkIn(session: s, now: TestClock.date(10, 10).addingTimeInterval(hours * 3600), risePercent: rise, tempC: 21,
                                          availability: worker, calendar: TestClock.calendar, model: FermentationModel())
            text.append(r.summary)
            text += r.options.flatMap { [$0.title, $0.detail] + $0.steps.map(\.detail) }
        }
        text += Reminders.specs(for: s, now: TestClock.date(10, 10, 30)).flatMap { [$0.title, $0.body] }
        return text
    }

    func testNoTimingTextClaimsCertainty() throws {
        let text = try allGeneratedText()
        XCTAssertGreaterThan(text.count, 40)
        for line in text {
            for word in banned {
                XCTAssertFalse(line.lowercased().contains(word), "“\(word)” in: \(line)")
            }
        }
    }

    func testFermentationDurationsAreStatedAsRangesOrApproximations() throws {
        let plan = try XCTUnwrap(Planner.plan(PlanRequest(now: TestClock.date(10, 7), readyBy: TestClock.date(10, 20), kitchenTempC: 23,
                                                          starterNeedsFeed: false, proofModes: [.room]), calendar: TestClock.calendar).primary)
        for step in plan.steps where [.bulk, .roomProof].contains(step.kind) {
            XCTAssertTrue(step.detail.hasPrefix("Likely"), step.detail)
        }
        let shape = try XCTUnwrap(plan.step("shape"))
        XCTAssertNotNil(shape.likelyStart)
        XCTAssertLessThan(shape.likelyStart!, shape.likelyEnd!, "Shaping is a window, not an instant")
    }

    func testCheckInSummaryCallsItselfAnEstimate() {
        let plan = makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11))
        var s = BakeSession(plan: plan, startedAt: TestClock.date(10, 10))
        s.complete("mix", at: plan.step("mix")!.end)
        let r = LiveReplanner.checkIn(session: s, now: TestClock.date(10, 14), risePercent: 40, tempC: 21,
                                      availability: .typicalWeekdayWorker, calendar: TestClock.calendar, model: FermentationModel())
        XCTAssertTrue(r.summary.contains("Likely"))
        XCTAssertTrue(r.summary.contains("estimate"))
        let ready = LiveReplanner.checkIn(session: s, now: TestClock.date(10, 17), risePercent: 80, tempC: 21,
                                          availability: .typicalWeekdayWorker, calendar: TestClock.calendar, model: FermentationModel())
        XCTAssertTrue(ready.summary.contains("Go by the dough"))
    }
}
