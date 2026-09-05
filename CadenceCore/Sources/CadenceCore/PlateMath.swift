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
    /// log stays honest on sparse racks. Mirrored 1:1 in web/app/js/core.js
    /// The kg↔lb denomination twins. Lifters switching racks stop going by
    /// exact numbers and go by plates — a 20 kg plate stands in for a 45, a
    /// 5 kg pair for a 10 lb pair — not because the masses match (a 10 kg
    /// plate is 22 lb standing in for a 25) but because the plates are, for
    /// training purposes, the same object. Below maximal loads the drift is a
    /// rounding error; the plate is the currency, the number is its label.
    public static let plateTwinKg: [Double: Double] = [
        45: 20, 35: 15, 25: 10, 10: 5, 5: 2.5, 2.5: 1.25,
    ]

    /// The mass, in lb, of the kg-twin stack for one side loaded to `sideLb`
    /// with standard lb denominations — or nil when `sideLb` is not a clean
    /// lb stack. Decomposition is GREEDY (biggest plates first): that is the
    /// stack a lifter actually builds, and it pins down which of several
    /// equal-total loadings the twins are taken from.
    // MARK: - Load quantization (epic #155 Stage 3)

    /// A plate below this is a change plate: real to load, annoying to chase,
    /// and never worth a warmup or a low-percentage working set.
    public static let fiddlyPlateLb = 5.0

    public struct QuantizeOptions: Sendable {
        /// Which side of the target a swap may land on. A hard constraint,
        /// not a tiebreak: quantizing a progressing lifter DOWN onto the load
        /// they just left would stall the program.
        public enum Bias: Sendable { case nearest, up, down }

        /// How far the load may move from the theoretical target.
        public var bandLb: Double
        /// Denominations below this are excluded from the quantized load
        /// entirely (warmups: no change plates, ever).
        public var minimumPlateLb: Double
        public var bias: Bias

        public init(bandLb: Double, minimumPlateLb: Double, bias: Bias) {
            self.bandLb = bandLb
            self.minimumPlateLb = minimumPlateLb
            self.bias = bias
        }

        /// Working sets move at most one plate step and keep every
        /// denomination available — the goal is trading a change plate for a
        /// clean stack, not rewriting the prescription.
        public static func workingSet(bias: Bias) -> QuantizeOptions {
            QuantizeOptions(bandLb: 5, minimumPlateLb: 0, bias: bias)
        }

        /// Warmups are approximate by nature, so they get a wider band and
        /// large plates only: a ramp rung is a number you build in one grab.
        public static let warmup = QuantizeOptions(bandLb: 10, minimumPlateLb: 10, bias: .nearest)
    }

    /// Snap a theoretical target onto the nearest load a human would actually
    /// build on this rack. Ranking, in order: fewest change plates per side,
    /// then fewest plates, then fewest distinct denominations, then closest to
    /// the target (the target itself wins any exact tie).
    ///
    /// This runs at prescription materialization — after the methodology has
    /// converted capability into a number — never inside capability
    /// resolution, and the result is never written back into program cursor
    /// state: the same history must resolve identically at every gym.
    /// Mirrors web `quantizeLoad`.
    public static func quantize(
        targetLb: Double,
        bar: Bar,
        plates: [Plate],
        collarLb: Double = 0,
        options: QuantizeOptions,
        maxPerPlateSide: Int = 10
    ) -> Double {
        let collarLb = max(0, collarLb)
        // One unit system only — the bar's. A quantized load is a NUMBER the
        // lifter reads and the app stores, so a kg stack must not turn an lb
        // prescription into 211.14: mixed-unit stacks stay what they always
        // were, loading guidance produced by `solve` under the neat target.
        let sameSystem = Array(Set(plates)).filter { $0.unit == bar.unit }
        let pool = sameSystem.isEmpty ? Array(Set(plates)) : sameSystem
        let usable = pool.filter { $0.lb >= options.minimumPlateLb - 1e-9 }
            .sorted { $0.lb > $1.lb }
        guard targetLb > 0 else { return targetLb }

        let lower: Double
        let upper: Double
        switch options.bias {
        case .nearest: lower = targetLb - options.bandLb; upper = targetLb + options.bandLb
        case .up: lower = targetLb; upper = targetLb + options.bandLb
        case .down: lower = targetLb - options.bandLb; upper = targetLb
        }

        // (fiddly, used, distinct, deviation, total)
        var best: (fiddly: Int, used: Int, distinct: Int, deviation: Double, total: Double)?
        func consider(total: Double, fiddly: Int, used: Int, distinct: Int) {
            guard total >= lower - 1e-9, total <= upper + 1e-9 else { return }
            let deviation = abs(total - targetLb)
            guard let current = best else {
                best = (fiddly, used, distinct, deviation, total); return
            }
            if fiddly != current.fiddly { if fiddly < current.fiddly { best = (fiddly, used, distinct, deviation, total) }; return }
            if used != current.used { if used < current.used { best = (fiddly, used, distinct, deviation, total) }; return }
            if distinct != current.distinct { if distinct < current.distinct { best = (fiddly, used, distinct, deviation, total) }; return }
            if deviation < current.deviation - 1e-9 { best = (fiddly, used, distinct, deviation, total) }
        }

        let barTotal = bar.lb + collarLb
        consider(total: barTotal, fiddly: 0, used: 0, distinct: 0)
        // Per-side depth-first fill, pruned by the band's upper edge.
        let maxPerSide = (upper - barTotal) / 2.0
        func walk(_ index: Int, perSide: Double, fiddly: Int, used: Int, distinct: Int) {
            guard index < usable.count else { return }
            let plate = usable[index]
            walk(index + 1, perSide: perSide, fiddly: fiddly, used: used, distinct: distinct)
            guard plate.lb > 1e-9 else { return }
            var count = 0
            var side = perSide
            while count < maxPerPlateSide {
                side += plate.lb
                count += 1
                guard side <= maxPerSide + 1e-9 else { return }
                let isFiddly = plate.lb < fiddlyPlateLb - 1e-9
                let nextFiddly = fiddly + (isFiddly ? count : 0)
                consider(total: barTotal + 2 * side, fiddly: nextFiddly,
                         used: used + count, distinct: distinct + 1)
                walk(index + 1, perSide: side, fiddly: nextFiddly,
                     used: used + count, distinct: distinct + 1)
            }
        }
        walk(0, perSide: 0, fiddly: 0, used: 0, distinct: 0)
        return best?.total ?? targetLb
    }

    public static func kgTwinSideMassLb(_ sideLb: Double) -> Double? {
        guard sideLb.isFinite, sideLb >= 0 else { return nil }
        var remaining = sideLb
        var twinLb = 0.0
        for plate in [45.0, 35, 25, 10, 5, 2.5] {
            while remaining >= plate - 1e-9 {
                remaining -= plate
                guard let twin = plateTwinKg[plate] else { return nil }
                twinLb += twin * WeightUnit.lbPerKg
            }
        }
        return abs(remaining) < 1e-6 ? twinLb : nil
    }

    /// Whether `performedLb` is the plate-for-plate kg twin of the lb-clean
    /// `targetLb` — same plates, kg denominations, on the same bar or on the
    /// bar's own twin (a 45 lb bar and a 20 kg bar are the same object in the
    /// same sense the plates are). This is what makes a kg-gym session read
    /// as AT its lb plan instead of a below-plan miss that stalls the cycle.
    public static func plateEquivalent(
        targetLb: Double, performedLb: Double, barLb: Double = 45
    ) -> Bool {
        guard targetLb > barLb, performedLb > 0 else { return false }
        let side = (targetLb - barLb) / 2
        guard let twinSide = kgTwinSideMassLb(side) else { return false }
        let barTwinLb = plateTwinKg[barLb].map { $0 * WeightUnit.lbPerKg } ?? barLb
        return [barLb + 2 * twinSide, barTwinLb + 2 * twinSide]
            .contains { abs(performedLb - $0) <= 0.15 }
    }

    /// `storedPrescription`.
    public static func storedPrescription(
        targetLb: Double, achievedLb: Double, barLb: Double = 45
    ) -> Double {
        if abs(achievedLb - targetLb) <= toleranceLb + 1e-9 { return targetLb }
        // Beyond the absolute band, the denomination twin still stores the
        // canonical number: the flat 2 lb tolerance dies exactly as plates
        // stack (a four-pair side is ~7 lb adrift), which is precisely where
        // the lifter says the drift matters least. The plates are the loading
        // guidance; the number is its label.
        if plateEquivalent(targetLb: targetLb, performedLb: achievedLb, barLb: barLb) { return targetLb }
        return achievedLb
    }

    /// The canonical grid label of a PERFORMED load — the number the stack on
    /// the bar goes by, not the number its mass happens to be. A load already
    /// on the rounding grid snaps to it exactly (never returns float noise);
    /// a kg stack labels CONSTRUCTIVELY: decompose each side into kg
    /// denominations (greedy, heaviest first — the stack a lifter actually
    /// builds) and read each plate's lb twin label back off the twin table.
    /// The label can sit above the raw mass (221.4 → 225, 838.7 → 855: 20 kg
    /// pairs run light) or BELOW it (67.05 → 65: a 5 kg pair masses 22.05
    /// but reads 10 a side) — which is why this is a decomposition, not a
    /// directional search, and why it carries no window constant that a
    /// plate-table edit could silently invalidate. The same bar-or-bar-twin
    /// reading `plateEquivalent` uses applies, and every candidate must
    /// survive that same predicate, so labeling and grading can never
    /// disagree about a stack. Only when no twin label exists does it fall
    /// back to the next grid step up. Mirrored 1:1 in web/app/js/core.js
    /// `performedLabel`.
    public static func performedLabel(
        _ performedLb: Double, barLb: Double = 45,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> Double {
        guard performedLb > 0, roundingLb > 0 else { return performedLb }
        let nearest = (performedLb / roundingLb).rounded() * roundingLb
        if abs(nearest - performedLb) < 1e-6 { return nearest }
        let barTwinLb = plateTwinKg[barLb].map { $0 * WeightUnit.lbPerKg } ?? barLb
        for barMass in [barLb, barTwinLb] {
            if let side = kgSideLabelLb((performedLb - barMass) / 2) {
                let label = barLb + 2 * side
                if plateEquivalent(targetLb: label, performedLb: performedLb, barLb: barLb) {
                    return label
                }
            }
        }
        return (performedLb / roundingLb).rounded(.up) * roundingLb
    }

    /// The lb label of one side's kg stack: greedy decomposition of
    /// `sideMassLb` into kg denominations by their true masses, summed as
    /// their lb twin labels — the inverse of `kgTwinSideMassLb`. Nil when
    /// the mass is not a clean kg stack. The greedy epsilon absorbs the
    /// rounding of stored weights; the remainder bound is half of
    /// `plateEquivalent`'s total band, and the caller re-verifies through
    /// that predicate anyway.
    static func kgSideLabelLb(_ sideMassLb: Double) -> Double? {
        guard sideMassLb.isFinite, sideMassLb >= 0 else { return nil }
        var remaining = sideMassLb
        var labelLb = 0.0
        for lbLabel in [45.0, 35, 25, 10, 5, 2.5] {
            guard let kg = plateTwinKg[lbLabel] else { return nil }
            let mass = kg * WeightUnit.lbPerKg
            while remaining >= mass - 0.05 {
                remaining -= mass
                labelLb += lbLabel
            }
        }
        return abs(remaining) < 0.075 ? labelLb : nil
    }

    /// The plate inventory a lift's STATION actually stocks. A station
    /// preference filters the gym's inventory to that denomination — the
    /// deadlift platform by the window has only kg plates, the squat racks
    /// only lb — falling back to the full standard set of that denomination
    /// when the gym stocks none of it (a preference is a statement about the
    /// station, not about the gym's shopping). No preference means the gym
    /// inventory, unchanged — exactly what every lift did before stations
    /// existed. Mirrored 1:1 in web/app/js/core.js `stationPlates`.
    public static func stationPlates(
        preference: WeightUnit?, gymPlates: [Plate]
    ) -> [Plate] {
        guard let preference else { return gymPlates }
        let stocked = gymPlates.filter { $0.unit == preference }
        if !stocked.isEmpty { return stocked }
        return preference == .kg ? Plate.standardKg : Plate.standardLb
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

    /// Moves one visible reverse-mode denomination relative to the other
    /// visible rows while preserving IDs hidden by the current gym. A visible
    /// row index cannot address `storedOrder` directly after an inventory
    /// switch because the two index spaces may differ. Mirrors web
    /// `movedVisiblePlateIDs`.
    public static func movedVisiblePlateIDs(
        id: String,
        by offset: Int,
        storedOrder: [String],
        visibleOrder: [String]
    ) -> [String] {
        guard let visibleIndex = visibleOrder.firstIndex(of: id) else { return storedOrder }
        let destination = visibleIndex + offset
        guard visibleOrder.indices.contains(destination),
              let storedIndex = storedOrder.firstIndex(of: id),
              let storedDestination = storedOrder.firstIndex(of: visibleOrder[destination])
        else { return storedOrder }

        var result = storedOrder
        result.swapAt(storedIndex, storedDestination)
        return result
    }
}
