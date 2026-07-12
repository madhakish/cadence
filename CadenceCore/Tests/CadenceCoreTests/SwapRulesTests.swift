import XCTest
@testable import CadenceCore

/// Mirrors the swapCompatible block in web/tests/core.test.mjs — keep the two
/// in lockstep (same cases, same expectations). Regression for issue 20's bad
/// swaps: accessory→main jumps, loadability breaks, shelved substitutes.
final class SwapRulesTests: XCTestCase {

    private func compatible(
        current: (name: String, category: String, type: String, group: String),
        candidate: (name: String, category: String, type: String, group: String),
        shelved: Bool = false
    ) -> Bool {
        SwapRules.compatible(
            currentName: current.name, currentCategory: current.category,
            currentType: current.type, currentGroup: current.group,
            candidateName: candidate.name, candidateCategory: candidate.category,
            candidateType: candidate.type, candidateGroup: candidate.group,
            candidateShelved: shelved
        )
    }

    func testSwapCompatibility() {
        let backSquat = (name: "Back Squat", category: "Main", type: "barbell", group: "squat")
        let frontSquat = (name: "Front Squat", category: "Main", type: "barbell", group: "squat")
        let walkingLunges = (name: "Walking Lunges", category: "Accessory", type: "bodyweight", group: "squat")
        let dbPress = (name: "Incline DB Press", category: "Main", type: "dumbbell", group: "press")
        let machinePress = (name: "Machine Press", category: "Main", type: "machine", group: "press")
        let bwPress = (name: "Pike Push-up", category: "Main", type: "bodyweight", group: "press")
        let benchShelved = (name: "Barbell Bench", category: "Main", type: "barbell", group: "press")
        let dips = (name: "Dips", category: "Accessory", type: "bodyweight", group: "press")
        let chinups = (name: "Chin-ups", category: "Accessory", type: "bodyweight", group: "pull")
        let pullups = (name: "Pull-ups", category: "Accessory", type: "bodyweight", group: "pull")
        let ungrouped = (name: "Back Squat", category: "Main", type: "barbell", group: "")

        XCTAssertTrue(compatible(current: backSquat, candidate: frontSquat), "same tier/pattern/loadability → offered")
        XCTAssertTrue(compatible(current: chinups, candidate: pullups), "bodyweight→bodyweight is fine")
        XCTAssertFalse(compatible(current: walkingLunges, candidate: backSquat), "accessory can't jump to a main competition lift")
        XCTAssertFalse(compatible(current: dbPress, candidate: dips), "loaded press can't swap to an unloadable accessory")
        XCTAssertFalse(compatible(current: dbPress, candidate: bwPress), "loadability mismatch alone filters (same tier/group)")
        XCTAssertTrue(compatible(current: dbPress, candidate: machinePress), "equipment change within loadable types is fine")
        XCTAssertFalse(compatible(current: dbPress, candidate: benchShelved, shelved: true), "shelved is never offered")
        XCTAssertFalse(compatible(current: backSquat, candidate: dbPress), "different movement pattern")
        XCTAssertFalse(compatible(current: backSquat, candidate: backSquat), "never itself")
        XCTAssertFalse(compatible(current: ungrouped, candidate: frontSquat), "ungrouped lift offers no swaps")
    }
}
