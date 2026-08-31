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
    // The container must outlive every context handed to a test — a context
    // whose container deallocates is a crash, not an error.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV11.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// Mirrors ProgramSession.make's construction order exactly: insert the
    /// session, insert each entry then append it, insert each set then
    /// append it.
    private func makeBankedFiveByFive(context: ModelContext) -> (WorkoutSession, [SetEntry]) {
        let session = WorkoutSession(date: .now)
        context.insert(session)
        let entry = SessionExercise(order: 0, exercise: nil)
        context.insert(entry)
        session.exercises.append(entry)
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
        session.isCompleted = true
        session.completedAt = .now
        return (session, sets)
    }

    func testCompletingTheMissedSetChangesOnlyItsStatus() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, sets) = makeBankedFiveByFive(context: context)

        SessionCorrectionService.apply([(set: sets[4], correction: SetLifecycle.SetCorrection(status: .completed))])
        try context.save()

        XCTAssertTrue(sets.allSatisfy { $0.status == .completed && $0.weightLb == 235 && $0.reps == 5 },
                      "the corrected record is exactly five completed 235x5 work sets")
    }

    func testRepsCorrectionCannotResetWeight() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, sets) = makeBankedFiveByFive(context: context)

        SessionCorrectionService.apply([(set: sets[3], correction: SetLifecycle.SetCorrection(reps: 8))])
        try context.save()

        XCTAssertEqual(sets[3].reps, 8)
        XCTAssertEqual(sets[3].weightLb, 235, "editing reps must never reset weight")
        XCTAssertEqual(sets[3].status, .completed, "editing reps must not disturb set status")
    }

    func testReapplyingTheSameCorrectionIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, sets) = makeBankedFiveByFive(context: context)
        let correction = SetLifecycle.SetCorrection(status: .completed)

        SessionCorrectionService.apply([(set: sets[4], correction: correction)])
        try context.save()
        SessionCorrectionService.apply([(set: sets[4], correction: correction)])

        XCTAssertFalse(context.hasChanges,
                       "reapplying an identical correction writes nothing (write-only-changed)")
    }


    /// Stage 6: the correction rebuilds what is deterministically
    /// rebuildable — the touched lifts' PR milestones — replayed from the
    /// corrected canonical sessions rather than appended to, and idempotent.
    /// [INV-CORRECTION-REBUILDS-DERIVED-STATE]
    func testCorrectionRegeneratesMilestonesDeterministically() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Good Morning", category: .accessory, type: .barbell,
                                movementGroup: "hinge")
        context.insert(exercise)

        func bank(_ date: Date, reps: Int) -> [SetEntry] {
            let session = WorkoutSession(date: date)
            context.insert(session)
            session.isCompleted = true
            session.completedAt = date
            let entry = SessionExercise(order: 0, exercise: exercise)
            context.insert(entry)
            session.exercises.append(entry)
            let set = SetEntry(order: 0, weightLb: 185, reps: reps, status: .completed)
            context.insert(set)
            entry.sets.append(set)
            return [set]
        }
        _ = bank(Date(timeIntervalSince1970: 1_900_000_000), reps: 5)
        let later = bank(Date(timeIntervalSince1970: 1_902_000_000), reps: 3)
        try context.save()

        let outcome = try SessionCorrectionService.applyAndRebuild(
            [(set: later[0], correction: SetLifecycle.SetCorrection(reps: 8))],
            in: try XCTUnwrap(later[0].sessionExercise?.session),
            context: context, formatWeight: { String(format: "%g lb", $0) }
        )
        try context.save()

        XCTAssertGreaterThan(outcome.rebuiltMilestones, 0,
                             "the corrected history earns milestones on replay")
        XCTAssertFalse(outcome.programStateReplayed,
                       "and the banked program grade is deliberately NOT replayed")
        let first = try context.fetch(FetchDescriptor<Milestone>())
            .filter { $0.exerciseName == "Good Morning" }
            .map { "\($0.date.timeIntervalSince1970)|\($0.kindRaw)|\($0.label)" }.sorted()
        XCTAssertFalse(first.isEmpty)

        // Replaying unchanged history reproduces the same set — no duplicates.
        _ = try MilestoneProjection.rebuild(
            exerciseNames: ["Good Morning"], context: context,
            formatWeight: { String(format: "%g lb", $0) })
        try context.save()
        let second = try context.fetch(FetchDescriptor<Milestone>())
            .filter { $0.exerciseName == "Good Morning" }
            .map { "\($0.date.timeIntervalSince1970)|\($0.kindRaw)|\($0.label)" }.sorted()
        XCTAssertEqual(second, first, "a second rebuild regenerates, never appends")
    }

    func testEmptyCorrectionWritesNothing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, sets) = makeBankedFiveByFive(context: context)
        try context.save()

        SessionCorrectionService.apply([(set: sets[0], correction: SetLifecycle.SetCorrection())])

        XCTAssertFalse(context.hasChanges, "a no-op correction must not dirty the record")
    }
}
