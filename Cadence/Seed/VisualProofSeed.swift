#if DEBUG
import Foundation
import SwiftData
import CadenceCore

/// Deterministic, disposable content for the iPhone visual-regression suite.
/// Production startup never calls this type; `AppBootstrap` gates it behind
/// the explicit `--visual-proof` launch argument and an in-memory container.
enum VisualProofSeed {
    private static let calendar = Calendar(identifier: .gregorian)

    static func install(in context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        guard let squat = exercises.first(where: { $0.name == "Back Squat" }),
              let rdl = exercises.first(where: { $0.name == "Romanian Deadlift" })
        else {
            throw NSError(
                domain: "Cadence.VisualProof",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The seeded proof exercises are missing."]
            )
        }
        guard let gym = try context.fetch(FetchDescriptor<Gym>()).first else {
            throw NSError(
                domain: "Cadence.VisualProof",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The seeded proof gym is missing."]
            )
        }

        // A pound bar at a kilogram-only rack is the mixed-unit case that is
        // easiest to misunderstand between sets. Keep the real metadata and
        // solver in charge; the fixture supplies inventory, never a fake stack.
        gym.name = "Foundry Barbell"
        gym.defaultBar = .bar45lb
        gym.plateToggles = Plate.allStandard.map {
            PlateToggle(plate: $0, enabled: $0.unit == .kg)
        }
        gym.collarWeightLb = 0
        gym.loadingPolicy = .closest
        if arguments.contains("--visual-proof-sparse-rack") {
            let sparseRack = Gym(name: "Sparse Rack", defaultBar: .bar45lb)
            let visiblePlateIDs: Set<String> = ["20-kg", "10-kg"]
            sparseRack.plateToggles = Plate.allStandard.map {
                PlateToggle(plate: $0, enabled: visiblePlateIDs.contains($0.id))
            }
            context.insert(sparseRack)
        }
        squat.stationDenomination = .kg
        rdl.stationDenomination = .kg
        squat.notes = "High-bar stance. Brace before the walkout; drive evenly through the whole foot."

        if let settings = try context.fetch(FetchDescriptor<AppSettings>()).first {
            settings.unitDisplay = .lbPrimary
            settings.themeNameRaw = ThemeName.carbon.rawValue
            settings.haptics = false
        }

        let program = Program(
            name: "Foundry Hypertrophy",
            focus: .hypertrophy,
            cycleNumber: 3,
            currentWeek: 2,
            nextDayIndex: 0,
            roundingLb: 5,
            isActive: true
        )
        program.coachEnabled = false
        context.insert(program)

        let day = ProgramDay(name: "Lower Forge", order: 0)
        day.trainingIntent = .volume
        context.insert(day)
        program.days.append(day)

        let squatSlot = ProgramLift(
            exerciseName: squat.name,
            role: .main,
            order: 0,
            prescription: .hypertrophy,
            baseWeightLb: 139,
            estimatedMaxLb: 185
        )
        squatSlot.exerciseID = squat.id
        context.insert(squatSlot)
        day.lifts.append(squatSlot)

        let rdlSlot = ProgramLift(
            exerciseName: rdl.name,
            role: .complementary,
            order: 1,
            prescription: .automatic,
            baseWeightLb: 183,
            estimatedMaxLb: 235
        )
        rdlSlot.exerciseID = rdl.id
        context.insert(rdlSlot)
        day.lifts.append(rdlSlot)

        try addHistoricalSquatSessions(
            exercise: squat,
            gym: gym,
            program: program,
            slot: squatSlot,
            context: context
        )
        try addOpenSession(
            squat: squat,
            rdl: rdl,
            gym: gym,
            program: program,
            squatSlot: squatSlot,
            rdlSlot: rdlSlot,
            leavesSecondWarmupPlanned: arguments.contains("--visual-proof-unresolved-warmup"),
            context: context
        )
        try addWoodSplittingActivity(context: context)
        try context.save()
    }

    private static func addOpenSession(
        squat: Exercise,
        rdl: Exercise,
        gym: Gym,
        program: Program,
        squatSlot: ProgramLift,
        rdlSlot: ProgramLift,
        leavesSecondWarmupPlanned: Bool,
        context: ModelContext
    ) throws {
        let session = WorkoutSession(
            date: Date.now.addingTimeInterval(-24 * 60),
            notes: "",
            gymID: gym.id,
            gymName: gym.name
        )
        session.programID = program.id
        session.programName = program.name
        session.programTemplateID = "visual-proof"
        session.programCycleNumber = program.cycleNumber
        session.programWeek = program.currentWeek
        session.programDayIndex = 0
        session.programPlanNames = [squat.name, rdl.name]
        context.insert(session)

        let squatLoad = solution(targetLb: 139, gym: gym)
        let squatEntry = entry(
            order: 0,
            exercise: squat,
            slot: squatSlot,
            programRole: .main,
            targetLb: 139,
            plannedLb: squatLoad.loadout.totalLb,
            sets: 3,
            reps: 6,
            context: context
        )
        session.exercises.append(squatEntry)

        appendSet(
            SetEntry(order: 0, weightLb: gym.defaultBar.lb, reps: 8, isWarmup: true,
                     status: .completed, enteredUnit: .lb,
                     targetWeightLb: gym.defaultBar.lb, plannedWeightLb: gym.defaultBar.lb,
                     plannedReps: 8, prescriptionBlock: .warmup),
            to: squatEntry,
            context: context
        )
        let secondWarmup = solution(targetLb: 89, gym: gym).loadout.totalLb
        appendSet(
            SetEntry(order: 1, weightLb: secondWarmup, reps: 5, isWarmup: true,
                     status: leavesSecondWarmupPlanned ? .planned : .completed, enteredUnit: .lb,
                     targetWeightLb: 89, plannedWeightLb: secondWarmup,
                     plannedReps: 5, prescriptionBlock: .warmup),
            to: squatEntry,
            context: context
        )
        for index in 0..<3 {
            appendSet(
                SetEntry(
                    order: index + 2,
                    weightLb: squatLoad.loadout.totalLb,
                    reps: 6,
                    status: index == 0 ? .completed : .planned,
                    enteredUnit: .lb,
                    targetWeightLb: 139,
                    plannedWeightLb: squatLoad.loadout.totalLb,
                    plannedReps: 6,
                    prescriptionBlock: .work
                ),
                to: squatEntry,
                context: context
            )
        }

        let rdlLoad = solution(targetLb: 183, gym: gym)
        let rdlEntry = entry(
            order: 1,
            exercise: rdl,
            slot: rdlSlot,
            programRole: .complementary,
            targetLb: 183,
            plannedLb: rdlLoad.loadout.totalLb,
            sets: 3,
            reps: 8,
            context: context
        )
        session.exercises.append(rdlEntry)
        for index in 0..<3 {
            appendSet(
                SetEntry(
                    order: index,
                    weightLb: rdlLoad.loadout.totalLb,
                    reps: 8,
                    status: .planned,
                    enteredUnit: .lb,
                    targetWeightLb: 183,
                    plannedWeightLb: rdlLoad.loadout.totalLb,
                    plannedReps: 8,
                    prescriptionBlock: .work
                ),
                to: rdlEntry,
                context: context
            )
        }
    }

    private static func addHistoricalSquatSessions(
        exercise: Exercise,
        gym: Gym,
        program: Program,
        slot: ProgramLift,
        context: ModelContext
    ) throws {
        for (index, target) in [125.0, 132.0, 136.0].enumerated() {
            let date = calendar.date(byAdding: .day, value: -21 + index * 7, to: .now) ?? .now
            let session = WorkoutSession(date: date, gymID: gym.id, gymName: gym.name)
            session.isCompleted = true
            session.completedAt = date.addingTimeInterval(62 * 60)
            session.programID = program.id
            session.programName = program.name
            session.programCycleNumber = max(1, program.cycleNumber - 1)
            session.programWeek = index + 1
            session.programDayIndex = 0
            context.insert(session)

            let load = solution(targetLb: target, gym: gym).loadout.totalLb
            let historyEntry = entry(
                order: 0,
                exercise: exercise,
                slot: slot,
                programRole: .main,
                targetLb: target,
                plannedLb: load,
                sets: 3,
                reps: 6,
                context: context
            )
            session.exercises.append(historyEntry)
            appendSet(
                SetEntry(order: 0, weightLb: load, reps: 6, status: .completed,
                         enteredUnit: .lb, targetWeightLb: target,
                         plannedWeightLb: load, plannedReps: 6),
                to: historyEntry,
                context: context
            )
        }
    }

    private static func addWoodSplittingActivity(context: ModelContext) throws {
        let start = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        _ = try ActivitySession.create(
            input: .init(
                kind: .woodSplitting,
                startDate: start,
                durationSeconds: 4 * 3_600 + 20 * 60,
                sessionRPE: 8.5,
                loadLb: Weight.toLb(8, from: .kg),
                notes: "Oak rounds after rain; Fiskars IsoCore maul.",
                woodSplitting: .init(
                    rounds: 38,
                    splitPieces: 214,
                    estimatedStrikes: 510,
                    cordVolume: 0.42
                ),
                enteredUnit: .kg
            ),
            context: context
        )
    }

    private static func solution(targetLb: Double, gym: Gym) -> PlateSolution {
        PlateMath.solve(
            targetLb: targetLb,
            bar: gym.defaultBar,
            plates: gym.availablePlates,
            collarLb: gym.collarWeightLb,
            policy: gym.loadingPolicy
        )
    }

    private static func entry(
        order: Int,
        exercise: Exercise,
        slot: ProgramLift,
        programRole: LiftRole,
        targetLb: Double,
        plannedLb: Double,
        sets: Int,
        reps: Int,
        context: ModelContext
    ) -> SessionExercise {
        let result = SessionExercise(order: order, exercise: exercise)
        result.exerciseID = exercise.id
        result.stampBarID(for: exercise, bar: .bar45lb)
        result.programRole = programRole.rawValue
        result.programSlotID = slot.id
        result.prescriptionStyleRaw = slot.prescriptionRaw
        result.phase = .load
        result.targetWeightLb = targetLb
        result.plannedWeightLb = plannedLb
        result.plannedSets = sets
        result.plannedReps = reps
        context.insert(result)
        return result
    }

    private static func appendSet(
        _ set: SetEntry,
        to entry: SessionExercise,
        context: ModelContext
    ) {
        context.insert(set)
        entry.sets.append(set)
    }
}
#endif
