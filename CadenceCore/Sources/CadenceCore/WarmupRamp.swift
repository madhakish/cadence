import Foundation

/// One warmup set in the auto-generated ramp.
public struct WarmupSet: Hashable, Codable, Sendable, Identifiable {
    public let weightLb: Double
    public let reps: Int

    public init(weightLb: Double, reps: Int) {
        self.weightLb = weightLb
        self.reps = reps
    }

    public var id: String { "\(weightLb)x\(reps)" }
    public var label: String { "\(Weight.trim(weightLb)) × \(reps)" }
}

public enum WarmupRamp {
    /// Standard ramp percentages (of working weight) and reps.
    public static let steps: [(percent: Double, reps: Int)] = [
        (0.40, 5), (0.55, 3), (0.70, 2), (0.85, 1),
    ]

    /// Generate an optional empty-bar opener followed by ~40/55/70/85% of the
    /// working weight, rounded to loadable increments. Steps at or below the
    /// bar are skipped. The result is a starting point — every set is editable.
    public static func ramp(
        workingLb: Double,
        barLb: Double = 45,
        roundingLb: Double = 5,
        includeEmptyBar: Bool = true
    ) -> [WarmupSet] {
        var sets = includeEmptyBar ? [WarmupSet(weightLb: barLb, reps: 10)] : []
        for step in steps {
            let w = Weight.round(workingLb * step.percent, to: roundingLb)
            guard w > barLb + 1e-9, w < workingLb - 1e-9 else { continue }
            sets.append(WarmupSet(weightLb: w, reps: step.reps))
        }
        return sets
    }

    /// A short per-hand dumbbell ramp for a main lift. Unlike a barbell ramp
    /// there is no empty-bar opener; use three distinct, rack-friendly steps
    /// and never duplicate or reach the working weight.
    public static func dumbbellRamp(
        workingLb: Double,
        roundingLb: Double = 5
    ) -> [WarmupSet] {
        guard workingLb > 0 else { return [] }
        let steps: [(percent: Double, reps: Int)] = [(0.40, 10), (0.60, 5), (0.80, 2)]
        var seen = Set<Double>()
        return steps.compactMap { step in
            let weight = Swift.max(roundingLb, Weight.round(workingLb * step.percent, to: roundingLb))
            guard weight < workingLb - 1e-9, seen.insert(weight).inserted else { return nil }
            return WarmupSet(weightLb: weight, reps: step.reps)
        }
    }
}
