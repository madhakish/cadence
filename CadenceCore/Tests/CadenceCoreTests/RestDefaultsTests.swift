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

    func testSecondaryRoleAndConfig() {
        // Complementary ("secondary") lifts rest at the secondary bucket regardless of movement.
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Deadlift", role: "complementary"), 180)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Back Squat", role: "complementary"), 180)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Deadlift", role: "main"), 300)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", name: "DB Curls", role: "accessory"), 90)
        // Configurable buckets override the defaults both directions.
        let rc = RestConfig(mainCompoundSeconds: 210, olympicSeconds: 200, mainUpperSeconds: 150, secondarySeconds: 120, accessorySeconds: 60)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Deadlift", role: "main", config: rc), 210)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", name: "Deadlift", role: "complementary", config: rc), 120)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", name: "DB Curls", config: rc), 60)
    }
}
