import XCTest
@testable import CadenceCore

final class ProgramPolicyTests: XCTestCase {
    func testAnyEquipmentPreservesLegacyBehavior() {
        for type in ["barbell", "dumbbell", "kettlebell", "bodyweight", "band", "machine", "conditioning"] {
            XCTAssertTrue(EquipmentPolicy.any.allows(exerciseType: type))
        }
    }

    func testFreeWeightPolicyIsAnExplicitClosedSet() {
        // "timed" is a LOGGING type, not equipment — every timed movement in
        // the catalog is a bodyweight isometric (planks, holds), and
        // excluding it made the adductor volume floor permanently unfillable
        // under this policy.
        for type in ["barbell", "dumbbell", "kettlebell", "bodyweight", "timed"] {
            XCTAssertTrue(EquipmentPolicy.freeWeightsOnly.allows(exerciseType: type), type)
        }
        for type in ["machine", "band", "conditioning", "cable"] {
            XCTAssertFalse(EquipmentPolicy.freeWeightsOnly.allows(exerciseType: type), type)
        }
    }
}
