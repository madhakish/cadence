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

    public var name: String {
        switch self {
        case .automatic: return "Automatic"
        case .wave: return "Strength wave"
        case .offsetWave: return "Strength wave — offsets"
        case .secondary: return "Secondary strength"
        case .hypertrophy: return "Hypertrophy"
        case .technique: return "Technique"
        case .doubleProgression: return "Double progression"
        }
    }
}

public enum PrescriptionBlockKind: String, Codable, CaseIterable, Sendable {
    case warmup
    case primer
    case topSingle
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
        let raw = plan(for: state, roundingLb: step, style: style, configuration: configuration)
        guard exerciseType == "dumbbell", raw.weightLb > state.baseWeightLb else { return raw }
        return SessionPlan(
            weightLb: Swift.min(raw.weightLb, state.baseWeightLb + 5),
            sets: raw.sets,
            reps: raw.reps,
            phase: raw.phase,
            cycleNumber: raw.cycleNumber
        )
    }

    /// Repair an impossible rising-wave prescription from the immediately
    /// preceding clean exposure of this exact program slot. This is deliberately
    /// narrow: only Volume→Load and Load→Peak can re-anchor, and only when the
    /// stored next plan would fail to exceed work the athlete just completed.
    /// Deloads, new cycles, manual holds above the prior load, and unclean work
    /// remain owned by the stored program state.
    public static func reconciledBaseWeight(
        storedBaseWeightLb: Double,
        previousPerformedWeightLb: Double,
        previousPhase: CyclePhase,
        currentPhase: CyclePhase,
        programRoundingLb: Double,
        exerciseType: String?,
        movementGroup: String? = nil,
        role: LiftRole = .main,
        focus: TrainingFocus = .strength,
        prescriptionStyle: PrescriptionStyle = .automatic,
        configuration: LiftPrescriptionConfiguration = .init()
    ) -> Double {
        guard currentPhase.rawValue == previousPhase.rawValue + 1,
              currentPhase == .load || currentPhase == .peak,
              previousPerformedWeightLb > 0,
              resolvedStyle(prescriptionStyle, movementGroup: movementGroup, role: role, focus: focus) != .doubleProgression
        else { return storedBaseWeightLb }

        func plan(base: Double, phase: CyclePhase) -> SessionPlan {
            programPlan(
                for: CycleState(baseWeightLb: base, nextPhase: phase, incrementLb: 0),
                programRoundingLb: programRoundingLb,
                exerciseType: exerciseType,
                movementGroup: movementGroup,
                role: role,
                focus: focus,
                prescriptionStyle: prescriptionStyle,
                configuration: configuration
            )
        }

        let storedNext = plan(base: storedBaseWeightLb, phase: currentPhase).weightLb
        guard storedNext <= previousPerformedWeightLb else { return storedBaseWeightLb }

        let step = max(0.5, loadStep(programRoundingLb: programRoundingLb, exerciseType: exerciseType))
        let upper = max(2_000, previousPerformedWeightLb * 2)
        var bestBase = storedBaseWeightLb
        var bestError = Double.greatestFiniteMagnitude
        var candidate = step
        while candidate <= upper {
            let error = abs(plan(base: candidate, phase: previousPhase).weightLb - previousPerformedWeightLb)
            if error < bestError - 1e-9
                || (abs(error - bestError) < 1e-9
                    && abs(candidate - storedBaseWeightLb) < abs(bestBase - storedBaseWeightLb)) {
                bestBase = candidate
                bestError = error
            }
            candidate += step
        }
        return plan(base: bestBase, phase: currentPhase).weightLb > storedNext
            ? bestBase : storedBaseWeightLb
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
        configuration: LiftPrescriptionConfiguration = .init()
    ) -> SessionPlan {
        let phase = state.nextPhase
        let prescription: (sets: Int, reps: Int, multiplier: Double)
        switch style {
        case .automatic, .wave:
            prescription = (phase.sets, phase.reps, phase.multiplier)
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
            switch phase {
            case .volume: prescription = (3, 5, 1.0)
            case .load: prescription = (3, 4, 1.05)
            case .peak: prescription = (3, 3, 1.10)
            case .deload: prescription = (2, 5, 0.80)
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
        if configuration.phasePrimerEnabled, style != .doubleProgression,
           let primer = primerWeight(
            baseWeightLb: state.baseWeightLb, phase: state.nextPhase, style: style,
            roundingLb: step, configuration: configuration
           ), primer > 0, primer < work.weightLb {
            blocks.append(PrescriptionBlock(kind: .primer, weightLb: primer, sets: 1, reps: 1))
        }
        if configuration.peakSingleEnabled, state.nextPhase == .peak,
           style != .technique, style != .doubleProgression {
            let seed = configuration.lastPeakSingleLb > 0
                ? configuration.lastPeakSingleLb + configuration.peakSingleIncrementLb
                : estimatedMaxLb * 0.90
            let target = Weight.round(seed, to: step)
            if target > work.weightLb {
                blocks.append(PrescriptionBlock(kind: .topSingle, weightLb: target, sets: 1, reps: 1))
            }
        }
        blocks.append(PrescriptionBlock(kind: .work, weightLb: work.weightLb, sets: work.sets, reps: work.reps))
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
