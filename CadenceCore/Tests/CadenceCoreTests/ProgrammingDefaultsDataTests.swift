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
