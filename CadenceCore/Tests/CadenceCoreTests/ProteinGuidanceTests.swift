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

    /// Age changes the per-meal threshold and nothing else. The daily figure is
    /// already the resistance-training one, so training type does not scale it.
    func testAgeRaisesThePerMealThresholdOnly() {
        XCTAssertEqual(ProteinGuidance.perMealGrams(bodyweightLb: 201, age: 40), 25)
        XCTAssertEqual(ProteinGuidance.perMealGrams(bodyweightLb: 201, age: 70), 35)
        XCTAssertEqual(ProteinGuidance.perMealGrams(bodyweightLb: 201, age: 65), 35,
                       "65 is the older-adult threshold, not one past it")
        XCTAssertEqual(ProteinGuidance.dailyTargetGrams(bodyweightLb: 201), 145,
                       "the daily figure does not move with age")
    }

    /// An unknown age takes the higher per-dose threshold. Eating to it costs a
    /// younger lifter nothing; under-dosing an older one is the failure that
    /// matters.
    func testUnknownAgeIsConservative() {
        XCTAssertEqual(ProteinGuidance.mealGramsPerKg(age: nil), ProteinGuidance.mealGramsPerKgOlder)
        XCTAssertEqual(ProteinGuidance.perMealGrams(bodyweightLb: 201, age: nil), 35)
        XCTAssertNil(ProteinGuidance.perMealRationale(age: nil),
                     "nothing to explain when there is no age")
    }

    func testAgeIsNeverGuessedFromANonsenseBirthYear() {
        XCTAssertEqual(ProteinGuidance.age(birthYear: 1980, inYear: 2026), 46)
        XCTAssertNil(ProteinGuidance.age(birthYear: 0, inYear: 2026), "unset is not a birth year")
        XCTAssertNil(ProteinGuidance.age(birthYear: 1899, inYear: 2026))
        XCTAssertNil(ProteinGuidance.age(birthYear: 2030, inYear: 2026), "not yet born")
        XCTAssertNil(ProteinGuidance.age(birthYear: 1901, inYear: 2026), "past a plausible lifespan")
        XCTAssertEqual(ProteinGuidance.age(birthYear: 2026, inYear: 2026), 0)
    }

    func testRationaleExplainsWhichThresholdApplies() throws {
        let older = try XCTUnwrap(ProteinGuidance.perMealRationale(age: 70))
        XCTAssertTrue(older.contains("0.4 g/kg"), older)
        let younger = try XCTUnwrap(ProteinGuidance.perMealRationale(age: 40))
        XCTAssertTrue(younger.contains("0.25 g/kg"), younger)
    }
}
