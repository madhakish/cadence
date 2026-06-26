import Foundation

/// Cross-cycle, performance-gated progression for program lifts. It tapers
/// toward an estimated ceiling and auto-deloads on repeated stalls, so weight
/// is never added blindly. Pure & deterministic — consumes a performance
/// SUMMARY (never a session), no clock/random. Mirrored 1:1 in web/js/core.js.

public enum CycleGrade: String, Codable, Sendable { case success, hold, fail }

public enum TrainingFocus: String, Codable, Sendable {
    case strength, hypertrophy, maintain

    /// Training-max ceiling as a fraction of estimated 1RM.
    public var tmFraction: Double {
        switch self {
        case .strength: return 0.90
        case .hypertrophy: return 0.78
        case .maintain: return 0.0
        }
    }

    /// Per-cycle increment as a fraction of the current base weight.
    public var incrementFraction: Double {
        switch self {
        case .strength: return 0.025
        case .hypertrophy: return 0.015
        case .maintain: return 0.0
        }
    }
}

public enum LiftRole: String, Codable, Sendable { case main, complementary }

/// What the core consumes about a lift's KEY work (the Peak / week-3 top sets).
/// Built by the data layer from logged sets; never holds a session or a clock.
public struct CycleLiftPerformance: Hashable, Sendable {
    public var prescribedSets: Int
    public var prescribedReps: Int
    public var completedSets: Int          // sets that met or beat target reps
    public var anyStoppedEarly: Bool
    public var anyDroppedLoad: Bool        // a working set carried an autoreg reason
    public var grindyOrWobbleSets: Int
    public var topSetWeightLb: Double
    public var topSetReps: Int

    public init(prescribedSets: Int, prescribedReps: Int, completedSets: Int, anyStoppedEarly: Bool,
                anyDroppedLoad: Bool, grindyOrWobbleSets: Int, topSetWeightLb: Double, topSetReps: Int) {
        self.prescribedSets = prescribedSets
        self.prescribedReps = prescribedReps
        self.completedSets = completedSets
        self.anyStoppedEarly = anyStoppedEarly
        self.anyDroppedLoad = anyDroppedLoad
        self.grindyOrWobbleSets = grindyOrWobbleSets
        self.topSetWeightLb = topSetWeightLb
        self.topSetReps = topSetReps
    }
}

/// Per-lift progression state owned by a program (main/complementary lift).
public struct ProgramLiftState: Codable, Hashable, Sendable {
    public var baseWeightLb: Double        // week-1 volume weight (drives planFor)
    public var estimatedMaxLb: Double      // smoothed Epley e1RM
    public var stallCount: Int             // consecutive non-success cycles
    public var role: LiftRole
    public var lastIncrementLb: Double

    public init(baseWeightLb: Double, estimatedMaxLb: Double, stallCount: Int = 0,
                role: LiftRole = .main, lastIncrementLb: Double = 0) {
        self.baseWeightLb = baseWeightLb
        self.estimatedMaxLb = estimatedMaxLb
        self.stallCount = stallCount
        self.role = role
        self.lastIncrementLb = lastIncrementLb
    }
}

public struct ProgressionResult: Sendable {
    public let state: ProgramLiftState
    public let grade: CycleGrade
    public let note: String?
}

/// Accessory double-progression state (rep range → weight).
public struct AccessoryState: Codable, Hashable, Sendable {
    public var sets: Int
    public var minReps: Int
    public var maxReps: Int
    public var currentReps: Int
    public var weightLb: Double
    public var incrementLb: Double
    public var stallCount: Int

    public init(sets: Int, minReps: Int, maxReps: Int, currentReps: Int,
                weightLb: Double, incrementLb: Double, stallCount: Int = 0) {
        self.sets = sets
        self.minReps = minReps
        self.maxReps = maxReps
        self.currentReps = currentReps
        self.weightLb = weightLb
        self.incrementLb = incrementLb
        self.stallCount = stallCount
    }
}

public struct AccessoryPerformance: Hashable, Sendable {
    public var completedSets: Int
    public var minRepsAchieved: Int        // lowest rep count across the working sets
    public var anyStoppedEarly: Bool

    public init(completedSets: Int, minRepsAchieved: Int, anyStoppedEarly: Bool) {
        self.completedSets = completedSets
        self.minRepsAchieved = minRepsAchieved
        self.anyStoppedEarly = anyStoppedEarly
    }
}

public enum ProgramProgression {
    public static let qualityFlagTolerance = 1     // ≤1 grindy/wobble set still SUCCESS
    public static let stallLimit = 2               // 2 consecutive non-success → auto deload
    public static let deloadRebuildFraction = 0.90

    public static func epleyE1RM(weightLb: Double, reps: Int) -> Double {
        reps >= 1 ? weightLb * (1 + Double(reps) / 30.0) : weightLb
    }

    public static func smoothE1RM(prior: Double, sample: Double) -> Double {
        prior <= 0 ? sample : 0.7 * prior + 0.3 * sample
    }

    public static func gradeCycle(_ perf: CycleLiftPerformance) -> CycleGrade {
        if perf.completedSets < perf.prescribedSets || perf.anyStoppedEarly || perf.anyDroppedLoad { return .fail }
        if perf.grindyOrWobbleSets > qualityFlagTolerance { return .hold }
        return .success
    }

    /// Increment = fraction of base × headroom-to-ceiling, floored at plate
    /// granularity, 0 at/over the focus-dependent training-max ceiling.
    public static func taperedIncrement(
        baseWeightLb: Double, estimatedMaxLb: Double, focus: TrainingFocus,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> Double {
        guard focus.incrementFraction > 0 else { return 0 } // maintain never increments
        let ceiling = estimatedMaxLb * focus.tmFraction
        guard ceiling > 0, baseWeightLb < ceiling else { return 0 }
        let headroom = Swift.max(0, Swift.min(1, (ceiling - baseWeightLb) / ceiling))
        let raw = baseWeightLb * focus.incrementFraction * headroom
        var inc = (raw / roundingLb).rounded(.down) * roundingLb
        if inc < roundingLb && headroom > 0.02 { inc = roundingLb }
        if baseWeightLb + inc > ceiling {
            inc = Swift.max(0, ((ceiling - baseWeightLb) / roundingLb).rounded(.down) * roundingLb)
        }
        return inc
    }

    public static func advanceCycleLift(
        _ state: ProgramLiftState, perf: CycleLiftPerformance, focus: TrainingFocus,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> ProgressionResult {
        let grade = gradeCycle(perf)
        let sample = epleyE1RM(weightLb: perf.topSetWeightLb, reps: perf.topSetReps)
        let estimatedMaxLb = smoothE1RM(prior: state.estimatedMaxLb, sample: sample)
        var next = state
        next.estimatedMaxLb = estimatedMaxLb
        var note: String?

        if grade == .success {
            next.stallCount = 0
            let inc = taperedIncrement(baseWeightLb: state.baseWeightLb, estimatedMaxLb: estimatedMaxLb, focus: focus, roundingLb: roundingLb)
            next.baseWeightLb = state.baseWeightLb + inc
            next.lastIncrementLb = inc
            if inc == 0 { note = focus.incrementFraction <= 0 ? "Maintaining — holding weight." : "At training-max ceiling — holding weight." }
        } else {
            next.stallCount = state.stallCount + 1
            next.lastIncrementLb = 0
            if next.stallCount >= stallLimit {
                let old = next.baseWeightLb
                next.baseWeightLb = Weight.round(old * deloadRebuildFraction, to: roundingLb)
                next.stallCount = 0
                note = "Two cycles without a clean peak — deloaded \(Weight.trim(old))→\(Weight.trim(next.baseWeightLb)) lb to rebuild."
            } else {
                note = grade == .fail ? "Missed peak work — holding weight, retry the cycle."
                                      : "Grindy peak — holding weight, retry the cycle."
            }
        }
        return ProgressionResult(state: next, grade: grade, note: note)
    }

    /// Accessory double progression: earn the top of the rep range across all
    /// sets, then add the smallest increment and reset reps. Never adds weight
    /// that wasn't earned.
    public static func advanceAccessory(_ state: AccessoryState, perf: AccessoryPerformance) -> AccessoryState {
        var next = state
        let hitAll = perf.completedSets >= state.sets && perf.minRepsAchieved >= state.currentReps && !perf.anyStoppedEarly
        if hitAll && state.currentReps >= state.maxReps {
            next.weightLb = state.weightLb + state.incrementLb
            next.currentReps = state.minReps
            next.stallCount = 0
        } else if hitAll {
            next.currentReps = Swift.min(state.currentReps + 1, state.maxReps)
            next.stallCount = 0
        } else {
            next.stallCount = state.stallCount + 1
        }
        return next
    }
}
