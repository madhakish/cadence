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
        // The performed log backs the honest-base repair (planningBase): a
        // stale stored base must not keep prescribing the plates the lifter
        // already lifted.
        let completedSessions = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.isCompleted }
        ))

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
        // The gym (and its bar) resolve before the resume check: the honest
        // base labels performed stacks against the bar the session loads.
        let gyms = try context.fetch(FetchDescriptor<Gym>())
        let defaultGym = gyms.first(where: { $0.isDefault }) ?? gyms.first
        let selectedBar = defaultGym?.defaultBar ?? .bar45lb
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
            sessionTargetsMatch(s, program: program, day: day, exercises: allExercises,
                                completedSessions: completedSessions)
        }) { return existing }

        let entryUnit = try context.fetch(FetchDescriptor<AppSettings>()).first?.unitDisplay.primaryUnit ?? .lb
        let session = WorkoutSession(gymID: defaultGym?.id, gymName: defaultGym?.name)
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

        for (liftIndex, lift) in day.orderedLifts.enumerated() {
            let exercise = try findExercise(named: lift.exerciseName, context: context)
            let loadStep = ProgramEngine.loadStep(programRoundingLb: program.roundingLb,
                                                  exerciseType: exercise.typeRaw)
            let configuration = lift.prescriptionConfiguration(movementGroup: exercise.movementGroup)
            let prescription = ProgramEngine.sessionPrescription(
                for: CycleState(cycleNumber: program.cycleNumber,
                                baseWeightLb: planningBase(for: lift, exercise: exercise,
                                                           program: program,
                                                           sessions: completedSessions),
                                nextPhase: phase, incrementLb: 0),
                programRoundingLb: program.roundingLb,
                exerciseType: exercise.typeRaw,
                movementGroup: exercise.movementGroup,
                role: lift.role,
                focus: program.focus,
                prescriptionStyle: lift.prescription,
                configuration: configuration,
                estimatedMaxLb: lift.estimatedMaxLb,
                // A held cycle moves the needle with volume: the stall the
                // grade recorded adds one set to this volume rotation, with
                // the rotation-wide budget allocated across stalled slots.
                // Pure state, so the Home card computes the identical count.
                addedVolumeSets: volumeFallbackSets(for: lift, program: program)
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
            // A complementary lift that FOLLOWS other work finds the lifter
            // already warm, so two bridging sets are enough. A complementary
            // slot ordered first in the day still ramps fully — nothing has
            // warmed the lifter yet. An explicit per-slot policy always wins.
            let resolvedWarmup: WarmupPolicy = {
                guard lift.warmupPolicy == .automatic else { return lift.warmupPolicy }
                if lift.role == .complementary && liftIndex > 0 { return .short }
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
                                                     gym: defaultGym, bar: selectedBar, exercise: exercise)
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
            // [INV-RUCK-CARRIES-ITS-LOAD] A programmed ruck or sled is built
            // wearing its load. The slot's own weight wins when the program
            // carries one; otherwise the movement's default pack.
            let carryLb: Double = exercise.type == .conditioning
                && CardioFormat.carriesLoad(exerciseName: exercise.name)
                ? (weightLb > 0 ? weightLb : (CardioFormat.defaultLoadLb(exerciseName: exercise.name) ?? 0))
                : 0
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = "accessory"
            entry.programSlotID = acc.id
            entry.plannedWeightLb = weightLb
            entry.targetWeightLb = acc.weightLb
            let ordinarySets = acc.capacityManaged
                ? max(1, Int((Double(acc.sets) * Double(accessoryPercent) / 100).rounded()))
                : acc.sets
            // Recovery keeps the authored movements familiar without carrying
            // a normal accessory session into the bridge. One easy set per
            // slot is enough exposure; completion deliberately cannot advance
            // its rep/load target (see SessionCompletion).
            let effectiveSets = phase == .deload ? 1 : ordinarySets
            entry.plannedSets = effectiveSets
            entry.plannedReps = isTimed ? 1 : acc.currentReps
            entry.plannedDurationSeconds = isTimed ? acc.targetSeconds : nil
            context.insert(entry)
            session.exercises.append(entry)
            for i in 0..<effectiveSets {
                insertSet(entry, order: i, weight: isTimed ? carryLb : weightLb, reps: isTimed ? 1 : acc.currentReps,
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
        exercises: [Exercise],
        completedSessions: [WorkoutSession]
    ) -> Bool {
        guard let phase = CyclePhase(rawValue: program.currentWeek) else { return false }
        return day.orderedLifts.allSatisfy { lift in
            let exercise = exercises.first { $0.name == lift.exerciseName }
            // The same honest base the builder plans from — an open session
            // built from the stale label must not resume once the repair
            // raises the plan.
            let expected = ProgramEngine.programPlan(
                for: CycleState(cycleNumber: program.cycleNumber,
                                baseWeightLb: planningBase(for: lift, exercise: exercise,
                                                           program: program,
                                                           sessions: completedSessions),
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

    /// The most recent completed base-training exposure for this slot: the
    /// volume rotation for wave slots (other rotations prescribe multiples
    /// of the base, so their weights are not comparable), any exposure for
    /// per-exposure styles (their plan is the base every session). For wave
    /// slots the caller scopes the CYCLE: planning reads evidence from
    /// before the cycle being planned (`beforeCycle`) so a cycle's own
    /// possibly-repaired exposure can never feed the repair that produced
    /// it, while the graded advance reads exactly the graded cycle's own
    /// volume work (`inCycle`). Entry matching reuses `programmedEntry`
    /// (slot ID + role, lineage fallback) plus a same-movement check, so a
    /// coaching rotation's renamed slot never inherits the old exercise's
    /// evidence; set selection reuses `SessionCompletion.prescribedWork`
    /// (planned-set window, completed, non-warmup), so user-added bonus rows
    /// stay history-only on both clients. Returns the heaviest qualifying
    /// working weight and the BAR IT WAS LIFTED UNDER — the label the twin
    /// math must use, not whatever bar today's gym defaults to. Nil means no
    /// evidence. Mirrors web `lastVolumeEvidence`.
    static func lastVolumeEvidence(
        for lift: ProgramLift, program: Program, sessions: [WorkoutSession],
        beforeCycle: Int? = nil, inCycle: Int? = nil
    ) -> (performedLb: Double, barLabelLb: Double)? {
        // The name is a fallback for ID-less legacy sessions only — two
        // programs can share a display name, and a non-nil foreign ID must
        // never feed this program's evidence (mirrors the resume filter).
        let mine = sessions
            .filter { $0.isCompleted && ($0.programID == program.id
                || ($0.programID == nil && $0.programName == program.name)) }
            .sorted { ($0.completedAt ?? $0.date) > ($1.completedAt ?? $1.date) }
        for session in mine {
            if !lift.prescription.advancesPerExposure {
                guard session.programWeek == 1 else { continue }
                if let beforeCycle, (session.programCycleNumber ?? 0) >= beforeCycle { continue }
                if let inCycle, session.programCycleNumber != inCycle { continue }
            }
            guard let entry = programmedEntry(for: lift, in: session),
                  entry.exercise?.name == lift.exerciseName else { continue }
            let top = SessionCompletion.prescribedWork(entry).map(\.weightLb).max() ?? 0
            guard top > 0 else { continue }
            return (top, (entry.barID.map { Bar.by(id: $0) } ?? .bar45lb).labelLb)
        }
        return nil
    }

    /// The base every planning surface builds `CycleState` from: the stored
    /// base, repaired by `honestBase` when the log proves the last earned
    /// advance moved the label but not the plates (a kg rack solves 215 and
    /// 225 to the identical 2×20 kg stack). Total-bar work only — the repair
    /// reasons about the number as a bar-and-plates stack, which is exactly
    /// the reading machines and dumbbells must never get. Shared by the
    /// session builder, the resume comparison, and every preview surface so
    /// the card, the preview, and the stored prescription agree by
    /// construction. Mirrors web `planningBase`.
    static func planningBase(
        for lift: ProgramLift, exercise: Exercise?, program: Program,
        sessions: [WorkoutSession]
    ) -> Double {
        guard exercise?.loadBasis == .totalBar,
              let evidence = lastVolumeEvidence(
                  for: lift, program: program, sessions: sessions,
                  beforeCycle: lift.prescription.advancesPerExposure ? nil : program.cycleNumber
              ) else { return lift.baseWeightLb }
        return ProgramProgression.honestBase(
            baseWeightLb: lift.baseWeightLb,
            lastIncrementLb: lift.lastIncrementLb,
            lastVolumePerformedLb: evidence.performedLb,
            roundingLb: program.roundingLb,
            barLb: evidence.barLabelLb
        )
    }

    /// The volume-fallback sets this lift carries, with the rotation-wide
    /// added-set budget allocated deterministically: stalled peak-graded
    /// slots in program order (day order, then slot order) receive one set
    /// each until `maximumAddedSetsPerRotation` is spent. Slots whose
    /// resolved style ignores the fallback still hold a rank — that spends
    /// budget conservatively rather than ever exceeding it. Shared by the
    /// session builder and every preview surface so the card and the stored
    /// prescription agree. Mirrors web `volumeFallbackSets`.
    static func volumeFallbackSets(for lift: ProgramLift, program: Program) -> Int {
        let stalled = program.orderedDays.flatMap { day in
            day.orderedLifts.filter { $0.stallCount > 0 && !$0.prescription.advancesPerExposure }
        }
        guard let rank = stalled.firstIndex(where: { $0.id == lift.id }) else { return 0 }
        return ProgramProgression.volumeIncrementSets(
            stallCount: lift.stallCount, stalledRank: rank,
            maximumAddedSetsPerRotation: program.maximumAddedSetsPerRotation
        )
    }

    /// Secondary/accessory barbell prescriptions snap to a neat bar-loadable
    /// weight; mains and non-barbell work are left as-is. Shared with HomeView's
    /// preview so the card and the started session agree. Mirrors web `neatProgramWeight`.
    static func neatWeight(_ weightLb: Double, isBarbell: Bool, isMain: Bool, barLb: Double, stepLb: Double) -> Double {
        (!isMain && isBarbell) ? Weight.barLoadable(weightLb, barLb: barLb, stepLb: stepLb) : weightLb
    }

    /// Resolve the prescription to equipment that exists at this gym. When
    /// the rack lands within the good-enough band the neat programmed number
    /// is what gets stored and the plate hint explains the actual stack; only
    /// a genuinely unreachable target stores the achieved total, so sparse
    /// racks keep the logged set, history, and progression honest.
    static func achievableWeight(_ weightLb: Double, exercise: Exercise?, isMain: Bool,
                                 gym: Gym?, bar: Bar, stepLb: Double,
                                 phase: CyclePhase? = nil) -> Double {
        guard exercise?.type == .barbell, weightLb > 0 else { return weightLb }
        let rounded = neatWeight(weightLb, isBarbell: true, isMain: isMain,
                                 barLb: bar.lb, stepLb: stepLb)
        let options = PlateMath.prescriptionOptions(
            targetLb: rounded, bar: bar,
            plates: PlateMath.stationPlates(
                preference: exercise?.stationDenomination,
                gymPlates: gym?.availablePlates ?? Plate.allStandard
            ),
            collarLb: gym?.collarWeightLb ?? 0,
            policy: gym?.loadingPolicy ?? .closest,
            preferOverOnTie: phase == .volume
        )
        // A near-miss clean stack (e.g. kg plates on a lb prescription) stays
        // loading guidance — the neat programmed number is what gets stored.
        return PlateMath.storedPrescription(
            targetLb: rounded, achievedLb: options.selected.loadout.totalLb,
            barLb: bar.labelLb
        )
    }

    /// Resolve every theoretical warmup against the same rack, collars, and
    /// directional policy as the working prescription. Sparse inventories can
    /// collapse several targets to one load; never store duplicates or an
    /// extra warmup equal to the working weight.
    static func achievableWarmups(_ ramp: [WarmupSet], workingLb: Double,
                                  gym: Gym?, bar: Bar, exercise: Exercise? = nil) -> [WarmupSet] {
        var seen: Set<Double> = []
        return ramp.compactMap { warmup in
            let solution = PlateMath.solve(
                targetLb: warmup.weightLb, bar: bar,
                plates: PlateMath.stationPlates(
                    preference: exercise?.stationDenomination,
                    gymPlates: gym?.availablePlates ?? Plate.allStandard
                ),
                collarLb: gym?.collarWeightLb ?? 0,
                policy: gym?.loadingPolicy ?? .closest
            )
            let stored = PlateMath.storedPrescription(
                targetLb: warmup.weightLb, achievedLb: solution.loadout.totalLb,
                barLb: bar.labelLb
            )
            guard stored < workingLb - 1e-9, seen.insert(stored).inserted else { return nil }
            return WarmupSet(weightLb: stored, reps: warmup.reps)
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
        let achieved = PlateMath.solve(
            targetLb: target, bar: bar,
            plates: PlateMath.stationPlates(
                preference: exercise?.stationDenomination,
                gymPlates: gym?.availablePlates ?? Plate.allStandard
            ),
            collarLb: gym?.collarWeightLb ?? 0,
            policy: .under
        ).loadout.totalLb
        return PlateMath.storedPrescription(targetLb: target, achievedLb: achieved, barLb: bar.labelLb)
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
