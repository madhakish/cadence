import XCTest
@testable import CadenceCore

final class SessionPrescriptionCompatibilityTests: XCTestCase {
    func testLegacyInitializerRemainsSourceCompatible() {
        let work = SessionPlan(weightLb: 100, sets: 3, reps: 5)
        let blocks = [PrescriptionBlock(kind: .work, weightLb: 100, sets: 3, reps: 5)]
        let prescription = SessionPrescription(mainWork: work, blocks: blocks)
        XCTAssertEqual(prescription.mainWork, work)
        XCTAssertEqual(prescription.blocks, blocks)
        XCTAssertEqual(prescription.resolvedStyle, .automatic)
    }
}
