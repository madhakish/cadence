import XCTest
@testable import CadenceCore

/// Mirrors the protein block in web/tests/core.test.mjs — keep the two in
/// lockstep (same cases, same expected numbers).
final class ProteinGuidanceTests: XCTestCase {

    func testDailyTargetScalesWithBodyweight() {
        XCTAssertEqual(ProteinGuidance.dailyTargetGrams(bodyweightLb: 201), 145)
        XCTAssertEqual(ProteinGuidance.perMealGrams(bodyweightLb: 201), 35)
        // The old flat 100 g literal was the same for a 130 lb and a 250 lb
        // lifter; a derived target is the whole point.
        let light = ProteinGuidance.dailyTargetGrams(bodyweightLb: 130) ?? 0
        let heavy = ProteinGuidance.dailyTargetGrams(bodyweightLb: 250) ?? 0
        XCTAssertGreaterThan(heavy, light, "the target scales with bodyweight")
    }

    /// The app never invents a bodyweight, so it says nothing without one.
    func testSaysNothingWithoutABodyweight() {
        XCTAssertNil(ProteinGuidance.dailyTargetGrams(bodyweightLb: nil))
        XCTAssertNil(ProteinGuidance.dailyTargetGrams(bodyweightLb: 0))
        XCTAssertNil(ProteinGuidance.perMealGrams(bodyweightLb: nil))
        XCTAssertNil(ProteinGuidance.summary(bodyweightLb: nil))
    }

    func testSummaryNamesBothFigures() throws {
        let summary = try XCTUnwrap(ProteinGuidance.summary(bodyweightLb: 201))
        XCTAssertTrue(summary.contains("145 g/day"), summary)
        XCTAssertTrue(summary.contains("35 g per meal"), summary)
    }
}
