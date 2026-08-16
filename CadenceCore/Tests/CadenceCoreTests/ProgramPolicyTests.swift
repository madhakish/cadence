import XCTest
@testable import CadenceCore

final class ProgramPolicyTests: XCTestCase {
    func testAnyEquipmentPreservesLegacyBehavior() {
        for type in ["barbell", "dumbbell", "kettlebell", "bodyweight", "band", "machine", "conditioning"] {
            XCTAssertTrue(EquipmentPolicy.any.allows(exerciseType: type))
        }
    }

    func testFreeWeightPolicyIsAnExplicitClosedSet() {
        for type in ["barbell", "dumbbell", "kettlebell", "bodyweight"] {
            XCTAssertTrue(EquipmentPolicy.freeWeightsOnly.allows(exerciseType: type), type)
        }
        for type in ["machine", "band", "timed", "conditioning", "cable"] {
            XCTAssertFalse(EquipmentPolicy.freeWeightsOnly.allows(exerciseType: type), type)
        }
    }
}
