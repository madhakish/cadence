import XCTest
@testable import CadenceCore

/// Mirrors the swapCompatible block in web/tests/core.test.mjs — keep the two
/// in lockstep (same cases, same expectations). Regression for issue 20's bad
/// swaps: accessory→main jumps, loadability breaks, shelved substitutes.
final class SwapRulesTests: XCTestCase {

    private func compatible(
        current: (name: String, category: String, basis: LoadBasis, group: String),
        candidate: (name: String, category: String, basis: LoadBasis, group: String),
        shelved: Bool = false
    ) -> Bool {
        SwapRules.compatible(
            currentName: current.name, currentCategory: current.category,
            currentLoadBasis: current.basis, currentGroup: current.group,
            candidateName: candidate.name, candidateCategory: candidate.category,
            candidateLoadBasis: candidate.basis, candidateGroup: candidate.group,
            candidateShelved: shelved
        )
    }

    func testSwapCompatibility() {
        let backSquat = (name: "Back Squat", category: "Main", basis: LoadBasis.totalBar, group: "squat")
        let frontSquat = (name: "Front Squat", category: "Main", basis: LoadBasis.totalBar, group: "squat")
        let walkingLunges = (name: "Walking Lunges", category: "Accessory", basis: LoadBasis.bodyweight, group: "squat")
        let dbPress = (name: "Incline DB Press", category: "Main", basis: LoadBasis.perImplement, group: "press")
        let machinePress = (name: "Machine Press", category: "Main", basis: LoadBasis.externalTotal, group: "press")
        let bwPress = (name: "Pike Push-up", category: "Main", basis: LoadBasis.bodyweight, group: "press")
        let benchShelved = (name: "Barbell Bench", category: "Main", basis: LoadBasis.totalBar, group: "press")
        let dips = (name: "Dips", category: "Accessory", basis: LoadBasis.bodyweight, group: "press")
        let chinups = (name: "Chin-ups", category: "Accessory", basis: LoadBasis.bodyweight, group: "pull")
        let pullups = (name: "Pull-ups", category: "Accessory", basis: LoadBasis.bodyweight, group: "pull")
        let weightedPullup = (name: "Weighted Pull-up", category: "Accessory", basis: LoadBasis.externalTotal, group: "pull")
        let ungrouped = (name: "Back Squat", category: "Main", basis: LoadBasis.totalBar, group: "")

        XCTAssertTrue(compatible(current: backSquat, candidate: frontSquat), "same tier/pattern/loadability → offered")
        XCTAssertTrue(compatible(current: chinups, candidate: pullups), "bodyweight→bodyweight is fine")
        XCTAssertFalse(compatible(current: weightedPullup, candidate: pullups),
                       "weighted and unloaded pull-ups cannot carry the same prescription")
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
