import XCTest
@testable import CadenceCore

final class ProgramEngineTests: XCTestCase {

    // Fictional state-machine examples; fresh installs carry no progression.

    func testDeadliftPeakSuggestion() {
        // A lift completed Load → next is Peak 3×3 around 245-250.
        let state = CycleState(cycleNumber: 1, baseWeightLb: 210, nextPhase: .peak, incrementLb: 10)
        let plan = ProgramEngine.plan(for: state)
        XCTAssertEqual(plan.weightLb, 245)
        XCTAssertEqual(plan.sets, 3)
        XCTAssertEqual(plan.reps, 3)
        XCTAssertEqual(plan.phase, .peak)
    }

    func testSquatLoadSuggestion() {
        // A lift completed Volume at 175 → next is Load 5×3 around 190-195.
        let state = CycleState(cycleNumber: 1, baseWeightLb: 175, nextPhase: .load, incrementLb: 10)
        let plan = ProgramEngine.plan(for: state)
        XCTAssertEqual(plan.weightLb, 195)
        XCTAssertEqual(plan.sets, 5)
        XCTAssertEqual(plan.reps, 3)
    }

    func testVolumeWeekIsBaseWeight() {
        let state = CycleState(baseWeightLb: 210, nextPhase: .volume)
        let plan = ProgramEngine.plan(for: state)
        XCTAssertEqual(plan.weightLb, 210)
        XCTAssertEqual(plan.sets, 5)
        XCTAssertEqual(plan.reps, 5)
    }

    func testDeloadLandsIn75To80PercentBand() {
        let state = CycleState(baseWeightLb: 210, nextPhase: .deload)
        let plan = ProgramEngine.plan(for: state)
        XCTAssertEqual(plan.weightLb, 165)
        XCTAssertEqual(plan.sets, 3)
        XCTAssertEqual(plan.reps, 5)
        let pct = plan.weightLb / state.baseWeightLb
        XCTAssertTrue((0.75...0.80).contains(pct), "deload \(pct) outside 75-80% band")
    }

    func testPhaseAdvanceWithinCycle() {
        var state = CycleState(cycleNumber: 1, baseWeightLb: 210, nextPhase: .volume, incrementLb: 10)
        state = ProgramEngine.advancing(state, afterCompleting: .volume)
        XCTAssertEqual(state.nextPhase, .load)
        state = ProgramEngine.advancing(state, afterCompleting: .load)
        XCTAssertEqual(state.nextPhase, .peak)
        state = ProgramEngine.advancing(state, afterCompleting: .peak)
        XCTAssertEqual(state.nextPhase, .deload)
        // No base-weight change mid-cycle.
        XCTAssertEqual(state.baseWeightLb, 210)
        XCTAssertEqual(state.cycleNumber, 1)
    }

    func testCycleRolloverBumpsBaseWeight() {
        // Lower body: +10 lb next cycle.
        var lower = CycleState(cycleNumber: 1, baseWeightLb: 210, nextPhase: .deload, incrementLb: 10)
        lower = ProgramEngine.advancing(lower, afterCompleting: .deload)
        XCTAssertEqual(lower.cycleNumber, 2)
        XCTAssertEqual(lower.baseWeightLb, 220)
        XCTAssertEqual(lower.nextPhase, .volume)

        // Upper body: +5 lb next cycle.
        var upper = CycleState(cycleNumber: 1, baseWeightLb: 95, nextPhase: .deload, incrementLb: 5)
        upper = ProgramEngine.advancing(upper, afterCompleting: .deload)
        XCTAssertEqual(upper.baseWeightLb, 100)
    }

    func testTracksAreIndependentOfCalendar() {
        // Two lifts at different phases advance independently — nothing
        // in the engine references dates at all.
        let deadlift = CycleState(baseWeightLb: 210, nextPhase: .peak)
        let squat = CycleState(baseWeightLb: 175, nextPhase: .load)
        XCTAssertEqual(ProgramEngine.plan(for: deadlift).phase, .peak)
        XCTAssertEqual(ProgramEngine.plan(for: squat).phase, .load)
    }

    // MARK: - Autoregulation

    func testDroppedLoadCutsAndRounds() {
        XCTAssertEqual(ProgramEngine.droppedLoad(from: 232), 215) // 232·0.93 = 215.76 → 215
        XCTAssertEqual(ProgramEngine.droppedLoad(from: 100), 95)
    }

    func testDroppedLoadNeverGoesBelowBar() {
        XCTAssertEqual(ProgramEngine.droppedLoad(from: 50), 45)
        XCTAssertEqual(ProgramEngine.droppedLoad(from: 45), 45)
    }

    func testDroppedLoadAlwaysDropsWhenAboveBar() {
        // Rounding up must not return the same weight.
        let dropped = ProgramEngine.droppedLoad(from: 65)
        XCTAssertLessThan(dropped, 65)
        XCTAssertGreaterThanOrEqual(dropped, 45)
    }

    func testDropLoadPlanTargetsUnperformedSetsFromTheirOwnWeight() {
        // Warmup 45, top 300, back-offs 240 (one already flagged/done):
        // plan drops the two unflagged working sets, EACH from its own weight —
        // a lighter back-off must never be raised toward the top set's drop.
        let plan = ProgramEngine.dropLoadPlan(sets: [
            (weightLb: 45, isWarmup: true, isFlagged: false),
            (weightLb: 300, isWarmup: false, isFlagged: false),
            (weightLb: 240, isWarmup: false, isFlagged: false),
            (weightLb: 240, isWarmup: false, isFlagged: true),
        ])
        XCTAssertEqual(plan.map(\.index), [1, 2])
        XCTAssertEqual(plan[0].weightLb, 280) // 300·0.93 = 279 → 280
        XCTAssertEqual(plan[1].weightLb, 225) // 240·0.93 = 223.2 → 225, NOT 280
    }

    func testDropLoadPlanEmptyWhenAllSetsPerformed() {
        let plan = ProgramEngine.dropLoadPlan(sets: [
            (weightLb: 225, isWarmup: false, isFlagged: true),
            (weightLb: 225, isWarmup: false, isFlagged: true),
        ])
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Rounding

    func testRoundingToFive() {
        XCTAssertEqual(Weight.round(192.5, to: 5), 195) // half rounds away from zero
        XCTAssertEqual(Weight.round(246.75, to: 5), 245)
        XCTAssertEqual(Weight.round(162.75, to: 5), 165)
    }

    func testDumbbellProgramStepIsCappedPerHand() {
        XCTAssertEqual(ProgramEngine.loadStep(programRoundingLb: 10, exerciseType: "dumbbell"), 5)
        XCTAssertEqual(ProgramEngine.loadStep(programRoundingLb: 2.5, exerciseType: "dumbbell"), 2.5)
        XCTAssertEqual(ProgramEngine.loadStep(programRoundingLb: 10, exerciseType: "barbell"), 10)
    }

    func testDumbbellProgramPeakStaysWithinOneRackJumpOfBase() {
        let state = CycleState(cycleNumber: 2, baseWeightLb: 55, nextPhase: .peak, incrementLb: 0)
        XCTAssertEqual(ProgramEngine.programPlan(for: state, programRoundingLb: 5,
                                                 exerciseType: "dumbbell").weightLb, 60)
        XCTAssertEqual(ProgramEngine.programPlan(for: state, programRoundingLb: 5,
                                                 exerciseType: "barbell").weightLb, 65)
    }

    func testMainDumbbellWarmupRamp() {
        XCTAssertEqual(WarmupRamp.dumbbellRamp(workingLb: 60).map(\.weightLb), [25, 35, 50])
        XCTAssertEqual(WarmupRamp.dumbbellRamp(workingLb: 60).map(\.reps), [10, 5, 2])
        XCTAssertTrue(WarmupRamp.dumbbellRamp(workingLb: 5).isEmpty)
    }
}
