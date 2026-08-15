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
        "Assisted Pull-up", "Weighted Pull-up", "Weighted Chin-up",
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
    /// Strategy stamped on the completed session entry. Nil is legacy history
    /// and cannot prove which strategy produced the prescription.
    public var prescriptionStyle: PrescriptionStyle?
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
        prescriptionStyle: PrescriptionStyle? = nil,
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
        self.prescriptionStyle = prescriptionStyle
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
    /// Current, resolved strategy and its authored working shape. These are
    /// value snapshots, not new persistence: the coaching engine needs them to
    /// recommend a stage change without reading a SwiftData model.
    public var prescriptionStyle: PrescriptionStyle
    public var baseWeightLb: Double
    public var workingSets: Int
    public var workingReps: Int
    /// Consecutive non-success exposures already on record for this slot. Lift
    /// slots reset it whenever the base is rebuilt, so a non-zero value always
    /// means "the weight is being retried rather than added to".
    public var stallCount: Int
    /// The lifter has shelved the exercise this slot prescribes.
    public var exerciseIsShelved: Bool

    public init(
        id: String,
        exerciseName: String,
        dayIndex: Int,
        pattern: MovementPattern,
        plannedSets: Int,
        role: String? = nil,
        isMain: Bool = false,
        capacityManaged: Bool = true,
        maximumSets: Int = 6,
        prescriptionStyle: PrescriptionStyle = .automatic,
        baseWeightLb: Double = 0,
        workingSets: Int = 0,
        workingReps: Int = 0,
        stallCount: Int = 0,
        exerciseIsShelved: Bool = false
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
        self.prescriptionStyle = prescriptionStyle
        self.baseWeightLb = max(0, baseWeightLb)
        self.workingSets = max(0, workingSets)
        self.workingReps = max(0, workingReps)
        self.stallCount = max(0, stallCount)
        self.exerciseIsShelved = exerciseIsShelved
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
    /// True when this rotation is closed and was measured by the days it
    /// actually ran, because the program has since changed shape.
    public let judgedAsRun: Bool
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
    /// Keep per-exposure linear loading, but trade 3x5 for 5x3 on one upper
    /// slot after its load has already needed a rebuild.
    case useLinearTriples(slotID: String, exerciseName: String, expectedBaseWeightLb: Double)
    /// Retire a day's accessory-tier vertical pulls (a machine pulldown, a
    /// pull-up accessory) and train the pattern as programmed lift work
    /// instead. The engine names the day and the accessories; the client
    /// supplies the pull-up slot from the library — the same engine/client
    /// split rotateExercise uses.
    case promoteVerticalPull(dayIndex: Int, accessorySlotIDs: [String], accessoryNames: [String])
    /// Swap one slot to a compatible variation of the same movement. The
    /// engine names the slot only; resolving an actual replacement needs the
    /// exercise library, which lives on the clients — the same split the
    /// pattern-based capacity additions already use.
    case rotateExercise(slotID: String, exerciseName: String)
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
    // v2: a second consecutive red rotation escalates to a deeper cut.
    public static let ruleVersion = 2
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
        // A rotation must be judged against the program as it stood WHEN IT WAS
        // RUN, not as it stands today. Programs legitimately gain and lose days
        // — adding a complementary lift, moving from a 2-day to a 4-day split —
        // and reading today's day list back over old rotations made every one
        // of them permanently "in progress, 1/4 days banked" for work that was
        // actually finished.
        //
        // Only the CURRENT rotation is measured against the live program. A
        // rotation the schedule has already moved past is closed: it ran the
        // days it ran, and the shape it ran under is not recoverable from a
        // program that has since changed. Judging it by its own days reports
        // history instead of inventing a standard it was never held to.
        for (index, entry) in orderedGroups.enumerated() {
            let (key, group) = entry
            let isCurrent = index == orderedGroups.count - 1
            // A closed rotation that DID meet today's day set is genuinely
            // complete and behaves normally. Only one that falls short is
            // reported as-run — its shortfall may be a program that has since
            // changed shape, which is unknowable from here, so it is shown as
            // history but never trusted as a verified baseline.
            let shortfall = !Set(group.map(\.dayIndex)).isSuperset(of: program.expectedDayIndexes)
            let asRun = !isCurrent && shortfall
            let assessment = assessRotation(
                key: key,
                sessions: group,
                expectedDayIndexes: asRun ? Set(group.map(\.dayIndex)) : program.expectedDayIndexes,
                judgedAsRun: asRun,
                priorPerformance: previousPerformance,
                priorReadiness: previousReadiness
            )
            rotations.append(assessment)
            // Only a rotation VERIFIED complete against a known day set may
            // seed the next comparison. An as-run rotation is complete by
            // construction, so trusting it would launder an unknown into a
            // baseline.
            if assessment.isComplete, !assessment.judgedAsRun {
                previousPerformance = performanceBySlot(group)
                previousReadiness = assessment.readiness
            }
        }

        // Streaks and capacity plans require verified rotations only.
        let completed = rotations.filter { $0.isComplete && !$0.judgedAsRun }
        // Once a complete baseline exists, an in-progress rotation can report
        // provisional readiness from the programmed slots already banked.
        // Program changes still use complete rotations only.
        let readiness = rotations.last?.readiness ?? .unknown
        var greenStreak = 0
        for rotation in completed.reversed() {
            guard rotation.readiness == .green else { break }
            greenStreak += 1
        }
        let recommendations = recommend(
            program: program,
            latest: completed.last,
            // The rotation before the latest verified one, so a red that
            // persists can escalate past a red that is one bad week.
            previousReadiness: completed.dropLast().last?.readiness ?? .unknown,
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
        judgedAsRun: Bool = false,
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
            !$0.isWarmup && $0.prescriptionBlock.countsAsPrescribedWork
        }
        let completedWorking = working.filter(\.completed)
        let plannedCount = liftingExercises.reduce(0) { $0 + max(0, $1.plannedSets) }
        let atPlan = completedWorking.filter(setMeetsPlan).count
        let patternSets = Dictionary(grouping: allExercises, by: \.pattern).mapValues { entries in
            entries.flatMap(\.sets).filter {
                !$0.isWarmup && $0.prescriptionBlock.countsAsPrescribedWork && $0.completed
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
        if hardStopCheckIn || stoppedWithBody || completionRate < redCompletionFloor || meaningfulDrops >= 2
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

        if judgedAsRun {
            // First, because both clients surface only the leading reason.
            reasons.insert("Closed rotation — reported as run (\(completedDays.count) day\(completedDays.count == 1 ? "" : "s")); the program's shape at the time is not recoverable.", at: 0)
        }
        if !isComplete {
            let progress = "Rotation is still in progress (\(completedDays.count)/\(expectedDayIndexes.count) days banked)."
            if readiness == .green {
                reasons[0] = "\(progress) Completed programmed slots are tracking at plan."
            } else if readiness == .unknown {
                reasons.insert(progress, at: 0)
            } else {
                reasons.append(progress)
            }
        }

        return RotationAssessment(
            key: key,
            startedAt: sessions.map(\.date).min() ?? .distantPast,
            completedAt: isComplete ? sessions.map(\.date).max() : nil,
            completedDayIndexes: completedDays,
            expectedDayIndexes: expectedDayIndexes,
            judgedAsRun: judgedAsRun,
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
                !$0.isWarmup && $0.prescriptionBlock.countsAsPrescribedWork && $0.completed && $0.actualReps > 0
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
                guard set.prescriptionBlock.countsAsProgramInstruction else {
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
        previousReadiness: ReadinessState,
        greenStreak: Int,
        sessions: [CoachingSessionSnapshot]
    ) -> [CoachingRecommendation] {
        guard let latest else { return [] }
        let evidenceKey = "c\(latest.key.cycleNumber)-r\(latest.key.rotation)"
        // Rotation suggestions are program hygiene, not capacity: a slot
        // pointing at a shelved exercise or stuck retrying the same weight is
        // wrong at every readiness level, so these are offered alongside the
        // readiness verdict rather than gated behind a green streak. They sort
        // below every readiness rule, so the light stays the headline.
        let programChanges = (
            rotationSuggestions(program: program, evidenceKey: evidenceKey)
            + linearStageSuggestions(program: program, sessions: sessions, evidenceKey: evidenceKey)
            + verticalPullPromotions(program: program)
        )
        func decided(_ recommendation: CoachingRecommendation) -> [CoachingRecommendation] {
            ([recommendation] + programChanges).sorted { ($0.priority, $0.id) > ($1.priority, $1.id) }
        }
        // A second consecutive red rotation escalates: one bad rotation is
        // noise, two in a row is a trend, and the 25% cut has already been
        // tried and did not restore output. Deloading is near-universal
        // practice but thinly studied; the survey evidence (Rogerson 2024)
        // describes cutting volume while KEEPING frequency, which is exactly
        // what this does — the rotation still runs, it just carries less work.
        //
        // Note this does NOT jump the program to its scheduled deload week.
        // Skipping the peak would mark every wave-family slot as a missed peak
        // and start them toward a 10% rebuild, which is a second punishment for
        // a lifter the engine has just judged to be under-recovered.
        //
        // It also deliberately leaves main-lift LOAD alone. The same survey
        // describes dropping load ~10%, but Cadence grades a cycle on the peak
        // work actually performed (`ProgramProgression.gradeCycle`), and a
        // session carries no "this was a planned deload" marker. Prescribing
        // lighter mains would read back as a failed peak, so two recovery
        // rotations would trip `stallLimit` and rebuild the base at 90%.
        // Cutting accessory SETS has no such effect: double progression grades
        // reps at a held weight, so fewer sets is invisible to it.
        if latest.readiness == .red, previousReadiness == .red {
            return decided(CoachingRecommendation(
                ruleID: "readiness.red.persistent.recovery-rotation.v\(ruleVersion)",
                priority: 110,
                title: "Run a recovery rotation",
                explanation: "Two rotations in a row are red and the lighter rotation did not restore output. Hold main-lift loading and cut accessory sets about 50% for one rotation, keeping every session.",
                change: .reduceAccessoryVolume(percent: 50), evidenceKey: evidenceKey
            ))
        }
        if latest.readiness == .red {
            return decided(CoachingRecommendation(
                ruleID: "readiness.red.reduce-accessories.v\(ruleVersion)",
                priority: 100,
                title: "Run one lower-volume rotation",
                explanation: "Repeated output markers are red. Hold main-lift loading and cut accessory sets about 25% for one rotation.",
                change: .reduceAccessoryVolume(percent: 25), evidenceKey: evidenceKey
            ))
        }
        if latest.readiness == .yellow {
            return decided(CoachingRecommendation(
                ruleID: "readiness.yellow.hold.v\(ruleVersion)",
                priority: 80,
                title: "Hold the current prescription",
                explanation: latest.reasons.first ?? "One or more output markers need another exposure before adding work.",
                change: .hold, evidenceKey: evidenceKey
            ))
        }
        guard greenStreak >= 2 else {
            return programChanges.sorted { ($0.priority, $0.id) > ($1.priority, $1.id) }
        }

        let budgets: [(MovementPattern, Int)] = [
            (.verticalPull, 3), (.kneeFlexion, 3), (.shoulderStability, 2),
            (.adductor, 2), (.core, 4),
        ]
        let planned = Dictionary(grouping: program.slots, by: \.pattern)
            .mapValues { $0.reduce(0) { $0 + $1.plannedSets } }
        let capacity = program.maximumAddedSetsPerRotation
        var changes = 0
        var result: [CoachingRecommendation] = programChanges
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

    /// A lift slot's counter resets the moment the base is rebuilt, so any
    /// non-zero value means the weight is being retried. Accessory counters are
    /// unbounded and nothing ever resolves them, so they need a real plateau.
    static let liftStallRotationThreshold = 1
    static let accessoryStallRotationThreshold = 3

    /// Slots the program should stop prescribing as they stand: the exercise
    /// has been shelved, or the slot is stuck retrying a weight it is not
    /// making. Both are suggestions — the engine names the slot, the client
    /// resolves a compatible variation, and the athlete decides.
    private static func rotationSuggestions(
        program: CoachingProgramSnapshot, evidenceKey: String
    ) -> [CoachingRecommendation] {
        var result: [CoachingRecommendation] = []
        for slot in program.slots.sorted(by: { ($0.dayIndex, $0.id) < ($1.dayIndex, $1.id) }) {
            guard !slot.pattern.isConditioning else { continue }
            if slot.exerciseIsShelved {
                result.append(CoachingRecommendation(
                    ruleID: "program.slot.rotate.shelved.v\(ruleVersion)",
                    priority: 70,
                    title: "\(slot.exerciseName) is shelved but still programmed",
                    explanation: "This slot still prescribes \(slot.exerciseName), which you have shelved. Rotate it to a compatible variation of the same movement, or reopen the exercise.",
                    change: .rotateExercise(slotID: slot.id, exerciseName: slot.exerciseName),
                    evidenceKey: "\(evidenceKey)-\(slot.id)"
                ))
                continue
            }
            let threshold = slot.role == "accessory"
                ? accessoryStallRotationThreshold
                : liftStallRotationThreshold
            guard slot.stallCount >= threshold else { continue }
            result.append(CoachingRecommendation(
                ruleID: "program.slot.rotate.stalled.v\(ruleVersion)",
                priority: 60,
                title: "\(slot.exerciseName) is stuck",
                explanation: "\(slot.exerciseName) has \(slot.stallCount) exposure\(slot.stallCount == 1 ? "" : "s") on record without meeting its prescription, so it is being retried rather than added to. Rotating to a compatible variation of the same movement is the usual answer before the weight gets cut.",
                change: .rotateExercise(slotID: slot.id, exerciseName: slot.exerciseName),
                evidenceKey: "\(evidenceKey)-\(slot.id)"
            ))
        }
        return result
    }

    /// The vertical pull belongs at the lift tier (issue #126): current
    /// templates train pull-ups as programmed double-progression work that
    /// earns load at the top of its rep window — never as an accessory buried
    /// under the press, and never only as a machine stack. A program
    /// instantiated before that change still carries the old shape, and no
    /// migration rewrites an authored program, so the coach offers the
    /// upgrade instead: one recommendation per day whose ONLY vertical pull
    /// is accessory work. The evidence key is rotation-independent — this is
    /// a structural fact about the program, not a per-rotation reading — so
    /// one dismissal silences it for good, and applying removes the
    /// condition itself.
    static func verticalPullPromotions(
        program: CoachingProgramSnapshot
    ) -> [CoachingRecommendation] {
        var result: [CoachingRecommendation] = []
        let byDay = Dictionary(grouping: program.slots, by: \.dayIndex)
        for (dayIndex, slots) in byDay.sorted(by: { $0.key < $1.key }) {
            let lifts = slots.filter { $0.role != "accessory" }
            // A day with no lift work at all is not a training day to
            // reshape, and a day already pulling at the lift tier needs
            // nothing.
            guard !lifts.isEmpty,
                  !lifts.contains(where: { $0.pattern == .verticalPull }) else { continue }
            // Sorted by slot id: the snapshot is built from unsorted
            // relationship arrays, and the recommendation id derives from
            // these ids — reordering the same slots must not re-emit a
            // dismissed offer.
            let pulls = slots.filter {
                $0.role == "accessory" && $0.pattern == .verticalPull && !$0.exerciseIsShelved
            }.sorted { $0.id < $1.id }
            guard !pulls.isEmpty else { continue }
            let names = pulls.map(\.exerciseName)
            result.append(CoachingRecommendation(
                ruleID: "program.day.vertical-pull-tier.v1",
                priority: 55,
                title: "Train the pull as lift work",
                explanation: "This day's only vertical pull is accessory work (\(names.joined(separator: ", "))). Pulling is main work: retire the accessory and train pull-ups as a programmed lift on a rep window that earns load at the top — the same shape new programs start with.",
                change: .promoteVerticalPull(dayIndex: dayIndex,
                                             accessorySlotIDs: pulls.map(\.id),
                                             accessoryNames: names),
                evidenceKey: "day\(dayIndex):" + pulls.map(\.id).joined(separator: ",")
            ))
        }
        return result
    }

    /// The first adaptive stage inside Progressive Barbell Strength.
    ///
    /// A single miss is not evidence. `linearFives` already retries three
    /// consecutive misses and then rebuilds the base by 10%. Only after that
    /// rebuild is observable do we offer the smallest next change supported by
    /// the existing slot data: keep 15 total reps, expressed as 5x3 instead of
    /// 3x5, for this upper-body lift only. Squat and pull transitions require
    /// light-day/frequency semantics and deliberately do not guess here.
    private static func linearStageSuggestions(
        program: CoachingProgramSnapshot,
        sessions: [CoachingSessionSnapshot],
        evidenceKey: String
    ) -> [CoachingRecommendation] {
        let upperPresses: Set<MovementPattern> = [.horizontalPress, .verticalPress]
        let orderedSessions = sessions.sorted(by: { $0.date > $1.date })
        return program.slots.compactMap { slot in
            guard slot.prescriptionStyle == .linearFives,
                  upperPresses.contains(slot.pattern),
                  slot.capacityManaged,
                  slot.maximumSets >= 5,
                  slot.workingSets == 3, slot.workingReps == 5,
                  slot.baseWeightLb > 0 else { return nil }

            let slotHistory: [(sessionID: String, exercise: CoachingExerciseSnapshot)] = orderedSessions
                .compactMap { session in
                    guard let exercise = session.exercises.first(where: { $0.slotID == slot.id }) else {
                        return nil
                    }
                    return (session.id, exercise)
                }
            let exposureCandidates: [(sessionID: String, plannedWeight: Double, missed: Bool)?] = slotHistory
                .prefix(while: { $0.exercise.prescriptionStyle == .linearFives })
                .map { entry in
                    let exercise = entry.exercise
                    let prescribedWork = exercise.sets.filter {
                        !$0.isWarmup && $0.prescriptionBlock.countsAsPrescribedWork
                    }
                    let setRepTargets = Set(prescribedWork.compactMap(\.plannedReps))
                    let plannedReps = exercise.plannedReps
                        ?? (setRepTargets.count == 1 ? setRepTargets.first : nil)
                    guard let plannedWeight = exercise.plannedWeightLb
                            ?? prescribedWork.compactMap(\.plannedWeightLb).max(),
                          plannedWeight > 0,
                          exercise.plannedSets == 3,
                          plannedReps == 5 else { return nil }
                    let metSets = prescribedWork.filter { $0.completed && setMeetsPlan($0) }.count
                    return (entry.sessionID, plannedWeight, metSets < exercise.plannedSets)
                }
            // Unknown/legacy plan data breaks the proof. Do not discard it and
            // join two failure runs that were never observed as consecutive.
            let exposures = exposureCandidates.prefix(while: { $0 != nil }).compactMap { $0 }
            let missesNeeded = ProgramProgression.linearRule(
                for: .linearFives, movementGroup: nil
            ).stallLimit
            guard exposures.count >= missesNeeded else { return nil }
            let attempts = Array(exposures.prefix(missesNeeded))
            guard attempts.allSatisfy({ $0.missed }),
                  let lightest = attempts.map(\.plannedWeight).min(),
                  let plannedWeight = attempts.map(\.plannedWeight).max(),
                  abs(plannedWeight - lightest) < 0.01,
                  slot.baseWeightLb <= plannedWeight * 0.925 else { return nil }
            let sessionID = attempts[0].sessionID

            return CoachingRecommendation(
                ruleID: "program.slot.linear-triples.v1",
                priority: 65,
                title: "Move \(slot.exerciseName) to triples",
                explanation: "\(slot.exerciseName)'s linear base was rebuilt from \(Weight.trim(plannedWeight)) to \(Weight.trim(slot.baseWeightLb)) lb after the last prescription was not met. Keep session-to-session loading, but change this slot from 3x5 to 5x3 so only rep structure changes.",
                change: .useLinearTriples(
                    slotID: slot.id,
                    exerciseName: slot.exerciseName,
                    expectedBaseWeightLb: slot.baseWeightLb
                ),
                evidenceKey: "\(evidenceKey)-\(sessionID)-\(slot.id)"
            )
        }
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
