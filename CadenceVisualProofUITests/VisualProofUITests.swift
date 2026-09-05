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
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["ACHIEVED — BAR INCLUDED"].waitForExistence(timeout: 3))
        capture("after-07-plate-calculator-iphone")

        // A typical stack fits the phone with no redundant expand control.
        XCTAssertFalse(element("expand-loaded-bar").exists)
        target.tap()
        target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "1500")
        app.swipeDown()
        let expand = element("expand-loaded-bar")
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()
        XCTAssertTrue(app.navigationBars["Loaded bar"].waitForExistence(timeout: 5))
        capture("after-08-expanded-bar-iphone")
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
        XCTAssertTrue(app.buttons["Delete activity"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
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
