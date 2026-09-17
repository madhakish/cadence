import XCTest

final class VisualProofUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--visual-proof",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()
        XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
    }

    func test01HomeAndAdHocWork() {
        capture("after-01-home-iphone")

        let activity = app.buttons["activity-quick-log"]
        for _ in 0..<4 where !activity.isHittable { app.swipeUp() }
        XCTAssertTrue(activity.waitForExistence(timeout: 3))
        activity.tap()
        XCTAssertTrue(element("activity-log-screen").waitForExistence(timeout: 5))
        capture("after-02-ad-hoc-work-iphone")
    }

    func test02CurrentSessionAndExactPlateStack() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["CURRENT SET · NEXT ACTION"].waitForExistence(timeout: 3))
        capture("after-03-current-session-iphone")
    }

    func test03ExercisePaneAndPreservedAnatomy() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        app.buttons["exercise-info-Back Squat"].tap()
        XCTAssertTrue(element("exercise-detail-screen").waitForExistence(timeout: 6))
        capture("after-04-exercise-pane-iphone")

        let frontLabel = app.staticTexts["Front"]
        for _ in 0..<4 where !frontLabel.isHittable { app.swipeUp() }
        XCTAssertTrue(frontLabel.waitForExistence(timeout: 3))
        capture("after-05-anatomy-unselected-iphone")

        let quads = app.buttons["Quads, primary muscle"]
        for _ in 0..<4 where !quads.isHittable { app.swipeUp() }
        XCTAssertTrue(quads.waitForExistence(timeout: 3))
        quads.tap()
        for _ in 0..<4 where !frontLabel.isHittable { app.swipeDown() }
        XCTAssertTrue(frontLabel.isHittable)
        capture("after-06-anatomy-selected-iphone")
    }

    func test04PlateCalculatorHero() {
        app.buttons["Plate calculator"].tap()
        XCTAssertTrue(element("plate-calculator-screen").waitForExistence(timeout: 6))
        let target = app.textFields["plate-target"]
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        target.tap()
        target.typeText("139")
        let keyboardDone = app.buttons["plate-target-done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 3))
        keyboardDone.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let achieved = app.staticTexts["ACHIEVED — BAR INCLUDED"]
        for _ in 0..<3 where !achieved.isHittable { app.swipeUp() }
        XCTAssertTrue(achieved.isHittable)
        capture("after-07-plate-calculator-iphone")

        let inspect = element("expand-loaded-bar")
        for _ in 0..<3 where !inspect.isHittable { app.swipeUp() }
        XCTAssertTrue(inspect.isHittable)
        inspect.tap()
        XCTAssertTrue(app.navigationBars["Loaded bar"].waitForExistence(timeout: 5))
        let toggle = app.buttons["barbell-explode-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "Exploded")
        // The calculator beneath this sheet has its own accessible bar.
        let artwork = app.scrollViews["barbell-inspection-artwork"]
        let firstLeft = artwork.staticTexts["barbell-plate-left-0"]
        XCTAssertTrue(firstLeft.waitForExistence(timeout: 3))
        XCTAssertTrue(firstLeft.label.contains("Left plate 1 from inside"))
        XCTAssertTrue(artwork.staticTexts["barbell-plate-right-0"].exists)
        capture("barbell-exploded-iphone")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Assembled")
        capture("barbell-assembled-iphone")

        app.navigationBars["Loaded bar"].buttons["Done"].tap()
        let equipment = app.buttons["Equipment & loading"]
        for _ in 0..<10 where !equipment.isHittable { app.swipeUp() }
        XCTAssertTrue(equipment.isHittable)
        equipment.tap()
        app.segmentedControls.buttons["Bumper"].tap()
        for _ in 0..<10 where !inspect.isHittable { app.swipeDown() }
        XCTAssertTrue(inspect.isHittable)
        inspect.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        capture("barbell-bumper-exploded-iphone")
    }

    /// #196: the floating plate button must never sit on top of a control.
    /// Every tab is scrolled to its end, then every hittable control's frame
    /// is checked against the button's. The reserved band (RootView's
    /// plateCalculatorClearance) is what makes this hold at large text too.
    func test08PlateButtonNeverCoversContent() {
        let plate = app.buttons["Plate calculator"]
        XCTAssertTrue(plate.waitForExistence(timeout: 5))
        for tab in ["Settings", "History", "Program", "Body", "Today"] {
            app.tabBars.buttons[tab].tap()
            for _ in 0..<6 { app.swipeUp() }
            let queries = [app.buttons, app.cells, app.switches, app.textFields, app.segmentedControls, app.staticTexts]
            for query in queries {
                for control in query.allElementsBoundByIndex
                where control.isHittable && control.label != "Plate calculator" && !control.frame.isEmpty {
                    XCTAssertFalse(control.frame.intersects(plate.frame),
                                   "\(tab): '\(control.label)' sits under the plate calculator button")
                }
            }
            if tab == "Settings" { capture("after-11-settings-end-clears-plate-button-iphone") }
        }
    }

    func test09WorkoutPreviewInspection() {
        let preview = app.buttons["preview-program-day"]
        for _ in 0..<10 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertTrue(element("workout-preview-screen").waitForExistence(timeout: 5))
        capture("barbell-workout-preview-iphone")
        let inspect = app.buttons["expand-loaded-bar"].firstMatch
        for _ in 0..<5 where !inspect.isHittable { app.swipeUp() }
        XCTAssertTrue(inspect.isHittable)
        inspect.tap()
        XCTAssertTrue(app.buttons["barbell-explode-toggle"].waitForExistence(timeout: 3))
        capture("barbell-workout-preview-inspection-iphone")
    }

    func test10PlankCountdownAndLog() {
        app.terminate()
        app.launchArguments += ["--hold-timer-proof", "--hold-short-proof"]
        app.launch()
        XCTAssertTrue(app.buttons["resume-session"].waitForExistence(timeout: 20))
        app.buttons["resume-session"].tap()
        let start = app.buttons["start-hold-timer"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        allowHoldNotificationsIfPrompted()
        let log = app.buttons["hold-timer-log"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        XCTAssertEqual(element("hold-timer-status").label, "HOLD COMPLETE")
        XCTAssertEqual(element("hold-timer-clock").value as? String, "3 seconds")
        capture("plank-target-complete-iphone")
        log.tap()
        XCTAssertTrue(app.navigationBars["Hold timer"].waitForNonExistence(timeout: 5))
    }

    func test11PlankTimerAtAccessibilityTextSize() {
        app.terminate()
        app.launchArguments += ["--hold-timer-proof",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["resume-session"].waitForExistence(timeout: 20))
        app.buttons["resume-session"].tap()
        let start = app.buttons["start-hold-timer"].firstMatch
        for _ in 0..<6 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        allowHoldNotificationsIfPrompted()
        let stop = app.buttons["hold-timer-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        capture("plank-countdown-accessibility-iphone")
        for _ in 0..<3 where !stop.isHittable { app.swipeUp() }
        stop.tap()
        XCTAssertEqual(element("hold-timer-status").label, "STOPPED")
        app.navigationBars["Hold timer"].buttons["Close"].tap()
        app.buttons["Discard attempt"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Discard keeps the set planned")
    }

    private func allowHoldNotificationsIfPrompted() {
        for owner in [app!, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let allow = owner.alerts.buttons["Allow"].firstMatch
            if allow.waitForExistence(timeout: 2) { allow.tap(); return }
        }
    }

    func test05SettingsAndHistory() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(element("settings-screen").waitForExistence(timeout: 5))
        capture("after-09-settings-iphone")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(element("history-screen").waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Log"].tap()
        let activitySummary = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Ad-hoc work ·'")
        ).firstMatch
        XCTAssertTrue(activitySummary.waitForExistence(timeout: 5))
        capture("after-10-history-ad-hoc-iphone")

        let activityRow = app.staticTexts["Wood Splitting"].firstMatch
        XCTAssertTrue(activityRow.waitForExistence(timeout: 3))
        activityRow.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        let deleteConfirmation = app.buttons["Delete activity"]
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 3))
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 1) {
            cancel.tap()
        } else {
            let dismissRegion = element("PopoverDismissRegion")
            XCTAssertTrue(dismissRegion.waitForExistence(timeout: 3))
            dismissRegion.tap()
        }
        XCTAssertTrue(deleteConfirmation.waitForNonExistence(timeout: 3))
        XCTAssertTrue(activitySummary.waitForExistence(timeout: 3), "cancelling keeps the banked activity")
    }

    func test06ComplementaryTrainingFocusIsTruthful() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        let complementary = app.buttons["exercise-info-Romanian Deadlift"]
        for _ in 0..<8 where !complementary.isHittable { app.swipeUp() }
        XCTAssertTrue(complementary.waitForExistence(timeout: 4))
        complementary.tap()
        XCTAssertTrue(element("exercise-detail-screen").waitForExistence(timeout: 6))
        let focus = element("training-focus-context")
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        XCTAssertEqual(focus.label, "Complementary lift · Hypertrophy focus")
        XCTAssertFalse(app.staticTexts["Target 2–3 reps left. Adjust the next set if the load misses that range."].exists)
    }

    func test07FinalSetAdvancesToNextAuthoredExercise() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(element("current-exercise-Back Squat").waitForExistence(timeout: 3))

        // The proof fixture starts on squat work set 2 of 3. Resolve both;
        // focus must move to the next authored lift without another tap.
        for _ in 0..<2 {
            let status = app.buttons["Set status"].firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 3))
            status.tap()
        }
        XCTAssertTrue(element("current-exercise-Romanian Deadlift").waitForExistence(timeout: 5))
        XCTAssertFalse(element("current-exercise-Back Squat").exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
