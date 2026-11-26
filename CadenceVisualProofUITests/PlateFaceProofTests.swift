import XCTest

final class PlateFaceProofTests: XCTestCase {
    func testCustomPlatesKeepBothUnitsAtAccessibilitySizes() {
        continueAfterFailure = false
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = ["--visual-proof", "--plate-proof=astra-custom-faces",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                   "-UIPreferredContentSizeCategoryName", category]
            app.launch()
            let calculator = app.buttons["plate-calculator-button"].firstMatch
            XCTAssertTrue(calculator.waitForExistence(timeout: 15))
            calculator.tap()
            let reverse = app.segmentedControls.buttons["On the bar"]
            XCTAssertTrue(reverse.waitForExistence(timeout: 5))
            reverse.tap()
            for unit in ["lb", "kg"] {
                let plate = app.steppers.matching(NSPredicate(format: "label CONTAINS %@", "1.125 " + unit)).firstMatch
                for _ in 0..<12 where !plate.isHittable { app.swipeUp() }
                XCTAssertTrue(plate.isHittable, "The custom denomination and its unit are reachable in the reverse rack")
                XCTAssertGreaterThanOrEqual(plate.frame.minX, app.windows.firstMatch.frame.minX)
                XCTAssertLessThanOrEqual(plate.frame.maxX, app.windows.firstMatch.frame.maxX)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "astra-plate-face-1.125-\(unit)-\(category)"
                shot.lifetime = .keepAlways
                add(shot)
            }
            app.terminate()
        }
    }
}
