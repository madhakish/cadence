import XCTest
@testable import CadenceCore

final class PlateMathTests: XCTestCase {

    // The kg↔lb denomination twins: the plate is the currency, the number is
    // its label. Mirrors web/tests/core.test.mjs — same stacks, same masses.
    // [INV-PLATES-ARE-THE-CURRENCY]
    func testDenominationTwins() {
        let kg20 = 20 * WeightUnit.lbPerKg
        XCTAssertEqual(PlateMath.kgTwinSideMassLb(90) ?? 0, 2 * kg20, accuracy: 1e-6,
                       "90/side is two 45s, twinned to two 20 kg")
        XCTAssertNil(PlateMath.kgTwinSideMassLb(91), "a non-stack side has no twin")
        XCTAssertNil(PlateMath.kgTwinSideMassLb(.infinity),
                     "a non-finite side refuses instead of looping the greedy solver")
        XCTAssertNil(PlateMath.kgTwinSideMassLb(.nan))
        XCTAssertFalse(PlateMath.plateEquivalent(targetLb: .infinity, performedLb: 221.37),
                       "a non-finite target cannot claim equivalence")

        XCTAssertTrue(PlateMath.plateEquivalent(targetLb: 225, performedLb: 221.37),
                      "the kg stack IS the 225 plan")
        XCTAssertTrue(PlateMath.plateEquivalent(targetLb: 225, performedLb: kg20 + 4 * kg20),
                      "a 20 kg bar twins the 45 the same way the plates do")
        XCTAssertFalse(PlateMath.plateEquivalent(targetLb: 215, performedLb: 221.37),
                       "an overshoot is not an equivalence")
        let heavyTwin = 45 + 8 * kg20
        XCTAssertTrue(PlateMath.plateEquivalent(targetLb: 405, performedLb: heavyTwin),
                      "a four-pair side twins despite ~7 lb of drift")

        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 405, achievedLb: heavyTwin), 405,
                       "the twin stores the programmed number, not the drift")

        // The bar's denomination label, not its converted mass, is what the
        // twin maths against — and threading it is what lets a 35-class plan
        // twin at all (the default 45 reads its side stacks wrong).
        XCTAssertEqual(Bar.bar35lb.labelLb, 35)
        XCTAssertEqual(Bar.bar20kg.labelLb, 45, "a 20 kg bar labels under the 45")
        XCTAssertEqual(Bar.bar15kg.labelLb, 35, "a 15 kg bar labels under the 35")
        let thirtyFiveTwin = 35 + 8 * kg20
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 395, achievedLb: thirtyFiveTwin, barLb: 35), 395,
                       "a 35-bar plan twins when its own bar is threaded through")
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 395, achievedLb: thirtyFiveTwin), thirtyFiveTwin,
                       "without the bar the decomposition is wrong and the achieved load stays")
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 405, achievedLb: 380), 380,
                       "a non-twin unreachable target still stores what the rack can do")
        // [INV-LOAD-STORED-NEAT] the absolute band is untouched underneath.
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 220, achievedLb: 221.37), 220)
    }


    // A station preference filters the gym inventory to its own denomination,
    // falling back to that denomination's full standard set when the gym
    // stocks none of it; no preference is the gym inventory unchanged.
    // Mirrored in web/tests/core.test.mjs. [INV-STATION-OWNS-ITS-PLATES]
    func testStationPlates() {
        let mixed = Plate.allStandard
        XCTAssertEqual(PlateMath.stationPlates(preference: nil, gymPlates: mixed), mixed,
                       "no preference is the gym inventory, exactly as before stations existed")
        XCTAssertEqual(PlateMath.stationPlates(preference: .kg, gymPlates: mixed),
                       mixed.filter { $0.unit == .kg },
                       "the kg station sees only the gym's kg plates")
        XCTAssertEqual(PlateMath.stationPlates(preference: .lb, gymPlates: mixed),
                       mixed.filter { $0.unit == .lb })
        XCTAssertEqual(PlateMath.stationPlates(preference: .kg, gymPlates: Plate.standardLb),
                       Plate.standardKg,
                       "a kg station in an lb-stocked gym is a statement about the station — standard kg")
        // The motivating rack: the kg deadlift station prescribes the twin
        // stack natively, and the twin math stores the canonical number.
        let solved = PlateMath.solve(
            targetLb: 235,
            bar: .bar45lb,
            plates: PlateMath.stationPlates(preference: .kg, gymPlates: Plate.allStandard)
        )
        XCTAssertTrue(solved.loadout.perSide.allSatisfy { $0.plate.unit == .kg },
                      "every prescribed plate is a kg plate")
    }

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
        // (25 + 15 + 2.5, heaviest first) = 93.696 lb/side → 232.39 lb total.
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

    // MARK: - Realistic loading (heaviest plates first, clean stack over exact-to-the-pound)

    func testRoundsToCleanHeaviestFirstStack() {
        // 220 on a 45 lb bar: 25 + 15 kg per side (~221.4 lb), competition
        // style — heaviest plate first — NOT the exact-but-awful
        // 45 + 35 + 5 + 2.5 lb. Within the 2 lb band, the greedy stack of a
        // single unit system wins.
        let s = PlateMath.solve(targetLb: 220, bar: .bar45lb, plates: Plate.allStandard)
        XCTAssertEqual(s.loadout.perSide, [PlateCount(plate: Plate(value: 25, unit: .kg), count: 1),
                                           PlateCount(plate: Plate(value: 15, unit: .kg), count: 1)])
        XCTAssertFalse(s.isOffTarget)
        XCTAssertEqual(Set(s.loadout.perSide.map(\.plate.unit)).count, 1, "no kg+lb frankenstack")
    }

    func testHeaviestFirstBeatsFewestPlates() {
        // 255: per-side 105 = 45+45+10+5, never 35×3 — equal weight and fewer
        // plates, but nobody skips the 45s.
        let s = PlateMath.solve(targetLb: 255, bar: .bar45lb, plates: Plate.standardLb)
        XCTAssertEqual(s.loadout.perSide, [PlateCount(plate: Plate(value: 45, unit: .lb), count: 2),
                                           PlateCount(plate: Plate(value: 10, unit: .lb), count: 1),
                                           PlateCount(plate: Plate(value: 5, unit: .lb), count: 1)])
        XCTAssertEqual(s.deviationLb, 0, accuracy: 1e-9)
    }

    func testHeaviestFirstMidWeight() {
        // 195: per-side 75 = 45+25+5, not 25×3.
        let s = PlateMath.solve(targetLb: 195, bar: .bar45lb, plates: Plate.standardLb)
        XCTAssertEqual(s.loadout.perSide, [PlateCount(plate: Plate(value: 45, unit: .lb), count: 1),
                                           PlateCount(plate: Plate(value: 25, unit: .lb), count: 1),
                                           PlateCount(plate: Plate(value: 5, unit: .lb), count: 1)])
        XCTAssertEqual(s.deviationLb, 0, accuracy: 1e-9)
    }

    func testNoFrankenstackAcrossUnits() {
        // With the full mixed inventory, a mid load still picks one unit rather
        // than intermixing kg and lb change plates to nail an exact number.
        let s = PlateMath.solve(targetLb: 315, bar: .bar45lb, plates: Plate.allStandard)
        XCTAssertEqual(s.loadout.perSide, [PlateCount(plate: Plate(value: 45, unit: .lb), count: 3)])
        XCTAssertEqual(Set(s.loadout.perSide.map(\.plate.unit)).count, 1)
    }

    func testHeavyLoadReachesCleanStackDespiteNodeCap() {
        // 405 on a 45 lb bar is exactly 45×4/side. The greedy single-unit seed
        // guarantees that clean stack even though a naive branch-and-bound would
        // exhaust its node budget in the 25 kg-heavy branches first and settle
        // for a kg+lb frankenstack (25 kg×2 + 35 lb×2).
        let s = PlateMath.solve(targetLb: 405, bar: .bar45lb, plates: Plate.allStandard)
        XCTAssertEqual(s.loadout.perSide, [PlateCount(plate: Plate(value: 45, unit: .lb), count: 4)])
        XCTAssertEqual(s.deviationLb, 0, accuracy: 1e-9)
        XCTAssertEqual(Set(s.loadout.perSide.map(\.plate.unit)).count, 1)
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

    func testCollarsCountTowardAchievedWeight() {
        let s = PlateMath.solve(targetLb: 140, bar: .bar45lb, plates: Plate.standardLb, collarLb: 5)
        XCTAssertEqual(s.loadout.totalLb, 140, accuracy: 1e-9)
        XCTAssertEqual(s.loadout.collarLb, 5, accuracy: 1e-9)
        XCTAssertEqual(PlateMath.total(bar: .bar45lb, perSide: s.loadout.perSide, collarLb: 5), 140, accuracy: 1e-9)
    }

    func testDirectionalLoadingPolicies() {
        let plates = [Plate(value: 5, unit: .lb)]
        let under = PlateMath.solve(targetLb: 133, bar: .bar45lb, plates: plates, policy: .under)
        let over = PlateMath.solve(targetLb: 133, bar: .bar45lb, plates: plates, policy: .over)
        XCTAssertLessThanOrEqual(under.loadout.totalLb, 133)
        XCTAssertGreaterThanOrEqual(over.loadout.totalLb, 133)
        XCTAssertTrue(under.satisfiesPolicy)
        XCTAssertTrue(over.satisfiesPolicy)
    }

    func testPrescriptionTieBreakAndAlternatives() throws {
        let plates = [Plate(value: 45, unit: .lb), Plate(value: 25, unit: .lb), Plate(value: 5, unit: .lb)]
        let volume = PlateMath.prescriptionOptions(
            targetLb: 200, bar: .bar45lb, plates: plates, preferOverOnTie: true
        )
        XCTAssertEqual(volume.selected.loadout.totalLb, 205)
        XCTAssertEqual(try XCTUnwrap(volume.below).loadout.totalLb, 195)
        XCTAssertEqual(try XCTUnwrap(volume.above).loadout.totalLb, 205)

        let peak = PlateMath.prescriptionOptions(
            targetLb: 200, bar: .bar45lb, plates: plates, preferOverOnTie: false
        )
        XCTAssertEqual(peak.selected.loadout.totalLb, 195)
    }

    func testExplicitGymPolicyOverridesPrescriptionTieBreak() {
        let plates = [Plate(value: 45, unit: .lb), Plate(value: 25, unit: .lb), Plate(value: 5, unit: .lb)]
        let neverOver = PlateMath.prescriptionOptions(
            targetLb: 200, bar: .bar45lb, plates: plates,
            policy: .under, preferOverOnTie: true
        )
        XCTAssertEqual(neverOver.selected.loadout.totalLb, 195)
    }

    func testNeverUnderSearchFindsDistantValidOvershoot() {
        let s = PlateMath.solve(targetLb: 50, bar: .bar45lb,
                                plates: [Plate(value: 10, unit: .lb)], policy: .over)
        XCTAssertEqual(s.loadout.totalLb, 65, accuracy: 1e-9)
        XCTAssertTrue(s.satisfiesPolicy)
    }

    func testImpossibleExactPolicyReturnsClosestWithWarning() {
        let s = PlateMath.solve(targetLb: 133, bar: .bar45lb,
                                plates: [Plate(value: 5, unit: .lb)], policy: .exact)
        XCTAssertFalse(s.satisfiesPolicy)
        XCTAssertEqual(s.loadout.totalLb, 135, accuracy: 1e-9)
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
        XCTAssertEqual(Plate(value: 2.5, unit: .kg).colorToken(for: .steel), "black")
        XCTAssertEqual(Plate(value: 20, unit: .kg).diameterFactor(for: .bumper), 1)
        XCTAssertEqual(Plate(value: 10, unit: .kg).diameterFactor(for: .bumper), 1)
        XCTAssertGreaterThan(Plate(value: 20, unit: .kg).diameterFactor(for: .steel),
                             Plate(value: 10, unit: .kg).diameterFactor(for: .steel),
                             "calibrated steel diameter steps down by denomination")
        XCTAssertGreaterThan(Plate(value: 20, unit: .kg).thicknessFactor(for: .bumper),
                             Plate(value: 20, unit: .kg).thicknessFactor(for: .steel),
                             "rubber bumpers consume more sleeve than calibrated steel")
    }

    // [INV-LOAD-STORED-NEAT]
    func testStoredPrescriptionKeepsTheProgrammedNumberInsideTheBand() {
        // A 10 kg pair on a 90 lb warmup loads 89.1 — guidance, not a new
        // prescription. The card keeps saying 90.
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 90, achievedLb: 89.1), 90)
        // The kg "clean stack" for 220 loads 221.4 — the card keeps 220.
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 220, achievedLb: 221.37), 220)
        // Exactly loadable targets pass straight through.
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 155, achievedLb: 155), 155)
        // A genuinely unreachable target stores the honest achieved load.
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 90, achievedLb: 85), 85)
        XCTAssertEqual(PlateMath.storedPrescription(targetLb: 50, achievedLb: 65), 65)
    }

    // The canonical grid label a performed stack goes by — twin-aware, never
    // understating the work. Mirrored in web/tests/core.test.mjs.
    // [INV-ADVANCE-BUYS-PLATES]
    func testPerformedLabelNamesTheStack() {
        XCTAssertEqual(PlateMath.performedLabel(221.37), 225,
                       "2×20 kg a side on a 45 bar goes by 225")
        XCTAssertEqual(PlateMath.performedLabel(232.39), 235,
                       "20+20+2.5 kg a side goes by 235")
        XCTAssertEqual(PlateMath.performedLabel(226.87), 230,
                       "20+20+1.25 kg a side goes by 230")
        XCTAssertEqual(PlateMath.performedLabel(397.74), 405,
                       "four 20 kg pairs drift past one grid step and still find their 405 label")
        XCTAssertEqual(PlateMath.performedLabel(838.66), 855,
                       "nine 20 kg pairs drift three grid steps up and still find their label")
        XCTAssertEqual(PlateMath.performedLabel(67.05), 65,
                       "a 5 kg pair outweighs its 10-a-side label — the true label sits BELOW the raw mass")
        XCTAssertEqual(PlateMath.performedLabel(225), 225,
                       "a grid-clean load is its own label")
        XCTAssertEqual(PlateMath.performedLabel(223), 225,
                       "no twin label → the next grid step up, never understating")
        XCTAssertEqual(PlateMath.performedLabel(0), 0, "no load, no label")
    }
}
