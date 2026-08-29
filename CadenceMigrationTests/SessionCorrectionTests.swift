import Foundation
import SwiftData
import XCTest
import CadenceCore

/// Epic #155 Stage 0: pins the banked-correction boundary's semantics on
/// real SwiftData rows. The full production banking regression (grade/
/// milestone staleness after a correction) lives in the web smoke suite,
/// which can drive completeSession end-to-end; this hostless target cannot
/// compile SessionCompletion because HealthKitService imports HealthKit
/// without a canImport guard — recorded as a Stage 6 prerequisite.
@MainActor
final class SessionCorrectionTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CadenceSchemaV10.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return container.mainContext
    }

    private func makeBankedFiveByFive(context: ModelContext) -> (WorkoutSession, [SetEntry]) {
        let session = WorkoutSession(date: .now)
        session.isCompleted = true
        session.completedAt = .now
        let entry = SessionExercise(order: 0, exercise: nil)
        var sets: [SetEntry] = []
        for index in 0..<5 {
            // The epic's topology: the fifth work set never got its checkmark.
            let set = SetEntry(order: index, weightLb: 235, reps: 5,
                               status: index < 4 ? .completed : .planned,
                               plannedWeightLb: 235, plannedReps: 5)
            context.insert(set)
            entry.sets.append(set)
            sets.append(set)
        }
        context.insert(session)
        session.exercises.append(entry)
        return (session, sets)
    }

    func testCompletingTheMissedSetChangesOnlyItsStatus() throws {
        let context = try makeContext()
        let (_, sets) = makeBankedFiveByFive(context: context)

        SessionCorrectionService.apply([(set: sets[4], correction: SetLifecycle.SetCorrection(status: .completed))])
        try context.save()

        XCTAssertTrue(sets.allSatisfy { $0.status == .completed && $0.weightLb == 235 && $0.reps == 5 },
                      "the corrected record is exactly five completed 235x5 work sets")
    }

    func testRepsCorrectionCannotResetWeight() throws {
        let context = try makeContext()
        let (_, sets) = makeBankedFiveByFive(context: context)

        SessionCorrectionService.apply([(set: sets[3], correction: SetLifecycle.SetCorrection(reps: 8))])
        try context.save()

        XCTAssertEqual(sets[3].reps, 8)
        XCTAssertEqual(sets[3].weightLb, 235, "editing reps must never reset weight")
        XCTAssertEqual(sets[3].status, .completed, "editing reps must not disturb set status")
    }

    func testReapplyingTheSameCorrectionIsIdempotent() throws {
        let context = try makeContext()
        let (_, sets) = makeBankedFiveByFive(context: context)
        let correction = SetLifecycle.SetCorrection(status: .completed)

        SessionCorrectionService.apply([(set: sets[4], correction: correction)])
        try context.save()
        SessionCorrectionService.apply([(set: sets[4], correction: correction)])

        XCTAssertFalse(context.hasChanges,
                       "reapplying an identical correction writes nothing (write-only-changed)")
    }

    func testEmptyCorrectionWritesNothing() throws {
        let context = try makeContext()
        let (_, sets) = makeBankedFiveByFive(context: context)
        try context.save()

        SessionCorrectionService.apply([(set: sets[0], correction: SetLifecycle.SetCorrection())])

        XCTAssertFalse(context.hasChanges, "a no-op correction must not dirty the record")
    }
}
