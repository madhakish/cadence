import Foundation

public enum LoadingPolicy: String, Codable, CaseIterable, Sendable {
    case closest, under, over, exact

    public var label: String {
        switch self {
        case .closest: return "Closest"
        case .under: return "Never over"
        case .over: return "Never under"
        case .exact: return "Exact / competition"
        }
    }
}

/// Result of a plate-math solve.
public struct PlateSolution: Hashable, Codable, Sendable {
    public let loadout: Loadout
    public let targetLb: Double
    public let policy: LoadingPolicy
    public let satisfiesPolicy: Bool

    public init(loadout: Loadout, targetLb: Double, policy: LoadingPolicy = .closest,
                satisfiesPolicy: Bool = true) {
        self.loadout = loadout
        self.targetLb = targetLb
        self.policy = policy
        self.satisfiesPolicy = satisfiesPolicy
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

/// The selected prescription plus the nearest achievable load on either side
/// of the theoretical target. This keeps the engine's choice explainable in
/// the session UI instead of silently replacing a programmed number.
public struct PlatePrescriptionOptions: Hashable, Sendable {
    public let targetLb: Double
    public let selected: PlateSolution
    public let below: PlateSolution?
    public let above: PlateSolution?
}

public enum PlateMath {
    /// Warn when achieved differs from target by more than this. Also the
    /// "good enough" band: any load within this of the target is treated as
    /// interchangeable, so a human rounds to a clean stack rather than chasing
    /// the last pound with change plates.
    public static let toleranceLb = 2.0

    private typealias Candidate = (dev: Double, signed: Double, used: Int, distinct: Int, mixed: Bool, canonical: Bool)

    /// Find the per-side plate combination closest to the target total, loaded
    /// the way a human actually loads: within `toleranceLb` of the target, a
    /// stack that IS the heaviest-first greedy fill of its own weight (in its
    /// own unit system) beats any re-shuffled stack — 105/side is 45+45+10+5,
    /// never 35×3, because the big plates go on first. Between greedy stacks
    /// the fewest plates win (220 → 2×20 kg, not 45+35+5+2.5), then fewest
    /// distinct denominations (matched pairs), then a single unit system (no
    /// kg+lb frankenstacks), then closeness, then erring under. Outside the
    /// band it falls back to plain closest-then-fewest. Mixed units are still
    /// produced when they're the only way to get close.
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
        collarLb: Double = 0,
        policy: LoadingPolicy = .closest,
        maxPerPlateSide: Int = 10
    ) -> PlateSolution {
        let collarLb = max(0, collarLb)
        let perSideTarget = (targetLb - bar.lb - collarLb) / 2.0
        let sorted = Array(Set(plates)).sorted { $0.lb > $1.lb }

        guard perSideTarget > 1e-9, !sorted.isEmpty else {
            let loadout = Loadout(bar: bar, perSide: [], collarLb: collarLb)
            return PlateSolution(loadout: loadout, targetLb: targetLb, policy: policy,
                                 satisfiesPolicy: policyAllows(loadout.totalLb - targetLb, policy: policy))
        }

        let values = sorted.map(\.lb)
        var counts = [Int](repeating: 0, count: sorted.count)
        var bestCounts = counts
        var best: Candidate? = nil
        var policyBestCounts = counts
        var policyBest: Candidate? = nil
        var nodes = 0

        func isBetter(_ c: Candidate, than b: Candidate?) -> Bool {
            guard let b else { return true }
            let tol = toleranceLb + 1e-9
            let cIn = c.dev <= tol, bIn = b.dev <= tol
            if cIn != bIn { return cIn } // a good-enough load beats an out-of-band one
            if cIn { // both good enough → cleanest to load, heaviest plates first
                if c.canonical != b.canonical { return c.canonical }
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

        // True when the stack IS the heaviest-first greedy fill of its own
        // achieved weight within one unit system — how a human racks plates
        // (max out the 45s, then work down). Mixed stacks are never canonical.
        func isGreedyCanonical(achieved: Double, mixed: Bool, used: Int) -> Bool {
            if used == 0 { return true }
            if mixed { return false }
            guard let system = zip(sorted, counts).first(where: { $0.1 > 0 })?.0.unit else { return true }
            var rem = achieved
            for i in sorted.indices where sorted[i].unit == system {
                let c = min(maxPerPlateSide, Int((rem / values[i] + 1e-9).rounded(.down)))
                if counts[i] != c { return false }
                rem -= Double(c) * values[i]
            }
            return true
        }

        // used/distinct/kg/lb are threaded through the recursion so each node is
        // O(1) (no per-node rescan of counts) — solve runs on every keystroke.
        func consider(_ remaining: Double, _ used: Int, _ distinct: Int, _ mixed: Bool) {
            let signed = -remaining * 2.0 // achieved − target (total lb)
            // Canonicality only matters inside the band — skip the O(denoms)
            // walk everywhere else.
            let canonical = abs(signed) <= toleranceLb + 1e-9
                && isGreedyCanonical(achieved: perSideTarget - remaining, mixed: mixed, used: used)
            let c: Candidate = (dev: abs(signed), signed: signed, used: used, distinct: distinct, mixed: mixed, canonical: canonical)
            if isBetter(c, than: best) { best = c; bestCounts = counts }
            if Self.policyAllows(signed, policy: policy), isBetter(c, than: policyBest) {
                policyBest = c
                policyBestCounts = counts
            }
        }

        func search(_ index: Int, _ remaining: Double, _ used: Int, _ distinct: Int, _ kg: Int, _ lb: Int) {
            nodes += 1
            guard nodes < 300_000 else { return }
            consider(remaining, used, distinct, kg > 0 && lb > 0)
            guard index < values.count, remaining > 1e-9 else { return }
            let v = values[index]
            let isKg = sorted[index].unit == .kg
            // +1 allows one plate of overshoot so "closest over" is reachable.
            let maxCount = min(maxPerPlateSide, Int((remaining / v).rounded(.down)) + 1)
            // Prune overshoots past the good-enough band and the best relevant
            // deviation. A never-under search cannot borrow the unrestricted
            // closest result as its initial bound: the nearest valid overshoot
            // may be much farther away (50 target, 45 bar, 10s -> 65).
            let directionalBound = policy == .over
                ? (policyBest?.dev ?? Double.infinity)
                : 0
            let bound = max(toleranceLb,
                            max(best?.dev ?? perSideTarget * 2.0, directionalBound))
            var c = maxCount
            while c >= 0 {
                let next = remaining - Double(c) * v
                if next < 0 && -next * 2.0 > bound + 1e-9 {
                    c -= 1
                    continue
                }
                counts[index] = c
                let d = distinct + (c > 0 ? 1 : 0)
                search(index + 1, next, used + c, d, kg + (c > 0 && isKg ? 1 : 0), lb + (c > 0 && !isKg ? 1 : 0))
                c -= 1
            }
            counts[index] = 0
        }

        // Seed best with a clean single-unit greedy fill per unit system: a
        // tight bound from the first node, and never a worse-than-simple stack
        // if the 300k cap trips on a heavy mixed inventory (e.g. 405 → 45×4,
        // not a kg+lb frankenstack).
        func seedGreedy(_ unit: WeightUnit) {
            for i in counts.indices { counts[i] = 0 }
            var remaining = perSideTarget, used = 0, distinct = 0
            for i in sorted.indices where sorted[i].unit == unit {
                let c = min(maxPerPlateSide, Int((remaining / values[i] + 1e-9).rounded(.down)))
                if c > 0 { counts[i] = c; remaining -= Double(c) * values[i]; used += c; distinct += 1 }
            }
            if used > 0 { consider(remaining, used, distinct, false) }
        }
        seedGreedy(.lb)
        seedGreedy(.kg)
        for i in counts.indices { counts[i] = 0 }

        search(0, perSideTarget, 0, 0, 0, 0)

        let selectedCounts = policyBest == nil ? bestCounts : policyBestCounts
        let perSide = zip(sorted, selectedCounts).compactMap { plate, count in
            count > 0 ? PlateCount(plate: plate, count: count) : nil
        }
        return PlateSolution(loadout: Loadout(bar: bar, perSide: perSide, collarLb: collarLb),
                             targetLb: targetLb, policy: policy, satisfiesPolicy: policyBest != nil)
    }

    /// What a session stores for a solved rack load. Inside the good-enough
    /// band the clean stack is loading GUIDANCE, not a new prescription — the
    /// programmed number stays on the card (90, not the 89.1 lb a 10 kg pair
    /// happens to weigh), and the barbell hint explains the actual plates.
    /// Only a genuinely unreachable target stores the achieved load, so the
    /// log stays honest on sparse racks. Mirrored 1:1 in web/js/core.js
    /// `storedPrescription`.
    public static func storedPrescription(targetLb: Double, achievedLb: Double) -> Double {
        abs(achievedLb - targetLb) <= toleranceLb + 1e-9 ? targetLb : achievedLb
    }

    /// Resolve a programmed target against the active rack. An explicit gym
    /// policy wins. With the default closest policy, equal misses select the
    /// heavier option on a volume exposure and the lighter option otherwise
    /// (notably peak work), while returning both choices for display.
    public static func prescriptionOptions(
        targetLb: Double,
        bar: Bar,
        plates: [Plate],
        collarLb: Double = 0,
        policy: LoadingPolicy = .closest,
        preferOverOnTie: Bool = false,
        maxPerPlateSide: Int = 10
    ) -> PlatePrescriptionOptions {
        let underCandidate = solve(
            targetLb: targetLb, bar: bar, plates: plates, collarLb: collarLb,
            policy: .under, maxPerPlateSide: maxPerPlateSide
        )
        let overCandidate = solve(
            targetLb: targetLb, bar: bar, plates: plates, collarLb: collarLb,
            policy: .over, maxPerPlateSide: maxPerPlateSide
        )
        let below = underCandidate.satisfiesPolicy ? underCandidate : nil
        let above = overCandidate.satisfiesPolicy ? overCandidate : nil

        let selected: PlateSolution
        if policy != .closest {
            selected = solve(
                targetLb: targetLb, bar: bar, plates: plates, collarLb: collarLb,
                policy: policy, maxPerPlateSide: maxPerPlateSide
            )
        } else if let below, let above {
            let underMiss = abs(below.deviationLb)
            let overMiss = abs(above.deviationLb)
            if abs(underMiss - overMiss) <= 1e-9 {
                selected = preferOverOnTie ? above : below
            } else {
                selected = underMiss < overMiss ? below : above
            }
        } else {
            selected = below ?? above ?? solve(
                targetLb: targetLb, bar: bar, plates: plates, collarLb: collarLb,
                policy: .closest, maxPerPlateSide: maxPerPlateSide
            )
        }
        return PlatePrescriptionOptions(
            targetLb: targetLb, selected: selected, below: below, above: above
        )
    }

    private static func policyAllows(_ deviationLb: Double, policy: LoadingPolicy) -> Bool {
        switch policy {
        case .closest: return true
        case .under: return deviationLb <= 1e-9
        case .over: return deviationLb >= -1e-9
        case .exact: return abs(deviationLb) <= 0.01
        }
    }

    /// Reverse mode: what's on the bar (per side, mixed units) → total.
    public static func total(bar: Bar, perSide: [PlateCount], collarLb: Double = 0) -> Double {
        Loadout(bar: bar, perSide: perSide, collarLb: collarLb).totalLb
    }
}
