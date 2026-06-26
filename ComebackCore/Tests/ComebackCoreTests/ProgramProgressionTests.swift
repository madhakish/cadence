import XCTest
@testable import ComebackCore

/// Mirrors the adaptive-progression block in web/tests/core.test.mjs — keep the
/// two in lockstep (same cases, same expected numbers).
final class ProgramProgressionTests: XCTestCase {
    typealias P = ProgramProgression

    private func cleanPerf() -> CycleLiftPerformance {
        CycleLiftPerformance(prescribedSets: 3, prescribedReps: 3, completedSets: 3, anyStoppedEarly: false,
                             anyDroppedLoad: false, grindyOrWobbleSets: 0, topSetWeightLb: 206, topSetReps: 3)
    }
    private func liftState() -> ProgramLiftState {
        ProgramLiftState(baseWeightLb: 175, estimatedMaxLb: 226, stallCount: 0, role: .main, lastIncrementLb: 0)
    }

    func testE1RMMath() {
        XCTAssertEqual(P.epleyE1RM(weightLb: 225, reps: 5), 262.5, accuracy: 1e-9)
        XCTAssertEqual(P.smoothE1RM(prior: 0, sample: 262.5), 262.5, accuracy: 1e-9)
        XCTAssertEqual(P.smoothE1RM(prior: 200, sample: 300), 230, accuracy: 1e-9)
    }

    func testGrading() {
        XCTAssertEqual(P.gradeCycle(cleanPerf()), .success)
        var p = cleanPerf(); p.grindyOrWobbleSets = 1
        XCTAssertEqual(P.gradeCycle(p), .success, "exactly the tolerance is still success")
        p.grindyOrWobbleSets = 2
        XCTAssertEqual(P.gradeCycle(p), .hold)
        p = cleanPerf(); p.completedSets = 2
        XCTAssertEqual(P.gradeCycle(p), .fail)
        p = cleanPerf(); p.anyStoppedEarly = true
        XCTAssertEqual(P.gradeCycle(p), .fail)
        p = cleanPerf(); p.anyDroppedLoad = true
        XCTAssertEqual(P.gradeCycle(p), .fail)
    }

    func testCleanCycleAddsTaperedIncrement() {
        let r = P.advanceCycleLift(liftState(), perf: cleanPerf(), focus: .strength, roundingLb: 5)
        XCTAssertEqual(r.grade, .success)
        XCTAssertEqual(r.state.baseWeightLb, 180, accuracy: 1e-9)
        XCTAssertEqual(r.state.stallCount, 0)
        XCTAssertEqual(r.state.lastIncrementLb, 5, accuracy: 1e-9)
    }

    func testGrindyHolds() {
        var p = cleanPerf(); p.grindyOrWobbleSets = 3
        let r = P.advanceCycleLift(liftState(), perf: p, focus: .strength, roundingLb: 5)
        XCTAssertEqual(r.grade, .hold)
        XCTAssertEqual(r.state.baseWeightLb, 175, accuracy: 1e-9)
        XCTAssertEqual(r.state.stallCount, 1)
    }

    func testTwoStallsAutoDeload() {
        var grindy = cleanPerf(); grindy.grindyOrWobbleSets = 3
        let s1 = P.advanceCycleLift(liftState(), perf: grindy, focus: .strength, roundingLb: 5).state
        var missed = cleanPerf(); missed.completedSets = 1
        let s2 = P.advanceCycleLift(s1, perf: missed, focus: .strength, roundingLb: 5)
        XCTAssertEqual(s2.state.baseWeightLb, 160, accuracy: 1e-9, "175 → −10% → 160")
        XCTAssertEqual(s2.state.stallCount, 0)
        XCTAssertTrue((s2.note ?? "").contains("deloaded"))
    }

    func testTaperShrinksTowardCeiling() {
        XCTAssertEqual(P.taperedIncrement(baseWeightLb: 150, estimatedMaxLb: 226, focus: .strength, roundingLb: 5), 5, accuracy: 1e-9)
        XCTAssertEqual(P.taperedIncrement(baseWeightLb: 200, estimatedMaxLb: 226, focus: .strength, roundingLb: 5), 0, accuracy: 1e-9)
        XCTAssertEqual(P.taperedIncrement(baseWeightLb: 210, estimatedMaxLb: 226, focus: .strength, roundingLb: 5), 0, accuracy: 1e-9)
    }

    func testMaintainNeverIncrements() {
        let r = P.advanceCycleLift(liftState(), perf: cleanPerf(), focus: .maintain, roundingLb: 5)
        XCTAssertEqual(r.state.baseWeightLb, 175, accuracy: 1e-9)
        XCTAssertEqual(r.state.stallCount, 0)
    }

    func testAccessoryDoubleProgression() {
        let acc = AccessoryState(sets: 3, minReps: 8, maxReps: 12, currentReps: 12, weightLb: 50, incrementLb: 5)
        let a = P.advanceAccessory(acc, perf: AccessoryPerformance(completedSets: 3, minRepsAchieved: 12, anyStoppedEarly: false))
        XCTAssertEqual(a.weightLb, 55, accuracy: 1e-9)
        XCTAssertEqual(a.currentReps, 8)

        var below = acc; below.currentReps = 10
        let b = P.advanceAccessory(below, perf: AccessoryPerformance(completedSets: 3, minRepsAchieved: 10, anyStoppedEarly: false))
        XCTAssertEqual(b.weightLb, 50, accuracy: 1e-9)
        XCTAssertEqual(b.currentReps, 11)

        let c = P.advanceAccessory(below, perf: AccessoryPerformance(completedSets: 2, minRepsAchieved: 10, anyStoppedEarly: false))
        XCTAssertEqual(c.weightLb, 50, accuracy: 1e-9)
        XCTAssertEqual(c.currentReps, 10)
        XCTAssertEqual(c.stallCount, 1)
    }
}
