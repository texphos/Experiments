import XCTest

/// Drives the real app on a simulator: onboarding → plan → start → check-in → re-plan → finish → journal,
/// in light and dark appearance, saving screenshots as test attachments.
final class HearthdayUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func launch(reset: Bool, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hearthday-ui-testing", dark ? "-hearthday-dark" : "-hearthday-light"]
            + (reset ? ["-hearthday-reset-state"] : [])
        app.launch()
        return app
    }

    func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "Missing \(id)")
        scrollIntoView(app, e)
        e.tap()
        return e
    }

    func scrollIntoView(_ app: XCUIApplication, _ e: XCUIElement) {
        var attempts = 0
        while !e.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
    }

    func completeOnboarding(_ app: XCUIApplication, appearance: String) {
        XCTAssertTrue(app.staticTexts["Hearthday"].waitForExistence(timeout: 10) || element(app, "onboarding.next").exists)
        snapshot(app, "\(appearance)-01-onboarding")
        tap(app, "onboarding.next")
        snapshot(app, "\(appearance)-02-busy-times")
        tap(app, "onboarding.next")
        tap(app, "onboarding.next")
    }

    func planAndStart(_ app: XCUIApplication, appearance: String) {
        XCTAssertTrue(element(app, "home.plan").waitForExistence(timeout: 10))
        snapshot(app, "\(appearance)-03-home")
        tap(app, "home.plan")
        let start = element(app, "plan.start")
        let earliest = element(app, "plan.earliest")
        let deadline = Date().addingTimeInterval(30)
        while !start.exists && Date() < deadline {
            if earliest.exists {
                snapshot(app, "\(appearance)-04b-infeasible")
                earliest.tap()
            }
            _ = start.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(start.exists, "A plan should be offered, directly or via the earliest time that fits")
        snapshot(app, "\(appearance)-04-plan")
        tap(app, "plan.start")
        XCTAssertTrue(element(app, "step.done").waitForExistence(timeout: 5), "Starting a bake shows the live bake")
        XCTAssertFalse(element(app, "plan.start").exists, "The plan screen doesn't stay on top of the live bake")
    }

    func runLoop(appearance: String) throws {
        let app = launch(reset: true, dark: appearance == "dark")
        completeOnboarding(app, appearance: appearance)
        planAndStart(app, appearance: appearance)

        // Mark steps done until bulk has started and a check-in is possible.
        let checkIn = element(app, "live.checkin")
        var guardCount = 0
        while !checkIn.exists && guardCount < 4 {
            tap(app, "step.done")
            guardCount += 1
        }
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        app.swipeDown()
        snapshot(app, "\(appearance)-05-live-bake")

        tap(app, "live.checkin")
        let slider = element(app, "checkin.rise")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.4)
        tap(app, "checkin.replan")
        let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'option.'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10), "A check-in offers at least one option")
        XCTAssertTrue(element(app, "checkin.summary").exists)
        snapshot(app, "\(appearance)-06-check-in-options")
        scrollIntoView(app, option)
        option.tap()

        // Finish the remaining steps; answer the shaping question when it appears.
        let logBake = element(app, "live.logBake")
        let justRight = element(app, "readiness.justRight")
        guardCount = 0
        while !logBake.exists && guardCount < 12 {
            if justRight.exists && justRight.isHittable {
                justRight.tap()
            } else {
                let done = element(app, "step.done")
                if done.waitForExistence(timeout: 3) {
                    scrollIntoView(app, done)
                    done.tap()
                }
            }
            guardCount += 1
        }
        XCTAssertTrue(logBake.waitForExistence(timeout: 5), "The bake reaches “Bread’s out”")
        snapshot(app, "\(appearance)-07-bread-out")
        logBake.tap()
        tap(app, "finish.save")

        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["Everyday country loaf"].waitForExistence(timeout: 5), "The finished bake is in the journal")
        snapshot(app, "\(appearance)-08-journal")

        app.tabBars.buttons["Settings"].tap()
        tap(app, "settings.pro")
        let settled = [element(app, "pro.buy"), element(app, "pro.unavailable"), element(app, "pro.unlocked")]
        let deadline = Date().addingTimeInterval(15)
        while !settled.contains(where: \.exists) && Date() < deadline { _ = settled[0].waitForExistence(timeout: 1) }
        XCTAssertTrue(settled.contains(where: \.exists), "The Pro screen shows a price, an explicit unavailable state, or unlocked")
        snapshot(app, "\(appearance)-09-pro")
    }

    func testCompleteLoopLight() throws {
        try runLoop(appearance: "light")
    }

    func testCompleteLoopDark() throws {
        try runLoop(appearance: "dark")
    }

    func testBakeInProgressSurvivesTerminationAndRelaunch() throws {
        let app = launch(reset: true)
        completeOnboarding(app, appearance: "relaunch")
        planAndStart(app, appearance: "relaunch")
        XCTAssertTrue(element(app, "step.done").waitForExistence(timeout: 5))
        app.terminate()

        let relaunched = launch(reset: false)
        XCTAssertTrue(element(relaunched, "step.done").waitForExistence(timeout: 10), "The live bake is restored, not the home screen")
        XCTAssertFalse(element(relaunched, "home.plan").exists)
        snapshot(relaunched, "relaunch-restored-bake")
    }
}
