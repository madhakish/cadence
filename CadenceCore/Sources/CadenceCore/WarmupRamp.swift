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
    ///
    /// `priorWorkLb` is the heaviest working load already completed earlier
    /// in the session on the same movement with the same implement (see
    /// `priorWorkLb(order:movementGroup:exerciseType:in:)`). Every step at or
    /// below it — the empty bar included — is a climb the lifter has already
    /// made and is dropped. A lift that would otherwise ramp never loses its
    /// ramp entirely: when fewer than two steps clear the prior work, the
    /// heaviest two of the untrimmed ramp remain — the same bridge a `short`
    /// policy keeps.
    public static func ramp(
        workingLb: Double,
        barLb: Double = 45,
        roundingLb: Double = 5,
        includeEmptyBar: Bool = true,
        priorWorkLb: Double? = nil
    ) -> [WarmupSet] {
        var sets = includeEmptyBar ? [WarmupSet(weightLb: barLb, reps: 10)] : []
        for step in steps {
            let w = Weight.round(workingLb * step.percent, to: roundingLb)
            guard w > barLb + 1e-9, w < workingLb - 1e-9 else { continue }
            sets.append(WarmupSet(weightLb: w, reps: step.reps))
        }
        guard let priorWorkLb = priorWorkLb, priorWorkLb > 0 else { return sets }
        let trimmed = sets.filter { $0.weightLb > priorWorkLb + 1e-9 }
        return trimmed.count >= 2 ? trimmed : Array(sets.suffix(2))
    }

    /// What one session entry has already lifted, in the shape `priorWorkLb`
    /// reads. `completedWorkLbs` holds COMPLETED working loads only: planned
    /// and skipped sets, and warmups, prepared nobody.
    public struct SessionWork: Hashable, Sendable {
        public let order: Int
        public let movementGroup: String
        public let exerciseType: String
        public let completedWorkLbs: [Double]

        public init(order: Int, movementGroup: String, exerciseType: String, completedWorkLbs: [Double]) {
            self.order = order
            self.movementGroup = movementGroup
            self.exerciseType = exerciseType
            self.completedWorkLbs = completedWorkLbs
        }
    }

    /// The heaviest working load already completed EARLIER in the session
    /// (lower order) on the same movement group with the same implement — the
    /// climb a later ramp need not repeat. The implement matters: a dumbbell's
    /// 80 per hand is not 80 on a bar. Nil when nothing qualifies or the
    /// movement group is unknown.
    public static func priorWorkLb(
        order: Int, movementGroup: String, exerciseType: String, in session: [SessionWork]
    ) -> Double? {
        guard !movementGroup.isEmpty else { return nil }
        let heaviest = session
            .filter { $0.order < order && $0.movementGroup == movementGroup && $0.exerciseType == exerciseType }
            .flatMap(\.completedWorkLbs)
            .max()
        guard let heaviest = heaviest, heaviest > 0 else { return nil }
        return heaviest
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
