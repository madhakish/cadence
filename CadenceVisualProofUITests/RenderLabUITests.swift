import XCTest

/// Drives the DEBUG render lab: the production studio renderer draws a fixed
/// matrix of loadouts, themes and shots; the PNGs land in the app's tmp
/// directory (`tmp/render-lab`).
final class RenderLabUITests: XCTestCase {
    func testRenderLab() {
        let app = XCUIApplication()
        app.launchArguments = ["--visual-proof", "--render-lab", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let done = app.staticTexts["render-lab-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 900), "Render lab did not finish")
        XCTAssertEqual(done.label, "render-lab-done", "Render lab had failed renders")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "render-lab-screen"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
