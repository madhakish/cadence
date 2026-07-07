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
    /// Standard ramp percentages (of working weight) and reps, after bar×10.
    public static let steps: [(percent: Double, reps: Int)] = [
        (0.40, 5), (0.55, 3), (0.70, 2), (0.85, 1),
    ]

    /// Generate bar×10 then ~40/55/70/85% of the working weight,
    /// rounded to loadable increments. Steps at or below the bar are skipped.
    /// The result is a starting point — every set is editable.
    public static func ramp(
        workingLb: Double,
        barLb: Double = 45,
        roundingLb: Double = 5
    ) -> [WarmupSet] {
        var sets = [WarmupSet(weightLb: barLb, reps: 10)]
        for step in steps {
            let w = Weight.round(workingLb * step.percent, to: roundingLb)
            guard w > barLb + 1e-9, w < workingLb - 1e-9 else { continue }
            sets.append(WarmupSet(weightLb: w, reps: step.reps))
        }
        return sets
    }
}
