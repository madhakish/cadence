import XCTest

/// The watch smoke test from design #339's verification plan: start → log a
/// set → rest → end, on a watch simulator, against the debug-only fixture plan.
final class CadenceWatchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
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
        app.swipeUp()
        app.swipeUp()
        let end = app.buttons["endWorkout"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()
        // The confirmation is a system sheet, which drops custom identifiers.
        let confirm = app.buttons["End now"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let summary = app.staticTexts["summarySets"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "1 working set")
    }
}
