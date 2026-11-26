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
                // SwiftUI exposes the Stepper as a group. Its Increment
                // button receives taps, including when the group is not hittable.
                let increment = plate.buttons["Increment"]
                for _ in 0..<16 where !increment.isHittable {
                    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.70))
                    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
                    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
                }
                XCTAssertTrue(increment.isHittable, "The custom denomination’s adjustment is reachable in the reverse rack")
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
