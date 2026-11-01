import XCTest

/// Photographs the cold open one instant at a time. A live 1.2 s animation
/// outruns XCUIScreen, so each launch pins the splash at a fixed time with the
/// DEBUG-only `--launch-splash-frame` argument. Every other visual-proof launch
/// passes `--visual-proof` alone and never sees the splash.
final class LaunchSplashProofUITests: XCTestCase {
    func testLaunchSplashFrames() {
        continueAfterFailure = false
        let frames: [(String, String, [String])] = [
            ("0-launch-screen", "0", []),
            ("1-wordmark", "0.22", []),
            ("2-ignition", "0.32", []),
            ("3-mid-burn", "0.55", []),
            ("4-near-end", "0.80", []),
            ("5-pop", "0.90", []),
            ("6-fading", "1.06", []),
            ("7-reduce-motion", "0.3", ["--launch-splash-reduce-motion"]),
        ]
        for (name, time, extra) in frames {
            let app = XCUIApplication()
            app.launchArguments = ["--visual-proof", "--launch-splash-frame=\(time)",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
            app.launch()
            // The splash is hidden from accessibility; the app under it is not.
            XCTAssertTrue(app.descendants(matching: .any)["home-screen"].waitForExistence(timeout: 20))
            Thread.sleep(forTimeInterval: 0.5)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "launch-splash-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
