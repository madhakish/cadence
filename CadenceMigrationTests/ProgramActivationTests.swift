import CadenceCore
import Foundation
import SwiftData
import XCTest

/// Epic #155 Stage 4 acceptance tests (A–E). Program switching is suspend +
/// activate, never delete + recreate: history outlives programs, cursors
/// survive, and nothing asks the lifter for a weight they already earned.
@MainActor
final class ProgramActivationTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        // These are current-service behavior tests and instantiate the live
        // Program/ProgramDay/ProgramLift models. V11 is a frozen namespaced
        // migration snapshot; mixing its schema with the live V12 classes
        // traps in SwiftData's relationship casts on Xcode 26.
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func makeProgram(_ context: ModelContext, name: String, active: Bool) -> Program {
        let program = Program(name: name, focus: .strength, isActive: active)
        context.insert(program)
        let day = ProgramDay(name: "Pull", order: 0)
        context.insert(day)
        program.days.append(day)
        let lift = ProgramLift(exerciseName: "Deadlift", role: .main, order: 0,
                               baseWeightLb: 235, estimatedMaxLb: 320)
        context.insert(lift)
        day.lifts.append(lift)
        return program
    }

    /// B — resume preserves the cursor exactly (the Stage 4 gate).
    /// [INV-SWITCH-PRESERVES-CURSOR]
    func testSwitchingAwayAndBackPreservesEveryCursor() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let a = makeProgram(context, name: "Program A", active: true)
        let b = makeProgram(context, name: "Program B", active: false)
        // A is mid-cycle with earned state on its slot.
        a.cycleNumber = 3
        a.currentWeek = 3
        a.nextDayIndex = 2
        let liftA = a.days[0].lifts[0]
        liftA.stallCount = 1
        liftA.pendingBaseWeightLb = 245
        liftA.pendingNote = "held at the peak"
        try context.save()

        try ProgramActivationService.activate(b, context: context)
        XCTAssertTrue(b.isActive)
        XCTAssertFalse(a.isActive, "activation is exclusive")
        XCTAssertEqual(a.cycleNumber, 3, "a suspended program keeps its cycle")
        XCTAssertEqual(a.currentWeek, 3)
        XCTAssertEqual(a.nextDayIndex, 2)
        XCTAssertEqual(liftA.stallCount, 1, "and its per-slot progression state")
        XCTAssertEqual(liftA.pendingBaseWeightLb, 245, "and its pending peak result")

        try ProgramActivationService.activate(a, context: context)
        XCTAssertTrue(a.isActive)
        XCTAssertFalse(b.isActive)
        XCTAssertEqual(a.cycleNumber, 3)
        XCTAssertEqual(a.currentWeek, 3)
        XCTAssertEqual(a.nextDayIndex, 2)
        XCTAssertEqual(liftA.pendingNote, "held at the peak",
                       "resuming re-derives nothing — it is a pause, not a restart")
    }

    /// A + C — a new block seeds from global history and preserves the old
    /// instance, its sessions, and its cursor.
    /// [INV-NEW-BLOCK-USES-CURRENT-HISTORY] [INV-HISTORY-OUTLIVES-PROGRAM]
    func testStartingANewBlockKeepsEveryPriorSessionAndInstance() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let squat = Exercise(name: "Back Squat", category: .main, type: .barbell, movementGroup: "squat")
        context.insert(squat)
        let old = makeProgram(context, name: "Old Block", active: true)
        old.cycleNumber = 2
        // Real work banked under the old program.
        let session = WorkoutSession(date: .now)
        context.insert(session)
        session.isCompleted = true
        session.completedAt = .now
        session.programID = old.id
        session.programName = old.name
        let entry = SessionExercise(order: 0, exercise: squat)
        context.insert(entry)
        session.exercises.append(entry)
        for index in 0..<5 {
            let set = SetEntry(order: index, weightLb: 300, reps: 5, status: .completed)
            context.insert(set)
            entry.sets.append(set)
        }
        try context.save()

        let template = try XCTUnwrap(ProgramTemplateData.all.first)
        let fresh = try ProgramActivationService.startBlock(template, context: context)

        XCTAssertTrue(fresh.isActive)
        XCTAssertFalse(old.isActive, "the previous block is suspended, never deleted")
        XCTAssertEqual(old.cycleNumber, 2, "and keeps its cursor")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1,
                       "no session is deleted by switching")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.programID, old.id,
                       "completed work keeps its original program context")
        XCTAssertEqual(fresh.templateID, template.id, "the new block records its methodology")
        // The banked 300×5 is the only squat evidence in the store, so any
        // squat slot the template seeds must start from it — never a prompt.
        if let squatSlot = fresh.days.flatMap(\.lifts).first(where: { $0.exerciseName == "Back Squat" }) {
            XCTAssertGreaterThan(squatSlot.estimatedMaxLb, 300,
                                 "a new block seeds from banked history, not a catalog default")
        }
    }

    /// The open-session rule: switching fails visibly rather than orphaning
    /// or silently retagging work in progress.
    func testAnOpenSessionFromAnotherProgramBlocksTheSwitch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let a = makeProgram(context, name: "Program A", active: true)
        let b = makeProgram(context, name: "Program B", active: false)
        let open = WorkoutSession(date: .now)
        context.insert(open)
        open.programID = a.id
        open.programName = a.name
        try context.save()

        XCTAssertThrowsError(try ProgramActivationService.activate(b, context: context)) { error in
            XCTAssertEqual(error as? ProgramActivationService.ActivationError,
                           .openSessionBelongsToAnotherProgram("Program A"))
        }
        XCTAssertTrue(a.isActive, "the failed switch changed nothing")
        XCTAssertFalse(b.isActive)

        // An untagged ad-hoc session blocks nothing.
        open.programID = nil
        open.programName = nil
        XCTAssertNoThrow(try ProgramActivationService.activate(b, context: context))
    }

    func testSuspendingIsAPauseNotAReset() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let program = makeProgram(context, name: "Solo", active: true)
        program.currentWeek = 4
        try context.save()

        ProgramActivationService.suspend(program)
        XCTAssertFalse(program.isActive)
        XCTAssertEqual(program.currentWeek, 4)
        XCTAssertEqual(program.days[0].lifts[0].baseWeightLb, 235)
    }
}
