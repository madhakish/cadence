import XCTest
@testable import CadenceCore

final class WorkoutClassificationTests: XCTestCase {
    func testStrengthOnly() {
        XCTAssertEqual(WorkoutClassification.classify([
            CompletedExerciseKind(name: "Deadlift", type: "barbell", category: "Main")
        ]), .traditionalStrength)
    }

    func testSingleConditioningModality() {
        XCTAssertEqual(WorkoutClassification.classify([
            CompletedExerciseKind(name: "Row Erg", type: "conditioning", category: "Conditioning")
        ]), .rowing)
        XCTAssertEqual(WorkoutClassification.classify([
            CompletedExerciseKind(name: "Ruck", type: "conditioning", category: "Conditioning")
        ]), .hiking)
    }

    func testMixedWorkIsCrossTraining() {
        XCTAssertEqual(WorkoutClassification.classify([
            CompletedExerciseKind(name: "Deadlift", type: "barbell", category: "Main"),
            CompletedExerciseKind(name: "Bike", type: "conditioning", category: "Conditioning")
        ]), .crossTraining)
    }
}
