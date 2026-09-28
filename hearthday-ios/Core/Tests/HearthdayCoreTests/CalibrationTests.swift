import XCTest
@testable import HearthdayCore

final class CalibrationTests: XCTestCase {
    func sample(speed: Double) -> Calibration.Sample {
        Calibration.Sample(date: TestClock.date(5, 12), tempC: 21, inoculationPercent: 20, modelHours: 7, actualHours: 7 / speed)
    }

    func testEmptyCalibrationIsTextbook() {
        let c = Calibration()
        XCTAssertEqual(c.speedFactor, 1)
        XCTAssertEqual(c.uncertainty, Calibration.defaultUncertainty)
        XCTAssertFalse(c.isPersonalized)
    }

    func testOneFastBakeMovesTheEstimateOnlyPartway() {
        var c = Calibration()
        c.record(sample(speed: 1.5))
        XCTAssertEqual(c.speedFactor, exp(log(1.5) / 3), accuracy: 1e-9)
        XCTAssertEqual(c.uncertainty, Calibration.defaultUncertainty, "One bake is not evidence of consistency")
    }

    func testConsistentBakesNarrowTheWindow() {
        var c = Calibration()
        for _ in 0..<5 { c.record(sample(speed: 1.2)) }
        XCTAssertTrue(c.isPersonalized)
        XCTAssertGreaterThan(c.speedFactor, 1.1)
        XCTAssertLessThan(c.speedFactor, 1.2)
        XCTAssertLessThan(c.uncertainty, Calibration.defaultUncertainty)
        XCTAssertGreaterThanOrEqual(c.uncertainty, Calibration.minimumUncertainty)
    }

    func testInconsistentBakesWidenTheWindow() {
        var c = Calibration()
        for speed in [0.7, 1.4, 0.7, 1.4, 0.7, 1.4] { c.record(sample(speed: speed)) }
        XCTAssertGreaterThan(c.uncertainty, Calibration.defaultUncertainty)
        XCTAssertLessThanOrEqual(c.uncertainty, Calibration.maximumUncertainty)
    }

    func testKeepsOnlyRecentSamplesAndIgnoresNonsense() {
        var c = Calibration()
        for _ in 0..<20 { c.record(sample(speed: 1.1)) }
        XCTAssertEqual(c.samples.count, Calibration.maxSamples)
        c.record(Calibration.Sample(date: TestClock.date(5, 12), tempC: 21, inoculationPercent: 20, modelHours: 7, actualHours: 0.1))
        XCTAssertEqual(c.samples.count, Calibration.maxSamples)
    }

    func testModelApplyingCalibration() {
        var c = Calibration()
        for _ in 0..<4 { c.record(sample(speed: 1.3)) }
        let m = FermentationModel().applying(c)
        XCTAssertEqual(m.speedFactor, c.speedFactor)
        XCTAssertEqual(m.uncertainty, c.uncertainty)
    }
}
