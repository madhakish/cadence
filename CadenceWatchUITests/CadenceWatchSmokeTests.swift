import XCTest

/// The watch smoke test from design #339's verification plan: start → log a
/// set → rest → end, on a watch simulator, against the debug-only fixture plan.
final class CadenceWatchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Vertical pages swallow a swipe fired mid-animation, so page until the
    /// element appears (a few tries) rather than counting swipes.
    private func page(_ app: XCUIApplication, upTo element: XCUIElement, down: Bool = false) -> Bool {
        // CI's watch simulators run on busy shared runners: be patient.
        for _ in 0..<8 {
            if element.waitForExistence(timeout: 3), element.isHittable { return true }
            if down { app.swipeDown() } else { app.swipeUp() }
        }
        return element.exists
    }

    func testStartLogASetRestAndEnd() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-fixture"]
        app.launch()

        let start = app.buttons["start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 1 of 2")
        app.buttons["done"].tap()

        // Auto-started rest, with the optional effort tags.
        XCTAssertTrue(app.staticTexts["restTitle"].waitForExistence(timeout: 5))
        app.buttons["quality-clean"].tap()
        app.buttons["skipRest"].tap()

        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 2 of 2")

        // The End page is two pages down: set → exercise list → end.
        let end = app.buttons["endWorkout"]
        XCTAssertTrue(page(app, upTo: end))
        end.tap()
        // The confirmation is a system sheet, which drops custom identifiers.
        let confirm = app.buttons["End now"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let summary = app.staticTexts["summarySets"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "1 working set")
    }

    func testATimedHoldIsLoggedByItsDuration() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.buttons["start"].tap()

        // Jump to the plank from the exercise list.
        let plank = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Plank'")).firstMatch
        XCTAssertTrue(page(app, upTo: plank))
        plank.tap()
        let startTimer = app.buttons["startTimer"]
        XCTAssertTrue(page(app, upTo: startTimer, down: true))
        startTimer.tap()
        sleep(2)
        app.buttons["Stop"].tap()
        app.buttons["Done"].tap()

        // The list row's label combines the name and the progress line.
        let logged = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Plank' AND label CONTAINS '1 of 1 sets'")).firstMatch
        XCTAssertTrue(page(app, upTo: logged), "the hold is logged")
    }

    /// Phase 5: a detected set logs itself with its reps and offers Edit.
    func testADetectedSetLogsItselfAndOffersEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-fixture", "--watch-fixture-motion"]
        app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.buttons["start"].tap()

        let logged = app.buttons["autoLogged"]
        XCTAssertTrue(logged.waitForExistence(timeout: 30), "the synthetic set is detected and logged")
        XCTAssertEqual(logged.label, "5 reps · Edit")
        // Edit reopens the set for a manual entry.
        logged.tap()
        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 1 of 2")
    }

    /// Review on #356: a set detected after its load was changed on the watch
    /// logs the load the watch showed, not the planned one.
    func testADetectedSetLogsTheLoadAdjustedOnTheWatch() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-fixture", "--watch-fixture-motion"]
        app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.buttons["start"].tap()

        // During the fixture's lead-in: 185 lb planned, 190 lb on the bar.
        let load = app.buttons["load"]
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        XCTAssertTrue(load.label.hasPrefix("185 lb"), load.label)
        load.tap()
        let up = app.buttons["+5"]
        XCTAssertTrue(up.waitForExistence(timeout: 5))
        up.tap()
        app.buttons["loadDone"].tap()
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        XCTAssertTrue(load.label.hasPrefix("190 lb"), load.label)
        XCTAssertFalse(app.buttons["autoLogged"].exists, "the load is adjusted before the set is detected")

        let logged = app.buttons["autoLogged"]
        XCTAssertTrue(logged.waitForExistence(timeout: 30), "the synthetic set is detected and logged")
        // Edit reopens the logged set, showing the load it was logged with.
        logged.tap()
        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 1 of 2")
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        XCTAssertTrue(load.label.hasPrefix("190 lb"), "logged with the adjusted load, not the plan's: \(load.label)")
    }

    /// Tap-to-confirm: a manual Done on a detected set clears its proposal, so
    /// Confirm can't log the same set a second time.
    func testAManualDoneClearsAPendingDetectedSet() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-fixture", "--watch-fixture-motion", "--watch-confirm-detected"]
        app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.buttons["start"].tap()

        // Detection starts rest and proposes the set without logging it.
        let confirm = app.buttons["confirmDetected"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "the synthetic set is detected and proposed")
        XCTAssertTrue(app.staticTexts["Detected 5 reps"].exists)
        XCTAssertFalse(app.buttons["autoLogged"].exists, "a proposal isn't logged before Confirm")

        // Log that set by hand instead.
        app.buttons["skipRest"].tap()
        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 1 of 2")
        app.buttons["done"].tap()

        // The manual Done took the proposal with it: nothing is left to confirm.
        XCTAssertTrue(app.staticTexts["restTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Detected 5 reps"].exists)
        XCTAssertFalse(confirm.exists)
        app.buttons["skipRest"].tap()
        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 2 of 2", "the set was logged once")
        XCTAssertFalse(confirm.exists)
    }
}
