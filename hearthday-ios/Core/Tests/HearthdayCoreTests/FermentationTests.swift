import XCTest
@testable import HearthdayCore

final class FermentationTests: XCTestCase {
    let model = FermentationModel()

    func testReferencePoint() {
        XCTAssertEqual(model.bulkHours(tempC: 21, inoculationPercent: 20), 7, accuracy: 1e-9)
    }

    func testCoolerDoughAndLessStarterAreSlower() {
        let base = model.bulkHours(tempC: 21, inoculationPercent: 20)
        XCTAssertGreaterThan(model.bulkHours(tempC: 18, inoculationPercent: 20), base)
        XCTAssertGreaterThan(model.bulkHours(tempC: 21, inoculationPercent: 10), base)
        XCTAssertLessThan(model.bulkHours(tempC: 26, inoculationPercent: 20), base)
    }

    /// The defaults should land inside published home-baker ranges (dough-lab.com chart, Sept 2026).
    /// The sources disagree with each other, so these are sanity bounds, not accuracy claims.
    func testDefaultsFallWithinPublishedRanges() {
        let cases: [(temp: Double, inoc: Double, low: Double, high: Double)] = [
            (18, 10, 12, 16),
            (21, 10, 8, 12),
            (21, 20, 6, 8),
            (24, 20, 4, 8.5),
            (24, 30, 2.5, 5),
        ]
        for c in cases {
            let h = model.bulkHours(tempC: c.temp, inoculationPercent: c.inoc)
            XCTAssert((c.low...c.high).contains(h), "\(c.temp) °C \(c.inoc)% → \(h) h outside \(c.low)–\(c.high)")
        }
    }

    func testTargetRiseFollowsTemperature() {
        XCTAssertEqual(FermentationModel.targetRisePercent(tempC: 21), 75, accuracy: 1e-9)
        XCTAssertEqual(FermentationModel.targetRisePercent(tempC: 23), 57.5, accuracy: 1e-9)
        XCTAssertEqual(FermentationModel.targetRisePercent(tempC: 15), 100)
        XCTAssertEqual(FermentationModel.targetRisePercent(tempC: 30), 30)
    }

    func testSpeedFactorScalesTime() {
        var fast = model
        fast.speedFactor = 1.25
        XCTAssertEqual(fast.bulkHours(tempC: 21, inoculationPercent: 20), 7 / 1.25, accuracy: 1e-9)
    }

    func testStarterPeaksLaterWithBiggerFeeds() {
        let peaks = FeedRatio.allCases.map { model.starterPeakHours(ratio: $0, tempC: 22) }
        XCTAssertEqual(peaks, peaks.sorted())
    }

    func testFormulaAmounts() {
        let a = Formula.countryLoaf.amounts()
        XCTAssertEqual(a.water, 360)
        XCTAssertEqual(a.starter, 100)
        XCTAssertEqual(a.salt, 10)
        XCTAssertEqual(Formula.countryLoaf.amounts(starterPercent: 10).starter, 50)
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.halfHours(5.3), "5½")
        XCTAssertEqual(DurationText.halfHours(0.4), "½")
        XCTAssertEqual(DurationText.hoursRange(5.6, 8.4), "5½–8½ h")
        XCTAssertEqual(DurationText.hoursRange(2, 2.1), "about 2 h")
        XCTAssertEqual(DurationText.compact(minutes: 85), "1 h 25 min")
    }
}
