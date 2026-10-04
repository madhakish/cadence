import XCTest

/// The same DP-1 scenarios run against both real application revisions.
/// Fixture launch arguments configure inventory; visible controls exercise
/// the calculator. No result or artwork is supplied by the test.
enum CalculatorProofCases {
    static func run(in test: XCTestCase, legacy: Bool = false) {
        let app = XCUIApplication()
        for (scenario, target) in [("lb-exact", "135"), ("mixed", "139"),
                                   ("kg-change", "22.5"), ("unreachable", "200")] {
            app.terminate()
            app.launchArguments = ["--visual-proof", "--plate-proof=\(scenario)", "--plate-target=\(target)",
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
            app.buttons["Plate calculator"].tap()
            XCTAssertTrue(app.navigationBars["Plates"].waitForExistence(timeout: 6))
            if !legacy {
                let field = app.textFields["plate-target"]
                XCTAssertTrue(field.waitForExistence(timeout: 3))
                field.tap(); field.typeText(target)
                app.buttons["plate-target-done"].tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
            }
            if scenario == "kg-change" { app.segmentedControls.buttons["kg"].tap() }
            let summary = app.staticTexts[legacy ? "Total on bar" : "ACHIEVED WITH BAR"].firstMatch
            for _ in 0..<4 where !summary.isHittable { app.swipeUp() }
            XCTAssertTrue(summary.isHittable)
            if scenario == "unreachable" {
                let warning = app.staticTexts["No available stack satisfies this loading policy; showing the closest load."]
                for _ in 0..<5 where !warning.isHittable { app.swipeUp() }
                XCTAssertTrue(warning.waitForExistence(timeout: 3))
                let window = app.windows.firstMatch.frame
                let visible = CGRect(x: window.minX, y: window.minY + 100,
                                     width: window.width, height: window.height - 200)
                for _ in 0..<5 where !visible.contains(warning.frame) { app.swipeUp() }
                XCTAssertTrue(visible.contains(warning.frame), "Unreachable proof must show the policy warning")
            }
            capture(test, "\(legacy ? "before" : "after")-calculator-\(scenario)-iphone")
            if scenario == "mixed" {
                for _ in 0..<4 where !app.segmentedControls.buttons["On the bar"].isHittable { app.swipeDown() }
                app.segmentedControls.buttons["On the bar"].tap()
                let count = app.steppers.matching(NSPredicate(format: "label CONTAINS '1.25' AND label CONTAINS 'kg'")).firstMatch
                // A SwiftUI Stepper can expose a non-hittable grouping
                // element even while its Increment button is on screen.
                let increment = count.buttons["Increment"]
                for _ in 0..<8 where !increment.isHittable { app.swipeUp() }
                XCTAssertTrue(increment.isHittable)
                increment.tap()
                for _ in 0..<5 where !app.segmentedControls.buttons["On the bar"].isHittable { app.swipeDown() }
                capture(test, "\(legacy ? "before" : "after")-calculator-reverse-iphone")
            }
        }
    }

    private static func capture(_ test: XCTestCase, _ name: String) {
        // Retain the settled painted state, on both application revisions.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
