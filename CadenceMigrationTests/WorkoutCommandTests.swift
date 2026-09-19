import CadenceCore
import SwiftData
import XCTest

/// The one command path the logger and the Lock Screen share: a face names a
/// set structurally, the service re-derives whether that set is still the one
/// to act on, changes it, saves, and decides what follows.
@MainActor
final class WorkoutCommandTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV13.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// Back Squat as a main lift: one warmup and two work sets, all planned.
    private func makeSession(context: ModelContext, autoStart: Bool) throws -> (WorkoutSession, AppSettings) {
        let settings = AppSettings()
        settings.autoStartRest = autoStart
        context.insert(settings)
        let squat = Exercise(name: "Back Squat", category: .main, type: .barbell, movementGroup: "squat")
        context.insert(squat)
        let session = WorkoutSession()
        context.insert(session)
        let entry = SessionExercise(order: 0, exercise: squat)
        entry.programRole = "main"
        context.insert(entry)
        session.exercises.append(entry)
        for (index, plan) in [(95.0, true), (185.0, false), (185.0, false)].enumerated() {
            let set = SetEntry(order: index, weightLb: plan.0, reps: plan.1 ? 5 : 6, isWarmup: plan.1)
            context.insert(set)
            entry.sets.append(set)
        }
        try context.save()
        return (session, settings)
    }

    private func sets(_ session: WorkoutSession) -> [SetEntry] { session.orderedExercises[0].orderedSets }

    func testCompletingTheFaceSetLogsItAndDecidesTheRest() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (session, settings) = try makeSession(context: context, autoStart: true)

        let warmup = try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)
        XCTAssertEqual(sets(session)[0].status, .completed)
        XCTAssertEqual(warmup.decision.restSeconds, 60, "a warmup rests a minute")
        XCTAssertEqual(warmup.decision.focusExerciseIndex, 0)
        XCTAssertEqual(warmup.decision.nextExerciseName, "Back Squat")
        XCTAssertEqual(warmup.decision.currentSet?.setIndex, 1)
        XCTAssertEqual(warmup.decision.currentSet?.positionLabel, "Set 1 of 2")
        XCTAssertEqual(warmup.decision.currentSet?.prescriptionLabel, "6 reps · 185 lb / 83.9 kg")

        let work = try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 1, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)
        XCTAssertEqual(work.decision.restSeconds,
                       smartRestSeconds(for: session.orderedExercises[0].exercise, role: "main", settings: settings),
                       "a work set arms the exercise's smart rest")
        XCTAssertEqual(work.decision.currentSet?.positionLabel, "Set 2 of 2")
        XCTAssertTrue(work.message.hasPrefix("Back Squat logged. Rest "), work.message)

        let last = try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 2, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)
        XCTAssertNil(last.decision.currentSet, "nothing is left to show once the last set is logged")
        XCTAssertEqual(last.decision.nextExerciseName, "", "no pending work means no rest target")
    }

    func testAStaleFaceNeverCompletesTheFollowingSet() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (session, settings) = try makeSession(context: context, autoStart: true)
        XCTAssertThrowsError(try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 1, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)) { error in
            XCTAssertEqual(error as? WorkoutCommandService.Failure, .movedOn)
        }
        XCTAssertEqual(sets(session).map(\.status), [.planned, .planned, .planned], "nothing moved")
    }

    func testACompletionIsNeverAppliedTwice() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (session, settings) = try makeSession(context: context, autoStart: true)
        _ = try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)
        XCTAssertThrowsError(try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)) { error in
            XCTAssertEqual(error as? WorkoutCommandService.Failure, .alreadyResolved)
        }
        XCTAssertEqual(sets(session)[0].status, .completed)
        XCTAssertEqual(sets(session)[1].status, .planned, "the duplicate tap did not spill onto the next set")
    }

    func testUndoReturnsTheSetToPlannedAndFocusToItsExercise() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (session, settings) = try makeSession(context: context, autoStart: true)
        _ = try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)
        let undo = try WorkoutCommandService.perform(
            .undoSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)
        XCTAssertEqual(sets(session)[0].status, .planned)
        XCTAssertNil(undo.decision.restSeconds, "an undo never arms a rest")
        XCTAssertEqual(undo.decision.focusExerciseIndex, 0)
        XCTAssertEqual(undo.decision.currentSet?.setIndex, 0)
        XCTAssertEqual(undo.message, "Back Squat set back to planned.")
    }

    func testSkipResolvesWithoutArmingARest() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (session, settings) = try makeSession(context: context, autoStart: true)
        let skip = try WorkoutCommandService.perform(
            .skipSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)
        XCTAssertEqual(sets(session)[0].status, .skipped)
        XCTAssertNil(skip.decision.restSeconds)
        XCTAssertEqual(skip.decision.currentSet?.setIndex, 1)
    }

    func testNoRestIsArmedWhileOneRunsOrWhenAutoStartIsOff() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (session, settings) = try makeSession(context: context, autoStart: false)
        let off = try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)
        XCTAssertNil(off.decision.restSeconds)
        XCTAssertEqual(off.message, "Back Squat logged.")
        settings.autoStartRest = true
        let running = try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 1, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: true, context: context)
        XCTAssertNil(running.decision.restSeconds, "a running rest is never restarted")
    }

    func testABankedSessionRefusesCommands() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (session, settings) = try makeSession(context: context, autoStart: true)
        session.isCompleted = true
        try context.save()
        XCTAssertThrowsError(try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: WorkoutCommandService.layout(of: session)),
            settings: settings, restRunning: false, context: context)) { error in
            XCTAssertEqual(error as? WorkoutCommandService.Failure, .sessionAlreadyBanked)
        }
        XCTAssertThrowsError(try WorkoutCommandService.perform(
            .completeSet(sessionID: "no-such-session", exerciseIndex: 0, setIndex: 0, layout: ""),
            settings: settings, restRunning: false, context: context)) { error in
            XCTAssertEqual(error as? WorkoutCommandService.Failure, .sessionNotFound)
        }
    }

    /// A face built before the session was edited names offsets that may now
    /// point elsewhere; its layout no longer matches, so it is refused.
    func testACommandFromABeforeEditFaceIsRefused() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (session, settings) = try makeSession(context: context, autoStart: false)
        let stale = WorkoutCommandService.layout(of: session)
        let extra = SetEntry(order: 3, weightLb: 185, reps: 6, isWarmup: false)
        context.insert(extra)
        session.orderedExercises[0].sets.append(extra)
        try context.save()
        XCTAssertNotEqual(stale, WorkoutCommandService.layout(of: session), "adding a set changes the layout")
        XCTAssertThrowsError(try WorkoutCommandService.perform(
            .completeSet(sessionID: session.id, exerciseIndex: 0, setIndex: 0, layout: stale),
            settings: settings, restRunning: false, context: context)) { error in
            XCTAssertEqual(error as? WorkoutCommandService.Failure, .movedOn)
        }
        XCTAssertEqual(session.orderedExercises[0].orderedSets[0].status, .planned, "nothing was written")
    }

    func testProjectionNamesTheFirstUnresolvedSetOfTheFocusedExercise() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (session, _) = try makeSession(context: context, autoStart: true)
        let face = try XCTUnwrap(WorkoutCommandService.projection(for: session, focus: nil))
        XCTAssertEqual(face.exerciseIndex, 0)
        XCTAssertEqual(face.setIndex, 0)
        XCTAssertTrue(face.isWarmup)
        XCTAssertEqual(face.positionLabel, "Warmup 1 of 1")
        XCTAssertEqual(face.prescriptionLabel, "5 reps · 95 lb / 43.1 kg")
        XCTAssertEqual(face.exerciseName, "Back Squat")
    }
}
