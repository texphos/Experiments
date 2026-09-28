import XCTest
@testable import HearthdayCore

final class AppStateTests: XCTestCase {
    func finishedJustRightBake(into state: inout AppState, bulkHours: Double) {
        let mix = TestClock.date(10, 10)
        state.start(makeFridgePlan(mixAt: mix, readyAt: TestClock.date(11, 11)), now: mix)
        state.completeStep("mix", at: state.activeSession!.plan.step("mix")!.end)
        state.completeStep("shape", at: mix.addingTimeInterval(bulkHours * 3600 + 20 * 60))
        state.setShapeReadiness(.justRight)
        state.finishActiveBake(rating: 4, notes: "", at: TestClock.date(11, 11))
    }

    func testFinishingAJustRightBakeTeachesCalibration() {
        var state = AppState()
        XCTAssertNil(state.calibrationInsight)
        finishedJustRightBake(into: &state, bulkHours: 6)
        XCTAssertNil(state.activeSession)
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.calibration.samples.count, 1)
        XCTAssertTrue(state.calibrationInsight?.contains("2 more") ?? false, state.calibrationInsight ?? "nil")
        XCTAssertEqual(state.history[0].planHeld, true)
    }

    func testInsightAfterThreeBakesAndProAppliesIt() {
        var state = AppState()
        for _ in 0..<3 { finishedJustRightBake(into: &state, bulkHours: 6) }
        XCTAssertTrue(state.calibration.isPersonalized)
        XCTAssertTrue(state.calibrationInsight?.contains("faster") ?? false)
        XCTAssertEqual(state.planningModel.speedFactor, 1, "Free plans use the textbook model")
        state.isPro = true
        XCTAssertGreaterThan(state.planningModel.speedFactor, 1)
        let r = state.request(readyBy: TestClock.date(11, 11), now: TestClock.date(10, 7), formula: .countryLoaf)
        XCTAssertGreaterThan(r.model.speedFactor, 1)
    }

    func testUnjudgedBakesDoNotCalibrate() {
        var state = AppState()
        state.start(makeFridgePlan(mixAt: TestClock.date(10, 10), readyAt: TestClock.date(11, 11)), now: TestClock.date(10, 10))
        state.finishActiveBake(rating: nil, notes: "forgot to judge", at: TestClock.date(11, 11))
        XCTAssertTrue(state.calibration.samples.isEmpty)
        XCTAssertEqual(state.history.count, 1)
    }

    func testFreeLimitsAreHonestAndProLiftsThem() {
        var state = AppState()
        for i in 0..<8 {
            state.history.append(BakeRecord(
                id: UUID(), finishedAt: TestClock.date(1 + i, 12), formulaName: "Loaf", proofMode: .fridge,
                inoculationPercent: 20, tempC: 21, originalReadyAt: TestClock.date(1 + i, 12), actualReadyAt: TestClock.date(1 + i, 12),
                replanCount: 0, checkInCount: 0, shapeReadiness: nil, rating: nil, notes: "", modelBulkHours: 7, actualBulkHours: nil
            ))
        }
        XCTAssertEqual(state.visibleHistory.count, AppState.freeHistoryLimit)
        XCTAssertEqual(state.hiddenHistoryCount, 3, "Older bakes are kept, just not shown")
        XCTAssertEqual(state.visibleHistory.first?.finishedAt, TestClock.date(8, 12), "Newest first")
        XCTAssertTrue(state.canAddFormula)
        state.formulas.append(.countryLoaf)
        XCTAssertFalse(state.canAddFormula)
        state.isPro = true
        XCTAssertTrue(state.canAddFormula)
        XCTAssertEqual(state.visibleHistory.count, 8)
    }

    func testPersistenceRoundTripAndCorruptFileIsKept() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = JSONFileStore(url: dir.appendingPathComponent("state.json"))
        XCTAssertEqual(try store.load(), AppState(), "Missing file means a fresh start")

        var state = AppState()
        state.settings.hasCompletedOnboarding = true
        finishedJustRightBake(into: &state, bulkHours: 6.5)
        state.start(makeFridgePlan(mixAt: TestClock.date(12, 18), readyAt: TestClock.date(13, 19)), now: TestClock.date(12, 18))
        try store.save(state)
        XCTAssertEqual(try store.load(), state)

        try Data("{not json".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        let backup = try store.quarantineCorruptFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try store.load(), AppState())
    }
}
