import XCTest
@testable import CadenceCore

final class ExerciseSearchTests: XCTestCase {
    func testMatchesEveryAuthoredSearchField() {
        let fields = (
            name: "Nordic Hamstring Curl",
            movementGroup: "hinge",
            movementPatternName: "Hamstring isolation",
            exerciseType: "bodyweight",
            aliases: ["Nordic curl"],
            strategyTags: ["posterior-chain"]
        )
        for query in ["nordic ham", "HINGE", "isolation", "body", "nordic curl", "posterior"] {
            XCTAssertTrue(ExerciseSearch.matches(
                query, name: fields.name, movementGroup: fields.movementGroup,
                movementPatternName: fields.movementPatternName,
                exerciseType: fields.exerciseType, aliases: fields.aliases,
                strategyTags: fields.strategyTags
            ), "expected \(query) to match")
        }
    }

    func testEmptyAndDiacriticInsensitiveQueries() {
        XCTAssertTrue(ExerciseSearch.matches(
            "  ", name: "Press", movementGroup: "press",
            movementPatternName: "Horizontal press", exerciseType: "barbell"
        ))
        XCTAssertTrue(ExerciseSearch.matches(
            "degage", name: "Dégagé Step", movementGroup: "squat",
            movementPatternName: "Unilateral lower", exerciseType: "bodyweight"
        ))
        XCTAssertFalse(ExerciseSearch.matches(
            "row", name: "Back Squat", movementGroup: "squat",
            movementPatternName: "Squat", exerciseType: "barbell"
        ))
    }
}
