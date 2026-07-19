import XCTest
@testable import CadenceCore

final class LoadSemanticsTests: XCTestCase {
    func testEquipmentInference() {
        XCTAssertEqual(LoadSemantics.inferredBasis(exerciseType: "barbell"), .totalBar)
        XCTAssertEqual(LoadSemantics.inferredBasis(exerciseType: "dumbbell"), .perImplement)
        XCTAssertEqual(LoadSemantics.inferredBasis(exerciseType: "bodyweight"), .bodyweight)
        XCTAssertEqual(LoadSemantics.inferredBasis(exerciseType: "machine"), .externalTotal)
        XCTAssertEqual(LoadSemantics.inferredImplementCount(exerciseType: "dumbbell"), 2)
    }

    func testPerImplementAndPerSideVolume() {
        XCTAssertEqual(LoadSemantics.volume(weightLb: 60, reps: 5, isPerSide: false,
                                            basis: .perImplement, implementCount: 2), 600)
        XCTAssertEqual(LoadSemantics.volume(weightLb: 60, reps: 5, isPerSide: true,
                                            basis: .perImplement, implementCount: 1), 600)
        XCTAssertEqual(LoadSemantics.volume(weightLb: 100, reps: 8, isPerSide: true,
                                            basis: .externalTotal), 1_600)
    }

    func testUnsupportedTonnageAndCompatibility() {
        XCTAssertNil(LoadSemantics.volume(weightLb: 0, reps: 20, isPerSide: false, basis: .bodyweight))
        XCTAssertNil(LoadSemantics.volume(weightLb: 40, reps: 8, isPerSide: false, basis: .assisted))
        XCTAssertTrue(LoadSemantics.compatible(.perImplement, .perImplement))
        XCTAssertFalse(LoadSemantics.compatible(.perImplement, .externalTotal))
    }
}
