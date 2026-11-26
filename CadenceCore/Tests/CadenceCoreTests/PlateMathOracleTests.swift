import XCTest
import CadenceCore

/// An independent brute-force oracle for `PlateMath.solve`, `solveLoad` and
/// `quantize`. Seeded random racks are small enough to enumerate EVERY
/// per-side stack; the oracle ranks them by the documented objective in exact
/// integer arithmetic and checks the solver landed on an optimum.
///
/// Public API only (no `@testable`): nothing here calls the solver's ranking,
/// greedy or search helpers, so the two cannot agree by sharing a bug. Where
/// the objective ties, any tied answer is accepted; the comparison is on the
/// objective, never on the solver's particular plate list.
///
/// The objective, restated from the documentation:
///
/// - `solve` (per-side stack, each denomination 0...maxPerPlateSide):
///   a load within `toleranceLb` (2 lb, inclusive) of the target beats any
///   load outside it. Inside the band, a stack that IS the heaviest-first
///   greedy fill of its own weight within its unit system beats one that is
///   not; then fewest plates, fewest denominations, one unit system over
///   mixed, closest, and finally under over over. Outside the band: closest,
///   then fewest plates, then under. A policy (never over, never under,
///   exact = within 0.01 lb) restricts the field when any stack satisfies it;
///   otherwise the unrestricted optimum comes back marked unsatisfied.
/// - `solveLoad`: when any stack reconstructs the load exactly (within
///   0.01 lb) the best exact stack wins and is reported as `.exact`;
///   otherwise it is `solve` under the gym's policy.
/// - `quantize`: among loads inside the band (one-sided for up/down bias),
///   built from the bar's unit system when the rack stocks it and only from
///   plates at or above the minimum: fewest change plates (< 5 lb) per side,
///   then fewest plates, fewest denominations, closest. Nothing in band
///   leaves the target untouched.
///
/// Racks stay small enough to enumerate, so the solver's 300k-node budget
/// never binds here; PlateMathTests pins the default-rack cases where it did.
final class PlateMathOracleTests: XCTestCase {

    // MARK: - solve and solveLoad

    func testSolveAndSolveLoadAreOptimalOnEveryEnumeratedRack() {
        var rng = SplitMix64(seed: 0xCADE_9CE0_0001)
        var failures = Failures()
        var seen = Coverage()

        for rackNumber in 0..<75 {
            let stacks = Stacks(Rack.random(&rng))
            for target in stacks.rack.targets(&rng, stacks: stacks) {
                let field = stacks.field(target: target)
                seen.note(field, stacks: stacks)
                failures.checkEverySolve(stacks: stacks, field: field, label: "#\(rackNumber)")
            }
        }

        failures.report()
        // Not vacuous: the scenarios must reach every rule of the objective.
        // Floors sit near half of what seed 0xCADE_9CE0_0001 actually reaches.
        seen.require(\.cleanBeatsCloser, atLeast: 200, "a clean stack beat a strictly closer one")
        seen.require(\.outOfBand, atLeast: 250, "nothing within 2 lb")
        seen.require(\.tiedOptima, atLeast: 3, "several stacks share the optimal key")
        seen.require(\.mixedOptimum, atLeast: 250, "the optimum mixes kg and lb")
        seen.require(\.noUnder, atLeast: 20, "no stack is at or under the target")
        seen.require(\.noOver, atLeast: 35, "no stack is at or over the target")
        seen.require(\.noExact, atLeast: 600, "no exact stack")
        seen.require(\.exactNotPolicyBest, atLeast: 100, "solveLoad's exact pick differs from the closest pick")
        seen.require(\.belowBar, atLeast: 20, "the target is below bar and collars")
        let floors: [Rule: Int] = [.clean: 50, .plates: 150, .denominations: 20, .oneUnit: 2, .under: 12]
        for rule in Rule.allCases {
            XCTAssertGreaterThanOrEqual(seen.decidedBy[rule.rawValue], floors[rule]!,
                                        "coverage: switching off the \(rule) rule changes an optimum")
        }
    }

    /// The one-unit rule only decides when no clean stack and no smaller
    /// stack is in band and two equally sized messy stacks differ only in
    /// unit mix: rare on random racks, so here is one built by hand. 163 on a
    /// 45 lb bar wants 59 lb/side; 35+25 lb (60, 2 lb heavy) beats the closer
    /// 25 lb + 15 kg (58.07, 1.86 lb light) because it is one unit system.
    func testOneUnitRuleDecidesAHandBuiltContest() {
        let rack = Rack(bar: .bar45lb, plates: [Plate(value: 45, unit: .lb), Plate(value: 35, unit: .lb),
                                                Plate(value: 25, unit: .lb), Plate(value: 20, unit: .kg),
                                                Plate(value: 15, unit: .kg)], cap: 2)
        XCTAssertEqual(rack.oracleSolve(163), [Plate(value: 35, unit: .lb), Plate(value: 25, unit: .lb)])
        let stacks = Stacks(rack)
        let field = stacks.field(target: Mass.of(163, .lb))
        var seen = Coverage()
        seen.note(field, stacks: stacks)
        XCTAssertEqual(seen.decidedBy[Rule.oneUnit.rawValue], 1, "the one-unit rule must be what decides here")
        var failures = Failures()
        failures.checkEverySolve(stacks: stacks, field: field, label: "hand-built")
        failures.report()
    }

    // MARK: - quantize

    func testQuantizeIsOptimalOnEveryEnumeratedRack() {
        var rng = SplitMix64(seed: 0xCADE_9CE0_0002)
        var failures = Failures()
        var nothingInBand = 0, moved = 0, tiedTotals = 0, fiddlyDecided = 0

        for rackNumber in 0..<60 {
            let rack = Rack.random(&rng)
            let stacks = Stacks(rack)
            let options: [PlateMath.QuantizeOptions] = [
                .workingSet(bias: .up), .workingSet(bias: .down), .workingSet(bias: .nearest), .warmup,
                PlateMath.QuantizeOptions(
                    bandLb: rng.pick([2.5, 5, 7.5, 10, 20]),
                    minimumPlateLb: rng.pick([0, 2.5, 5, 10, 25]),
                    bias: rng.pick([.up, .down, .nearest])),
            ]
            for target in rack.targets(&rng, stacks: stacks) where target > 0 {
                let targetLb = Mass.lb(target)
                for option in options {
                    func context() -> String { "#\(rackNumber) quantize \(Mass.text(target)) \(option.text) on \(rack)" }
                    let got = PlateMath.quantize(targetLb: targetLb, bar: rack.bar, plates: rack.input,
                                                 collarLb: rack.collarLb, options: option,
                                                 maxPerPlateSide: rack.cap)
                    guard let best = stacks.quantizeOptimum(target: target, options: option) else {
                        nothingInBand += 1
                        if got != targetLb {
                            failures.add("\(context()): nothing is in band, so the target must come back untouched; got \(got)")
                        }
                        continue
                    }
                    if best.totals.count > 1 { tiedTotals += 1 }
                    if best.decidedByPlates { fiddlyDecided += 1 }
                    guard let total = best.totals.first(where: { abs(Mass.lb($0) - got) <= 1e-6 }) else {
                        failures.add("\(context()): got \(got), optimum \(best.key) is reached only by "
                            + best.totals.map(Mass.text).joined(separator: ", "))
                        continue
                    }
                    if total != target { moved += 1 }
                }
            }
        }

        failures.report()
        // Floors sit near half of what seed 0xCADE_9CE0_0002 actually reaches.
        XCTAssertGreaterThanOrEqual(nothingInBand, 1500, "coverage: nothing in band")
        XCTAssertGreaterThanOrEqual(moved, 1500, "coverage: the quantized load moved")
        XCTAssertGreaterThanOrEqual(tiedTotals, 3, "coverage: equally good totals on both sides")
        XCTAssertGreaterThanOrEqual(fiddlyDecided, 400, "coverage: fewer plates beat a closer load")
    }

    func testQuantizeLeavesNonPositiveTargetsAlone() {
        for target in [0.0, -5] {
            XCTAssertEqual(PlateMath.quantize(targetLb: target, bar: .bar45lb, plates: Plate.standardLb,
                                              options: .warmup), target)
        }
    }

    // MARK: - The oracle reproduces the documented examples

    /// Hand-checked cases from the documentation and the existing tests,
    /// answered by the ORACLE alone. If these fail, the oracle misreads the
    /// objective and its agreement with the solver means nothing.
    func testOracleReproducesDocumentedExamples() {
        let lb = { (value: Double) in Plate(value: value, unit: .lb) }
        let kg = { (value: Double) in Plate(value: value, unit: .kg) }
        let standardLb = Rack(bar: .bar45lb, plates: Plate.standardLb, cap: 4)

        // Heaviest plates first: 105/side is 45+45+10+5, never 35×3.
        XCTAssertEqual(standardLb.oracleSolve(255), [lb(45), lb(45), lb(10), lb(5)])
        // 75/side is 45+25+5, not 25×3.
        XCTAssertEqual(standardLb.oracleSolve(195), [lb(45), lb(25), lb(5)])
        // Fewest plates among clean stacks: 95 is one 25 per side.
        XCTAssertEqual(standardLb.oracleSolve(95), [lb(25)])
        // 220 → 25+15 kg (1.37 lb heavy) over the exact 45+35+5+2.5 lb, and
        // not 2×20 kg: same mass, but not the greedy fill when 25 kg is
        // stocked. (The doc comment used to say 2×20 kg; the rule says 25+15.)
        let mixed = Rack(bar: .bar45lb, plates: [lb(45), lb(35), lb(5), lb(2.5), kg(25), kg(20), kg(15)], cap: 2)
        XCTAssertEqual(mixed.oracleSolve(220), [kg(25), kg(15)])
        // A never-under rack of 10s: the nearest valid overshoot is 65.
        let tens = Rack(bar: .bar45lb, plates: [lb(10)], cap: 10)
        XCTAssertEqual(tens.oracleSolve(50, policy: .over), [lb(10)])
        XCTAssertEqual(tens.oracleSolve(50, policy: .under), [])
        // Impossible exact policy: the unrestricted optimum (135, 2 lb heavy).
        let fives = Rack(bar: .bar45lb, plates: [lb(5)], cap: 10)
        XCTAssertEqual(fives.oracleSolve(133, policy: .exact), Array(repeating: lb(5), count: 9))

        let quantizeRack = Stacks(Rack(bar: .bar45lb, plates: Plate.standardLb, cap: 4))
        func quantized(_ target: Double, _ options: PlateMath.QuantizeOptions) -> [Double] {
            quantizeRack.quantizeOptimum(target: Mass.of(target, .lb), options: options)?.totals.map(Mass.lb) ?? []
        }
        XCTAssertEqual(quantized(260, .workingSet(bias: .up)), [265])
        XCTAssertEqual(quantized(260, .workingSet(bias: .down)), [255])
        XCTAssertEqual(quantized(130, .warmup), [135])
        XCTAssertEqual(quantized(45, .warmup), [45])
    }
}

// MARK: - Exact mass

/// 1 lb = 45_359_237_000 units and 1 kg = 10^11 units: the international
/// pound is exactly 0.45359237 kg, so every plate, bar, collar and generated
/// target expressed in thousandths of a lb or kg is an integer and the
/// objective never compares two floats.
private enum Mass {
    static let perLb = 45_359_237_000
    static let band = 2 * perLb             // PlateMath.toleranceLb
    static let exact = perLb / 100          // solveLoad / .exact: 0.01 lb
    static let changePlate = 5 * perLb      // PlateMath.fiddlyPlateLb

    static func of(_ value: Double, _ unit: WeightUnit) -> Int {
        let milli = (value * 1000).rounded()
        precondition(milli == value * 1000, "\(value) \(unit) is not exact in thousandths")
        return Int(milli) * (unit == .lb ? 45_359_237 : 100_000_000)
    }

    static func lb(_ units: Int) -> Double { Double(units) / Double(perLb) }
    static func text(_ units: Int) -> String { "\(lb(units)) lb" }
}

// MARK: - Racks

private struct Rack: CustomStringConvertible {
    let bar: Bar
    let collarLb: Double
    let collarMass: Int
    /// As handed to the solver: shuffled, sometimes with a duplicate.
    let input: [Plate]
    /// Distinct denominations, heaviest first.
    let plates: [Plate]
    let mass: [Int]
    let cap: Int

    init(bar: Bar, plates: [Plate], cap: Int, collar: (lb: Double, mass: Int) = (0, 0), input: [Plate]? = nil) {
        self.bar = bar
        self.collarLb = collar.lb
        self.collarMass = collar.mass
        self.input = input ?? plates
        let distinct = plates.reduce(into: [Plate]()) { if !$0.contains($1) { $0.append($1) } }
        let sorted = distinct.map { ($0, Mass.of($0.value, $0.unit)) }.sorted { $0.1 > $1.1 }
        self.plates = sorted.map(\.0)
        self.mass = sorted.map(\.1)
        self.cap = cap
    }

    /// Bar plus collars, exact.
    var emptyMass: Int { Mass.of(bar.value, bar.unit) + collarMass }

    var description: String {
        "\(bar.label), collars \(collarLb) lb, cap \(cap), [" + plates.map(\.label).joined(separator: ", ") + "]"
    }

    static let lbDenominations: [Double] = [55, 45, 35, 25, 15, 10, 5, 2.5, 1.25, 1, 0.5]
    static let kgDenominations: [Double] = [25, 20, 15, 10, 5, 2.5, 2, 1.5, 1.25, 1, 0.5]
    static let bars: [Bar] = Bar.all + [Bar(value: 15, unit: .lb), Bar(value: 10, unit: .kg)]

    static func random(_ rng: inout SplitMix64) -> Rack {
        // lb only, kg only, mixed, and mixed big plates only: without change
        // plates the band often holds no clean stack, which is the only place
        // the plate-count, denomination and one-unit rules get to decide.
        let kind = rng.int(0...3)
        let count = kind == 3 ? rng.int(3...4) : rng.int(1...5)
        var plates: [Plate] = []
        while plates.count < count {
            let unit: WeightUnit
            switch kind {
            case 0: unit = .lb
            case 1: unit = .kg
            default: unit = plates.count == 0 ? .lb : (plates.count == 1 ? .kg : rng.pick([.lb, .kg]))
            }
            let pool = unit == .lb ? lbDenominations : kgDenominations
            let plate = Plate(value: rng.pick(kind == 3 ? Array(pool.prefix(6)) : pool), unit: unit)
            if !plates.contains(plate) { plates.append(plate) }
        }
        // Keep (cap + 1)^n at or under 4096 so enumeration stays cheap.
        let maxCap = [10, 10, 10, 7, 4][count - 1]
        let cap = rng.int(1...maxCap)
        let collar: (lb: Double, mass: Int)
        switch rng.int(0...5) {
        case 0: collar = (2.5, Mass.of(2.5, .lb))
        case 1: collar = (5, Mass.of(5, .lb))
        case 2: collar = (Weight.lb(fromKg: 5), Mass.of(5, .kg)) // 2 × 2.5 kg competition collars
        default: collar = (0, 0)
        }
        var input = plates
        if rng.int(0...3) == 0 { input.append(rng.pick(plates)) }
        rng.shuffle(&input)
        return Rack(bar: rng.pick(bars), plates: plates, cap: cap, collar: collar, input: input)
    }

    /// Lb- and kg-grid targets, arbitrary exact masses, recorded loads (an
    /// achievable total, sometimes nudged by under 0.01 lb), and contested
    /// targets between two near stacks, where only the tie-breaks decide.
    func targets(_ rng: inout SplitMix64, stacks: Stacks) -> [Int] {
        let low = emptyMass - 6 * Mass.perLb
        let high = emptyMass + 2 * zip(mass, plates).map { $0.0 * cap }.reduce(0, +) + 12 * Mass.perLb
        var targets: [Int] = []
        for round in 0..<4 {
            targets.append(rng.int(low / (Mass.perLb / 2)...high / (Mass.perLb / 2)) * (Mass.perLb / 2))
            targets.append(rng.int(low / Mass.of(0.5, .kg)...high / Mass.of(0.5, .kg)) * Mass.of(0.5, .kg))
            targets.append(rng.int(low...high))
            let recorded = stacks.total(rng.int(0...(stacks.count - 1)))
            targets.append(recorded + (rng.int(0...2) == 0 ? 0 : rng.int(-9...9) * Mass.perLb / 1000))
            targets.append(contested(&rng, stacks: stacks, rival: .any))
            targets.append(contested(&rng, stacks: stacks, rival: round % 2 == 0 ? .sameShape : .otherUnitMix))
        }
        return targets
    }

    /// Halfway between a stack and its nearest rival (exact: both totals are
    /// bar + 2 × side), or a little toward the rival.
    private func contested(_ rng: inout SplitMix64, stacks: Stacks, rival kind: Stacks.Rival) -> Int {
        var i = rng.int(0...(stacks.count - 1))
        // The one-unit rule only ever parts two messy stacks: try to start from one.
        for _ in 0..<8 where kind == .otherUnitMix && (stacks.clean[i] || stacks.mixed[i] || stacks.distinct[i] < 2) {
            i = rng.int(0...(stacks.count - 1))
        }
        let gap = stacks.total(stacks.nearestRival(of: i, kind)) - stacks.total(i)
        return stacks.total(i) + gap / 2 + (rng.int(0...1) == 0 ? 0 : gap / 8)
    }

    /// The oracle's own answer, for checking it against hand-worked examples.
    func oracleSolve(_ targetLb: Double, policy: LoadingPolicy = .closest) -> [Plate] {
        let stacks = Stacks(self)
        let best = stacks.field(target: Mass.of(targetLb, .lb)).expected(policy, preferExact: false).best
        return stacks.counts(best.index).enumerated().flatMap { Array(repeating: plates[$0.offset], count: $0.element) }
    }
}

// MARK: - Every stack

private struct Stacks {
    let rack: Rack
    let count: Int
    private(set) var side: [Int] = []
    private(set) var used: [Int] = []
    private(set) var distinct: [Int] = []
    private(set) var mixed: [Bool] = []
    private(set) var clean: [Bool] = []
    private(set) var changePlates: [Int] = []
    private(set) var mask: [Int] = []

    init(_ rack: Rack) {
        self.rack = rack
        let n = rack.plates.count
        count = Array(repeating: rack.cap + 1, count: n).reduce(1, *)
        var counts = [Int](repeating: 0, count: n)
        for index in 0..<count {
            if index > 0 { // odometer
                var digit = 0
                while counts[digit] == rack.cap { counts[digit] = 0; digit += 1 }
                counts[digit] += 1
            }
            var sideMass = 0, plates = 0, kinds = 0, change = 0, bits = 0
            var hasLb = false, hasKg = false
            for i in 0..<n where counts[i] > 0 {
                sideMass += counts[i] * rack.mass[i]
                plates += counts[i]
                kinds += 1
                bits |= 1 << i
                if rack.plates[i].unit == .lb { hasLb = true } else { hasKg = true }
                if rack.mass[i] < Mass.changePlate { change += counts[i] }
            }
            side.append(sideMass)
            used.append(plates)
            distinct.append(kinds)
            mixed.append(hasLb && hasKg)
            let unit: WeightUnit? = hasLb ? .lb : (hasKg ? .kg : nil)
            clean.append(Self.isGreedyFill(counts, of: sideMass, in: unit, rack: rack))
            changePlates.append(change)
            mask.append(bits)
        }
    }

    /// True when `counts` is exactly what a lifter racking heaviest-first
    /// would build for this weight from this rack's plates of one unit
    /// system: as many of the biggest plate as fit (up to the cap), then the
    /// next. The empty bar counts; a mixed stack never does.
    private static func isGreedyFill(_ counts: [Int], of weight: Int, in unit: WeightUnit?, rack: Rack) -> Bool {
        guard let unit else { return true }
        if counts.indices.contains(where: { counts[$0] > 0 && rack.plates[$0].unit != unit }) { return false }
        var left = weight
        for i in rack.plates.indices where rack.plates[i].unit == unit {
            let take = min(rack.cap, left / rack.mass[i])
            if counts[i] != take { return false }
            left -= take * rack.mass[i]
        }
        return left == 0
    }

    func total(_ index: Int) -> Int { rack.emptyMass + 2 * side[index] }

    enum Rival { case any, sameShape, otherUnitMix }

    /// The other stack whose total is closest to this one's (itself if none
    /// qualifies). `sameShape` rivals share the plate and denomination
    /// counts; `otherUnitMix` ones also differ in unit mix, so only closeness
    /// and the one-unit rule can part them.
    func nearestRival(of index: Int, _ kind: Rival) -> Int {
        var rival = index, gap = Int.max
        for other in 0..<count where other != index {
            if kind != .any, used[other] != used[index] || distinct[other] != distinct[index] { continue }
            if kind == .otherUnitMix, mixed[other] == mixed[index] { continue }
            let distance = abs(side[other] - side[index])
            if distance < gap { (rival, gap) = (other, distance) }
        }
        return rival
    }

    func counts(_ index: Int) -> [Int] {
        var rest = index
        var counts: [Int] = []
        for _ in rack.plates {
            counts.append(rest % (rack.cap + 1))
            rest /= rack.cap + 1
        }
        return counts
    }

    func label(_ index: Int) -> String {
        let rows = zip(rack.plates, counts(index)).filter { $0.1 > 0 }.map { PlateCount(plate: $0.0, count: $0.1) }
        return Loadout(bar: rack.bar, perSide: rows).perSideLabel
    }

    func index(of counts: [Int]) -> Int {
        counts.reversed().reduce(0) { $0 * (rack.cap + 1) + $1 }
    }

    // MARK: solve objective

    /// The documented solve objective as a lexicographic key; smaller wins.
    func solveKey(_ index: Int, target: Int) -> Key {
        let signed = total(index) - target
        let dev = abs(signed)
        if dev <= Mass.band {
            return Key(0, clean[index] ? 0 : 1, used[index], distinct[index], mixed[index] ? 1 : 0, dev, signed)
        }
        return Key(1, dev, used[index], signed)
    }

    func field(target: Int) -> Field {
        var field = Field()
        for index in 0..<count {
            let key = solveKey(index, target: target)
            let signed = total(index) - target
            field.all.offer(key, index)
            for rule in Rule.allCases { field.without[rule.rawValue].offer(key.ignoring(rule), index) }
            if signed <= 0 { field.under.offer(key, index) }
            if signed >= 0 { field.over.offer(key, index) }
            if abs(signed) <= Mass.exact { field.exact.offer(key, index) }
            field.closestDev = min(field.closestDev, abs(signed))
        }
        field.target = target
        field.emptyMass = rack.emptyMass
        return field
    }

    // MARK: quantize objective

    struct QuantizeOptimum {
        var key: (Int, Int, Int, Int)
        /// Every total reaching the optimal key (ties on both sides of the target).
        var totals: [Int]
        /// The plate keys, not closeness, chose the load.
        var decidedByPlates: Bool
    }

    func quantizeOptimum(target: Int, options: PlateMath.QuantizeOptions) -> QuantizeOptimum? {
        guard target > 0 else { return nil }
        let band = Mass.of(options.bandLb, .lb)
        let lower = options.bias == .up ? target : target - band
        let upper = options.bias == .down ? target : target + band
        let minimum = Mass.of(options.minimumPlateLb, .lb)
        let barSystemStocked = rack.plates.contains { $0.unit == rack.bar.unit }
        var pool = 0
        for i in rack.plates.indices
        where (!barSystemStocked || rack.plates[i].unit == rack.bar.unit) && rack.mass[i] >= minimum {
            pool |= 1 << i
        }
        var best: QuantizeOptimum?
        var closest = Int.max
        for index in 0..<count where mask[index] & ~pool == 0 {
            let total = total(index)
            guard total >= lower, total <= upper else { continue }
            let key = (changePlates[index], used[index], distinct[index], abs(total - target))
            closest = min(closest, key.3)
            if best == nil || key < best!.key {
                best = QuantizeOptimum(key: key, totals: [total], decidedByPlates: false)
            } else if key == best!.key, !best!.totals.contains(total) {
                best!.totals.append(total)
            }
        }
        if let key = best?.key { best?.decidedByPlates = key.3 > closest }
        return best
    }
}

/// A lexicographic key of up to seven exact integers (fixed fields, not an
/// array: it is built a few million times per run).
private struct Key: Equatable, CustomStringConvertible {
    let a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int
    init(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int = 0, _ f: Int = 0, _ g: Int = 0) {
        (self.a, self.b, self.c, self.d, self.e, self.f, self.g) = (a, b, c, d, e, f, g)
    }

    static func < (l: Key, r: Key) -> Bool {
        if l.a != r.a { return l.a < r.a }
        if l.b != r.b { return l.b < r.b }
        if l.c != r.c { return l.c < r.c }
        if l.d != r.d { return l.d < r.d }
        if l.e != r.e { return l.e < r.e }
        if l.f != r.f { return l.f < r.f }
        return l.g < r.g
    }

    var description: String { "[\(a), \(b), \(c), \(d), \(e), \(f), \(g)]" }

    /// The solve key with one rule switched off (its field zeroed).
    func ignoring(_ rule: Rule) -> Key {
        switch (rule, a == 0) {
        case (.clean, true): return Key(a, 0, c, d, e, f, g)
        case (.plates, _): return Key(a, b, 0, d, e, f, g)
        case (.denominations, true): return Key(a, b, c, 0, e, f, g)
        case (.oneUnit, true): return Key(a, b, c, d, 0, f, g)
        case (.under, true): return Key(a, b, c, d, e, f, 0)
        case (.under, false): return Key(a, b, c, 0)
        default: return self // clean, denominations and unit only rank inside the band
        }
    }
}

/// The objective's tie-breaking rules, for proving each one decides something.
private enum Rule: Int, CaseIterable {
    case clean, plates, denominations, oneUnit, under
}

private struct Best {
    var key: Key?
    var index = -1
    var ties = 0

    mutating func offer(_ candidate: Key, _ at: Int) {
        if let key, !(candidate < key) {
            if candidate == key { ties += 1 }
            return
        }
        key = candidate
        index = at
        ties = 1
    }
}

private struct Field {
    var all = Best(), under = Best(), over = Best(), exact = Best()
    /// The same field ranked with one rule switched off, to see each rule decide.
    var without = [Best](repeating: Best(), count: Rule.allCases.count)
    var closestDev = Int.max
    var target = 0
    var emptyMass = 0

    func expected(_ policy: LoadingPolicy, preferExact: Bool) -> (best: Best, policy: LoadingPolicy, satisfies: Bool) {
        if preferExact, exact.key != nil { return (exact, .exact, true) }
        let feasible: Best
        switch policy {
        case .closest: feasible = all
        case .under: feasible = under
        case .over: feasible = over
        case .exact: feasible = exact
        }
        return feasible.key == nil ? (all, policy, false) : (feasible, policy, true)
    }
}

// MARK: - Checking and coverage

private struct Failures {
    private(set) var messages: [String] = []

    mutating func add(_ message: String) { messages.append(message) }

    /// `solve` under every policy and `solveLoad` under every gym policy.
    mutating func checkEverySolve(stacks: Stacks, field: Field, label: String) {
        let rack = stacks.rack, target = field.target
        for policy in LoadingPolicy.allCases {
            let solved = PlateMath.solve(
                targetLb: Mass.lb(target), bar: rack.bar, plates: rack.input,
                collarLb: rack.collarLb, policy: policy, maxPerPlateSide: rack.cap)
            check(solved, against: field.expected(policy, preferExact: false), stacks: stacks, target: target) {
                "\(label) solve \(policy) \(Mass.text(target)) on \(rack)"
            }
            let loaded = PlateMath.solveLoad(
                weightLb: Mass.lb(target), bar: rack.bar, plates: rack.input,
                collarLb: rack.collarLb, policy: policy, maxPerPlateSide: rack.cap)
            check(loaded, against: field.expected(policy, preferExact: true), stacks: stacks, target: target) {
                "\(label) solveLoad \(policy) \(Mass.text(target)) on \(rack)"
            }
        }
    }

    mutating func check(_ solution: PlateSolution,
                        against expected: (best: Best, policy: LoadingPolicy, satisfies: Bool),
                        stacks: Stacks, target: Int, context: () -> String) {
        let rack = stacks.rack
        var counts = [Int](repeating: 0, count: rack.plates.count)
        for row in solution.loadout.perSide {
            guard let i = rack.plates.firstIndex(of: row.plate) else {
                return add("\(context()): \(row.plate.label) is not on the rack")
            }
            guard counts[i] == 0, (1...rack.cap).contains(row.count) else {
                return add("\(context()): bad row \(row.label) (cap \(rack.cap))")
            }
            counts[i] = row.count
        }
        let index = stacks.index(of: counts)
        let got = stacks.solveKey(index, target: target)
        let want = expected.best.key!
        if solution.loadout.bar != rack.bar || abs(solution.loadout.collarLb - rack.collarLb) > 1e-12 {
            add("\(context()): bar or collars changed")
        }
        if abs(solution.loadout.totalLb - Mass.lb(stacks.total(index))) > 1e-6 {
            add("\(context()): totalLb \(solution.loadout.totalLb) does not match the stack")
        }
        if solution.targetLb != Mass.lb(target) { add("\(context()): targetLb changed") }
        if got != want {
            let optimum = stacks.label(expected.best.index)
            let wantTotal = Mass.text(stacks.total(expected.best.index))
            add("\(context()): got \(solution.loadout.perSideLabel) = \(Mass.text(stacks.total(index))) key \(got); "
                + "optimum \(optimum) = \(wantTotal) key \(want)")
        }
        if solution.policy != expected.policy || solution.satisfiesPolicy != expected.satisfies {
            add("\(context()): policy \(solution.policy)/\(solution.satisfiesPolicy), "
                + "expected \(expected.policy)/\(expected.satisfies)")
        }
    }

    func report(file: StaticString = #filePath, line: UInt = #line) {
        for message in messages.prefix(15) { XCTFail(message, file: file, line: line) }
        XCTAssertEqual(messages.count, 0, "oracle disagreements (first 15 shown)", file: file, line: line)
    }
}

private struct Coverage {
    var cleanBeatsCloser = 0, outOfBand = 0, tiedOptima = 0, mixedOptimum = 0
    var noUnder = 0, noOver = 0, noExact = 0, exactNotPolicyBest = 0, belowBar = 0
    /// Optima that change when the rule is switched off, per Rule.
    var decidedBy = [Int](repeating: 0, count: Rule.allCases.count)

    mutating func note(_ field: Field, stacks: Stacks) {
        let best = field.all
        guard let key = best.key else { return }
        if key.a == 0, field.closestDev < abs(stacks.total(best.index) - field.target) { cleanBeatsCloser += 1 }
        if key.a == 1 { outOfBand += 1 }
        if best.ties > 1 { tiedOptima += 1 }
        for rule in Rule.allCases {
            let without = field.without[rule.rawValue]
            if without.key != key.ignoring(rule) || without.ties != best.ties { decidedBy[rule.rawValue] += 1 }
        }
        if stacks.mixed[best.index] { mixedOptimum += 1 }
        if field.under.key == nil { noUnder += 1 }
        if field.over.key == nil { noOver += 1 }
        if field.exact.key == nil { noExact += 1 }
        if field.exact.key != nil, field.exact.key != key { exactNotPolicyBest += 1 }
        if field.target < field.emptyMass { belowBar += 1 }
    }

    func require(_ path: KeyPath<Coverage, Int>, atLeast minimum: Int, _ what: String,
                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(self[keyPath: path], minimum, "coverage: \(what)", file: file, line: line)
    }
}

// MARK: - Deterministic randomness

/// SplitMix64: a fixed seed gives the same racks and targets on every
/// platform and every run. No flakiness, no system RNG.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }

    mutating func pick<T>(_ options: [T]) -> T { options[int(0...(options.count - 1))] }

    mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) { items.swapAt(i, int(0...i)) }
    }
}

private extension PlateMath.QuantizeOptions {
    var text: String { "band \(bandLb) min \(minimumPlateLb) \(bias)" }
}
