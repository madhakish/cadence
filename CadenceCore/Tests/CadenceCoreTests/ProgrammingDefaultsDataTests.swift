import XCTest
@testable import CadenceCore

final class ProgrammingDefaultsDataTests: XCTestCase {

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("web/tests/fixtures/programming-defaults.json")
    }

    func testDefaultsMatchSharedFixture() throws {
        let data = try Data(contentsOf: fixtureURL())
        let fixture = try JSONDecoder().decode([ProgrammingDefaultsData.Recommendation].self, from: data)
        XCTAssertEqual(ProgrammingDefaultsData.all, fixture)
    }

    func testVeryLightAndUnloadedMovementsStayConservative() {
        let ytw = ProgrammingDefaultsData.recommendation(
            exerciseName: "Y-T-W Raises", slotCategory: "Accessory", exerciseType: "dumbbell"
        )
        XCTAssertEqual(ytw.weightLb, 5)
        XCTAssertEqual(ytw.incrementLb, 2.5)

        let bodyweight = ProgrammingDefaultsData.recommendation(
            exerciseName: "Custom Pull-up", slotCategory: "Accessory", exerciseType: "bodyweight"
        )
        XCTAssertEqual(bodyweight.weightLb, 0)
        XCTAssertEqual(bodyweight.incrementLb, 0)
    }

    /// Loaded carries start at a training load per hand, not the 5 lb
    /// accessory-dumbbell fallback; every other dumbbell accessory keeps it.
    func testCarriesHaveNamedPerHandDefaults() {
        let expected: [(String, String, Double)] = [
            ("Farmer Carry", "dumbbell", 50), ("Suitcase Carry", "dumbbell", 50),
            ("Front-rack Carry", "kettlebell", 35), ("Overhead Carry", "dumbbell", 25),
        ]
        for (name, type, lb) in expected {
            XCTAssertEqual(ProgrammingDefaultsData.recommendation(
                exerciseName: name, slotCategory: "Accessory", exerciseType: type
            ).weightLb, lb, name)
        }
        XCTAssertEqual(ProgrammingDefaultsData.recommendation(
            exerciseName: "DB Curls", slotCategory: "Accessory", exerciseType: "dumbbell"
        ).weightLb, 5, "the generic dumbbell fallback is unchanged")
    }

    func testUnknownLoadedMovementsNeverBootstrapBlank() {
        let barbell = ProgrammingDefaultsData.recommendation(
            exerciseName: "Custom Barbell Lift", slotCategory: "Main", exerciseType: "barbell"
        )
        XCTAssertEqual(barbell.weightLb, 45)
        XCTAssertEqual(barbell.estimatedMaxLb, 65)

        let importedType = ProgrammingDefaultsData.recommendation(
            exerciseName: "Imported Implement", slotCategory: "Accessory", exerciseType: "other"
        )
        XCTAssertGreaterThan(importedType.weightLb, 0)
    }
}
