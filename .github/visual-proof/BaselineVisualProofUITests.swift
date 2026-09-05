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

    func test01Home() {
        capture("before-01-home-iphone")
    }

    func test02SessionAndExercisePane() {
        let resume = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Resume workout'")
        ).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 8))
        capture("before-02-current-session-iphone")

        let squat = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Back Squat'")
        ).firstMatch
        XCTAssertTrue(squat.waitForExistence(timeout: 5))
        squat.tap()
        XCTAssertTrue(app.navigationBars["Back Squat"].waitForExistence(timeout: 6))
        capture("before-03-exercise-anatomy-iphone")
    }

    func test03PlateCalculator() {
        app.buttons["Plate calculator"].tap()
        XCTAssertTrue(app.navigationBars["Plates"].waitForExistence(timeout: 6))
        let target = app.textFields.firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        target.tap()
        target.typeText("139")
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["Total on bar"].waitForExistence(timeout: 3))
        capture("before-04-plate-calculator-iphone")
    }

    func test04Settings() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 6))
        capture("before-05-settings-iphone")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
