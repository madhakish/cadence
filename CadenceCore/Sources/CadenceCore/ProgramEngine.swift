import Foundation

/// 4-week microcycle phase. Each main lift runs its own track —
/// progression keys off the lift's last COMPLETED session, not the calendar.
public enum CyclePhase: Int, Codable, CaseIterable, Sendable {
    case volume = 1 // 5×5 moderate
    case load = 2   // 5×3 heavier
    case peak = 3   // 3×3 top working weight
    case deload = 4 // 3×5 ~75–80% of week 1

    public var name: String {
        switch self {
        case .volume: return "Volume"
        case .load: return "Load"
        case .peak: return "Peak"
        case .deload: return "Deload"
        }
    }

    public var sets: Int {
        switch self {
        case .volume, .load: return 5
        case .peak, .deload: return 3
        }
    }

    public var reps: Int {
        switch self {
        case .volume, .deload: return 5
        case .load, .peak: return 3
        }
    }

    /// Multiplier on the cycle's week-1 (volume) weight.
    public var multiplier: Double {
        switch self {
        case .volume: return 1.0
        case .load: return 1.10
        case .peak: return 1.175
        case .deload: return 0.775
        }
    }

    public var next: CyclePhase {
        CyclePhase(rawValue: rawValue + 1) ?? .volume
    }

    /// "R2 Load 5×3"
    public var label: String { "R\(rawValue) \(name) \(sets)×\(reps)" }
}

/// Linear vs 4-week cycle progression.
public enum TrackMode: String, Codable, Sendable {
    case cycle
    case linear
}

/// Set/rep strategy for a program slot. `automatic` keeps setup simple while
/// still respecting the program focus, lift role, and Olympic lift technique
/// needs. Coaches can override an individual slot when the default is not the
/// right training stimulus.
public enum PrescriptionStyle: String, Codable, CaseIterable, Sendable {
    case automatic
    case wave
    case offsetWave
    case secondary
    case hypertrophy
    case technique
    case doubleProgression
    case linearFives
    case texasVolume
    case texasLight
    case texasIntensity
    case fiveThreeOne
    case maxEffort
    case dynamicEffort

    public var name: String {
        switch self {
        case .automatic: return "Automatic"
        case .wave: return "Strength wave"
        case .offsetWave: return "Strength wave — offsets"
        case .secondary: return "Secondary volume"
        case .hypertrophy: return "Hypertrophy"
        case .technique: return "Technique"
        case .doubleProgression: return "Double progression"
        case .linearFives: return "Linear fives"
        case .texasVolume: return "Texas — volume day"
        case .texasLight: return "Texas — light day"
        case .texasIntensity: return "Texas — intensity day"
        case .fiveThreeOne: return "5/3/1 wave"
        case .maxEffort: return "Max effort"
        case .dynamicEffort: return "Dynamic effort"
        }
    }

    /// Styles whose base advances after every banked exposure of the slot
    /// (session-to-session or week-to-week linear progression) instead of
    /// being graded once per 4-week rotation at the Peak.
    public var advancesPerExposure: Bool {
        switch self {
        case .doubleProgression, .linearFives, .texasVolume, .texasLight, .texasIntensity:
            return true
        default:
            return false
        }
    }

    /// Styles that build their own session shape (sets-across, ramps, singles,
    /// speed sets). The generic phase primer and peak-single add-ons never
    /// apply to them.
    public var buildsOwnSessionShape: Bool {
        advancesPerExposure || self == .fiveThreeOne || self == .maxEffort || self == .dynamicEffort
    }

    /// Starting base weight as a fraction of a known estimated 1RM, used when
    /// a program is created from recorded history. 0 = keep the template's
    /// hand-set base. Values follow each methodology's published guidance:
    /// novice work starts with runway below a ~5RM, Texas days derive from the
    /// intensity 5RM (≈0.86 × 1RM), a 5/3/1 training max is 90% of 1RM, a max-
    /// effort target starts at 90%, and speed work sits at ~50%.
    public var defaultStartFraction: Double {
        switch self {
        case .linearFives: return 0.74
        case .texasVolume: return 0.77
        case .texasLight: return 0.62
        case .texasIntensity: return 0.86
        case .fiveThreeOne: return 0.90
        case .maxEffort: return 0.90
        case .dynamicEffort: return 0.50
        default: return 0
        }
    }
}

public enum PrescriptionBlockKind: String, Codable, CaseIterable, Sendable {
    case warmup
    case primer
    case topSingle
    /// Prescribed sub-maximal sets BEFORE the day's top work (the 5/3/1
    /// 65/75% sets). Real work, but not the set that gates progression.
    case ramp
    case work
    case backoff
    case conditioning
}

/// Persistable knobs for a lift slot. Defaults preserve the shipped multiplier
/// wave; an offset wave and double progression are explicit opt-ins.
public struct LiftPrescriptionConfiguration: Codable, Hashable, Sendable {
    public var loadOffsetLb: Double
    public var peakOffsetLb: Double
    public var deloadMultiplier: Double
    public var workingSets: Int
    public var minimumReps: Int
    public var maximumReps: Int
    public var currentReps: Int
    public var peakSingleEnabled: Bool
    public var lastPeakSingleLb: Double
    public var peakSingleIncrementLb: Double
    public var phasePrimerEnabled: Bool

    public init(
        loadOffsetLb: Double = 10,
        peakOffsetLb: Double = 15,
        deloadMultiplier: Double = 0.775,
        workingSets: Int = 3,
        minimumReps: Int = 5,
        maximumReps: Int = 8,
        currentReps: Int = 5,
        peakSingleEnabled: Bool = false,
        lastPeakSingleLb: Double = 0,
        peakSingleIncrementLb: Double = 5,
        phasePrimerEnabled: Bool = true
    ) {
        self.loadOffsetLb = loadOffsetLb
        self.peakOffsetLb = peakOffsetLb
        self.deloadMultiplier = deloadMultiplier
        self.workingSets = workingSets
        self.minimumReps = minimumReps
        self.maximumReps = maximumReps
        self.currentReps = currentReps
        self.peakSingleEnabled = peakSingleEnabled
        self.lastPeakSingleLb = lastPeakSingleLb
        self.peakSingleIncrementLb = peakSingleIncrementLb
        self.phasePrimerEnabled = phasePrimerEnabled
    }
}

public struct PrescriptionBlock: Hashable, Sendable {
    public let kind: PrescriptionBlockKind
    public let weightLb: Double
    public let sets: Int
    public let reps: Int

    public init(kind: PrescriptionBlockKind, weightLb: Double, sets: Int, reps: Int) {
        self.kind = kind
        self.weightLb = weightLb
        self.sets = sets
        self.reps = reps
    }
}

public struct SessionPrescription: Hashable, Sendable {
    public let mainWork: SessionPlan
    public let blocks: [PrescriptionBlock]

    public init(mainWork: SessionPlan, blocks: [PrescriptionBlock]) {
        self.mainWork = mainWork
        self.blocks = blocks
    }
}

/// Per-lift progression state. Serializable; the app wraps this in SwiftData.
public struct CycleState: Codable, Hashable, Sendable {
    public var cycleNumber: Int
    /// Week-1 (volume) working weight for the current cycle, lb.
    public var baseWeightLb: Double
    public var nextPhase: CyclePhase
    /// Per-cycle bump: +10 lb lower body, +5 lb upper body.
    public var incrementLb: Double

    public init(cycleNumber: Int = 1, baseWeightLb: Double, nextPhase: CyclePhase = .volume, incrementLb: Double = 10) {
        self.cycleNumber = cycleNumber
        self.baseWeightLb = baseWeightLb
        self.nextPhase = nextPhase
        self.incrementLb = incrementLb
    }
}

/// What the app suggests for the next session of a lift. Always editable.
public struct SessionPlan: Hashable, Sendable {
    public let weightLb: Double
    public let sets: Int
    public let reps: Int
    public let phase: CyclePhase?
    public let cycleNumber: Int?

    public init(weightLb: Double, sets: Int, reps: Int, phase: CyclePhase? = nil, cycleNumber: Int? = nil) {
        self.weightLb = weightLb
        self.sets = sets
        self.reps = reps
        self.phase = phase
        self.cycleNumber = cycleNumber
    }

    /// "245 × 3×3 — R3 Peak"
    public var label: String {
        let base = "\(Weight.trim(weightLb)) × \(sets)×\(reps)"
        if let phase { return "\(base) — R\(phase.rawValue) \(phase.name)" }
        return base
    }
}

public enum ProgramEngine {
    /// Default rounding for barbell suggestions.
    public static let defaultRoundingLb = 5.0

    /// Dumbbells are recorded per hand. A program-level 10 lb rounding step
    /// would therefore turn into a 20 lb total jump, which is too coarse for
    /// upper-body work. Keep per-hand prescriptions and adaptive progression
    /// to at most 5 lb while leaving the program's chosen granularity intact
    /// for barbells and machines.
    public static func loadStep(programRoundingLb: Double, exerciseType: String?) -> Double {
        exerciseType == "dumbbell" ? Swift.min(programRoundingLb, 5) : programRoundingLb
    }

    /// Program-specific wave plan. Dumbbells are logged per hand, so the
    /// standard Peak multiplier can otherwise turn a 55 lb volume base into a
    /// 65 lb prescription. Keep every above-base DB rotation within one 5 lb
    /// rack jump; barbell/machine waves retain their normal percentages.
    public static func programPlan(
        for state: CycleState,
        programRoundingLb: Double,
        exerciseType: String?,
        movementGroup: String? = nil,
        role: LiftRole = .main,
        focus: TrainingFocus = .strength,
        prescriptionStyle: PrescriptionStyle = .automatic,
        configuration: LiftPrescriptionConfiguration = .init()
    ) -> SessionPlan {
        let step = loadStep(programRoundingLb: programRoundingLb, exerciseType: exerciseType)
        let style = resolvedStyle(prescriptionStyle, movementGroup: movementGroup, role: role, focus: focus)
        let raw = plan(for: state, roundingLb: step, style: style, configuration: configuration,
                       movementGroup: movementGroup)
        guard exerciseType == "dumbbell", raw.weightLb > state.baseWeightLb else { return raw }
        return SessionPlan(
            weightLb: Swift.min(raw.weightLb, state.baseWeightLb + 5),
            sets: raw.sets,
            reps: raw.reps,
            phase: raw.phase,
            cycleNumber: raw.cycleNumber
        )
    }

    /// Resolves the low-friction automatic choice. Olympic lifts prioritize
    /// crisp practice; hypertrophy programs use a rep-range wave; secondary
    /// lifts carry less fatigue than main lifts.
    public static func resolvedStyle(
        _ requested: PrescriptionStyle,
        movementGroup: String?,
        role: LiftRole,
        focus: TrainingFocus
    ) -> PrescriptionStyle {
        guard requested == .automatic else { return requested }
        if movementGroup == "olympic" { return .technique }
        if focus == .hypertrophy { return .hypertrophy }
        if role == .complementary || focus == .maintain { return .secondary }
        return .wave
    }

    /// Phase-shaped plan for a specific training stimulus. The phase still
    /// advances with the unified four-rotation program, but every slot no
    /// longer has to inherit the main-lift 5×5 → 5×3 prescription.
    public static func plan(
        for state: CycleState,
        roundingLb: Double = defaultRoundingLb,
        style: PrescriptionStyle,
        configuration: LiftPrescriptionConfiguration = .init(),
        movementGroup: String? = nil
    ) -> SessionPlan {
        let phase = state.nextPhase
        let prescription: (sets: Int, reps: Int, multiplier: Double)
        switch style {
        case .automatic, .wave:
            prescription = (phase.sets, phase.reps, phase.multiplier)
        case .linearFives, .texasVolume, .texasLight, .texasIntensity:
            // Sets-across at the slot's own base; the base moves per exposure
            // (advanceLinearLift), so the 4-week phase never shapes the weight.
            prescription = (max(1, configuration.workingSets), 5, 1.0)
        case .fiveThreeOne:
            // baseWeightLb is the TRAINING MAX. The plan is the graded top set
            // ("+" set); the two ramp sets are emitted by sessionPrescription.
            let top: (pct: Double, reps: Int)
            switch phase {
            case .volume: top = (0.85, 5)
            case .load: top = (0.90, 3)
            case .peak: top = (0.95, 1)
            case .deload: top = (0.60, 5)
            }
            return SessionPlan(
                weightLb: Weight.round(state.baseWeightLb * top.pct, to: roundingLb),
                sets: 1, reps: top.reps, phase: phase, cycleNumber: state.cycleNumber
            )
        case .maxEffort:
            // Work up to a top single at the slot's current target; the deload
            // rotation trades the single for moderate triples.
            if phase == .deload {
                return SessionPlan(
                    weightLb: Weight.round(state.baseWeightLb * 0.70, to: roundingLb),
                    sets: 3, reps: 3, phase: phase, cycleNumber: state.cycleNumber
                )
            }
            return SessionPlan(
                weightLb: Weight.round(state.baseWeightLb, to: roundingLb),
                sets: 1, reps: 1, phase: phase, cycleNumber: state.cycleNumber
            )
        case .dynamicEffort:
            // Speed work: base ≈ 50% of the slot's max, waved up over the two
            // middle rotations, back to the wave floor on deload. Squat pattern
            // takes speed doubles, hinge takes speed pulls, presses take triples.
            let scheme: (sets: Int, reps: Int)
            if movementGroup == "squat" { scheme = (10, 2) }
            else if movementGroup == "hinge" { scheme = (6, 1) }
            else { scheme = (9, 3) }
            let multiplier: Double
            switch phase {
            case .volume, .deload: multiplier = 1.0
            case .load: multiplier = 1.10
            case .peak: multiplier = 1.20
            }
            return SessionPlan(
                weightLb: Weight.round(state.baseWeightLb * multiplier, to: roundingLb),
                sets: scheme.sets, reps: scheme.reps, phase: phase, cycleNumber: state.cycleNumber
            )
        case .offsetWave:
            let weight: Double
            switch phase {
            case .volume: weight = state.baseWeightLb
            case .load: weight = state.baseWeightLb + configuration.loadOffsetLb
            case .peak: weight = state.baseWeightLb + configuration.peakOffsetLb
            case .deload: weight = state.baseWeightLb * configuration.deloadMultiplier
            }
            return SessionPlan(
                weightLb: Weight.round(weight, to: roundingLb),
                sets: phase.sets, reps: phase.reps, phase: phase, cycleNumber: state.cycleNumber
            )
        case .secondary:
            // Complementary work is volume after the day's heavy main — never
            // a second miniature of the main wave. Sets stay at 5+ reps and at
            // or below the slot's base so the heavy stimulus stays with the
            // main lift (the base is a 5-rep-calibrated weight; 8s sit ~90%).
            switch phase {
            case .volume: prescription = (3, 8, 0.90)
            case .load: prescription = (3, 8, 0.95)
            case .peak: prescription = (3, 6, 1.0)
            case .deload: prescription = (2, 8, 0.75)
            }
        case .hypertrophy:
            switch phase {
            case .volume: prescription = (4, 10, 1.0)
            case .load: prescription = (4, 8, 1.025)
            case .peak: prescription = (3, 8, 1.05)
            case .deload: prescription = (2, 10, 0.85)
            }
        case .technique:
            switch phase {
            case .volume: prescription = (5, 3, 1.0)
            case .load: prescription = (6, 2, 1.05)
            case .peak: prescription = (6, 1, 1.10)
            case .deload: prescription = (3, 2, 0.80)
            }
        case .doubleProgression:
            return SessionPlan(
                weightLb: Weight.round(state.baseWeightLb, to: roundingLb),
                sets: max(1, configuration.workingSets),
                reps: min(max(configuration.currentReps, configuration.minimumReps), configuration.maximumReps),
                phase: phase,
                cycleNumber: state.cycleNumber
            )
        }
        return SessionPlan(
            weightLb: Weight.round(state.baseWeightLb * prescription.multiplier, to: roundingLb),
            sets: prescription.sets,
            reps: prescription.reps,
            phase: phase,
            cycleNumber: state.cycleNumber
        )
    }

    /// Full session prescription for slots that need more than one uniform
    /// work block. Top singles are controlled, optional peak work; primers are
    /// warm-up observations and never count toward the main work grade.
    public static func sessionPrescription(
        for state: CycleState,
        programRoundingLb: Double,
        exerciseType: String?,
        movementGroup: String? = nil,
        role: LiftRole = .main,
        focus: TrainingFocus = .strength,
        prescriptionStyle: PrescriptionStyle = .automatic,
        configuration: LiftPrescriptionConfiguration = .init(),
        estimatedMaxLb: Double = 0
    ) -> SessionPrescription {
        let step = loadStep(programRoundingLb: programRoundingLb, exerciseType: exerciseType)
        let style = resolvedStyle(prescriptionStyle, movementGroup: movementGroup, role: role, focus: focus)
        let work = programPlan(
            for: state, programRoundingLb: programRoundingLb, exerciseType: exerciseType,
            movementGroup: movementGroup, role: role, focus: focus,
            prescriptionStyle: style, configuration: configuration
        )
        var blocks: [PrescriptionBlock] = []
        if configuration.phasePrimerEnabled, !style.buildsOwnSessionShape,
           let primer = primerWeight(
            baseWeightLb: state.baseWeightLb, phase: state.nextPhase, style: style,
            roundingLb: step, configuration: configuration
           ), primer > 0, primer < work.weightLb {
            blocks.append(PrescriptionBlock(kind: .primer, weightLb: primer, sets: 1, reps: 1))
        }
        if configuration.peakSingleEnabled, state.nextPhase == .peak,
           style != .technique, !style.buildsOwnSessionShape {
            let seed = configuration.lastPeakSingleLb > 0
                ? configuration.lastPeakSingleLb + configuration.peakSingleIncrementLb
                : estimatedMaxLb * 0.90
            let target = Weight.round(seed, to: step)
            if target > work.weightLb {
                blocks.append(PrescriptionBlock(kind: .topSingle, weightLb: target, sets: 1, reps: 1))
            }
        }
        if style == .fiveThreeOne {
            // The two ramp sets below the "+" set. They are real prescribed
            // work but only the top set gates progression, so they carry the
            // non-graded ramp kind; block order puts them before the top set.
            let ramp: [(pct: Double, reps: Int)]
            switch state.nextPhase {
            case .volume: ramp = [(0.65, 5), (0.75, 5)]
            case .load: ramp = [(0.70, 3), (0.80, 3)]
            case .peak: ramp = [(0.75, 5), (0.85, 3)]
            case .deload: ramp = [(0.40, 5), (0.50, 5)]
            }
            for step531 in ramp {
                blocks.append(PrescriptionBlock(
                    kind: .ramp,
                    weightLb: Weight.round(state.baseWeightLb * step531.pct, to: step),
                    sets: 1, reps: step531.reps
                ))
            }
        }
        blocks.append(PrescriptionBlock(kind: .work, weightLb: work.weightLb, sets: work.sets, reps: work.reps))
        if style == .maxEffort, state.nextPhase != .deload {
            blocks.append(PrescriptionBlock(
                kind: .backoff,
                weightLb: Weight.round(state.baseWeightLb * 0.80, to: step),
                sets: 3, reps: 3
            ))
        }
        return SessionPrescription(mainWork: work, blocks: blocks)
    }

    public static func primerWeight(
        baseWeightLb: Double,
        phase: CyclePhase,
        style: PrescriptionStyle,
        roundingLb: Double,
        configuration: LiftPrescriptionConfiguration = .init()
    ) -> Double? {
        switch phase {
        case .volume, .deload: return nil
        case .load: return Weight.round(baseWeightLb, to: roundingLb)
        case .peak:
            if style == .offsetWave {
                return Weight.round(baseWeightLb + configuration.loadOffsetLb, to: roundingLb)
            }
            return Weight.round(baseWeightLb * CyclePhase.load.multiplier, to: roundingLb)
        }
    }

    /// Next suggested session for a cycle-tracked lift.
    public static func plan(for state: CycleState, roundingLb: Double = defaultRoundingLb) -> SessionPlan {
        let phase = state.nextPhase
        let raw = state.baseWeightLb * phase.multiplier
        return SessionPlan(
            weightLb: Weight.round(raw, to: roundingLb),
            sets: phase.sets,
            reps: phase.reps,
            phase: phase,
            cycleNumber: state.cycleNumber
        )
    }

    /// Advance state after completing a phase. Completing deload rolls the
    /// cycle: base weight += increment, back to volume.
    public static func advancing(_ state: CycleState, afterCompleting phase: CyclePhase) -> CycleState {
        var next = state
        if phase == .deload {
            next.cycleNumber += 1
            next.baseWeightLb += state.incrementLb
            next.nextPhase = .volume
        } else {
            next.nextPhase = phase.next
        }
        return next
    }

    /// Autoregulation: one tap on "dropping load" mid-session. Cuts the
    /// remaining sets ~7% and rounds to a loadable weight, never below the bar.
    public static func droppedLoad(
        from currentLb: Double,
        roundingLb: Double = defaultRoundingLb,
        barLb: Double = 45,
        dropIncrementLb: Double? = nil
    ) -> Double {
        let dropped = dropIncrementLb.flatMap { $0 > 0 ? currentLb - $0 : nil }
            ?? Weight.round(currentLb * 0.93, to: roundingLb)
        // Guarantee an actual drop even when rounding lands on the same number.
        let result = dropped >= currentLb ? currentLb - roundingLb : dropped
        return Swift.max(result, barLb)
    }

    /// Which sets a mid-session "dropping load" tap rewrites, and to what.
    /// Only sets not yet performed (unflagged working sets) are touched — a
    /// flagged set is history — and each is dropped from ITS OWN weight, so a
    /// lighter back-off set is never raised toward the top set's drop.
    /// Mirrored 1:1 in web/js/core.js `dropLoadPlan`.
    public static func dropLoadPlan(
        sets: [(weightLb: Double, isWarmup: Bool, isFlagged: Bool)],
        roundingLb: Double = defaultRoundingLb,
        barLb: Double = 45,
        dropIncrementLb: Double? = nil
    ) -> [(index: Int, weightLb: Double)] {
        sets.enumerated().compactMap { i, s in
            guard !s.isWarmup, !s.isFlagged else { return nil }
            return (index: i, weightLb: droppedLoad(from: s.weightLb, roundingLb: roundingLb,
                                                    barLb: barLb, dropIncrementLb: dropIncrementLb))
        }
    }
}

/// Why load was dropped mid-session. Logged with the change.
public enum AutoregReason: String, Codable, CaseIterable, Sendable {
    case barSpeed = "bar speed"
    case wobble
    case jointSignal = "joint signal"
    case heat
    case fatigue
    case notThere = "not there"
}
