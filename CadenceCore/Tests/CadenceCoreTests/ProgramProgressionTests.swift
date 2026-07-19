import XCTest
@testable import CadenceCore

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
        p = cleanPerf(); p.anyBelowPlanLoad = true
        XCTAssertEqual(P.gradeCycle(p), .fail)
    }

    func testStandaloneTrackAdvancesOnceOnlyFromActualPrescriptionSuccess() {
        let clean = cleanPerf()
        var adjusted = clean
        adjusted.anyBelowPlanLoad = true
        XCTAssertTrue(P.earnsStandaloneTrackAdvance([clean]))
        XCTAssertTrue(P.earnsStandaloneTrackAdvance([clean, clean]), "duplicate sections form one successful exposure")
        XCTAssertFalse(P.earnsStandaloneTrackAdvance([clean, adjusted]), "one adjusted occurrence holds the exposure")
        XCTAssertFalse(P.earnsStandaloneTrackAdvance([]), "no performed work never advances")
    }

    func testBelowPlanLoadTolerance() {
        // Met within half a rounding step; a full step down is a drop (issue 18).
        XCTAssertFalse(P.belowPlanLoad(actualLb: 175, plannedLb: 175, roundingLb: 5))
        XCTAssertFalse(P.belowPlanLoad(actualLb: 180, plannedLb: 175, roundingLb: 5), "heavier than plan is fine")
        XCTAssertFalse(P.belowPlanLoad(actualLb: 172.5, plannedLb: 175, roundingLb: 5), "half a step under is still met (boundary)")
        XCTAssertTrue(P.belowPlanLoad(actualLb: 172.4, plannedLb: 175, roundingLb: 5), "past half a step is a drop")
        XCTAssertTrue(P.belowPlanLoad(actualLb: 170, plannedLb: 175, roundingLb: 5), "a full plate step down is a drop")
        XCTAssertFalse(P.belowPlanLoad(actualLb: 100, plannedLb: nil, roundingLb: 5), "no prescription → nothing to compare")
        XCTAssertFalse(P.belowPlanLoad(actualLb: 100, plannedLb: 0, roundingLb: 5), "zero plan → nothing to compare")
    }

    func testBelowPlanWorkCountsPrescribedSets() {
        // The prescription is met by prescribedSets at-plan sets; extras are bonus.
        XCTAssertFalse(P.belowPlanWork(weightsLb: [175, 175, 175], plannedLb: 175, prescribedSets: 3, roundingLb: 5),
                       "all prescribed sets at plan → met")
        XCTAssertFalse(P.belowPlanWork(weightsLb: [175, 175, 175, 155], plannedLb: 175, prescribedSets: 3, roundingLb: 5),
                       "lighter back-off after the planned work is bonus volume")
        XCTAssertTrue(P.belowPlanWork(weightsLb: [100, 100, 100], plannedLb: 175, prescribedSets: 3, roundingLb: 5),
                      "whole lift performed light → below plan")
        XCTAssertTrue(P.belowPlanWork(weightsLb: [175, 175, 155], plannedLb: 175, prescribedSets: 3, roundingLb: 5),
                      "one prescribed set cut down → below plan")
        XCTAssertFalse(P.belowPlanWork(weightsLb: [100, 100, 100], plannedLb: nil, prescribedSets: 3, roundingLb: 5),
                       "no prescription → nothing to compare")
    }

    func testSessionTagCurrent() {
        // A session may advance the program only from its live position (issue 17).
        XCTAssertTrue(P.sessionTagCurrent(tagCycle: 2, tagWeek: 1, tagDayIndex: 3, cycleNumber: 2, currentWeek: 1, nextDayIndex: 3),
                      "tag at the live position → current")
        XCTAssertFalse(P.sessionTagCurrent(tagCycle: 1, tagWeek: 1, tagDayIndex: 3, cycleNumber: 2, currentWeek: 1, nextDayIndex: 3),
                       "stale cycle → not current")
        XCTAssertFalse(P.sessionTagCurrent(tagCycle: 2, tagWeek: 1, tagDayIndex: 3, cycleNumber: 2, currentWeek: 2, nextDayIndex: 3),
                       "stale week → not current")
        XCTAssertFalse(P.sessionTagCurrent(tagCycle: 2, tagWeek: 1, tagDayIndex: 3, cycleNumber: 2, currentWeek: 1, nextDayIndex: 0),
                       "stale day → not current")
    }

    func testCanResumeSession() {
        // First list is the plan the session was BUILT from (snapshot); second
        // is the day's current plan. Session-local edits don't touch the
        // snapshot, so they don't appear here.
        let plan = ["Overhead Press", "Incline DB Press", "Dips"]
        func resume(_ tagDay: Int, _ day: Int, _ snapshot: [String], _ current: [String],
                    cycle: Int = 2, week: Int = 1, tagCycle: Int = 2, tagWeek: Int = 1) -> Bool {
            P.canResumeSession(tagCycle: tagCycle, tagWeek: tagWeek, tagDayIndex: tagDay,
                               cycleNumber: cycle, currentWeek: week, dayIndex: day,
                               sessionPlanNames: snapshot, dayPlanNames: current)
        }
        XCTAssertTrue(resume(3, 3, plan, plan), "same position + unchanged plan → resume (session-local edits preserved)")
        // The reported bug: the PROGRAM day was edited, so the built-from
        // snapshot no longer equals the current plan → build fresh.
        XCTAssertFalse(resume(3, 3, ["Overhead Press", "Chest-supported Row", "Dips"], plan), "program-edited plan → build fresh")
        XCTAssertFalse(resume(2, 3, plan, plan), "different day → build fresh")
        XCTAssertFalse(resume(3, 3, plan, plan, tagCycle: 1), "stale cycle → build fresh")
        XCTAssertFalse(resume(3, 3, plan, plan, tagWeek: 2), "stale week → build fresh")
        XCTAssertFalse(resume(3, 3, [], plan), "pre-snapshot session → build fresh")
    }

    func testBelowPlanWorkFailsCycle() {
        // Issue 18 repro: 3×3 prescribed at 175 (e1RM 300) but performed at 100
        // must not grade success, reset the stall, or raise the base weight.
        var p = cleanPerf(); p.anyBelowPlanLoad = true; p.topSetWeightLb = 100
        let state = ProgramLiftState(baseWeightLb: 175, estimatedMaxLb: 300, stallCount: 0, role: .main, lastIncrementLb: 0)
        let r = P.advanceCycleLift(state, perf: p, focus: .strength, roundingLb: 5)
        XCTAssertEqual(r.grade, .fail, "below-plan cycle fails")
        XCTAssertEqual(r.state.baseWeightLb, 175, accuracy: 1e-9, "no bump off work that wasn't done")
        XCTAssertEqual(r.state.stallCount, 1, "below-plan counts as a stall, not a reset")
        XCTAssertEqual(r.state.lastIncrementLb, 0, accuracy: 1e-9, "no increment recorded")
    }

    func testCleanCycleAddsTaperedIncrement() {
        let r = P.advanceCycleLift(liftState(), perf: cleanPerf(), focus: .strength, roundingLb: 5)
        XCTAssertEqual(r.grade, .success)
        XCTAssertEqual(r.state.baseWeightLb, 180, accuracy: 1e-9)
        XCTAssertEqual(r.state.stallCount, 0)
        XCTAssertEqual(r.state.lastIncrementLb, 5, accuracy: 1e-9)
        XCTAssertEqual(r.note, "Clean peak — add 5 lb next cycle.")
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

    func testBodyweightAccessoryClimbsPastMax() {
        // No loadable increment → keep adding reps, never reset, never add weight.
        let bw = AccessoryState(sets: 3, minReps: 8, maxReps: 12, currentReps: 12, weightLb: 0, incrementLb: 0)
        let a = P.advanceAccessory(bw, perf: AccessoryPerformance(completedSets: 3, minRepsAchieved: 12, anyStoppedEarly: false))
        XCTAssertEqual(a.weightLb, 0, accuracy: 1e-9)
        XCTAssertEqual(a.currentReps, 13)
        XCTAssertEqual(a.stallCount, 0)
    }

    func testAccessoryDoesNotAdvanceFromAdjustedLowerLoadOrPoorQuality() {
        let state = AccessoryState(sets: 3, minReps: 8, maxReps: 12, currentReps: 10,
                                   weightLb: 55, incrementLb: 5)
        let adjusted = P.advanceAccessory(
            state,
            perf: AccessoryPerformance(completedSets: 3, minRepsAchieved: 10,
                                       anyStoppedEarly: false, performedAtPlannedLoad: false)
        )
        XCTAssertEqual(adjusted.currentReps, 10)
        XCTAssertEqual(adjusted.weightLb, 55)
        XCTAssertEqual(adjusted.stallCount, 1)

        let poorQuality = P.advanceAccessory(
            state,
            perf: AccessoryPerformance(completedSets: 3, minRepsAchieved: 10,
                                       anyStoppedEarly: false, grindyOrWobbleSets: 2)
        )
        XCTAssertEqual(poorQuality.currentReps, 10)
        XCTAssertEqual(poorQuality.stallCount, 1)
    }

    // MARK: - Methodology progression (mirrors core.test.mjs)

    private func fivesPerf(completedSets: Int = 3, topSetReps: Int = 5, stoppedEarly: Bool = false) -> CycleLiftPerformance {
        CycleLiftPerformance(prescribedSets: 3, prescribedReps: 5, completedSets: completedSets,
                             anyStoppedEarly: stoppedEarly, anyDroppedLoad: false, grindyOrWobbleSets: 0,
                             topSetWeightLb: 205, topSetReps: topSetReps)
    }

    func testLinearRuleIncrementsByMovementPatternAndStyle() {
        let novice = ProgramProgression.linearRule(for: .linearFives, movementGroup: "squat")
        XCTAssertEqual(novice.incrementLb, 10)
        XCTAssertEqual(novice.stallLimit, 3)
        XCTAssertEqual(novice.deloadFraction, 0.90)
        XCTAssertEqual(ProgramProgression.linearRule(for: .texasVolume, movementGroup: "press").incrementLb, 5)
        XCTAssertEqual(ProgramProgression.linearRule(for: .texasVolume, movementGroup: "squat").incrementLb, 5,
                       "Texas lower is also +5 — twin A/B slots are synchronized by the banking layer")
        XCTAssertEqual(ProgramProgression.linearRule(for: .texasIntensity, movementGroup: "hinge").stallLimit, 2)
    }

    func testLinearFivesAdvancesEverySessionAndDeloadsAfterThreeMisses() {
        let rule = ProgramProgression.linearRule(for: .linearFives, movementGroup: "squat")
        let state = ProgramLiftState(baseWeightLb: 205, estimatedMaxLb: 280)

        let up = ProgramProgression.advanceLinearLift(state, perf: fivesPerf(), rule: rule, roundingLb: 5)
        XCTAssertEqual(up.state.baseWeightLb, 215)
        XCTAssertEqual(up.state.stallCount, 0)
        XCTAssertEqual(up.grade, .success)

        let held = ProgramProgression.advanceLinearLift(state, perf: fivesPerf(completedSets: 2, topSetReps: 4), rule: rule, roundingLb: 5)
        XCTAssertEqual(held.state.baseWeightLb, 205)
        XCTAssertEqual(held.state.stallCount, 1)

        var stalled = state
        stalled.stallCount = 2
        let third = ProgramProgression.advanceLinearLift(stalled, perf: fivesPerf(completedSets: 2, topSetReps: 4), rule: rule, roundingLb: 5)
        XCTAssertEqual(third.state.baseWeightLb, 185)
        XCTAssertEqual(third.state.stallCount, 0)

        let grindy = CycleLiftPerformance(prescribedSets: 3, prescribedReps: 5, completedSets: 3,
                                          anyStoppedEarly: false, anyDroppedLoad: false, grindyOrWobbleSets: 2,
                                          topSetWeightLb: 205, topSetReps: 5)
        let heldGrind = ProgramProgression.advanceLinearLift(stalled, perf: grindy, rule: rule, roundingLb: 5)
        XCTAssertEqual(heldGrind.state.baseWeightLb, 205, "grindy-but-complete session holds the weight")
        XCTAssertEqual(heldGrind.state.stallCount, 2, "grinding never counts as a miss toward the deload")

        let skipped = CycleLiftPerformance(prescribedSets: 3, prescribedReps: 5, completedSets: 0,
                                           anyStoppedEarly: false, anyDroppedLoad: false, grindyOrWobbleSets: 0,
                                           topSetWeightLb: 0, topSetReps: 0)
        let heldSkip = ProgramProgression.advanceLinearLift(state, perf: skipped, rule: rule, roundingLb: 5)
        XCTAssertEqual(heldSkip.state.estimatedMaxLb, 280, "a fully missed top set never smooths the e1RM toward zero")
    }

    private func topSetPerf(made: Bool) -> CycleLiftPerformance {
        CycleLiftPerformance(prescribedSets: 1, prescribedReps: 1, completedSets: made ? 1 : 0,
                             anyStoppedEarly: !made, anyDroppedLoad: false, grindyOrWobbleSets: 0,
                             topSetWeightLb: 285, topSetReps: made ? 3 : 0)
    }

    func testFiveThreeOneCycleIncrementsAndThreeCycleReset() {
        let state = ProgramLiftState(baseWeightLb: 300, estimatedMaxLb: 330)
        let up = ProgramProgression.advanceProgramLift(state, perf: topSetPerf(made: true), focus: .strength,
                                                       style: .fiveThreeOne, movementGroup: "squat", roundingLb: 5)
        XCTAssertEqual(up.state.baseWeightLb, 310)
        let reset = ProgramProgression.advanceProgramLift(state, perf: topSetPerf(made: false), focus: .strength,
                                                          style: .fiveThreeOne, movementGroup: "squat", roundingLb: 5)
        XCTAssertEqual(reset.state.baseWeightLb, 270)
        XCTAssertEqual(reset.grade, .fail)
        XCTAssertEqual(reset.state.estimatedMaxLb, 330, "531 reset never smooths the e1RM off a missed set")

        let droppedButMade = CycleLiftPerformance(prescribedSets: 1, prescribedReps: 1, completedSets: 1,
                                                  anyStoppedEarly: false, anyDroppedLoad: true, grindyOrWobbleSets: 0,
                                                  topSetWeightLb: 285, topSetReps: 3)
        let held = ProgramProgression.advanceProgramLift(state, perf: droppedButMade, focus: .strength,
                                                         style: .fiveThreeOne, movementGroup: "squat", roundingLb: 5)
        XCTAssertEqual(held.state.baseWeightLb, 300, "531 autoreg drop that made the reps holds the TM — no reset")
        XCTAssertEqual(held.grade, .fail)
    }

    func testMaxEffortAddsAfterMadeSinglesAndHoldsOnMisses() {
        let state = ProgramLiftState(baseWeightLb: 315, estimatedMaxLb: 330)
        let up = ProgramProgression.advanceProgramLift(state, perf: topSetPerf(made: true), focus: .strength,
                                                       style: .maxEffort, movementGroup: "press", roundingLb: 5)
        XCTAssertEqual(up.state.baseWeightLb, 320)
        let miss = ProgramProgression.advanceProgramLift(state, perf: topSetPerf(made: false), focus: .strength,
                                                         style: .maxEffort, movementGroup: "press", roundingLb: 5)
        XCTAssertEqual(miss.state.baseWeightLb, 315)
        XCTAssertEqual(miss.state.stallCount, 1)
    }

    func testDynamicEffortHoldsBaseAndNeverSmoothsE1RMOffSpeedWork() {
        let state = ProgramLiftState(baseWeightLb: 150, estimatedMaxLb: 330)
        let result = ProgramProgression.advanceProgramLift(state, perf: topSetPerf(made: true), focus: .strength,
                                                           style: .dynamicEffort, movementGroup: "squat", roundingLb: 5)
        XCTAssertEqual(result.state.baseWeightLb, 150)
        XCTAssertEqual(result.state.estimatedMaxLb, 330)
    }

    func testNonMethodologyStylesKeepTheTaperedRule() {
        let state = ProgramLiftState(baseWeightLb: 300, estimatedMaxLb: 330)
        let result = ProgramProgression.advanceProgramLift(state, perf: topSetPerf(made: true), focus: .strength,
                                                           style: .wave, movementGroup: "squat", roundingLb: 5)
        XCTAssertGreaterThanOrEqual(result.state.baseWeightLb, 300)
    }
}
