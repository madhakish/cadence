import XCTest
@testable import CadenceCore

/// Epic #155 Stage 3: load quantization at prescription materialization.
/// Mirrored 1:1 by web/tests/core.test.mjs "quantizeLoad" — same fixtures,
/// same expectations.
final class PlateQuantizeTests: XCTestCase {
    private let plates = Plate.standardLb
    private let bar = Bar.bar45lb

    private func quantize(_ target: Double, _ options: PlateMath.QuantizeOptions) -> Double {
        PlateMath.quantize(targetLb: target, bar: bar, plates: plates, options: options)
    }

    func testWorkingSetTradesAFiddlyPlateForACleanNeighbour() {
        // 260 = 45+45+10+5+2.5 per side. 265 = 45+45+10+10: same plate count,
        // no change plate. Progressing, so the swap goes up.
        XCTAssertEqual(quantize(260, .workingSet(bias: .up)), 265)
        // Backing off resolves the other way: 255 = 45+45+10+5.
        XCTAssertEqual(quantize(260, .workingSet(bias: .down)), 255)
    }

    func testAlreadyCleanTargetsAreLeftAlone() {
        for clean in [135.0, 225.0, 315.0, 405.0] {
            XCTAssertEqual(quantize(clean, .workingSet(bias: .up)), clean,
                           "\(clean) already loads clean and must not move")
        }
    }

    func testBiasIsAHardConstraintSoProgressNeverStalls() {
        // 225 is prettier than 230, but a progressing lifter must never be
        // quantized back onto the load they just left.
        XCTAssertGreaterThanOrEqual(quantize(230, .workingSet(bias: .up)), 230)
        XCTAssertLessThanOrEqual(quantize(230, .workingSet(bias: .down)), 230)
    }

    func testWarmupsSnapToLargePlateLoads() {
        // Nobody builds a 130 lb warmup (42.5/side = 25+10+5+2.5).
        XCTAssertEqual(quantize(130, .warmup), 135)
        XCTAssertEqual(quantize(128, .warmup), 135)
        // The empty bar stays available as the lightest rung.
        XCTAssertEqual(quantize(45, .warmup), 45)
    }

    func testNothingInBandLeavesTheTargetUntouched() {
        // A kg-only rack can't build 137 lb near enough; the caller's own
        // plate solve still explains the real stack.
        XCTAssertEqual(
            PlateMath.quantize(targetLb: 137, bar: bar, plates: [], options: .workingSet(bias: .up)),
            137
        )
    }

    func testQuantizationNeverInventsAnUnloadableNumber() {
        // Property: every quantized load is exactly achievable on the rack.
        for target in stride(from: 95.0, through: 405.0, by: 2.5) {
            for options in [PlateMath.QuantizeOptions.workingSet(bias: .up),
                            .workingSet(bias: .down), .warmup] {
                let quantized = quantize(target, options)
                let solved = PlateMath.solve(targetLb: quantized, bar: bar, plates: plates)
                XCTAssertEqual(solved.loadout.totalLb, quantized, accuracy: 1e-6,
                               "\(target) quantized to an unloadable \(quantized)")
            }
        }
    }

    func testQuantizationStaysWithinItsBand() {
        for target in stride(from: 95.0, through: 405.0, by: 2.5) {
            let up = quantize(target, .workingSet(bias: .up))
            XCTAssertLessThanOrEqual(abs(up - target), PlateMath.QuantizeOptions.workingSet(bias: .up).bandLb + 1e-9)
        }
    }
}
