import XCTest
@testable import CadenceCore

final class PlateMathTests: XCTestCase {

    // MARK: - Exact loads

    func testExact135UsesOnePlatePerSide() {
        let s = PlateMath.solve(targetLb: 135, bar: .bar45lb, plates: Plate.standardLb)
        XCTAssertEqual(s.loadout.totalLb, 135, accuracy: 1e-9)
        XCTAssertFalse(s.isOffTarget)
        XCTAssertEqual(s.loadout.perSide.count, 1)
        XCTAssertEqual(s.loadout.perSide[0].plate, Plate(value: 45, unit: .lb))
        XCTAssertEqual(s.loadout.perSide[0].count, 1)
    }

    func testExact225() {
        let s = PlateMath.solve(targetLb: 225, bar: .bar45lb, plates: Plate.standardLb)
        XCTAssertEqual(s.loadout.totalLb, 225, accuracy: 1e-9)
        XCTAssertEqual(s.loadout.perSide, [PlateCount(plate: Plate(value: 45, unit: .lb), count: 2)])
    }

    // MARK: - kg plates against a lb target (the canonical fumble)

    func test232TargetOnKgPlates() {
        // 232 lb on a 45 lb bar with kg plates: best is 42.5 kg/side
        // (25 + 15 + 2.5) = 93.696 lb/side → 232.39 lb total.
        let s = PlateMath.solve(targetLb: 232, bar: .bar45lb, plates: Plate.standardKg)
        XCTAssertEqual(s.loadout.totalLb, 232.39, accuracy: 0.01)
        XCTAssertFalse(s.isOffTarget)
        let kgPerSide = s.loadout.perSide.reduce(0.0) { $0 + $1.plate.value * Double($1.count) }
        XCTAssertEqual(kgPerSide, 42.5, accuracy: 1e-9)
        // And the kg total reads sane for the lb-bar + kg-plates mix.
        XCTAssertEqual(Weight.kg(fromLb: s.loadout.totalLb), 105.41, accuracy: 0.01)
    }

    // MARK: - Mixed-unit loading

    func testMixedUnitsOnOneSide() {
        // Only 45 lb and 15 kg plates available. Target 200 lb:
        // per-side 77.5 → 45 lb + 15 kg (33.07 lb) = 78.07 → total 201.14, within 2 lb.
        let plates = [Plate(value: 45, unit: .lb), Plate(value: 15, unit: .kg)]
        let s = PlateMath.solve(targetLb: 200, bar: .bar45lb, plates: plates)
        XCTAssertEqual(s.loadout.totalLb, 201.14, accuracy: 0.01)
        XCTAssertFalse(s.isOffTarget)
        let units = Set(s.loadout.perSide.map(\.plate.unit))
        XCTAssertEqual(units, [.lb, .kg], "expected a mixed-unit load on the same side")
    }

    func testKgBeatsLbWhenCloser() {
        // Target 156 on 45 lb bar → 55.5/side. 25 kg = 55.12 (off 0.77 total)
        // beats 45+10 lb = 55 (off 1.0 total).
        let plates = Plate.standardLb + [Plate(value: 25, unit: .kg)]
        let s = PlateMath.solve(targetLb: 156, bar: .bar45lb, plates: plates)
        XCTAssertEqual(s.loadout.perSide, [PlateCount(plate: Plate(value: 25, unit: .kg), count: 1)])
        XCTAssertFalse(s.isOffTarget)
    }

    // MARK: - Off-target warning (> 2 lb miss)

    func testWarnsWhenInventoryCannotReachTarget() {
        // Only 45s in the gym, target 100: closest is 135 (one 45/side), 35 lb over.
        let s = PlateMath.solve(targetLb: 100, bar: .bar45lb, plates: [Plate(value: 45, unit: .lb)])
        XCTAssertEqual(s.loadout.totalLb, 135, accuracy: 1e-9)
        XCTAssertTrue(s.isOffTarget)
        XCTAssertEqual(s.deviationLb, 35, accuracy: 1e-9)
    }

    func testTargetBelowBar() {
        let s = PlateMath.solve(targetLb: 40, bar: .bar45lb, plates: Plate.standardLb)
        XCTAssertTrue(s.loadout.perSide.isEmpty)
        XCTAssertEqual(s.loadout.totalLb, 45, accuracy: 1e-9)
        XCTAssertTrue(s.isOffTarget)
    }

    func testNoWarningAtExactly2LbOff() {
        // Tolerance is "more than 2 lb": a 2.0 lb miss should NOT warn.
        let s = PlateMath.solve(targetLb: 137, bar: .bar45lb, plates: [Plate(value: 45, unit: .lb)])
        XCTAssertEqual(s.loadout.totalLb, 135, accuracy: 1e-9)
        XCTAssertFalse(s.isOffTarget)
    }

    // MARK: - Tie-breaking

    func testPrefersFewerPlatesOnEqualWeight() {
        // 95 lb: one 25/side, not 10+10+5.
        let s = PlateMath.solve(targetLb: 95, bar: .bar45lb, plates: Plate.standardLb)
        XCTAssertEqual(s.loadout.perSide, [PlateCount(plate: Plate(value: 25, unit: .lb), count: 1)])
    }

    // MARK: - Reverse mode

    func testReverseModeMixedUnits() {
        // "What did I just put on the bar?" 45 lb + 15 kg per side on a 45 bar.
        let perSide = [
            PlateCount(plate: Plate(value: 45, unit: .lb), count: 1),
            PlateCount(plate: Plate(value: 15, unit: .kg), count: 1),
        ]
        let total = PlateMath.total(bar: .bar45lb, perSide: perSide)
        XCTAssertEqual(total, 201.14, accuracy: 0.01)
        XCTAssertEqual(Weight.kg(fromLb: total), 91.23, accuracy: 0.01)
    }

    func testReverseModeBarOnly() {
        XCTAssertEqual(PlateMath.total(bar: .bar20kg, perSide: []), 44.09, accuracy: 0.01)
    }

    // MARK: - 20 kg bar

    func testKgBarKgPlates() {
        // 100 kg total on a 20 kg bar = 40 kg/side: 25 + 15. Exact.
        let target = Weight.lb(fromKg: 100)
        let s = PlateMath.solve(targetLb: target, bar: .bar20kg, plates: Plate.standardKg)
        XCTAssertEqual(s.deviationLb, 0, accuracy: 1e-9)
        let kgPerSide = s.loadout.perSide.reduce(0.0) { $0 + $1.plate.value * Double($1.count) }
        XCTAssertEqual(kgPerSide, 40, accuracy: 1e-9)
    }

    // MARK: - Bar list + id parity (mirrors web ALL_BARS / barId / barById)

    func testBarListMatchesWeb() {
        XCTAssertEqual(Bar.all.map(\.id), ["45-lb", "35-lb", "20-kg", "15-kg"])
        XCTAssertEqual(Bar.bar15kg.lb, 33.069, accuracy: 0.001)
        XCTAssertEqual(Bar.by(id: "15-kg"), .bar15kg)
        XCTAssertEqual(Bar.by(id: "nonsense"), .bar45lb, "unknown id falls back to the 45 lb bar")
        // Legacy untrimmed ids written by older builds (SwiftData gyms) must
        // still resolve — Swift-only concern; web never wrote this format.
        XCTAssertEqual(Bar.by(id: "20.0-kg"), .bar20kg)
        XCTAssertEqual(Bar.by(id: "35.0-lb"), .bar35lb)
        XCTAssertEqual(Bar.by(id: "45.0-lb"), .bar45lb)
        XCTAssertEqual(Plate(value: 45, unit: .lb).id, "45-lb")
        XCTAssertEqual(Plate(value: 2.5, unit: .lb).id, "2.5-lb")
        XCTAssertEqual(Plate(value: 1.25, unit: .kg).id, "1.25-kg")
    }

    // MARK: - Plate colours + drawn size (mirrors the web "plate colours" block)

    func testPlateColorTokens() {
        XCTAssertEqual(Plate(value: 55, unit: .lb).colorToken, "red")
        XCTAssertEqual(Plate(value: 45, unit: .lb).colorToken, "blue")
        XCTAssertEqual(Plate(value: 35, unit: .lb).colorToken, "yellow")
        XCTAssertEqual(Plate(value: 25, unit: .lb).colorToken, "green")
        XCTAssertEqual(Plate(value: 10, unit: .lb).colorToken, "white")
        XCTAssertEqual(Plate(value: 5, unit: .lb).colorToken, "black")
        XCTAssertEqual(Plate(value: 2.5, unit: .lb).colorToken, "black")
        XCTAssertEqual(Plate(value: 25, unit: .kg).colorToken, "red")
        XCTAssertEqual(Plate(value: 20, unit: .kg).colorToken, "blue")
        XCTAssertEqual(Plate(value: 15, unit: .kg).colorToken, "yellow")
        XCTAssertEqual(Plate(value: 10, unit: .kg).colorToken, "green")
        XCTAssertEqual(Plate(value: 5, unit: .kg).colorToken, "white")
        XCTAssertEqual(Plate(value: 2.5, unit: .kg).colorToken, "red")
        XCTAssertGreaterThan(Plate(value: 45, unit: .lb).sizeFactor,
                             Plate(value: 10, unit: .lb).sizeFactor,
                             "bigger plate draws taller")
    }
}
