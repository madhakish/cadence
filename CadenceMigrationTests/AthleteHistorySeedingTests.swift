import Foundation
import SwiftData
import XCTest
import CadenceCore

/// Epic #155 Stage 1 pin: history-driven slot seeding stays exact through
/// the recordedHistory -> AthleteHistory.index refactor. Twin of the
/// "history-driven slot seeding stays exact" block in web/tests/smoke.test.mjs.
@MainActor
final class AthleteHistorySeedingTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV10.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func addSession(_ context: ModelContext, exercise: Exercise, completedAt: Date,
                            sets: [(weightLb: Double, reps: Int, isWarmup: Bool, status: SetStatus)]) {
        let session = WorkoutSession(date: completedAt)
        context.insert(session)
        session.isCompleted = true
        session.completedAt = completedAt
        let entry = SessionExercise(order: 0, exercise: exercise)
        context.insert(entry)
        session.exercises.append(entry)
        for (index, spec) in sets.enumerated() {
            let set = SetEntry(order: index, weightLb: spec.weightLb, reps: spec.reps,
                               isWarmup: spec.isWarmup, status: spec.status)
            context.insert(set)
            entry.sets.append(set)
        }
    }

    func testSeedingReadsLatestLoadAndLifetimeBestExactly() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Good Morning", category: .accessory, type: .barbell,
                                movementGroup: "hinge")
        context.insert(exercise)
        // Older but heavier: 200x5 (Epley 233.33) is the lifetime best...
        addSession(context, exercise: exercise,
                   completedAt: Date(timeIntervalSince1970: 1_900_000_000),
                   sets: [(200, 5, false, .completed)])
        // ...the newer exposure is lighter, with a warmup and an unfinished
        // planned set that must both stay invisible to seeding.
        addSession(context, exercise: exercise,
                   completedAt: Date(timeIntervalSince1970: 1_902_000_000),
                   sets: [(135, 5, true, .completed), (180, 3, false, .completed), (500, 5, false, .planned)])
        try context.save()

        let accessory = try ProgramTemplates.bootstrapAccessory(exercise: exercise, context: context)
        XCTAssertEqual(accessory.weightLb, 180,
                       "accessory seeding takes the LATEST completed load, not the lifetime best")

        let lift = try ProgramTemplates.bootstrapLift(
            exercise: exercise, role: .complementary, focus: .strength, roundingLb: 5, context: context
        )
        let bestE1RM = 200 * (1 + 5.0 / 30.0)
        XCTAssertEqual(lift.estimatedMaxLb, bestE1RM.rounded(),
                       "lift seeding estimates max from the lifetime best set")
        let style = ProgramEngine.resolvedStyle(
            .automatic, movementGroup: exercise.movementGroup, role: .complementary, focus: .strength
        )
        let fallback = ProgrammingDefaultsData.recommendation(
            exerciseName: exercise.name, slotCategory: ExerciseCategory.main.rawValue,
            exerciseType: exercise.typeRaw
        )
        let floored = (style.templateStartFraction * bestE1RM / 5 + 1e-9).rounded(.down) * 5
        XCTAssertEqual(lift.baseWeightLb, Swift.max(fallback.weightLb, floored),
                       "lift base seeds from fraction x best e1RM floored to the step, never below the catalog fallback")
    }
}
