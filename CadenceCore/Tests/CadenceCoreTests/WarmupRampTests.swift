import XCTest
@testable import CadenceCore

final class WarmupRampTests: XCTestCase {

    func testRampFor245() {
        // bar×10 then ~40/55/70/85%: 100×5, 135×3, 170×2, 210×1.
        let ramp = WarmupRamp.ramp(workingLb: 245)
        XCTAssertEqual(ramp.map(\.weightLb), [45, 100, 135, 170, 210])
        XCTAssertEqual(ramp.map(\.reps), [10, 5, 3, 2, 1])
    }

    func testLightWorkingWeightSkipsSubBarSteps() {
        // Working 65: only the 85% step (55) clears the bar.
        let ramp = WarmupRamp.ramp(workingLb: 65)
        XCTAssertEqual(ramp.map(\.weightLb), [45, 55])
    }

    func testBarWeightWorkIsJustTheBar() {
        let ramp = WarmupRamp.ramp(workingLb: 45)
        XCTAssertEqual(ramp.map(\.weightLb), [45])
        XCTAssertEqual(ramp[0].reps, 10)
    }

    func testRampCanOmitTheEmptyBarOpener() {
        let ramp = WarmupRamp.ramp(workingLb: 245, includeEmptyBar: false)
        XCTAssertEqual(ramp.map(\.weightLb), [100, 135, 170, 210])
        XCTAssertEqual(ramp.map(\.reps), [5, 3, 2, 1])
    }

    func testRampNeverReachesWorkingWeight() {
        for working in stride(from: 50.0, through: 500.0, by: 7.5) {
            for set in WarmupRamp.ramp(workingLb: working).dropFirst() {
                XCTAssertLessThan(set.weightLb, working)
            }
        }
    }

    // Work already completed this session trims the climb below it (issue #64).

    func testPriorWorkTrimsTheStepsAlreadyClimbed() {
        // Working 225: bar, 90, 125, 160, 190. With 100 already lifted this
        // session the bar and 90 are a climb already made.
        XCTAssertEqual(WarmupRamp.ramp(workingLb: 225, priorWorkLb: 100).map(\.weightLb), [125, 160, 190])
        XCTAssertEqual(WarmupRamp.ramp(workingLb: 225, priorWorkLb: 100).map(\.reps), [3, 2, 1])
        // At or below: a step equal to the prior work is dropped too.
        XCTAssertEqual(WarmupRamp.ramp(workingLb: 225, priorWorkLb: 125).map(\.weightLb), [160, 190])
    }

    func testPriorWorkAboveEveryStepKeepsTheHeaviestTwo() {
        // 315 already lifted: nothing in the 225 ramp clears it, so the two
        // bridging sets remain rather than an empty ramp.
        let ramp = WarmupRamp.ramp(workingLb: 225, priorWorkLb: 315)
        XCTAssertEqual(ramp.map(\.weightLb), [160, 190])
        XCTAssertEqual(ramp.map(\.reps), [2, 1])
    }

    func testNoPriorWorkLeavesTheRampAlone() {
        let full = WarmupRamp.ramp(workingLb: 225)
        XCTAssertEqual(full.map(\.weightLb), [45, 90, 125, 160, 190])
        XCTAssertEqual(WarmupRamp.ramp(workingLb: 225, priorWorkLb: nil), full)
        XCTAssertEqual(WarmupRamp.ramp(workingLb: 225, priorWorkLb: 0), full)
    }

    func testPriorWorkCountsOnlyEarlierSameGroupSameImplementCompletedWork() {
        let session: [WarmupRamp.SessionWork] = [
            .init(order: 0, movementGroup: "squat", exerciseType: "barbell", completedWorkLbs: [225, 225, 245]),
            .init(order: 1, movementGroup: "squat", exerciseType: "dumbbell", completedWorkLbs: [80]),
            .init(order: 2, movementGroup: "hinge", exerciseType: "barbell", completedWorkLbs: [405]),
            .init(order: 3, movementGroup: "squat", exerciseType: "barbell", completedWorkLbs: []),
            .init(order: 5, movementGroup: "squat", exerciseType: "barbell", completedWorkLbs: [315]),
        ]
        // Earlier same-group barbell work counts; the later 315 does not.
        XCTAssertEqual(WarmupRamp.priorWorkLb(order: 4, movementGroup: "squat", exerciseType: "barbell", in: session), 245)
        // A dumbbell's per-hand load only counts for a dumbbell lift.
        XCTAssertEqual(WarmupRamp.priorWorkLb(order: 4, movementGroup: "squat", exerciseType: "dumbbell", in: session), 80)
        // Another group, an unknown group, or nothing earlier: nil.
        XCTAssertNil(WarmupRamp.priorWorkLb(order: 4, movementGroup: "press", exerciseType: "barbell", in: session))
        XCTAssertNil(WarmupRamp.priorWorkLb(order: 4, movementGroup: "", exerciseType: "barbell", in: session))
        XCTAssertNil(WarmupRamp.priorWorkLb(order: 0, movementGroup: "squat", exerciseType: "barbell", in: session))
        // An earlier entry with nothing completed yet prepared nobody.
        XCTAssertNil(WarmupRamp.priorWorkLb(
            order: 4, movementGroup: "squat", exerciseType: "barbell",
            in: [.init(order: 3, movementGroup: "squat", exerciseType: "barbell", completedWorkLbs: [])]
        ))
    }
}
