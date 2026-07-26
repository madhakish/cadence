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

    /// A loaded accessory with a zero increment silently behaves like
    /// bodyweight work: it climbs reps past its own maximum and the weight
    /// never moves. That is the misconfiguration the program editor flags.
    func testLoadedAccessoryWithZeroIncrementNeverAddsLoad() {
        let broken = AccessoryState(sets: 3, minReps: 8, maxReps: 12, currentReps: 12,
                                    weightLb: 75, incrementLb: 0)
        let a = P.advanceAccessory(broken, perf: AccessoryPerformance(completedSets: 3, minRepsAchieved: 12, anyStoppedEarly: false))
        XCTAssertEqual(a.weightLb, 75, accuracy: 1e-9, "the load cannot move without an increment")
        XCTAssertEqual(a.currentReps, 13, "and reps climb past the slot's own maximum instead")

        XCTAssertTrue(P.accessoryCannotProgressLoad(
            exerciseType: "dumbbell", loadBasis: .perImplement, weightLb: 75, incrementLb: 0
        ), "a per-hand dumbbell slot carrying load with no increment is flagged")
        XCTAssertTrue(P.accessoryCannotProgressLoad(
            exerciseType: "machine", loadBasis: .externalTotal, weightLb: 120, incrementLb: 0
        ), "a machine slot carrying load with no increment is flagged")
    }

    /// The rule must not fire on work that progresses by reps or duration —
    /// a plank steps `durationStepSeconds`, so its zero increment is correct.
    func testDurationAndBodyweightAccessoriesAreNotFlagged() {
        XCTAssertFalse(P.accessoryCannotProgressLoad(
            exerciseType: "timed", loadBasis: .externalTotal, weightLb: 25, incrementLb: 0
        ), "a timed slot progresses by duration, not load")
        XCTAssertFalse(P.accessoryCannotProgressLoad(
            exerciseType: "conditioning", loadBasis: .externalTotal, weightLb: 25, incrementLb: 0
        ), "conditioning is not load-progressed")
        XCTAssertFalse(P.accessoryCannotProgressLoad(
            exerciseType: "bodyweight", loadBasis: .bodyweight, weightLb: 0, incrementLb: 0
        ), "bodyweight work has no load to add")
        XCTAssertFalse(P.accessoryCannotProgressLoad(
            exerciseType: "barbell", loadBasis: .bodyweight, weightLb: 45, incrementLb: 0
        ), "an explicitly bodyweight basis wins over the equipment label")
        XCTAssertFalse(P.accessoryCannotProgressLoad(
            exerciseType: "dumbbell", loadBasis: .perImplement, weightLb: 10, incrementLb: 2.5
        ), "a fractional increment is a real increment")
        XCTAssertFalse(P.accessoryCannotProgressLoad(
            exerciseType: "DUMBBELL", loadBasis: .perImplement, weightLb: 40, incrementLb: 5
        ), "the type test is case-insensitive")

        // An unloaded slot is not a misconfiguration. 0/0 is how "no external
        // load" is spelled, and it is what every newly added accessory starts
        // at — flagging it would fire on every slot the moment it was created,
        // and on shipped templates that use bands.
        XCTAssertFalse(P.accessoryCannotProgressLoad(
            exerciseType: "dumbbell", loadBasis: .perImplement, weightLb: 0, incrementLb: 0
        ), "an unconfigured accessory is not flagged")
        XCTAssertFalse(P.accessoryCannotProgressLoad(
            exerciseType: "band", loadBasis: .externalTotal, weightLb: 0, incrementLb: 0
        ), "a band with no numeric load is not flagged")
    }

    /// Session spacing is advisory and only speaks when it has something to
    /// say. The preference was previously write-only.
    func testSessionSpacingShortfallOnlySpeaksWhenEarly() {
        XCTAssertEqual(P.sessionSpacingShortfall(daysSinceLastSession: 1, preferredDays: 3), 2)
        XCTAssertEqual(P.sessionSpacingShortfall(daysSinceLastSession: 0, preferredDays: 3), 3)
        XCTAssertNil(P.sessionSpacingShortfall(daysSinceLastSession: 3, preferredDays: 3),
                     "meeting the preference says nothing")
        XCTAssertNil(P.sessionSpacingShortfall(daysSinceLastSession: 9, preferredDays: 3),
                     "being well past it says nothing")
        XCTAssertNil(P.sessionSpacingShortfall(daysSinceLastSession: nil, preferredDays: 3),
                     "no prior session says nothing")
        XCTAssertNil(P.sessionSpacingShortfall(daysSinceLastSession: 1, preferredDays: 0),
                     "no preference recorded says nothing")
        XCTAssertNil(P.sessionSpacingShortfall(daysSinceLastSession: -1, preferredDays: 3),
                     "a negative gap is nonsense, not a warning")
    }

    /// Fractional increments have to survive: a 5 lb step on a 10 lb load is a
    /// 50% jump, so small-load slots need 2.5 and it must not round away.
    func testAccessoryAcceptsAFractionalIncrement() {
        let state = AccessoryState(sets: 3, minReps: 8, maxReps: 12, currentReps: 12,
                                   weightLb: 10, incrementLb: 2.5)
        let a = P.advanceAccessory(state, perf: AccessoryPerformance(completedSets: 3, minRepsAchieved: 12, anyStoppedEarly: false))
        XCTAssertEqual(a.weightLb, 12.5, accuracy: 1e-9, "the increment is added unrounded")
        XCTAssertEqual(a.currentReps, 8)
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
        XCTAssertEqual(heldGrind.state.stallCount, 0, "a completed session breaks the consecutive-miss chain")

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

        var compromised = state
        compromised.stallCount = 1
        let second = ProgramProgression.advanceProgramLift(compromised, perf: droppedButMade, focus: .strength,
                                                           style: .fiveThreeOne, movementGroup: "squat", roundingLb: 5)
        XCTAssertEqual(second.state.baseWeightLb, 270, "two compromised cycles self-correct the TM three cycles back")
        XCTAssertEqual(second.state.stallCount, 0, "the compromised-cycle counter is consumed by the reset")
    }

    func testMaxEffortAddsAfterMadeSinglesAndHoldsOnMisses() {
        let state = ProgramLiftState(baseWeightLb: 315, estimatedMaxLb: 330)
        let up = ProgramProgression.advanceProgramLift(state, perf: topSetPerf(made: true), focus: .strength,
                                                       style: .maxEffort, movementGroup: "press", roundingLb: 5)
        XCTAssertEqual(up.state.baseWeightLb, 320)
        let miss = ProgramProgression.advanceProgramLift(state, perf: topSetPerf(made: false), focus: .strength,
                                                         style: .maxEffort, movementGroup: "press", roundingLb: 5)
        XCTAssertEqual(miss.state.baseWeightLb, 315)
        XCTAssertEqual(miss.state.stallCount, 0,
                       "ME misses never accrue a counter another style could trip over")
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
    // MARK: - Schedule advance

    func testScheduleAdvanceWalksContiguousDayOrders() {
        let orders = [0, 1, 2, 3]
        XCTAssertEqual(ProgramProgression.scheduleAdvance(dayOrders: orders, bankedDayOrder: 0).nextDayOrder, 1)
        XCTAssertFalse(ProgramProgression.scheduleAdvance(dayOrders: orders, bankedDayOrder: 0).isLastDay)
        XCTAssertEqual(ProgramProgression.scheduleAdvance(dayOrders: orders, bankedDayOrder: 3).nextDayOrder, 0)
        XCTAssertTrue(ProgramProgression.scheduleAdvance(dayOrders: orders, bankedDayOrder: 3).isLastDay)
    }

    // [INV-SCHEDULE-WALKS-ORDERS]
    func testScheduleAdvanceReachesEveryDayDespiteAGapInOrders() {
        // Import validates day orders as unique but never as contiguous, so a
        // bundle can carry [0, 1, 5]. Index-space arithmetic then never
        // recognized the last day: the week stopped advancing, the cycle never
        // rolled over, and the day past the gap became unreachable.
        let sparse = [0, 1, 5]
        XCTAssertEqual(ProgramProgression.scheduleAdvance(dayOrders: sparse, bankedDayOrder: 1).nextDayOrder, 5,
                       "the day past the gap must be reachable")
        XCTAssertFalse(ProgramProgression.scheduleAdvance(dayOrders: sparse, bankedDayOrder: 1).isLastDay)
        XCTAssertTrue(ProgramProgression.scheduleAdvance(dayOrders: sparse, bankedDayOrder: 5).isLastDay,
                      "the highest order is the last day whatever its value")
        XCTAssertEqual(ProgramProgression.scheduleAdvance(dayOrders: sparse, bankedDayOrder: 5).nextDayOrder, 0)
    }

    func testScheduleAdvanceHandlesUnsortedAndUnknownAndSingleDayPrograms() {
        // Stored order is not guaranteed sorted.
        XCTAssertEqual(ProgramProgression.scheduleAdvance(dayOrders: [2, 0, 1], bankedDayOrder: 0).nextDayOrder, 1)
        // A one-day program banks its only day as the last day, every time.
        let single = ProgramProgression.scheduleAdvance(dayOrders: [0], bankedDayOrder: 0)
        XCTAssertEqual(single.nextDayOrder, 0)
        XCTAssertTrue(single.isLastDay)
        // A stale tag or deleted day still closes the rotation rather than
        // stranding it, and restarts at the first day.
        let unknown = ProgramProgression.scheduleAdvance(dayOrders: [0, 1], bankedDayOrder: 9)
        XCTAssertEqual(unknown.nextDayOrder, 0)
        XCTAssertTrue(unknown.isLastDay)
        // An empty program must not crash.
        XCTAssertEqual(ProgramProgression.scheduleAdvance(dayOrders: [], bankedDayOrder: 0).nextDayOrder, 0)
    }

    // [INV-SCHEDULE-WALKS-ORDERS]
    func testScheduleAdvanceCollapsesDuplicateDayOrders() {
        // Two DISTINCT days can share one order (a damaged store, or an add
        // that collided on days.count). Stepping inside the duplicate pair
        // would advance an order to itself and strand the rotation the same
        // way a gap did.
        let dup = ProgramProgression.scheduleAdvance(dayOrders: [0, 0, 1], bankedDayOrder: 0)
        XCTAssertEqual(dup.nextDayOrder, 1, "a duplicated order must not advance to itself")
        XCTAssertFalse(dup.isLastDay)
        let dupLast = ProgramProgression.scheduleAdvance(dayOrders: [0, 1, 1], bankedDayOrder: 1)
        XCTAssertTrue(dupLast.isLastDay, "a duplicated last order is still the last day")
        XCTAssertEqual(dupLast.nextDayOrder, 0)
        let allDup = ProgramProgression.scheduleAdvance(dayOrders: [0, 0], bankedDayOrder: 0)
        XCTAssertEqual(allDup.nextDayOrder, 0)
        XCTAssertTrue(allDup.isLastDay, "an all-duplicate program still closes its rotation")
    }
    // [INV-BELOW-PLAN-IS-BELOW-PLAN]
    func testLighterWorkStillGradesBelowPlan() {
        // Propagating an edit changes the work about to be done, not the bar
        // the session is graded against — otherwise the base weight could climb
        // on work that was never done.
        XCTAssertTrue(ProgramProgression.belowPlanWork(
            weightsLb: [205, 205, 205], plannedLb: 225, prescribedSets: 3))
        XCTAssertFalse(ProgramProgression.belowPlanWork(
            weightsLb: [225, 225, 225], plannedLb: 225, prescribedSets: 3))
        // Extra back-off volume beyond the prescription never fails the grade.
        XCTAssertFalse(ProgramProgression.belowPlanWork(
            weightsLb: [225, 225, 225, 185], plannedLb: 225, prescribedSets: 3))
        // kg-entry noise inside half a rounding step still counts as at plan.
        XCTAssertFalse(ProgramProgression.belowPlanWork(
            weightsLb: [223.5, 225, 225], plannedLb: 225, prescribedSets: 3))
    }

    // MARK: - Readiness-triggered deload
    // Mirrors the "Readiness-triggered deload" block in web/tests/core.test.mjs.

    func testTwoRedRotationsCutTheCycleShort() {
        let far = P.minimumSessionsBetweenDeloads
        XCTAssertTrue(P.shouldDeloadEarly(currentWeek: 2, readiness: .red,
                                          previousReadiness: .red, sessionsSinceLastDeload: far))
        XCTAssertTrue(P.shouldDeloadEarly(currentWeek: 1, readiness: .red,
                                          previousReadiness: .red, sessionsSinceLastDeload: far),
                      "rotation 1 can deload early once the floor is clear")
    }

    func testASingleRedRotationIsNoise() {
        let far = P.minimumSessionsBetweenDeloads
        XCTAssertFalse(P.shouldDeloadEarly(currentWeek: 2, readiness: .red,
                                           previousReadiness: .yellow, sessionsSinceLastDeload: far))
        XCTAssertFalse(P.shouldDeloadEarly(currentWeek: 2, readiness: .red,
                                           previousReadiness: .unknown, sessionsSinceLastDeload: far),
                       "a first-ever red has nothing to persist against")
        XCTAssertFalse(P.shouldDeloadEarly(currentWeek: 2, readiness: .yellow,
                                           previousReadiness: .red, sessionsSinceLastDeload: far),
                       "a recovered rotation finishes the cycle")
    }

    func testLateRotationsHaveNothingToSkip() {
        let far = P.minimumSessionsBetweenDeloads
        XCTAssertFalse(P.shouldDeloadEarly(currentWeek: 3, readiness: .red,
                                           previousReadiness: .red, sessionsSinceLastDeload: far),
                       "rotation 3 already advances into the deload")
        XCTAssertFalse(P.shouldDeloadEarly(currentWeek: P.deloadWeek, readiness: .red,
                                           previousReadiness: .red, sessionsSinceLastDeload: far),
                       "the deload rotation cannot deload again")
    }

    func testTheFloorStopsRecoveryDeloadsBecomingTheSchedule() {
        let far = P.minimumSessionsBetweenDeloads
        XCTAssertFalse(P.shouldDeloadEarly(currentWeek: 2, readiness: .red,
                                           previousReadiness: .red, sessionsSinceLastDeload: far - 1))
        XCTAssertTrue(P.shouldDeloadEarly(currentWeek: 2, readiness: .red,
                                          previousReadiness: .red, sessionsSinceLastDeload: far + 40),
                      "an old deload never blocks a new one")
    }

    func testACutShortCycleHoldsRatherThanCountingAMissedPeak() throws {
        let stuck = ProgramLiftState(baseWeightLb: 225, estimatedMaxLb: 290,
                                     stallCount: 1, role: .main, lastIncrementLb: 10)
        let held = P.recoveryDeloadHold(stuck, atWeek: 2)
        XCTAssertEqual(held.grade, .hold, "a cycle the program cut short is a hold, not a fail")
        XCTAssertEqual(held.state.baseWeightLb, 225,
                       "the base holds — the lifter did not miss a peak, the peak never ran")
        XCTAssertEqual(held.state.stallCount, 1, "no stall accrues for work that was never prescribed")
        XCTAssertEqual(held.state.lastIncrementLb, 0)
        XCTAssertTrue(try XCTUnwrap(held.note).contains("rotation 2"),
                      "the note says which rotation was cut short")
    }

    // MARK: - The cycle's strength sample
    // Mirrors the "cycle's strength sample" block in web/tests/core.test.mjs.

    func testExtraRepsAtTheTopWeightAreTheCyclesBestEstimate() {
        // Heaviest-first gave the tie to the FIRST set at that weight and threw
        // an AMRAP's extra reps away.
        XCTAssertEqual(P.strengthSampleIndex(weightsLb: [225, 225, 225], reps: [3, 3, 8]), 2)
        XCTAssertEqual(P.strengthSampleIndex(weightsLb: [225, 225], reps: [3, 3]), 0,
                       "with nothing to separate them the first top set stands")
    }

    func testBackOffVolumeNeverOutranksAHeavyTriple() {
        XCTAssertEqual(P.strengthSampleIndex(weightsLb: [215, 135], reps: [3, 10]), 0)
        XCTAssertEqual(P.strengthSampleIndex(weightsLb: [225, 185], reps: [3, 10]), 0)
    }

    func testVeryLongSetsAreNotStrengthSamplesWhileAUsableOneExists() {
        XCTAssertEqual(P.strengthSampleIndex(weightsLb: [185, 95], reps: [5, 25]), 0)
        XCTAssertEqual(P.strengthSampleIndex(weightsLb: [95, 95], reps: [20, 25]), 1,
                       "when every set is a long one, rank them anyway rather than reporting none")
        XCTAssertNil(P.strengthSampleIndex(weightsLb: [], reps: []))
    }
}
