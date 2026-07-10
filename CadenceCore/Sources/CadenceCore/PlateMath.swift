import Foundation

/// Result of a plate-math solve.
public struct PlateSolution: Hashable, Codable, Sendable {
    public let loadout: Loadout
    public let targetLb: Double

    public init(loadout: Loadout, targetLb: Double) {
        self.loadout = loadout
        self.targetLb = targetLb
    }

    /// achieved − target, in lb. Positive = bar is heavier than asked.
    public var deviationLb: Double { loadout.totalLb - targetLb }

    /// True when the closest achievable load misses the target by more than 2 lb.
    public var isOffTarget: Bool { abs(deviationLb) > PlateMath.toleranceLb }

    /// "42.5 kg/side on 45 lb bar = 232.4 lb / 105.4 kg total"
    public var summary: String {
        let side = loadout.perSideLabel
        return "\(side) per side on \(loadout.bar.label) = \(Weight.both(lb: loadout.totalLb)) total"
    }
}

public enum PlateMath {
    /// Warn when achieved differs from target by more than this. Also the
    /// "good enough" band: any load within this of the target is treated as
    /// interchangeable, so a human rounds to a clean stack rather than chasing
    /// the last pound with change plates.
    public static let toleranceLb = 2.0

    private typealias Candidate = (dev: Double, signed: Double, used: Int, distinct: Int, mixed: Bool)

    /// Find the per-side plate combination closest to the target total, loaded
    /// the way a human actually loads: within `toleranceLb` of the target, the
    /// fewest plates win, then the fewest distinct denominations (matched
    /// pairs), then a single unit system (no kg+lb frankenstacks), then
    /// closeness, then erring under. Outside that band it falls back to plain
    /// closest-then-fewest. Mixed units are still produced when they're the only
    /// way to get close.
    ///
    /// - Parameters:
    ///   - targetLb: desired TOTAL bar weight in lb (convert kg before calling).
    ///   - bar: the bar in use.
    ///   - plates: available denominations (unlimited pairs of each).
    ///   - maxPerPlateSide: sanity cap per denomination per side.
    public static func solve(
        targetLb: Double,
        bar: Bar,
        plates: [Plate],
        maxPerPlateSide: Int = 10
    ) -> PlateSolution {
        let perSideTarget = (targetLb - bar.lb) / 2.0
        let sorted = Array(Set(plates)).sorted { $0.lb > $1.lb }

        guard perSideTarget > 1e-9, !sorted.isEmpty else {
            return PlateSolution(loadout: Loadout(bar: bar, perSide: []), targetLb: targetLb)
        }

        let values = sorted.map(\.lb)
        var counts = [Int](repeating: 0, count: sorted.count)
        var bestCounts = counts
        var best: Candidate? = nil
        var nodes = 0

        func metrics(_ remaining: Double) -> Candidate {
            let signed = -remaining * 2.0 // achieved − target (total lb)
            var used = 0, distinct = 0
            var hasKg = false, hasLb = false
            for i in counts.indices where counts[i] > 0 {
                used += counts[i]
                distinct += 1
                if sorted[i].unit == .kg { hasKg = true } else { hasLb = true }
            }
            return (dev: abs(signed), signed: signed, used: used, distinct: distinct, mixed: hasKg && hasLb)
        }

        func isBetter(_ c: Candidate, than b: Candidate?) -> Bool {
            guard let b else { return true }
            let tol = toleranceLb + 1e-9
            let cIn = c.dev <= tol, bIn = b.dev <= tol
            if cIn != bIn { return cIn } // a good-enough load beats an out-of-band one
            if cIn { // both good enough → cleanest to load
                if c.used != b.used { return c.used < b.used }
                if c.distinct != b.distinct { return c.distinct < b.distinct }
                if c.mixed != b.mixed { return !c.mixed }
                if abs(c.dev - b.dev) > 1e-9 { return c.dev < b.dev }
                return c.signed < b.signed - 1e-9 // equal miss: prefer under target
            }
            // both out of band → closest, then fewest plates, then under
            if abs(c.dev - b.dev) > 1e-9 { return c.dev < b.dev }
            if c.used != b.used { return c.used < b.used }
            return c.signed < b.signed - 1e-9
        }

        func consider(_ remaining: Double) {
            let c = metrics(remaining)
            if isBetter(c, than: best) { best = c; bestCounts = counts }
        }

        func search(_ index: Int, _ remaining: Double) {
            nodes += 1
            guard nodes < 300_000 else { return }
            consider(remaining)
            guard index < values.count, remaining > 1e-9 else { return }
            let v = values[index]
            // +1 allows one plate of overshoot so "closest over" is reachable.
            let maxCount = min(maxPerPlateSide, Int((remaining / v).rounded(.down)) + 1)
            // Prune overshoots past the good-enough band AND the best deviation
            // so far, so cleaner in-tolerance loads are never pruned away.
            let bound = max(toleranceLb, best?.dev ?? perSideTarget * 2.0)
            var c = maxCount
            while c >= 0 {
                let next = remaining - Double(c) * v
                if next < 0 && -next * 2.0 > bound + 1e-9 {
                    c -= 1
                    continue
                }
                counts[index] = c
                search(index + 1, next)
                c -= 1
            }
            counts[index] = 0
        }

        search(0, perSideTarget)

        let perSide = zip(sorted, bestCounts).compactMap { plate, count in
            count > 0 ? PlateCount(plate: plate, count: count) : nil
        }
        return PlateSolution(loadout: Loadout(bar: bar, perSide: perSide), targetLb: targetLb)
    }

    /// Reverse mode: what's on the bar (per side, mixed units) → total.
    public static func total(bar: Bar, perSide: [PlateCount]) -> Double {
        Loadout(bar: bar, perSide: perSide).totalLb
    }
}
