import XCTest

/// Before/after captures for watch design passes, not a behavior test: each
/// screen the lifter reads mid-set is attached to the result bundle. Skipped
/// unless the runner gets `CADENCE_WATCH_SCREENSHOTS=1` (pass it to xcodebuild
/// as `TEST_RUNNER_CADENCE_WATCH_SCREENSHOTS=1`), so CI's watch job pays nothing.
/// Pull the PNGs out with `xcrun xcresulttool export attachments`.
final class CadenceWatchScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CADENCE_WATCH_SCREENSHOTS"] == "1",
                          "captures run only on request")
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        return app
    }

    /// Start, the set, the load sheet, rest after a manual Done, the summary.
    func testCaptureTheManualPath() {
        let app = launch(["--watch-fixture"])
        shoot("01-start")
        app.buttons["start"].tap()

        XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 5))
        shoot("02-set")
        app.buttons["load"].tap()
        XCTAssertTrue(app.buttons["loadDone"].waitForExistence(timeout: 5))
        shoot("03-load-adjuster")
        app.buttons["loadDone"].tap()

        // A tap while the sheet is still sliding away lands on the sheet.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["loadDone"])
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 5))
        app.buttons["done"].tap()
        XCTAssertTrue(app.staticTexts["restTitle"].waitForExistence(timeout: 5))
        shoot("04-rest")
        app.swipeUp()
        shoot("05-rest-scrolled")
        app.buttons["skipRest"].firstMatch.tap()

        let end = app.buttons["endWorkout"]
        for _ in 0..<8 where !(end.waitForExistence(timeout: 3) && end.isHittable) { app.swipeUp() }
        end.tap()
        XCTAssertTrue(app.buttons["End now"].waitForExistence(timeout: 5))
        app.buttons["End now"].tap()
        XCTAssertTrue(app.staticTexts["summarySets"].waitForExistence(timeout: 10))
        shoot("09-summary")
    }

    /// Confirm mode: the proposal on the rest screen, then on the set screen.
    func testCaptureADetectedSetWaitingForConfirm() {
        let app = launch(["--watch-fixture", "--watch-fixture-motion", "--watch-confirm-detected"])
        app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["confirmDetected"].waitForExistence(timeout: 30))
        shoot("06-rest-proposal")
        app.buttons["skipRest"].tap()
        XCTAssertTrue(app.buttons["skipSet"].waitForExistence(timeout: 5))
        shoot("07-proposal-card")
    }

    /// A detected set that logged itself: rest offers "N reps · Edit".
    func testCaptureAnAutoLoggedSet() {
        let app = launch(["--watch-fixture", "--watch-fixture-motion"])
        app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["autoLogged"].waitForExistence(timeout: 30))
        shoot("08-rest-auto-logged")
    }
}
