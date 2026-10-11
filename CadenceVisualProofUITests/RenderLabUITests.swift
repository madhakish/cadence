import XCTest

/// Drives the DEBUG render lab: the production studio renderer draws a fixed
/// matrix of loadouts, themes and shots; the PNGs land in the app's tmp
/// directory for the capture workflow to collect.
final class RenderLabUITests: XCTestCase {
    func testRenderLab() {
        let app = XCUIApplication()
        app.launchArguments = ["--visual-proof", "--render-lab", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["render-lab-done"].waitForExistence(timeout: 900), "Render lab did not finish")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "render-lab-screen"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
