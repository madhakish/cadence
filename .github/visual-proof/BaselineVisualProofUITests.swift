import XCTest

/// Proof-only navigation for the exact pre-pass application revision.
/// The workflow installs this target into a checkout of the PR base; none of
/// these hooks ship with the application.
final class BaselineVisualProofUITests: XCTestCase {
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
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
    }

    func test01HomeAndAdHocWork() {
        capture("before-01-home-iphone")

        let activity = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Wood Splitting'")
        ).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        XCTAssertTrue(app.navigationBars["Log ad-hoc work"].waitForExistence(timeout: 6))
        capture("before-02-ad-hoc-work-iphone")
    }

    func test02SessionAndExercisePane() {
        let resume = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Resume workout'")
        ).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 8))
        capture("before-03-current-session-iphone")

        let squat = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Back Squat'")
        ).firstMatch
        XCTAssertTrue(squat.waitForExistence(timeout: 5))
        squat.tap()
        XCTAssertTrue(app.navigationBars["Back Squat"].waitForExistence(timeout: 6))
        capture("before-04-exercise-anatomy-iphone")
    }

    func test03PlateCalculator() {
        app.buttons["Plate calculator"].tap()
        XCTAssertTrue(app.navigationBars["Plates"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Total on bar"].waitForExistence(timeout: 3))
        capture("before-05-plate-calculator-iphone")
    }

    func test04SettingsAndHistory() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 6))
        capture("before-06-settings-iphone")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 6))
        app.segmentedControls.buttons["Log"].tap()
        XCTAssertTrue(app.staticTexts["Wood Splitting"].firstMatch.waitForExistence(timeout: 5))
        capture("before-07-history-ad-hoc-iphone")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
