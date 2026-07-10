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
        barLb: Double = 45
    ) -> Double {
        let dropped = Weight.round(currentLb * 0.93, to: roundingLb)
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
        barLb: Double = 45
    ) -> [(index: Int, weightLb: Double)] {
        sets.enumerated().compactMap { i, s in
            guard !s.isWarmup, !s.isFlagged else { return nil }
            return (index: i, weightLb: droppedLoad(from: s.weightLb, roundingLb: roundingLb, barLb: barLb))
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
}
