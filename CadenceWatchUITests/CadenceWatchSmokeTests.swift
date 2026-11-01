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

    /// Each element is on screen and tappable as laid out: no scrolling, no
    /// paging, nothing under the screen edge (#359, a 40 mm watch included).
    private func assertOnScreen(_ app: XCUIApplication, _ elements: [XCUIElement],
                                file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.windows.firstMatch.frame
        for element in elements {
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) exists", file: file, line: line)
            XCTAssertTrue(screen.contains(element.frame), "\(element) at \(element.frame) is inside \(screen)",
                          file: file, line: line)
            XCTAssertTrue(element.isHittable, "\(element) is hittable", file: file, line: line)
        }
    }

    /// Tap-to-confirm: the fixture's first bench set is detected and proposed,
    /// and ending the rest it started brings the proposal to the set screen.
    private func launchWithAProposedSet() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-fixture", "--watch-fixture-motion", "--watch-confirm-detected"]
        app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.buttons["start"].tap()

        // Detection starts rest and proposes the set without logging it.
        XCTAssertTrue(app.buttons["confirmDetected"].waitForExistence(timeout: 30), "the synthetic set is detected and proposed")
        XCTAssertTrue(app.staticTexts["Detected 5 reps"].exists)
        XCTAssertFalse(app.buttons["autoLogged"].exists, "a proposal isn't logged before Confirm")
        app.buttons["skipRest"].tap()
        XCTAssertTrue(app.buttons["skipSet"].waitForExistence(timeout: 5))
        return app
    }

    private func endWorkout(_ app: XCUIApplication) -> XCUIElement {
        let end = app.buttons["endWorkout"]
        XCTAssertTrue(page(app, upTo: end))
        end.tap()
        let endNow = app.buttons["End now"]
        XCTAssertTrue(endNow.waitForExistence(timeout: 5))
        endNow.tap()
        let summary = app.staticTexts["summarySets"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        return summary
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

    /// Review on #356: a proposal lapses once its set stops being planned. Here
    /// the phone logs the set first (the fixture's phone, through the real sync
    /// path), so a stale Confirm can't overwrite the phone's reps. The same
    /// lapse covers a Skip on the watch.
    func testAProposalLapsesWhenThePhoneLogsItsSet() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-fixture", "--watch-fixture-motion", "--watch-confirm-detected",
                               "--watch-fixture-phone-logs-proposal"]
        app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.buttons["start"].tap()

        let confirm = app.buttons["confirmDetected"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "the synthetic set is detected and proposed")
        XCTAssertTrue(app.staticTexts["Detected 5 reps"].exists)

        // The phone logs the set five seconds later: nothing is left to confirm.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: confirm)
        wait(for: [gone], timeout: 15)
        XCTAssertFalse(app.staticTexts["Detected 5 reps"].exists)
        app.buttons["skipRest"].tap()
        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 2 of 2")
        XCTAssertFalse(confirm.exists)

        // The phone's 6 × 185 lb stands: one working set, 1110 lb of volume.
        let end = app.buttons["endWorkout"]
        XCTAssertTrue(page(app, upTo: end))
        end.tap()
        let endNow = app.buttons["End now"]
        XCTAssertTrue(endNow.waitForExistence(timeout: 5))
        endNow.tap()
        let summary = app.staticTexts["summarySets"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "1 working set")
        XCTAssertTrue(app.staticTexts["1110 lb volume"].exists)
    }

    /// #359: on a 40 mm watch, Skip sat under the screen edge while a detected
    /// set waited for Confirm. Skipping a proposed set skips it, and nothing is
    /// left to confirm.
    func testAProposedSetCanBeSkippedWithoutScrolling() {
        let app = launchWithAProposedSet()
        let skip = app.buttons["skipSet"], confirm = app.buttons["confirmDetected"]
        assertOnScreen(app, [skip, confirm, app.buttons["dismissDetected"], app.buttons["load"]])
        skip.tap()

        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 2 of 2")
        XCTAssertFalse(confirm.exists, "the skipped set's proposal is gone")
        XCTAssertFalse(app.staticTexts["restTitle"].exists, "a skip starts no rest")
        // Skipped, not logged: no working set.
        XCTAssertEqual(endWorkout(app).label, "0 working sets")
    }

    /// Not a set drops the proposal and hands the set its own controls back,
    /// still planned; a manual Done then logs it once.
    func testNotASetLeavesTheProposedSetPlanned() {
        let app = launchWithAProposedSet()
        let dismiss = app.buttons["dismissDetected"], confirm = app.buttons["confirmDetected"]
        assertOnScreen(app, [dismiss, confirm, app.buttons["skipSet"], app.buttons["load"]])
        XCTAssertFalse(app.buttons["done"].exists, "the proposal replaces the set's own Done")
        dismiss.tap()

        let done = app.buttons["done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 1 of 2")
        XCTAssertFalse(confirm.exists)
        done.tap()
        XCTAssertTrue(app.staticTexts["restTitle"].waitForExistence(timeout: 5))
        app.buttons["skipRest"].tap()
        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 2 of 2", "the set was logged once")
        XCTAssertEqual(endWorkout(app).label, "1 working set")
        XCTAssertTrue(app.staticTexts["925 lb volume"].exists, "5 × 185 lb, logged by hand")
    }

    /// The crown corrects the detected reps before Confirm, and Confirm logs
    /// the corrected reps with the load the watch shows, once.
    func testTheCrownCorrectsADetectedSetBeforeConfirm() throws {
        let app = launchWithAProposedSet()
        let load = app.buttons["load"], confirm = app.buttons["confirmDetected"]
        assertOnScreen(app, [confirm, app.buttons["dismissDetected"], app.buttons["skipSet"], load])
        XCTAssertEqual(load.label, "185 lb × 5")

        XCUIDevice.shared.rotateDigitalCrown(delta: 0.5)
        let corrected = expectation(for: NSPredicate(format: "label != '185 lb × 5'"), evaluatedWith: load)
        wait(for: [corrected], timeout: 5)
        let reps = try XCTUnwrap(Int(load.label.replacingOccurrences(of: "185 lb × ", with: "")), load.label)
        XCTAssertGreaterThan(reps, 5, "turning the crown up adds reps")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["setPosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setPosition"].label, "Set 2 of 2", "the set was logged once")
        XCTAssertFalse(confirm.exists)
        XCTAssertEqual(endWorkout(app).label, "1 working set")
        XCTAssertTrue(app.staticTexts["\(reps * 185) lb volume"].exists, "\(reps) × 185 lb, the corrected reps")
    }
}
