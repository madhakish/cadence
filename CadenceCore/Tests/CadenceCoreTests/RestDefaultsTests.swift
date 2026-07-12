import XCTest
@testable import CadenceCore

/// Mirrors the rest-default assertions in web/tests/core.test.mjs.
final class RestDefaultsTests: XCTestCase {
    func testCategoryAndMovementRules() {
        // Movement buckets key on movementGroup (the swap-pool grouping) —
        // never on exercise-name matching.
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "hinge"), 300)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "squat"), 300)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "olympic"), 240)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "press"), 180, "presses are mainUpper — Push Press is group press, not olympic")
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: ""), 180, "ungrouped custom main falls to mainUpper")
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", movementGroup: "arms"), 90)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", movementGroup: "olympic"), 90, "non-main olympic work is still accessory-bucketed")
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", movementGroup: "pull", exerciseDefaultRest: 120), 120)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "press", exerciseDefaultRest: 120), 120)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "hinge", exerciseDefaultRest: 360), 360)
        XCTAssertEqual(RestDefaults.seconds(category: "Conditioning", movementGroup: "conditioning"), 0)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", movementGroup: "conditioning"), 0, "conditioning movement never rests regardless of category")
        XCTAssertEqual(RestDefaults.seconds(category: "Conditioning", movementGroup: "conditioning", exerciseDefaultRest: 120), 120)
    }

    func testSecondaryRoleAndConfig() {
        // Complementary ("secondary") lifts rest at the secondary bucket regardless of movement.
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "hinge", role: "complementary"), 180)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "squat", role: "complementary"), 180)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "hinge", role: "main"), 300)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", movementGroup: "arms", role: "accessory"), 90)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", movementGroup: "pull", role: "accessory", exerciseDefaultRest: 180), 180, "a deliberate per-exercise rest beats the role bucket")
        // Configurable buckets override the defaults both directions.
        let rc = RestConfig(mainCompoundSeconds: 210, olympicSeconds: 200, mainUpperSeconds: 150, secondarySeconds: 120, accessorySeconds: 60)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "hinge", role: "main", config: rc), 210)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "press", role: "main", config: rc), 150)
        XCTAssertEqual(RestDefaults.seconds(category: "Main", movementGroup: "hinge", role: "complementary", config: rc), 120)
        XCTAssertEqual(RestDefaults.seconds(category: "Accessory", movementGroup: "arms", config: rc), 60)
    }
}
