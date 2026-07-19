import Foundation

/// A stable movement vocabulary used by program validation, rotation analytics,
/// and coaching rules. Broad `movementGroup` values remain useful for swaps;
/// these patterns describe the actual training dose more precisely.
public enum MovementPattern: String, Codable, CaseIterable, Sendable {
    case horizontalPress
    case verticalPress
    case horizontalPull
    case verticalPull
    case squat
    case hipHinge
    case kneeFlexion
    case hipExtension
    case unilateralKnee
    case olympicPower
    case shoulderStability
    case arms
    case core
    case adductor
    case calves
    case carry
    case easyAerobic
    case intervals
    case mixedConditioning
    case unknown

    public var name: String {
        switch self {
        case .horizontalPress: return "Horizontal press"
        case .verticalPress: return "Vertical press"
        case .horizontalPull: return "Horizontal pull"
        case .verticalPull: return "Vertical pull"
        case .squat: return "Squat"
        case .hipHinge: return "Hip hinge"
        case .kneeFlexion: return "Hamstring isolation"
        case .hipExtension: return "Hip extension"
        case .unilateralKnee: return "Unilateral lower"
        case .olympicPower: return "Olympic power"
        case .shoulderStability: return "Rear delt / cuff"
        case .arms: return "Arms"
        case .core: return "Core"
        case .adductor: return "Adductor / groin"
        case .calves: return "Calves"
        case .carry: return "Carry"
        case .easyAerobic: return "Easy aerobic"
        case .intervals: return "Intervals"
        case .mixedConditioning: return "Mixed conditioning"
        case .unknown: return "Unclassified"
        }
    }

    public var isConditioning: Bool {
        self == .easyAerobic || self == .intervals || self == .mixedConditioning
    }
}

/// Canonical classification for built-in exercises. Custom exercises may
/// persist an explicit pattern; otherwise this exact-name map falls back to
/// the broad movement group without pretending every pull or press is alike.
public enum MovementTaxonomy {
    private static let verticalPress: Set<String> = [
        "Overhead Press", "Push Press", "Push Jerk", "Split Jerk",
        "Overhead DB Press", "Seated Upright DB Press", "Arnold Press",
        "Landmine Press", "KB Press",
    ]
    private static let verticalPull: Set<String> = [
        "Lat Pulldown", "Straight-arm Pulldown", "Pull-ups", "Chin-ups",
        "Assisted Pull-up",
    ]
    private static let horizontalPull: Set<String> = [
        "Single-arm DB Row", "Chest-supported Row", "Ring Row", "Barbell Row",
        "Pendlay Row", "T-Bar Row", "Seated Cable Row", "One-arm Cable Row",
        "Bent-over DB Row", "Incline Bench DB Row", "KB Row", "Banded Row",
    ]
    private static let kneeFlexion: Set<String> = [
        "Seated Leg Curl", "Lying Leg Curl", "Nordic Hamstring Curl",
    ]
    private static let hipExtension: Set<String> = [
        "Back Extension", "Glute Bridge", "Barbell Hip Thrust", "Cable Pull-through",
    ]
    private static let unilateralKnee: Set<String> = [
        "Walking Lunges", "Bulgarian Split Squat", "Reverse Lunge",
        "Forward Lunge", "Step-up",
    ]
    private static let shoulderStability: Set<String> = [
        "Band Pull-aparts", "Face Pulls", "Y-T-W Raises", "Band External Rotation",
        "Rear Delt Fly", "Reverse Pec Deck",
    ]
    private static let easyAerobic: Set<String> = [
        "Walk", "Bike", "Ruck", "Elliptical", "Stair Climber", "Swimming",
        "Row Erg", "Ski Erg",
    ]
    private static let intervals: Set<String> = [
        "Run-Walk Intervals", "Jump Rope", "Sled Push", "Sled Pull",
        "Battle Ropes",
    ]

    public static func pattern(
        exerciseName: String,
        movementGroup: String,
        explicitPattern: String? = nil
    ) -> MovementPattern {
        if let explicitPattern, let value = MovementPattern(rawValue: explicitPattern), value != .unknown {
            return value
        }
        if verticalPress.contains(exerciseName) { return .verticalPress }
        if verticalPull.contains(exerciseName) { return .verticalPull }
        if horizontalPull.contains(exerciseName) { return .horizontalPull }
        if kneeFlexion.contains(exerciseName) { return .kneeFlexion }
        if hipExtension.contains(exerciseName) { return .hipExtension }
        if unilateralKnee.contains(exerciseName) { return .unilateralKnee }
        if shoulderStability.contains(exerciseName) { return .shoulderStability }
        if easyAerobic.contains(exerciseName) { return .easyAerobic }
        if intervals.contains(exerciseName) { return .intervals }
        if exerciseName.localizedCaseInsensitiveContains("Copenhagen") { return .adductor }

        switch movementGroup {
        case "press": return .horizontalPress
        case "pull": return .horizontalPull
        case "squat": return .squat
        case "hinge": return .hipHinge
        case "olympic": return .olympicPower
        case "shoulder": return .shoulderStability
        case "arms": return .arms
        case "core": return .core
        case "calves": return .calves
        case "carry": return .carry
        case "conditioning": return .mixedConditioning
        default: return .unknown
        }
    }
}

public enum ReadinessState: String, Codable, Sendable {
    case green, yellow, red, unknown

    public var name: String { rawValue.capitalized }
}

public enum CoachingSetQuality: String, Codable, Sendable {
    case clean, grindy, wobble, ungraded
}

/// Immutable performed/planned set snapshot. The core never reads persistence
/// models directly, and every comparison uses the final values banked by the
/// athlete rather than rebuilding history from the current program.
public struct CoachingSetSnapshot: Hashable, Sendable {
    public var actualWeightLb: Double
    public var actualReps: Int
    public var plannedWeightLb: Double?
    public var plannedReps: Int?
    public var isWarmup: Bool
    public var prescriptionBlock: PrescriptionBlockKind
    public var completed: Bool
    public var stoppedEarly: Bool
    public var hasBodyFlag: Bool
    public var quality: CoachingSetQuality
    public var durationSeconds: Int?

    public init(
        actualWeightLb: Double,
        actualReps: Int,
        plannedWeightLb: Double? = nil,
        plannedReps: Int? = nil,
        isWarmup: Bool = false,
        prescriptionBlock: PrescriptionBlockKind = .work,
        completed: Bool = true,
        stoppedEarly: Bool = false,
        hasBodyFlag: Bool = false,
        quality: CoachingSetQuality = .ungraded,
        durationSeconds: Int? = nil
    ) {
        self.actualWeightLb = actualWeightLb
        self.actualReps = actualReps
        self.plannedWeightLb = plannedWeightLb
        self.plannedReps = plannedReps
        self.isWarmup = isWarmup
        self.prescriptionBlock = prescriptionBlock
        self.completed = completed
        self.stoppedEarly = stoppedEarly
        self.hasBodyFlag = hasBodyFlag
        self.quality = quality
        self.durationSeconds = durationSeconds
    }
}

public struct CoachingExerciseSnapshot: Hashable, Sendable {
    public var slotID: String?
    public var programRole: String?
    public var exerciseName: String
    public var pattern: MovementPattern
    public var plannedSets: Int
    public var plannedWeightLb: Double?
    public var plannedReps: Int?
    public var roundingLb: Double
    public var sets: [CoachingSetSnapshot]

    public init(
        slotID: String? = nil,
        programRole: String? = nil,
        exerciseName: String,
        pattern: MovementPattern,
        plannedSets: Int,
        plannedWeightLb: Double? = nil,
        plannedReps: Int? = nil,
        roundingLb: Double = 5,
        sets: [CoachingSetSnapshot]
    ) {
        self.slotID = slotID
        self.programRole = programRole
        self.exerciseName = exerciseName
        self.pattern = pattern
        self.plannedSets = plannedSets
        self.plannedWeightLb = plannedWeightLb
        self.plannedReps = plannedReps
        self.roundingLb = roundingLb
        self.sets = sets
    }
}

public struct CoachingSessionSnapshot: Hashable, Sendable {
    public var id: String
    public var date: Date
    public var programID: String
    public var cycleNumber: Int
    public var rotation: Int
    public var dayIndex: Int
    public var completed: Bool
    /// A structured post-session check-in within the recovery window reported
    /// pain/swelling/off output. This is observable output, not a diagnosis.
    public var hasHardStopCheckIn: Bool
    public var exercises: [CoachingExerciseSnapshot]

    public init(
        id: String,
        date: Date,
        programID: String,
        cycleNumber: Int,
        rotation: Int,
        dayIndex: Int,
        completed: Bool = true,
        hasHardStopCheckIn: Bool = false,
        exercises: [CoachingExerciseSnapshot]
    ) {
        self.id = id
        self.date = date
        self.programID = programID
        self.cycleNumber = cycleNumber
        self.rotation = rotation
        self.dayIndex = dayIndex
        self.completed = completed
        self.hasHardStopCheckIn = hasHardStopCheckIn
        self.exercises = exercises
    }
}

public struct CoachingProgramSlot: Hashable, Sendable {
    public var id: String
    public var exerciseName: String
    public var dayIndex: Int
    public var pattern: MovementPattern
    public var plannedSets: Int
    public var role: String
    public var isMain: Bool
    public var capacityManaged: Bool
    public var maximumSets: Int

    public init(
        id: String,
        exerciseName: String,
        dayIndex: Int,
        pattern: MovementPattern,
        plannedSets: Int,
        role: String? = nil,
        isMain: Bool = false,
        capacityManaged: Bool = true,
        maximumSets: Int = 6
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.dayIndex = dayIndex
        self.pattern = pattern
        self.plannedSets = plannedSets
        self.role = role ?? (isMain ? LiftRole.main.rawValue : "accessory")
        self.isMain = isMain
        self.capacityManaged = capacityManaged
        self.maximumSets = maximumSets
    }
}

public struct CoachingProgramSnapshot: Hashable, Sendable {
    public var id: String
    public var expectedDayIndexes: Set<Int>
    public var slots: [CoachingProgramSlot]
    public var maximumAddedSetsPerRotation: Int

    public init(id: String, expectedDayIndexes: Set<Int>, slots: [CoachingProgramSlot],
                maximumAddedSetsPerRotation: Int = 6) {
        self.id = id
        self.expectedDayIndexes = expectedDayIndexes
        self.slots = slots
        self.maximumAddedSetsPerRotation = max(0, maximumAddedSetsPerRotation)
    }
}

public struct RotationKey: Hashable, Codable, Sendable {
    public let programID: String
    public let cycleNumber: Int
    public let rotation: Int

    public init(programID: String, cycleNumber: Int, rotation: Int) {
        self.programID = programID
        self.cycleNumber = cycleNumber
        self.rotation = rotation
    }
}

public struct RotationAssessment: Hashable, Sendable {
    public let key: RotationKey
    public let startedAt: Date
    public let completedAt: Date?
    public let completedDayIndexes: Set<Int>
    public let expectedDayIndexes: Set<Int>
    public let plannedWorkingSets: Int
    public let completedWorkingSets: Int
    public let atPlanWorkingSets: Int
    public let conditioningMinutes: Double
    public let patternSets: [MovementPattern: Int]
    public let readiness: ReadinessState
    public let reasons: [String]
    public let performanceDelta: Double?

    public var isComplete: Bool { completedDayIndexes.isSuperset(of: expectedDayIndexes) }
    public var completionRate: Double {
        plannedWorkingSets > 0 ? Double(completedWorkingSets) / Double(plannedWorkingSets) : 0
    }
}

public enum CoachingChange: Hashable, Sendable {
    case addSet(slotID: String, count: Int)
    case removeSet(slotID: String, count: Int)
    case addPattern(pattern: MovementPattern, dayIndex: Int, sets: Int)
    case capacityPlan([CoachingCapacityAdjustment])
    case hold
    case reduceAccessoryVolume(percent: Int)
    case tryShorterSpacing(days: Int)
}

public enum CoachingCapacityAdjustment: Hashable, Sendable {
    case addSet(slotID: String, exerciseName: String, count: Int)
    case addPattern(pattern: MovementPattern, dayIndex: Int, sets: Int)

    public var setCount: Int {
        switch self {
        case .addSet(_, _, let count): return count
        case .addPattern(_, _, let sets): return sets
        }
    }
}

public struct CoachingRecommendation: Hashable, Sendable, Identifiable {
    public let id: String
    public let ruleID: String
    public let priority: Int
    public let title: String
    public let explanation: String
    public let change: CoachingChange

    public init(ruleID: String, priority: Int, title: String, explanation: String,
                change: CoachingChange, evidenceKey: String = "") {
        self.ruleID = ruleID
        self.priority = priority
        self.title = title
        self.explanation = explanation
        self.change = change
        self.id = evidenceKey.isEmpty
            ? "\(ruleID):\(String(describing: change))"
            : "\(ruleID):\(evidenceKey)"
    }
}

public struct CoachingReport: Sendable {
    public let rotations: [RotationAssessment]
    public let currentReadiness: ReadinessState
    public let greenRotationStreak: Int
    public let recommendations: [CoachingRecommendation]
}

/// Pure, explainable coaching rules. Safety/body output wins over holds;
/// holds win over added capacity. The engine proposes changes but never mutates
/// a program or silently claims that incomplete alpha logs are complete.
public enum CoachingEngine {
    public static let ruleVersion = 1
    public static let greenCompletionFloor = 0.90
    public static let redCompletionFloor = 0.80
    public static let greenAtPlanFloor = 0.90
    public static let yellowPerformanceDrop = -0.02
    public static let redPerformanceDrop = -0.05

    public static func evaluate(
        program: CoachingProgramSnapshot,
        sessions: [CoachingSessionSnapshot],
        reliableHistoryStart: Date? = nil
    ) -> CoachingReport {
        let relevant = sessions.filter { session in
            guard session.completed, session.programID == program.id else { return false }
            return reliableHistoryStart.map { session.date >= $0 } ?? true
        }.map { programmedSnapshot($0, slots: program.slots) }
        let grouped = Dictionary(grouping: relevant) {
            RotationKey(programID: $0.programID, cycleNumber: $0.cycleNumber, rotation: $0.rotation)
        }
        let orderedGroups = grouped.sorted {
            ($0.value.map(\.date).min() ?? .distantPast) < ($1.value.map(\.date).min() ?? .distantPast)
        }

        var rotations: [RotationAssessment] = []
        var previousPerformance: [String: Double] = [:]
        var previousReadiness: ReadinessState = .unknown
        for (key, group) in orderedGroups {
            let assessment = assessRotation(
                key: key,
                sessions: group,
                expectedDayIndexes: program.expectedDayIndexes,
                priorPerformance: previousPerformance,
                priorReadiness: previousReadiness
            )
            rotations.append(assessment)
            if assessment.isComplete {
                previousPerformance = performanceBySlot(group)
                previousReadiness = assessment.readiness
            }
        }

        let completed = rotations.filter(\.isComplete)
        let readiness = completed.last?.readiness ?? .unknown
        var greenStreak = 0
        for rotation in completed.reversed() {
            guard rotation.readiness == .green else { break }
            greenStreak += 1
        }
        let recommendations = recommend(
            program: program,
            latest: completed.last,
            greenStreak: greenStreak,
            sessions: relevant
        )
        return CoachingReport(
            rotations: rotations,
            currentReadiness: readiness,
            greenRotationStreak: greenStreak,
            recommendations: recommendations
        )
    }

    private static func assessRotation(
        key: RotationKey,
        sessions: [CoachingSessionSnapshot],
        expectedDayIndexes: Set<Int>,
        priorPerformance: [String: Double],
        priorReadiness: ReadinessState
    ) -> RotationAssessment {
        let completedDays = Set(sessions.map(\.dayIndex))
        let isComplete = completedDays.isSuperset(of: expectedDayIndexes)
        // Program coaching is keyed to the durable day/role slot. A same-name
        // lift from another day, an exercise added on the fly, and sets beyond
        // the slot's immutable prescription remain valid workout history, but
        // none of them get a vote on program readiness or distribution.
        let allExercises = sessions.flatMap(\.exercises)
        let allSets = allExercises.flatMap(\.sets)
        // Conditioning has its own ledger. Its minutes remain visible on the
        // rotation report, but it must not inflate lifting-set completion or
        // readiness calculations.
        let liftingExercises = allExercises.filter { !$0.pattern.isConditioning }
        // Primers and top singles remain observable performance practice, but
        // they cannot substitute for a missing prescribed work set.
        let working = liftingExercises.flatMap(\.sets).filter {
            !$0.isWarmup && $0.prescriptionBlock == .work
        }
        let completedWorking = working.filter(\.completed)
        let plannedCount = liftingExercises.reduce(0) { $0 + max(0, $1.plannedSets) }
        let atPlan = completedWorking.filter(setMeetsPlan).count
        let patternSets = Dictionary(grouping: allExercises, by: \.pattern).mapValues { entries in
            entries.flatMap(\.sets).filter {
                !$0.isWarmup && $0.prescriptionBlock == .work && $0.completed
            }.count
        }
        let conditioningSeconds = allExercises.filter { $0.pattern.isConditioning }
            .flatMap(\.sets).filter(\.completed).compactMap(\.durationSeconds).reduce(0, +)
        let bodyFlags = allSets.filter(\.hasBodyFlag).count
        let stoppedWithBody = allSets.contains { $0.stoppedEarly && $0.hasBodyFlag }
        let hardStopCheckIn = sessions.contains(where: \.hasHardStopCheckIn)
        let warmupQualityFlags = allSets.filter {
            $0.isWarmup && ($0.quality == .grindy || $0.quality == .wobble)
        }.count
        let workingQualityFlags = completedWorking.filter {
            $0.quality == .grindy || $0.quality == .wobble
        }.count
        let currentPerformance = performanceBySlot(sessions)
        let deltas = currentPerformance.compactMap { slotID, value -> Double? in
            guard let prior = priorPerformance[slotID], prior > 0 else { return nil }
            return (value - prior) / prior
        }
        let meaningfulDrops = deltas.filter { $0 <= redPerformanceDrop }.count
        let delta = deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count)
        let completionRate = plannedCount > 0 ? Double(completedWorking.count) / Double(plannedCount) : 0
        let atPlanRate = plannedCount > 0 ? Double(atPlan) / Double(plannedCount) : 0

        var readiness: ReadinessState
        var reasons: [String] = []
        if !isComplete {
            readiness = .unknown
            reasons.append("Rotation is still in progress (\(completedDays.count)/\(expectedDayIndexes.count) days banked).")
        } else if hardStopCheckIn || stoppedWithBody || completionRate < redCompletionFloor || meaningfulDrops >= 2
                    || (priorReadiness == .red && (completionRate < greenCompletionFloor || bodyFlags > 0)) {
            readiness = .red
            if hardStopCheckIn { reasons.append("A post-session body check-in reported a hard-stop signal.") }
            if stoppedWithBody { reasons.append("A body signal stopped work early.") }
            if completionRate < redCompletionFloor { reasons.append("Only \(Int((completionRate * 100).rounded()))% of prescribed working sets were completed.") }
            if meaningfulDrops >= 2 { reasons.append("Performance fell at least 5% on \(meaningfulDrops) repeated lifts.") }
        } else if completionRate < greenCompletionFloor || atPlanRate < greenAtPlanFloor
                    || bodyFlags > 0 || warmupQualityFlags > 0
                    || workingQualityFlags > max(1, completedWorking.count / 4)
                    || (delta ?? 0) < yellowPerformanceDrop {
            readiness = .yellow
            if completionRate < greenCompletionFloor { reasons.append("Prescription completion was \(Int((completionRate * 100).rounded()))%.") }
            if atPlanRate < greenAtPlanFloor { reasons.append("Some completed work was below its planned load or reps.") }
            if bodyFlags > 0 { reasons.append("\(bodyFlags) body signal\(bodyFlags == 1 ? "" : "s") logged.") }
            if warmupQualityFlags > 0 { reasons.append("Warm-up quality was flagged.") }
            if workingQualityFlags > max(1, completedWorking.count / 4) { reasons.append("More than a quarter of working sets were grindy or wobbly.") }
            if let delta, delta < yellowPerformanceDrop { reasons.append("Repeated-lift output fell \(Int(abs(delta * 100).rounded()))% on average.") }
        } else if priorPerformance.isEmpty {
            readiness = .unknown
            reasons.append("First complete reliable rotation establishes the comparison baseline.")
        } else {
            readiness = .green
            reasons.append("At least 90% of prescribed work was completed at plan without a body stop.")
            if let delta { reasons.append("Repeated-lift output changed \(signedPercent(delta)).") }
        }

        return RotationAssessment(
            key: key,
            startedAt: sessions.map(\.date).min() ?? .distantPast,
            completedAt: isComplete ? sessions.map(\.date).max() : nil,
            completedDayIndexes: completedDays,
            expectedDayIndexes: expectedDayIndexes,
            plannedWorkingSets: plannedCount,
            completedWorkingSets: completedWorking.count,
            atPlanWorkingSets: atPlan,
            conditioningMinutes: Double(conditioningSeconds) / 60,
            patternSets: patternSets,
            readiness: readiness,
            reasons: reasons,
            performanceDelta: delta
        )
    }

    private static func setMeetsPlan(_ set: CoachingSetSnapshot) -> Bool {
        let repsMet = set.actualReps >= (set.plannedReps ?? set.actualReps)
        guard let planned = set.plannedWeightLb, planned > 0 else { return repsMet }
        return repsMet && set.actualWeightLb >= planned - 0.01
    }

    private static func performanceBySlot(_ sessions: [CoachingSessionSnapshot]) -> [String: Double] {
        var result: [String: Double] = [:]
        for exercise in sessions.flatMap(\.exercises) where !exercise.pattern.isConditioning {
            guard let slotID = exercise.slotID else { continue }
            let best = exercise.sets.filter {
                !$0.isWarmup && $0.prescriptionBlock == .work && $0.completed && $0.actualReps > 0
            }
                .map { ProgramProgression.epleyE1RM(weightLb: $0.actualWeightLb, reps: $0.actualReps) }
                .max() ?? 0
            if best > 0 { result[slotID] = max(result[slotID] ?? 0, best) }
        }
        return result
    }

    /// Resolve an exercise only to the slot that prescribed it. Exact IDs are
    /// authoritative. The day/name/role path exists solely for pre-slot-ID
    /// history and succeeds only when it identifies one unambiguous slot.
    private static func resolvedSlot(
        for exercise: CoachingExerciseSnapshot,
        dayIndex: Int,
        slots: [CoachingProgramSlot]
    ) -> CoachingProgramSlot? {
        if let slotID = exercise.slotID,
           let exact = slots.first(where: { $0.id == slotID && $0.dayIndex == dayIndex }) {
            return exact
        }
        guard let role = exercise.programRole else { return nil }
        let legacy = slots.filter {
            $0.dayIndex == dayIndex && $0.exerciseName == exercise.exerciseName && $0.role == role
        }
        return legacy.count == 1 ? legacy[0] : nil
    }

    private static func programmedSnapshot(
        _ session: CoachingSessionSnapshot,
        slots: [CoachingProgramSlot]
    ) -> CoachingSessionSnapshot {
        var copy = session
        copy.exercises = session.exercises.compactMap { exercise in
            guard let slot = resolvedSlot(for: exercise, dayIndex: session.dayIndex, slots: slots) else {
                return nil
            }
            var programmed = exercise
            programmed.slotID = slot.id
            programmed.programRole = slot.role
            programmed.pattern = slot.pattern

            // Added sets are appended after the immutable planned block. Keep
            // non-work prescription blocks for safety/quality observations,
            // but cap work and conditioning to what this slot prescribed.
            var remainingWork = max(0, exercise.plannedSets)
            programmed.sets = exercise.sets.filter { set in
                guard set.prescriptionBlock == .work || set.prescriptionBlock == .conditioning else {
                    return true
                }
                guard remainingWork > 0 else { return false }
                remainingWork -= 1
                return true
            }
            return programmed
        }
        return copy
    }

    private static func recommend(
        program: CoachingProgramSnapshot,
        latest: RotationAssessment?,
        greenStreak: Int,
        sessions: [CoachingSessionSnapshot]
    ) -> [CoachingRecommendation] {
        guard let latest else { return [] }
        let evidenceKey = "c\(latest.key.cycleNumber)-r\(latest.key.rotation)"
        if latest.readiness == .red {
            return [CoachingRecommendation(
                ruleID: "readiness.red.reduce-accessories.v\(ruleVersion)",
                priority: 100,
                title: "Run one lower-volume rotation",
                explanation: "Repeated output markers are red. Hold main-lift loading and cut accessory sets about 25% for one rotation.",
                change: .reduceAccessoryVolume(percent: 25), evidenceKey: evidenceKey
            )]
        }
        if latest.readiness == .yellow {
            return [CoachingRecommendation(
                ruleID: "readiness.yellow.hold.v\(ruleVersion)",
                priority: 80,
                title: "Hold the current prescription",
                explanation: latest.reasons.first ?? "One or more output markers need another exposure before adding work.",
                change: .hold, evidenceKey: evidenceKey
            )]
        }
        guard greenStreak >= 2 else { return [] }

        let budgets: [(MovementPattern, Int)] = [
            (.verticalPull, 3), (.kneeFlexion, 3), (.shoulderStability, 2),
            (.adductor, 2), (.core, 4),
        ]
        let planned = Dictionary(grouping: program.slots, by: \.pattern)
            .mapValues { $0.reduce(0) { $0 + $1.plannedSets } }
        let capacity = program.maximumAddedSetsPerRotation
        var changes = 0
        var result: [CoachingRecommendation] = []
        var capacityAdjustments: [CoachingCapacityAdjustment] = []
        var capacityEvidence: [String] = []
        for (pattern, target) in budgets {
            let current = planned[pattern, default: 0]
            guard current < target, changes < capacity else { continue }
            let amount = min(target - current, capacity - changes)
            if let slot = program.slots.first(where: {
                $0.pattern == pattern && $0.capacityManaged && !$0.isMain && $0.plannedSets < $0.maximumSets
            }) {
                let add = min(amount, slot.maximumSets - slot.plannedSets)
                guard add > 0 else { continue }
                capacityAdjustments.append(.addSet(
                    slotID: slot.id, exerciseName: slot.exerciseName, count: add
                ))
                capacityEvidence.append("\(pattern.name) \(current)/\(target) → +\(add)")
                changes += add
            } else {
                let day = preferredDay(for: pattern, slots: program.slots)
                capacityAdjustments.append(.addPattern(
                    pattern: pattern, dayIndex: day, sets: amount
                ))
                capacityEvidence.append("\(pattern.name) \(current)/\(target) → +\(amount)")
                changes += amount
            }
        }
        if !capacityAdjustments.isEmpty {
            let total = capacityAdjustments.reduce(0) { $0 + $1.setCount }
            result.append(CoachingRecommendation(
                ruleID: "capacity.rotation-plan.v\(ruleVersion)",
                priority: 40,
                title: "Add \(total) targeted set\(total == 1 ? "" : "s")",
                explanation: "Two rotations were green. " + capacityEvidence.joined(separator: "; ") + ".",
                change: .capacityPlan(capacityAdjustments),
                evidenceKey: evidenceKey
            ))
        }

        if let shorter = shorterSpacingTrial(sessions: sessions) {
            result.append(CoachingRecommendation(
                ruleID: "cadence.shorter-trial.v\(ruleVersion)",
                priority: 20,
                title: "A shorter recovery trial is supported",
                explanation: "Recent exposures stayed green at the observed spacing. Try the next session after \(shorter) days once, then reassess output.",
                change: .tryShorterSpacing(days: shorter), evidenceKey: evidenceKey
            ))
        }
        return result.sorted { ($0.priority, $0.id) > ($1.priority, $1.id) }
    }

    private static func preferredDay(for pattern: MovementPattern, slots: [CoachingProgramSlot]) -> Int {
        if pattern == .kneeFlexion || pattern == .hipExtension {
            if let squatDay = slots.first(where: { $0.isMain && $0.pattern == .squat })?.dayIndex {
                return squatDay
            }
        }
        if pattern == .verticalPull || pattern == .shoulderStability {
            if let upperDay = slots.first(where: {
                $0.isMain && ($0.pattern == .horizontalPress || $0.pattern == .verticalPress)
            })?.dayIndex { return upperDay }
        }
        return slots.map(\.dayIndex).min() ?? 0
    }

    /// A conservative individualized frequency experiment: after at least four
    /// clean completed program sessions, trim one day from the median spacing,
    /// never recommending less than 48 hours. This is a proposal, not a claim
    /// about an unobservable "CNS" state.
    private static func shorterSpacingTrial(sessions: [CoachingSessionSnapshot]) -> Int? {
        let ordered = sessions.sorted { $0.date < $1.date }
        guard ordered.count >= 4 else { return nil }
        let intervals = zip(ordered, ordered.dropFirst()).map { pair in
            Calendar(identifier: .gregorian).dateComponents([.day], from: pair.0.date, to: pair.1.date).day ?? 0
        }.filter { $0 > 0 }
        guard intervals.count >= 3 else { return nil }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        guard median >= 4 else { return nil }
        return max(2, median - 1)
    }

    private static func signedPercent(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return percent >= 0 ? "+\(percent)%" : "\(percent)%"
    }
}
