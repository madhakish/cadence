import XCTest
@testable import CadenceCore

/// Mirrors the rest-default assertions in web/tests/core.test.mjs.
final class RestDefaultsTests: XCTestCase {
    func testCategoryAndMovementRules() {
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Deadlift"), 300)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Back Squat"), 300)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Push Press"), 240)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Power Clean"), 240)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Incline DB Press"), 180)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Barbell Bench"), 180)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", name: "DB Curls"), 90)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", name: "Face Pulls", exerciseDefaultRest: 120), 120)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Barbell Bench", exerciseDefaultRest: 120), 120)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Deadlift", exerciseDefaultRest: 360), 360)
        XCTAssertEqual(RestDefaults.seconds(category: "Conditioning", name: "Run-Walk Intervals"), 0)
        XCTAssertEqual(RestDefaults.seconds(category: "Conditioning", name: "Sled Push", exerciseDefaultRest: 120), 120)
    }
}
