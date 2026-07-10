import XCTest
@testable import CadenceCore

final class UnitsTests: XCTestCase {

    func testConversionRoundTrip() {
        XCTAssertEqual(Weight.kg(fromLb: Weight.lb(fromKg: 42.5)), 42.5, accuracy: 1e-9)
        XCTAssertEqual(Weight.lb(fromKg: 20), 44.0924, accuracy: 0.001) // 20 kg bar
        XCTAssertEqual(Weight.kg(fromLb: 45), 20.4117, accuracy: 0.001) // 45 lb bar
    }

    func testToLbCanonicalStorage() {
        XCTAssertEqual(Weight.toLb(100, from: .lb), 100)
        XCTAssertEqual(Weight.toLb(100, from: .kg), 220.462, accuracy: 0.001)
    }

    func testTrimDropsTrailingZero() {
        XCTAssertEqual(Weight.trim(232.0), "232")
        XCTAssertEqual(Weight.trim(232.39), "232.4")
        XCTAssertEqual(Weight.trim(2.5, decimals: 2), "2.5")
        XCTAssertEqual(Weight.trim(1.25, decimals: 2), "1.25")
    }

    func testBothFormat() {
        XCTAssertEqual(Weight.both(lb: 232), "232 lb / 105.2 kg")
    }

    func testUnitDisplayModes() {
        XCTAssertEqual(UnitDisplay.lbPrimary.format(lb: 232), "232 lb")
        XCTAssertEqual(UnitDisplay.kgPrimary.format(lb: 232), "105.2 kg")
        XCTAssertEqual(UnitDisplay.both.format(lb: 232), "232 lb / 105.2 kg")
    }

    func testBarLoadableSnapsPerSideToStep() {
        // 150 on a 45 bar → 52.5/side, which needs a lonely 2.5. Snap per-side
        // to the step so it loads 45+10/side = 155.
        XCTAssertEqual(Weight.barLoadable(150, barLb: 45, stepLb: 5), 155)
        XCTAssertEqual(Weight.barLoadable(155, barLb: 45, stepLb: 5), 155) // already clean
        XCTAssertEqual(Weight.barLoadable(145, barLb: 45, stepLb: 5), 145)
        XCTAssertEqual(Weight.barLoadable(160, barLb: 45, stepLb: 5), 165)
        XCTAssertEqual(Weight.barLoadable(100, barLb: 45, stepLb: 5), 105)
        XCTAssertEqual(Weight.barLoadable(30, barLb: 45, stepLb: 5), 45) // below the bar
    }
}
