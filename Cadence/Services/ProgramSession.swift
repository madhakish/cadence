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
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())

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
                dayPlanNames: dayNames) &&
            sessionTargetsMatch(s, program: program, day: day, exercises: allExercises)
        }) { return existing }

        let gyms = try context.fetch(FetchDescriptor<Gym>())
        let defaultGym = gyms.first(where: { $0.isDefault }) ?? gyms.first
        let entryUnit = try context.fetch(FetchDescriptor<AppSettings>()).first?.unitDisplay.primaryUnit ?? .lb
        let session = WorkoutSession(gymID: defaultGym?.id, gymName: defaultGym?.name)
        let selectedBar = defaultGym?.defaultBar ?? .bar45lb
        let barLb = selectedBar.lb
        let phase = CyclePhase(rawValue: program.currentWeek) ?? .volume
        let accessoryPercent = try temporaryAccessoryPercent(
            program: program, context: context
        )
        func neat(_ weightLb: Double, _ exercise: Exercise?, isMain: Bool,
                  phase prescriptionPhase: CyclePhase? = nil) -> Double {
            achievableWeight(weightLb, exercise: exercise, isMain: isMain,
                             gym: defaultGym, bar: selectedBar, stepLb: program.roundingLb,
                             phase: prescriptionPhase)
        }
        session.programID = program.id
        session.programName = program.name
        session.programCycleNumber = program.cycleNumber
        session.programWeek = program.currentWeek
        session.programDayIndex = day.order
        session.programPlanNames = dayNames   // the plan this session is built from
        context.insert(session)

        var order = 0
        var preparedMovementGroups: Set<String> = []

        for lift in day.orderedLifts {
            let exercise = try findExercise(named: lift.exerciseName, context: context)
            let loadStep = ProgramEngine.loadStep(programRoundingLb: program.roundingLb,
                                                  exerciseType: exercise.typeRaw)
            let configuration = lift.prescriptionConfiguration(movementGroup: exercise.movementGroup)
            let prescription = ProgramEngine.sessionPrescription(
                for: CycleState(cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: phase, incrementLb: 0),
                programRoundingLb: program.roundingLb,
                exerciseType: exercise.typeRaw,
                movementGroup: exercise.movementGroup,
                role: lift.role,
                focus: program.focus,
                prescriptionStyle: lift.prescription,
                configuration: configuration,
                estimatedMaxLb: lift.estimatedMaxLb
            )
            let plan = prescription.mainWork
            // Methodology slots prescribe exact loads (a +5/session contract, TM
            // percentages, speed waves) — snap them like main lifts, never
            // through the complementary per-side rounding that would distort
            // the increments.
            let exactLoad = lift.role.rawValue == "main" || lift.prescription.buildsOwnSessionShape
            let weightLb = neat(plan.weightLb, exercise, isMain: exactLoad, phase: phase)
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = lift.role.rawValue
            entry.programSlotID = lift.id
            entry.plannedWeightLb = weightLb
            entry.targetWeightLb = plan.weightLb
            entry.plannedSets = plan.sets
            entry.plannedReps = plan.reps
            entry.prescriptionStyleRaw = lift.prescription.rawValue
            let automaticDrop = (exercise.movementGroup == "squat" || exercise.movementGroup == "hinge") ? 10.0 : 5.0
            entry.fallbackWeightLb = fallbackWeight(
                from: weightLb, exercise: exercise, gym: defaultGym, bar: selectedBar,
                roundingLb: loadStep, dropIncrementLb: lift.dropIncrementLb > 0 ? lift.dropIncrementLb : automaticDrop
            )
            entry.phase = phase
            context.insert(entry)
            session.exercises.append(entry)

            var so = 0
            let resolvedWarmup: WarmupPolicy = {
                guard lift.warmupPolicy == .automatic else { return lift.warmupPolicy }
                return preparedMovementGroups.contains(exercise.movementGroup) ? .short : .full
            }()
            let blockLoads = prescription.blocks.map {
                neat($0.weightLb, exercise, isMain: exactLoad, phase: phase)
            }
            let topPreparationLoad = blockLoads.max() ?? weightLb
            if exercise.type == .barbell && resolvedWarmup != .none {
                let fullRamp = WarmupRamp.ramp(
                    workingLb: topPreparationLoad, barLb: barLb,
                    roundingLb: program.roundingLb,
                    includeEmptyBar: includesEmptyBarWarmup(for: exercise)
                )
                let achievedRamp = achievableWarmups(fullRamp, workingLb: topPreparationLoad,
                                                     gym: defaultGym, bar: selectedBar)
                let ramp = resolvedWarmup == .short ? Array(achievedRamp.suffix(2)) : achievedRamp
                for wu in ramp {
                    insertSet(entry, order: so, weight: wu.weightLb, reps: wu.reps, warmup: true,
                              perSide: false, enteredUnit: entryUnit, targetWeight: wu.weightLb,
                              plannedWeight: wu.weightLb, plannedReps: wu.reps,
                              block: .warmup, context: context)
                    so += 1
                }
            } else if exercise.type == .dumbbell && resolvedWarmup != .none {
                let fullRamp = WarmupRamp.dumbbellRamp(workingLb: topPreparationLoad, roundingLb: loadStep)
                let ramp = resolvedWarmup == .short ? Array(fullRamp.suffix(2)) : fullRamp
                for wu in ramp {
                    insertSet(entry, order: so, weight: wu.weightLb, reps: wu.reps, warmup: true,
                              perSide: exercise.isUnilateral, enteredUnit: entryUnit,
                              targetWeight: wu.weightLb, plannedWeight: wu.weightLb, plannedReps: wu.reps,
                              block: .warmup, context: context)
                    so += 1
                }
            }
            for (blockIndex, block) in prescription.blocks.enumerated() {
                let achieved = blockLoads[blockIndex]
                let warmupBlock = block.kind == .primer
                // A standard ramp may already end on the exact primer load.
                // Keep only one observable set at that load.
                if warmupBlock, entry.orderedSets.last?.weightLb == achieved { continue }
                for _ in 0..<block.sets {
                    insertSet(entry, order: so, weight: achieved, reps: block.reps,
                              warmup: warmupBlock, perSide: exercise.isUnilateral,
                              enteredUnit: entryUnit, targetWeight: block.weightLb,
                              plannedWeight: achieved, plannedReps: block.reps,
                              block: block.kind, context: context)
                    so += 1
                }
            }
            if !exercise.movementGroup.isEmpty { preparedMovementGroups.insert(exercise.movementGroup) }
            order += 1
        }

        for acc in day.orderedAccessories {
            let exercise = try findExercise(named: acc.exerciseName, context: context)
            let weightLb = neat(acc.weightLb, exercise, isMain: false)
            let isTimed = exercise.type == .timed || exercise.type == .conditioning
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = "accessory"
            entry.programSlotID = acc.id
            entry.plannedWeightLb = weightLb
            entry.targetWeightLb = acc.weightLb
            let effectiveSets = acc.capacityManaged
                ? max(1, Int((Double(acc.sets) * Double(accessoryPercent) / 100).rounded()))
                : acc.sets
            entry.plannedSets = effectiveSets
            entry.plannedReps = isTimed ? 1 : acc.currentReps
            entry.plannedDurationSeconds = isTimed ? acc.targetSeconds : nil
            context.insert(entry)
            session.exercises.append(entry)
            for i in 0..<effectiveSets {
                insertSet(entry, order: i, weight: isTimed ? 0 : weightLb, reps: isTimed ? 1 : acc.currentReps,
                          warmup: false, perSide: exercise.isUnilateral, enteredUnit: entryUnit,
                          durationSeconds: isTimed ? acc.targetSeconds : nil,
                          targetWeight: isTimed ? 0 : acc.weightLb, plannedWeight: isTimed ? 0 : weightLb,
                          plannedReps: isTimed ? 1 : acc.currentReps,
                          plannedDurationSeconds: isTimed ? acc.targetSeconds : nil,
                          block: exercise.type == .conditioning ? .conditioning : .work,
                          context: context)
            }
            order += 1
        }

        return session
    }

    private static func sessionTargetsMatch(
        _ session: WorkoutSession,
        program: Program,
        day: ProgramDay,
        exercises: [Exercise]
    ) -> Bool {
        guard let phase = CyclePhase(rawValue: program.currentWeek) else { return false }
        return day.orderedLifts.allSatisfy { lift in
            let exercise = exercises.first { $0.name == lift.exerciseName }
            let expected = ProgramEngine.programPlan(
                for: CycleState(cycleNumber: program.cycleNumber,
                                baseWeightLb: lift.baseWeightLb,
                                nextPhase: phase, incrementLb: 0),
                programRoundingLb: program.roundingLb,
                exerciseType: exercise?.typeRaw,
                movementGroup: exercise?.movementGroup,
                role: lift.role,
                focus: program.focus,
                prescriptionStyle: lift.prescription,
                configuration: lift.prescriptionConfiguration(
                    movementGroup: exercise?.movementGroup ?? ""
                )
            ).weightLb
            if session.exercises.contains(where: {
                $0.programSlotID == lift.id && $0.programRole != lift.role.rawValue
            }) { return false }
            guard let entry = programmedEntry(for: lift, in: session)
            else { return true } // a session-local removal stays removed on resume
            guard let target = entry.targetWeightLb ?? entry.plannedWeightLb else { return false }
            return abs(target - expected) < 0.01
        }
    }

    /// Slot IDs are authoritative while they remain stable. Historical repair
    /// can legitimately replace an invalid/colliding ID, so a single
    /// day-scoped role+exercise match is the safe lineage fallback. Multiple
    /// matches are ambiguous and must never be guessed.
    private static func programmedEntry(
        for lift: ProgramLift,
        in session: WorkoutSession
    ) -> SessionExercise? {
        if let exact = session.exercises.first(where: {
            $0.programSlotID == lift.id && $0.programRole == lift.role.rawValue
        }) {
            return exact
        }
        let lineage = session.exercises.filter {
            $0.programRole == lift.role.rawValue && $0.exercise?.name == lift.exerciseName
        }
        return lineage.count == 1 ? lineage[0] : nil
    }

    private static func temporaryAccessoryPercent(
        program: Program, context: ModelContext
    ) throws -> Int {
        let decisions = try context.fetch(FetchDescriptor<CoachingDecision>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
        let value = decisions.first { decision in
            guard decision.programID == program.id, decision.action == .accepted,
                  let override = decision.temporaryAccessoryOverride else { return false }
            return override.cycleNumber == program.cycleNumber
                && override.rotation == program.currentWeek
        }?.temporaryAccessoryOverride?.percent
        return value ?? 100
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
                                 gym: Gym?, bar: Bar, stepLb: Double,
                                 phase: CyclePhase? = nil) -> Double {
        guard exercise?.type == .barbell, weightLb > 0 else { return weightLb }
        let rounded = neatWeight(weightLb, isBarbell: true, isMain: isMain,
                                 barLb: bar.lb, stepLb: stepLb)
        let options = PlateMath.prescriptionOptions(
            targetLb: rounded, bar: bar,
            plates: gym?.availablePlates ?? Plate.allStandard,
            collarLb: gym?.collarWeightLb ?? 0,
            policy: gym?.loadingPolicy ?? .closest,
            preferOverOnTie: phase == .volume
        )
        return options.selected.loadout.totalLb
    }

    /// Resolve every theoretical warmup against the same rack, collars, and
    /// directional policy as the working prescription. Sparse inventories can
    /// collapse several targets to one load; never store duplicates or an
    /// extra warmup equal to the working weight.
    static func achievableWarmups(_ ramp: [WarmupSet], workingLb: Double,
                                  gym: Gym?, bar: Bar) -> [WarmupSet] {
        var seen: Set<Double> = []
        return ramp.compactMap { warmup in
            let solution = PlateMath.solve(
                targetLb: warmup.weightLb, bar: bar,
                plates: gym?.availablePlates ?? Plate.allStandard,
                collarLb: gym?.collarWeightLb ?? 0,
                policy: gym?.loadingPolicy ?? .closest
            )
            let achieved = solution.loadout.totalLb
            guard achieved < workingLb - 1e-9, seen.insert(achieved).inserted else { return nil }
            return WarmupSet(weightLb: achieved, reps: warmup.reps)
        }
    }

    /// Back squats and deadlifts start their generated ramp at the first loaded
    /// step. The empty bar remains available for other barbell movements and
    /// every generated set remains editable.
    static func includesEmptyBarWarmup(for exercise: Exercise) -> Bool {
        let key = exercise.name.lowercased().filter { $0.isLetter || $0.isNumber }
        return key != "backsquat" && key != "deadlift"
    }

    static func fallbackWeight(from currentLb: Double, exercise: Exercise?, gym: Gym?, bar: Bar,
                               roundingLb: Double, dropIncrementLb: Double) -> Double {
        let target = ProgramEngine.droppedLoad(
            from: currentLb, roundingLb: roundingLb, barLb: exercise?.type == .barbell ? bar.lb : 0,
            dropIncrementLb: dropIncrementLb
        )
        guard exercise?.type == .barbell else { return target }
        return PlateMath.solve(
            targetLb: target, bar: bar,
            plates: gym?.availablePlates ?? Plate.allStandard,
            collarLb: gym?.collarWeightLb ?? 0,
            policy: .under
        ).loadout.totalLb
    }

    private static func insertSet(_ entry: SessionExercise, order: Int, weight: Double, reps: Int, warmup: Bool,
                                  perSide: Bool, enteredUnit: WeightUnit, durationSeconds: Int? = nil,
                                  targetWeight: Double? = nil, plannedWeight: Double? = nil,
                                  plannedReps: Int? = nil, plannedDurationSeconds: Int? = nil,
                                  block: PrescriptionBlockKind = .work,
                                  context: ModelContext) {
        let set = SetEntry(order: order, weightLb: weight, reps: reps, isWarmup: warmup, isPerSide: perSide,
                           enteredUnit: enteredUnit, durationSeconds: durationSeconds,
                           loadBasis: entry.exercise?.loadBasis,
                           implementCount: entry.exercise?.resolvedImplementCount ?? 1,
                           targetWeightLb: targetWeight, plannedWeightLb: plannedWeight,
                           plannedReps: plannedReps, plannedDurationSeconds: plannedDurationSeconds,
                           prescriptionBlock: block)
        context.insert(set)
        entry.sets.append(set)
    }

    private static func findExercise(named name: String, context: ModelContext) throws -> Exercise {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
        guard let exercise = try context.fetch(descriptor).first else { throw BuildError.missingExercise(name) }
        return exercise
    }
}
