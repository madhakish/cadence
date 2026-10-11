import CadenceCore
import Foundation
import SwiftData
import XCTest

/// Legacy recovery-bridge reconciliation on real SwiftData rows: stale
/// pointer repair, the open-session guard, and the manual Next-day choices
/// that repair must keep. All data is synthetic.
/// [INV-RECOVERY-IS-A-BRIDGE]
@MainActor
final class RecoveryBridgeTests: XCTestCase {
    private let asOf = Date(timeIntervalSince1970: 2_272_000_000)

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV15.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// Lower A / Upper A / Lower B / Upper B in recovery. The bridge selects
    /// Lower A (0) and Upper A (1); the pointer sits on omitted Lower B.
    private func makeRecoveryProgram(_ context: ModelContext) -> Program {
        let days: [(name: String, lift: String, group: String)] = [
            ("Lower A", "Back Squat", "squat"), ("Upper A", "Barbell Bench", "press"),
            ("Lower B", "Deadlift", "hinge"), ("Upper B", "Overhead Press", "press"),
        ]
        let program = Program(name: "Fixture Recovery Bridge", focus: .strength, isActive: true)
        context.insert(program)
        for (order, day) in days.enumerated() {
            context.insert(Exercise(name: day.lift, category: .main, type: .barbell, movementGroup: day.group))
            let programDay = ProgramDay(name: day.name, order: order)
            context.insert(programDay)
            program.days.append(programDay)
            let lift = ProgramLift(exerciseName: day.lift, role: .main, order: 0,
                                   baseWeightLb: 135, estimatedMaxLb: 185)
            context.insert(lift)
            programDay.lifts.append(lift)
        }
        program.currentWeek = ProgramProgression.deloadWeek
        program.nextDayIndex = 2
        return program
    }

    private func recoverySession(_ context: ModelContext, program: Program, dayIndex: Int, completed: Bool) {
        let session = WorkoutSession(date: asOf.addingTimeInterval(-86_400))
        context.insert(session)
        session.programID = program.id
        session.programName = program.name
        session.programCycleNumber = program.cycleNumber
        session.programWeek = ProgramProgression.deloadWeek
        session.programDayIndex = dayIndex
        if completed {
            session.isCompleted = true
            session.completedAt = session.date
        }
    }

    func testStalePointerIsRepairedAndSavedWithoutRollingTheCycle() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let program = makeRecoveryProgram(context)
        program.orderedDays[0].orderedLifts[0].pendingBaseWeightLb = 140
        try context.save()

        let omitted = try RecoveryBridgeService.reconcileRecoveryBridge(program: program, context: context, asOf: asOf)
        XCTAssertNil(omitted?.reason, "a pointer repair never declares recovery complete")
        XCTAssertEqual(omitted?.message.hasPrefix("Recovery continues"), true)
        XCTAssertEqual(program.nextDayIndex, 0, "an omitted pointer resumes the first selected exposure")
        XCTAssertEqual(program.cycleNumber, 1)
        XCTAssertEqual(program.currentWeek, ProgramProgression.deloadWeek)
        XCTAssertEqual(program.orderedDays[0].orderedLifts[0].pendingBaseWeightLb, 140, "pending grades are not applied")
        XCTAssertFalse(context.hasChanges, "the repair is saved, not left staged")

        recoverySession(context, program: program, dayIndex: 0, completed: true)
        try context.save()
        let banked = try RecoveryBridgeService.reconcileRecoveryBridge(program: program, context: context, asOf: asOf)
        XCTAssertNil(banked?.reason)
        XCTAssertEqual(program.nextDayIndex, 1, "an already-banked pointer moves to the remaining exposure")
        XCTAssertNil(try RecoveryBridgeService.reconcileRecoveryBridge(program: program, context: context, asOf: asOf),
                     "a valid pointer is left alone")
    }

    /// A tagged session for `program`. `instruction` is the status of its one
    /// program set; nil banks no program set at all (an empty finished session).
    @discardableResult
    private func taggedSession(
        _ context: ModelContext, program: Program, cycle: Int, week: Int, date: Date,
        completed: Bool = true, legacyName: Bool = false,
        instruction: SetStatus? = .completed, block: String = "work", warmup: Bool = false
    ) -> WorkoutSession {
        let session = WorkoutSession(date: date)
        context.insert(session)
        session.programID = legacyName ? nil : program.id
        session.programName = program.name
        session.programCycleNumber = cycle
        session.programWeek = week
        session.programDayIndex = 0
        if completed {
            session.isCompleted = true
            session.completedAt = session.date
        }
        if let instruction {
            let entry = SessionExercise(order: 0, exercise: nil)
            entry.programSlotID = program.orderedDays[0].orderedLifts[0].id
            entry.programRole = "main"
            entry.plannedSets = 1
            context.insert(entry)
            session.exercises.append(entry)
            let set = SetEntry(order: 0, weightLb: 135, reps: 5, isWarmup: warmup, status: instruction)
            set.prescriptionBlockRaw = block
            context.insert(set)
            entry.sets.append(set)
        }
        return session
    }

    // [INV-UNBANKED-ROTATION-STARTS-FIRST]
    func testRotationHasBankedWorkCountsOnlyCompletedProgramWorkOfThisCycleAndRotation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let program = makeRecoveryProgram(context)
        program.cycleNumber = 2
        program.currentWeek = 1
        let yesterday = asOf.addingTimeInterval(-86_400)
        try context.save()
        XCTAssertFalse(try RecoveryBridgeService.rotationHasBankedWork(for: program, context: context),
                       "a program with no sessions has banked nothing")

        taggedSession(context, program: program, cycle: 2, week: 1, date: yesterday, completed: false)
        taggedSession(context, program: program, cycle: 2, week: 2, date: yesterday)
        taggedSession(context, program: program, cycle: 1, week: 1, date: yesterday)
        try context.save()
        XCTAssertFalse(try RecoveryBridgeService.rotationHasBankedWork(for: program, context: context),
                       "an open session, another rotation, and an earlier cycle do not count")

        // A finished session is banked work only when a program instruction
        // was completed: the gate SessionCompletion advances behind.
        taggedSession(context, program: program, cycle: 2, week: 1, date: yesterday, instruction: nil)
        taggedSession(context, program: program, cycle: 2, week: 1, date: yesterday, instruction: .skipped)
        taggedSession(context, program: program, cycle: 2, week: 1, date: yesterday, warmup: true)
        taggedSession(context, program: program, cycle: 2, week: 1, date: yesterday, block: "backoff")
        try context.save()
        XCTAssertFalse(try RecoveryBridgeService.rotationHasBankedWork(for: program, context: context),
                       "empty, all-skipped, warm-up-only and bonus-only sessions never advanced the rotation")

        // Work inside an active-recovery interval never advanced it either
        // (INV-RECOVERY-WORK-IS-OFF-PROGRAM).
        let recovered = asOf.addingTimeInterval(-10 * 86_400)
        context.insert(TrainingInterval(kindRaw: "activeRecovery",
                                        startDate: recovered.addingTimeInterval(-86_400),
                                        endDate: recovered.addingTimeInterval(86_400)))
        taggedSession(context, program: program, cycle: 2, week: 1, date: recovered)
        try context.save()
        XCTAssertFalse(try RecoveryBridgeService.rotationHasBankedWork(for: program, context: context),
                       "a session inside an active-recovery interval is off-program and does not count")

        taggedSession(context, program: program, cycle: 2, week: 1, date: yesterday, legacyName: true)
        try context.save()
        XCTAssertTrue(try RecoveryBridgeService.rotationHasBankedWork(for: program, context: context),
                      "a completed program instruction of this cycle and rotation counts, through the legacy-name match too")
    }

    // [INV-UNBANKED-ROTATION-STARTS-FIRST]
    func testRotationHasBankedWorkIsNotCrowdedOutByNewerOffProgramSessions() throws {
        for legacyName in [false, true] {
            let container = try makeContainer()
            let context = container.mainContext
            let program = makeRecoveryProgram(context)
            program.currentWeek = 1
            // One real banked completion, then 32 newer completions inside an
            // active-recovery interval. A bounded newest-first fetch would see
            // only the recovery rows and call the rotation unbanked.
            context.insert(TrainingInterval(kindRaw: "activeRecovery",
                                            startDate: asOf.addingTimeInterval(-35 * 86_400), endDate: asOf))
            taggedSession(context, program: program, cycle: 1, week: 1,
                          date: asOf.addingTimeInterval(-40 * 86_400), legacyName: legacyName)
            for day in 0..<32 {
                taggedSession(context, program: program, cycle: 1, week: 1,
                              date: asOf.addingTimeInterval(Double(-34 + day) * 86_400))
            }
            try context.save()
            XCTAssertTrue(try RecoveryBridgeService.rotationHasBankedWork(for: program, context: context),
                          "the older real completion is found behind 32 newer off-program rows (legacyName: \(legacyName))")
        }
    }

    func testAnOpenSessionForThisProgramBlocksRepair() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let program = makeRecoveryProgram(context)
        recoverySession(context, program: program, dayIndex: 2, completed: false)
        try context.save()

        XCTAssertNil(try RecoveryBridgeService.reconcileRecoveryBridge(program: program, context: context, asOf: asOf))
        XCTAssertEqual(program.nextDayIndex, 2, "the program never changes underneath an open workout")

        // An open ad-hoc session belongs to no program and blocks nothing.
        let open = try context.fetch(FetchDescriptor<WorkoutSession>()).first
        open?.programID = nil
        open?.programName = nil
        try context.save()
        XCTAssertNotNil(try RecoveryBridgeService.reconcileRecoveryBridge(program: program, context: context, asOf: asOf))
        XCTAssertEqual(program.nextDayIndex, 0)
    }

    func testManualChoicesAreExactlyThePointersRepairKeeps() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let program = makeRecoveryProgram(context)
        try context.save()
        XCTAssertEqual(try RecoveryBridgeService.manualNextDayOrders(program: program, context: context), [0, 1])

        recoverySession(context, program: program, dayIndex: 0, completed: true)
        try context.save()
        let offered = try RecoveryBridgeService.manualNextDayOrders(program: program, context: context)
        XCTAssertEqual(offered, [1], "a banked recovery day is not offered again")
        for pointer in 0...3 {
            program.nextDayIndex = pointer
            try context.save()
            _ = try RecoveryBridgeService.reconcileRecoveryBridge(program: program, context: context, asOf: asOf)
            XCTAssertEqual(program.nextDayIndex == pointer, offered?.contains(pointer) == true,
                           "pointer \(pointer) is offered iff reconciliation keeps it")
        }

        program.currentWeek = ProgramProgression.gradedWeek
        XCTAssertNil(try RecoveryBridgeService.manualNextDayOrders(program: program, context: context),
                     "build rotations offer every day")
    }
}
