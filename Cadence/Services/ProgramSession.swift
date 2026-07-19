import Foundation
import SwiftData
import CadenceCore

/// Builds a workout session from a program day: main + complementary lifts
/// (planned at the program's current week, barbell mains get a warmup ramp)
/// plus accessories, all tagged so completion advances PROGRAM state.
/// Mirrors web `createSessionFromProgramDay`.
enum ProgramSession {

    enum BuildError: LocalizedError {
        case missingExercise(String)
        var errorDescription: String? {
            switch self {
            case .missingExercise(let name): return "The exercise library is missing \(name). Sync or restore the library, then try again."
            }
        }
    }

    static func make(program: Program, day: ProgramDay, context: ModelContext) throws -> WorkoutSession {
        // Resume, don't duplicate (mirrors web createSessionFromProgramDay):
        // an open session for THIS day at the current position, whose content
        // still matches the plan, is resumed instead of duplicated (issue 17).
        // But a name-only match resurrected STALE snapshots — after editing a
        // day, Start kept returning the pre-edit session (old complementary
        // lift). canResumeSession requires the tag AND the exercise list to
        // match the current plan, so an edited/moved day builds fresh.
        // (Predicate can't read a captured property, so filter in Swift.)
        let programName = program.name
        let programID = program.id
        let openDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { !$0.isCompleted }
        )
        let dayNames = day.orderedLifts.map(\.exerciseName) + day.orderedAccessories.map(\.exerciseName)
        if let existing = try context.fetch(openDescriptor).first(where: { s in
            (s.programID == programID || (s.programID == nil && s.programName == programName)) &&
            ProgramProgression.canResumeSession(
                // Missing tag fields → -1 sentinel (never equals a real
                // 1-based cycle/week/day), so ambiguously-tagged legacy
                // sessions build fresh rather than resume (Copilot).
                tagCycle: s.programCycleNumber ?? -1,
                tagWeek: s.programWeek ?? -1,
                tagDayIndex: s.programDayIndex ?? -1,
                cycleNumber: program.cycleNumber, currentWeek: program.currentWeek, dayIndex: day.order,
                sessionPlanNames: s.programPlanNames ?? [],
                dayPlanNames: dayNames)
        }) { return existing }

        let gyms = try context.fetch(FetchDescriptor<Gym>())
        let defaultGym = gyms.first(where: { $0.isDefault }) ?? gyms.first
        let entryUnit = try context.fetch(FetchDescriptor<AppSettings>()).first?.unitDisplay.primaryUnit ?? .lb
        let session = WorkoutSession(gymID: defaultGym?.id, gymName: defaultGym?.name)
        let selectedBar = defaultGym?.defaultBar ?? .bar45lb
        let barLb = selectedBar.lb
        func neat(_ weightLb: Double, _ exercise: Exercise?, isMain: Bool) -> Double {
            achievableWeight(weightLb, exercise: exercise, isMain: isMain,
                             gym: defaultGym, bar: selectedBar, stepLb: program.roundingLb)
        }
        session.programID = program.id
        session.programName = program.name
        session.programCycleNumber = program.cycleNumber
        session.programWeek = program.currentWeek
        session.programDayIndex = day.order
        session.programPlanNames = dayNames   // the plan this session is built from
        context.insert(session)

        let phase = CyclePhase(rawValue: program.currentWeek) ?? .volume
        var order = 0
        var preparedMovementGroups: Set<String> = []

        for lift in day.orderedLifts {
            let exercise = try findExercise(named: lift.exerciseName, context: context)
            let loadStep = ProgramEngine.loadStep(programRoundingLb: program.roundingLb,
                                                  exerciseType: exercise.typeRaw)
            let plan = ProgramEngine.programPlan(
                for: CycleState(cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: phase, incrementLb: 0),
                programRoundingLb: program.roundingLb,
                exerciseType: exercise.typeRaw,
                movementGroup: exercise.movementGroup,
                role: lift.role,
                focus: program.focus,
                prescriptionStyle: lift.prescription
            )
            let weightLb = neat(plan.weightLb, exercise, isMain: lift.role.rawValue == "main")
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = lift.role.rawValue
            entry.programSlotID = lift.id
            entry.plannedWeightLb = weightLb
            entry.plannedSets = plan.sets
            entry.plannedReps = plan.reps
            entry.phase = phase
            entry.session = session
            context.insert(entry)
            session.exercises.append(entry)

            var so = 0
            let resolvedWarmup: WarmupPolicy = {
                guard lift.warmupPolicy == .automatic else { return lift.warmupPolicy }
                return preparedMovementGroups.contains(exercise.movementGroup) ? .short : .full
            }()
            if exercise.type == .barbell && resolvedWarmup != .none {
                let fullRamp = WarmupRamp.ramp(workingLb: weightLb, barLb: barLb, roundingLb: program.roundingLb)
                let ramp = resolvedWarmup == .short ? Array(fullRamp.suffix(2)) : fullRamp
                for wu in ramp {
                    insertSet(entry, order: so, weight: wu.weightLb, reps: wu.reps, warmup: true, perSide: false, enteredUnit: entryUnit, context: context)
                    so += 1
                }
            } else if exercise.type == .dumbbell && resolvedWarmup != .none {
                let fullRamp = WarmupRamp.dumbbellRamp(workingLb: weightLb, roundingLb: loadStep)
                let ramp = resolvedWarmup == .short ? Array(fullRamp.suffix(2)) : fullRamp
                for wu in ramp {
                    insertSet(entry, order: so, weight: wu.weightLb, reps: wu.reps, warmup: true,
                              perSide: exercise.isUnilateral, enteredUnit: entryUnit, context: context)
                    so += 1
                }
            }
            for _ in 0..<plan.sets {
                insertSet(entry, order: so, weight: weightLb, reps: plan.reps, warmup: false, perSide: exercise.isUnilateral, enteredUnit: entryUnit, context: context)
                so += 1
            }
            if !exercise.movementGroup.isEmpty { preparedMovementGroups.insert(exercise.movementGroup) }
            order += 1
        }

        for acc in day.orderedAccessories {
            let exercise = try findExercise(named: acc.exerciseName, context: context)
            let weightLb = neat(acc.weightLb, exercise, isMain: false)
            let isTimed = exercise.type == .timed
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = "accessory"
            entry.programSlotID = acc.id
            entry.plannedWeightLb = weightLb
            entry.plannedSets = acc.sets
            entry.plannedReps = isTimed ? 1 : acc.currentReps
            entry.session = session
            context.insert(entry)
            session.exercises.append(entry)
            for i in 0..<acc.sets {
                insertSet(entry, order: i, weight: isTimed ? 0 : weightLb, reps: isTimed ? 1 : acc.currentReps,
                          warmup: false, perSide: exercise.isUnilateral, enteredUnit: entryUnit,
                          durationSeconds: isTimed ? acc.targetSeconds : nil, context: context)
            }
            order += 1
        }

        return session
    }

    /// Secondary/accessory barbell prescriptions snap to a neat bar-loadable
    /// weight; mains and non-barbell work are left as-is. Shared with HomeView's
    /// preview so the card and the started session agree. Mirrors web `neatProgramWeight`.
    static func neatWeight(_ weightLb: Double, isBarbell: Bool, isMain: Bool, barLb: Double, stepLb: Double) -> Double {
        (!isMain && isBarbell) ? Weight.barLoadable(weightLb, barLb: barLb, stepLb: stepLb) : weightLb
    }

    /// Resolve the prescription to equipment that exists at this gym. The
    /// achieved total is what the logger stores, so the plate picture, logged
    /// set, history, and next progression all describe the same load.
    static func achievableWeight(_ weightLb: Double, exercise: Exercise?, isMain: Bool,
                                 gym: Gym?, bar: Bar, stepLb: Double) -> Double {
        guard exercise?.type == .barbell, weightLb > 0 else { return weightLb }
        let rounded = neatWeight(weightLb, isBarbell: true, isMain: isMain,
                                 barLb: bar.lb, stepLb: stepLb)
        let solution = PlateMath.solve(
            targetLb: rounded, bar: bar,
            plates: gym?.availablePlates ?? Plate.allStandard,
            collarLb: gym?.collarWeightLb ?? 0,
            policy: gym?.loadingPolicy ?? .closest
        )
        return solution.loadout.totalLb
    }

    private static func insertSet(_ entry: SessionExercise, order: Int, weight: Double, reps: Int, warmup: Bool,
                                  perSide: Bool, enteredUnit: WeightUnit, durationSeconds: Int? = nil,
                                  context: ModelContext) {
        let set = SetEntry(order: order, weightLb: weight, reps: reps, isWarmup: warmup, isPerSide: perSide,
                           enteredUnit: enteredUnit, durationSeconds: durationSeconds,
                           loadBasis: entry.exercise?.loadBasis,
                           implementCount: entry.exercise?.resolvedImplementCount ?? 1)
        set.sessionExercise = entry
        context.insert(set)
        entry.sets.append(set)
    }

    private static func findExercise(named name: String, context: ModelContext) throws -> Exercise {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
        guard let exercise = try context.fetch(descriptor).first else { throw BuildError.missingExercise(name) }
        return exercise
    }
}
