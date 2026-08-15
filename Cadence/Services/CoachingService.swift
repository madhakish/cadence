import Foundation
import SwiftData
import CadenceCore

/// Persistence adapter and explicit mutation boundary for the deterministic
/// coaching engine. Evaluation is read-only; a program changes only after the
/// athlete/coach accepts a concrete recommendation, and every choice is kept
/// in the audit trail.
enum CoachingService {
    static func report(
        program: Program,
        sessions: [WorkoutSession],
        exercises: [Exercise],
        checkIns: [CheckIn] = []
    ) -> CoachingReport {
        let exerciseByName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        let phase = CyclePhase(rawValue: program.currentWeek) ?? .volume
        let slots = program.days.flatMap { day -> [CoachingProgramSlot] in
            let liftSlots = day.lifts.map { lift in
                let exercise = exerciseByName[lift.exerciseName]
                let configuration = lift.prescriptionConfiguration(
                    movementGroup: exercise?.movementGroup ?? ""
                )
                let plan = ProgramEngine.programPlan(
                    for: CycleState(
                        cycleNumber: program.cycleNumber,
                        baseWeightLb: lift.baseWeightLb,
                        nextPhase: phase,
                        incrementLb: 0
                    ),
                    programRoundingLb: program.roundingLb,
                    exerciseType: exercise?.typeRaw,
                    movementGroup: exercise?.movementGroup,
                    role: lift.role,
                    focus: program.focus,
                    prescriptionStyle: lift.prescription,
                    configuration: configuration
                )
                return CoachingProgramSlot(
                    id: lift.id,
                    exerciseName: lift.exerciseName,
                    dayIndex: day.order,
                    pattern: exercise?.movementPattern ?? .unknown,
                    plannedSets: plan.sets,
                    role: lift.role.rawValue,
                    isMain: lift.role == .main,
                    capacityManaged: lift.capacityManaged,
                    maximumSets: lift.maximumSets,
                    prescriptionStyle: ProgramEngine.resolvedStyle(
                        lift.prescription,
                        movementGroup: exercise?.movementGroup,
                        role: lift.role,
                        focus: program.focus
                    ),
                    baseWeightLb: lift.baseWeightLb,
                    workingSets: lift.doubleProgressionSets,
                    workingReps: lift.currentReps <= 3 ? 3 : 5,
                    // A graded peak waits in `pending` until the deload ends.
                    // Reading only the settled count would hide a stall for a
                    // whole cycle — exactly the cycle worth rotating out of.
                    stallCount: lift.pendingStallCount ?? lift.stallCount,
                    exerciseIsShelved: exercise?.gateStatus == .shelved
                )
            }
            let accessorySlots = day.accessories.map { accessory in
                CoachingProgramSlot(
                    id: accessory.id,
                    exerciseName: accessory.exerciseName,
                    dayIndex: day.order,
                    pattern: exerciseByName[accessory.exerciseName]?.movementPattern ?? .unknown,
                    plannedSets: accessory.sets,
                    role: "accessory",
                    capacityManaged: accessory.capacityManaged,
                    maximumSets: accessory.maximumSets,
                    stallCount: accessory.stallCount,
                    exerciseIsShelved: exerciseByName[accessory.exerciseName]?.gateStatus == .shelved
                )
            }
            return liftSlots + accessorySlots
        }
        let snapshot = CoachingProgramSnapshot(
            id: program.id,
            expectedDayIndexes: Set(program.days.map(\.order)),
            slots: slots,
            maximumAddedSetsPerRotation: program.maximumAddedSetsPerRotation
        )
        let history = sessions.compactMap { session -> CoachingSessionSnapshot? in
            guard session.isCompleted,
                  session.programID == program.id || session.programName == program.name,
                  let cycle = session.programCycleNumber,
                  let rotation = session.programWeek,
                  let dayIndex = session.programDayIndex else { return nil }
            let entries = session.orderedExercises.compactMap { entry -> CoachingExerciseSnapshot? in
                guard let exercise = entry.exercise else { return nil }
                let sets = entry.orderedSets.map { set in
                    CoachingSetSnapshot(
                        actualWeightLb: set.weightLb,
                        actualReps: set.reps,
                        plannedWeightLb: set.plannedWeightLb ?? entry.plannedWeightLb,
                        plannedReps: set.plannedReps ?? entry.plannedReps,
                        isWarmup: set.isWarmup,
                        prescriptionBlock: set.prescriptionBlock,
                        completed: set.status == .completed,
                        stoppedEarly: set.flags.contains(.stoppedEarly),
                        hasBodyFlag: set.bodyFlagSite != nil,
                        quality: coachingQuality(set.quality),
                        durationSeconds: set.durationSeconds
                    )
                }
                return CoachingExerciseSnapshot(
                    slotID: entry.programSlotID,
                    programRole: entry.programRole,
                    exerciseName: exercise.name,
                    pattern: exercise.movementPattern,
                    plannedSets: entry.plannedSets ?? entry.plannedWorkingSets.count,
                    plannedWeightLb: entry.plannedWeightLb,
                    plannedReps: entry.plannedReps,
                    prescriptionStyle: PrescriptionStyle(rawValue: entry.prescriptionStyleRaw),
                    roundingLb: ProgramEngine.loadStep(
                        programRoundingLb: program.roundingLb,
                        exerciseType: exercise.typeRaw
                    ),
                    sets: sets
                )
            }
            return CoachingSessionSnapshot(
                id: session.id,
                date: session.completedAt ?? session.date,
                programID: program.id,
                cycleNumber: cycle,
                rotation: rotation,
                dayIndex: dayIndex,
                hasHardStopCheckIn: checkIns.contains { checkIn in
                    let start = session.completedAt ?? session.date
                    let seconds = checkIn.date.timeIntervalSince(start)
                    return checkIn.isHardStop && seconds >= 0 && seconds <= 36 * 60 * 60
                },
                exercises: entries
            )
        }
        return CoachingEngine.evaluate(
            program: snapshot,
            sessions: history,
            reliableHistoryStart: program.reliableHistoryStart
        )
    }

    @discardableResult
    static func accept(
        _ recommendation: CoachingRecommendation,
        for program: Program,
        exercises: [Exercise],
        evidence: [String],
        context: ModelContext
    ) throws -> String {
        let before = programDescription(program)
        var decisionAfterValue: String?
        var result = "Recommendation recorded."
        switch recommendation.change {
        case .addSet(let slotID, let count):
            if let accessory = program.days.flatMap(\.accessories).first(where: { $0.id == slotID }) {
                let old = accessory.sets
                accessory.sets = min(accessory.maximumSets, accessory.sets + count)
                result = "\(accessory.exerciseName): \(old) → \(accessory.sets) sets per rotation."
            } else if let lift = program.days.flatMap(\.lifts).first(where: { $0.id == slotID }),
                      lift.prescription == .doubleProgression {
                let old = lift.doubleProgressionSets
                lift.doubleProgressionSets = min(lift.maximumSets, lift.doubleProgressionSets + count)
                result = "\(lift.exerciseName): \(old) → \(lift.doubleProgressionSets) sets per rotation."
            }
        case .removeSet(let slotID, let count):
            if let accessory = program.days.flatMap(\.accessories).first(where: { $0.id == slotID }) {
                let old = accessory.sets
                accessory.sets = max(1, accessory.sets - count)
                result = "\(accessory.exerciseName): \(old) → \(accessory.sets) sets per rotation."
            }
        case .addPattern(let pattern, let dayIndex, let sets):
            guard let day = program.days.first(where: { $0.order == dayIndex }) ?? program.orderedDays.first,
                  let exercise = preferredExercise(for: pattern, in: exercises) else {
                throw CoachingApplyError.noExercise(pattern.name)
            }
            let accessory = ProgramAccessory(
                exerciseName: exercise.name,
                order: day.accessories.count,
                sets: sets,
                minReps: defaultRepRange(pattern).0,
                maxReps: defaultRepRange(pattern).1,
                currentReps: defaultRepRange(pattern).0,
                targetSeconds: exercise.type == .timed ? 30 : 0,
                weightLb: 0,
                incrementLb: 0
            )
            context.insert(accessory)
            day.accessories.append(accessory)
            result = "Added \(sets) sets of \(exercise.name) to \(day.name)."
        case .capacityPlan(let adjustments):
            // Resolve every library/day dependency before mutating so a
            // missing custom classification cannot partially apply the plan.
            var resolvedPatterns: [(MovementPattern, Int, Int, ProgramDay, Exercise)] = []
            for adjustment in adjustments {
                guard case .addPattern(let pattern, let dayIndex, let sets) = adjustment else { continue }
                guard let day = program.days.first(where: { $0.order == dayIndex }) ?? program.orderedDays.first,
                      let exercise = preferredExercise(for: pattern, in: exercises) else {
                    throw CoachingApplyError.noExercise(pattern.name)
                }
                resolvedPatterns.append((pattern, dayIndex, sets, day, exercise))
            }
            var messages: [String] = []
            for adjustment in adjustments {
                switch adjustment {
                case .addSet(let slotID, let exerciseName, let count):
                    if let accessory = program.days.flatMap(\.accessories).first(where: { $0.id == slotID }) {
                        let old = accessory.sets
                        accessory.sets = min(accessory.maximumSets, accessory.sets + count)
                        messages.append("\(exerciseName) \(old)→\(accessory.sets)")
                    } else if let lift = program.days.flatMap(\.lifts).first(where: { $0.id == slotID }),
                              lift.prescription == .doubleProgression {
                        let old = lift.doubleProgressionSets
                        lift.doubleProgressionSets = min(lift.maximumSets, old + count)
                        messages.append("\(exerciseName) \(old)→\(lift.doubleProgressionSets)")
                    }
                case .addPattern(let pattern, let dayIndex, let sets):
                    guard let resolved = resolvedPatterns.first(where: {
                        $0.0 == pattern && $0.1 == dayIndex && $0.2 == sets
                    }) else { continue }
                    let accessory = ProgramAccessory(
                        exerciseName: resolved.4.name,
                        order: resolved.3.accessories.count,
                        sets: sets,
                        minReps: defaultRepRange(pattern).0,
                        maxReps: defaultRepRange(pattern).1,
                        currentReps: defaultRepRange(pattern).0,
                        targetSeconds: resolved.4.type == .timed ? 30 : 0,
                        weightLb: 0,
                        incrementLb: 0
                    )
                    context.insert(accessory)
                    resolved.3.accessories.append(accessory)
                    messages.append("\(resolved.4.name) +\(sets)")
                }
            }
            result = messages.isEmpty
                ? "Capacity plan was already satisfied."
                : "Applied for this rotation: " + messages.joined(separator: ", ") + "."
        case .reduceAccessoryVolume(let percent):
            let retainedPercent = max(1, 100 - percent)
            decisionAfterValue = CoachingDecision.temporaryAccessoryValue(
                percent: retainedPercent,
                cycleNumber: program.cycleNumber,
                rotation: program.currentWeek
            )
            result = "Scheduled a \(percent)% accessory-set cut for the next rotation only."
        case .tryShorterSpacing(let days):
            let old = program.preferredSessionSpacingDays
            program.preferredSessionSpacingDays = max(2, days)
            result = "Preferred spacing: \(old) → \(program.preferredSessionSpacingDays) days."
        case .useLinearTriples(let slotID, let exerciseName, let expectedBaseWeightLb):
            guard let lift = program.days.flatMap(\.lifts).first(where: { $0.id == slotID }) else {
                throw CoachingApplyError.unknownSlot(exerciseName)
            }
            guard lift.exerciseName == exerciseName,
                  lift.prescription == .linearFives,
                  lift.capacityManaged,
                  lift.maximumSets >= 5,
                  lift.doubleProgressionSets == 3,
                  lift.currentReps == 5,
                  abs(lift.baseWeightLb - expectedBaseWeightLb) < 0.01 else {
                throw CoachingApplyError.prescriptionChanged(exerciseName)
            }
            lift.doubleProgressionSets = 5
            lift.currentReps = 3
            lift.stallCount = 0
            lift.pendingBaseWeightLb = nil
            lift.pendingEstimatedMaxLb = nil
            lift.pendingStallCount = nil
            lift.pendingLastIncrementLb = nil
            lift.pendingNote = nil
            decisionAfterValue = "linearTriples:slot:\(slotID):5x3"
            result = "\(exerciseName): 3×5 → 5×3; session-to-session loading stays in place."
        case .promoteVerticalPull(let dayIndex, let accessorySlotIDs, let accessoryNames):
            guard let day = program.days.first(where: { $0.order == dayIndex }) else {
                throw CoachingApplyError.unknownSlot(accessoryNames.first ?? "vertical pull")
            }
            // The replacement is the template's own choice — pull-ups on a
            // double-progression window that grows into weighted pull-ups —
            // not a SwapRules candidate: crossing the tier is the point.
            guard let pullUps = exercises.first(where: {
                $0.name == "Pull-ups" && $0.gateStatus != .shelved
            }) else {
                throw CoachingApplyError.unknownExercise("Pull-ups")
            }
            let retiring = day.accessories.filter { accessorySlotIDs.contains($0.id) }
            guard !retiring.isEmpty else {
                throw CoachingApplyError.unknownSlot(accessoryNames.first ?? "vertical pull")
            }
            let retiredNames = retiring.map(\.exerciseName)
            for accessory in retiring {
                day.accessories.removeAll { $0 === accessory }
                context.delete(accessory)
            }
            for (index, accessory) in day.orderedAccessories.enumerated() { accessory.order = index }
            // Idempotent against a stale offer: if the day gained a pull-up
            // lift since evaluation (hand-edit, another apply), retiring the
            // accessories is still right but a second identical slot is not.
            if day.lifts.contains(where: { $0.exerciseName == pullUps.name }) {
                result = "Retired \(retiredNames.joined(separator: ", ")) — \(day.name) already trains \(pullUps.name) at the lift tier."
            } else {
                // The same slot shape the template authors: complementary
                // double progression, three sets, born at bodyweight (base 0)
                // — the rep window's model defaults match template
                // instantiation.
                // max(order)+1, not count: authored orders can be
                // noncontiguous (imports, edits), and the promoted slot must
                // append after the day's last lift, not land between them.
                let pullSlot = ProgramLift(exerciseName: pullUps.name, role: .complementary,
                                           order: (day.lifts.map(\.order).max() ?? -1) + 1,
                                           prescription: .doubleProgression,
                                           baseWeightLb: 0, estimatedMaxLb: 0)
                context.insert(pullSlot)
                day.lifts.append(pullSlot)
                result = "\(retiredNames.joined(separator: ", ")) → \(pullUps.name) as programmed lift work on \(day.name)."
            }
        case .rotateExercise(let slotID, let exerciseName):
            guard let current = exercises.first(where: { $0.name == exerciseName }) else {
                throw CoachingApplyError.unknownExercise(exerciseName)
            }
            guard let replacement = exercises.first(where: {
                SwapRules.compatible(
                    currentName: current.name, currentCategory: current.categoryRaw,
                    currentLoadBasis: current.loadBasis, currentGroup: current.movementGroup,
                    candidateName: $0.name, candidateCategory: $0.categoryRaw,
                    candidateLoadBasis: $0.loadBasis, candidateGroup: $0.movementGroup,
                    candidateShelved: $0.isShelved || $0.gateStatus == .shelved
                )
            }) else {
                throw CoachingApplyError.noVariation(exerciseName)
            }
            // Same policy as the manual swap gesture: the slot keeps its load
            // and estimate, because a compatible candidate trains the same
            // pattern at the same tier and those remain the best prior. The
            // stall counter does NOT carry — rotating is the answer to the
            // stall, so inheriting its countdown would deload a lift that has
            // not yet missed anything.
            if let lift = program.days.flatMap(\.lifts).first(where: { $0.id == slotID }) {
                lift.exerciseName = replacement.name
                lift.revertToExerciseName = nil
                lift.stallCount = 0
                // The earned increment belonged to the OLD movement; carrying
                // it would arm the honest-base repair against evidence the
                // new lift never produced (the evidence lookup also checks
                // the movement name — this keeps the stored state truthful).
                lift.lastIncrementLb = 0
                if lift.pendingStallCount != nil { lift.pendingStallCount = 0 }
            } else if let accessory = program.days.flatMap(\.accessories).first(where: { $0.id == slotID }) {
                accessory.exerciseName = replacement.name
                accessory.revertToExerciseName = nil
                accessory.stallCount = 0
            } else {
                throw CoachingApplyError.unknownSlot(exerciseName)
            }
            result = "\(exerciseName) → \(replacement.name) for this slot."
        case .hold:
            result = "Program held unchanged."
        }
        context.insert(CoachingDecision(
            programID: program.id,
            ruleID: recommendation.ruleID,
            recommendationID: recommendation.id,
            action: .accepted,
            title: recommendation.title,
            explanation: recommendation.explanation,
            evidence: evidence,
            beforeValue: before,
            afterValue: decisionAfterValue ?? programDescription(program)
        ))
        try context.save()
        return result
    }

    static func record(
        _ action: CoachingDecisionAction,
        recommendation: CoachingRecommendation,
        program: Program,
        evidence: [String],
        context: ModelContext
    ) throws {
        context.insert(CoachingDecision(
            programID: program.id,
            ruleID: recommendation.ruleID,
            recommendationID: recommendation.id,
            action: action,
            title: recommendation.title,
            explanation: recommendation.explanation,
            evidence: evidence
        ))
        try context.save()
    }

    private static func coachingQuality(_ flag: SetFlag?) -> CoachingSetQuality {
        switch flag {
        case .clean: return .clean
        case .grindy: return .grindy
        case .wobble: return .wobble
        default: return .ungraded
        }
    }

    private static func preferredExercise(for pattern: MovementPattern, in exercises: [Exercise]) -> Exercise? {
        let preferred: [MovementPattern: [String]] = [
            .verticalPull: ["Lat Pulldown", "Assisted Pull-up", "Pull-ups", "Chin-ups",
                            "Weighted Pull-up", "Weighted Chin-up"],
            .kneeFlexion: ["Seated Leg Curl", "Lying Leg Curl", "Nordic Hamstring Curl"],
            .shoulderStability: ["Face Pulls", "Band External Rotation", "Y-T-W Raises"],
            .adductor: ["Copenhagen Plank", "Cable Hip Adduction"],
            .core: ["Hanging Knee Raise", "Dead Bug", "Plank"],
        ]
        let available = exercises.filter { !$0.isShelved && $0.gateStatus != .shelved }
        for name in preferred[pattern] ?? [] {
            if let exercise = available.first(where: { $0.name == name }) { return exercise }
        }
        return available.first { $0.movementPattern == pattern }
    }

    private static func defaultRepRange(_ pattern: MovementPattern) -> (Int, Int) {
        switch pattern {
        case .adductor, .core: return (8, 12)
        default: return (6, 10)
        }
    }

    private static func programDescription(_ program: Program) -> String {
        program.orderedDays.map { day in
            let slots = day.orderedLifts.map { "\($0.exerciseName):lift" }
                + day.orderedAccessories.map { "\($0.exerciseName):\($0.sets)" }
            return "\(day.name)[\(slots.joined(separator: ","))]"
        }.joined(separator: " | ")
    }

    enum CoachingApplyError: LocalizedError {
        case noExercise(String)
        case noVariation(String)
        case unknownExercise(String)
        case unknownSlot(String)
        case prescriptionChanged(String)
        var errorDescription: String? {
            switch self {
            case .noExercise(let pattern):
                return "No available exercise is classified as \(pattern). Add or reclassify one in the library first."
            case .noVariation(let name):
                return "No compatible variation of \(name) is available. Add one to the library, or unshelve an existing one."
            case .unknownExercise(let name):
                return "\(name) is no longer in the library, so a compatible variation cannot be chosen."
            case .unknownSlot(let name):
                return "The program slot for \(name) no longer exists."
            case .prescriptionChanged(let name):
                return "The program slot for \(name) changed after this recommendation, so triples were not applied."
            }
        }
    }
}
