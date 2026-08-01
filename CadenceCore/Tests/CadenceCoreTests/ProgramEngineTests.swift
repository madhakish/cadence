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

    func testAutomaticPrescriptionRespectsRoleFocusAndMovement() {
        XCTAssertEqual(ProgramEngine.resolvedStyle(.automatic, movementGroup: "press", role: .main, focus: .strength), .wave)
        XCTAssertEqual(ProgramEngine.resolvedStyle(.automatic, movementGroup: "hinge", role: .complementary, focus: .strength), .secondary)
        XCTAssertEqual(ProgramEngine.resolvedStyle(.automatic, movementGroup: "press", role: .main, focus: .hypertrophy), .hypertrophy)
        XCTAssertEqual(ProgramEngine.resolvedStyle(.automatic, movementGroup: "olympic", role: .main, focus: .strength), .technique)
    }

    func testComplementaryVolumeDoesNotInheritMainFiveByFive() {
        let state = CycleState(baseWeightLb: 200, nextPhase: .volume)
        let plan = ProgramEngine.programPlan(for: state, programRoundingLb: 5, exerciseType: "barbell",
                                             movementGroup: "hinge", role: .complementary)
        XCTAssertEqual(plan.sets, 3)
        XCTAssertEqual(plan.reps, 8)
        XCTAssertEqual(plan.weightLb, 180)
    }

    // [INV-COMP-IS-VOLUME]
    func testComplementaryStaysVolumeOrientedAcrossTheWholeRotation() {
        // Complementary work never mirrors the main 5×5→5×3→3×3 wave: every
        // phase prescribes 5+ reps at or below the slot's base weight.
        let plans = CyclePhase.allCases.map { phase in
            ProgramEngine.programPlan(
                for: CycleState(baseWeightLb: 200, nextPhase: phase),
                programRoundingLb: 5, exerciseType: "barbell",
                movementGroup: "hinge", role: .complementary
            )
        }
        XCTAssertEqual(plans.map(\.sets), [3, 3, 3, 2])
        XCTAssertEqual(plans.map(\.reps), [8, 8, 6, 8])
        XCTAssertEqual(plans.map(\.weightLb), [180, 190, 200, 150])
        XCTAssertTrue(plans.allSatisfy { $0.reps >= 5 && $0.weightLb <= 200 })
    }

    func testTechniquePeakUsesCrispSingles() {
        let state = CycleState(baseWeightLb: 100, nextPhase: .peak)
        let plan = ProgramEngine.programPlan(for: state, programRoundingLb: 5, exerciseType: "barbell",
                                             movementGroup: "olympic", role: .main)
        XCTAssertEqual(plan.sets, 6)
        XCTAssertEqual(plan.reps, 1)
        XCTAssertEqual(plan.weightLb, 110)
    }

    func testOffsetWaveDerivesEveryPhaseFromTheVolumeBase() {
        let config = LiftPrescriptionConfiguration(
            loadOffsetLb: 25, peakOffsetLb: 33, deloadMultiplier: 0.80
        )
        let phases = CyclePhase.allCases.map { phase in
            ProgramEngine.plan(
                for: CycleState(cycleNumber: 2, baseWeightLb: 221, nextPhase: phase),
                roundingLb: 5, style: .offsetWave, configuration: config
            ).weightLb
        }
        XCTAssertEqual(phases, [220, 245, 255, 175])
    }

    func testPeakSingleAndPrimerAreSeparateFromMainWork() {
        let config = LiftPrescriptionConfiguration(
            loadOffsetLb: 25, peakOffsetLb: 33, deloadMultiplier: 0.80,
            peakSingleEnabled: true, lastPeakSingleLb: 270,
            peakSingleIncrementLb: 5, phasePrimerEnabled: true
        )
        let prescription = ProgramEngine.sessionPrescription(
            for: CycleState(cycleNumber: 2, baseWeightLb: 221, nextPhase: .peak),
            programRoundingLb: 5, exerciseType: "barbell", movementGroup: "hinge",
            role: .main, prescriptionStyle: .offsetWave,
            configuration: config, estimatedMaxLb: 300
        )
        XCTAssertEqual(prescription.mainWork.weightLb, 255)
        XCTAssertEqual(prescription.blocks.map(\.kind), [.primer, .topSingle, .work])
        XCTAssertEqual(prescription.blocks.map(\.weightLb), [245, 275, 255])
    }

    func testProgramLiftDoubleProgressionHoldsLoadAndUsesCurrentRepTarget() {
        let config = LiftPrescriptionConfiguration(
            workingSets: 5, minimumReps: 5, maximumReps: 8, currentReps: 5
        )
        let plan = ProgramEngine.programPlan(
            for: CycleState(baseWeightLb: 55, nextPhase: .load),
            programRoundingLb: 5, exerciseType: "dumbbell", movementGroup: "press",
            role: .main, prescriptionStyle: .doubleProgression, configuration: config
        )
        XCTAssertEqual(plan.weightLb, 55)
        XCTAssertEqual(plan.sets, 5)
        XCTAssertEqual(plan.reps, 5)
    }

    func testConfiguredDropIncrementWinsOverPercentageFallback() {
        XCTAssertEqual(ProgramEngine.droppedLoad(from: 205, roundingLb: 5, dropIncrementLb: 10), 195)
        XCTAssertEqual(ProgramEngine.droppedLoad(from: 140, roundingLb: 5, dropIncrementLb: 5), 135)
    }

    func testMainDumbbellWarmupRamp() {
        XCTAssertEqual(WarmupRamp.dumbbellRamp(workingLb: 60).map(\.weightLb), [25, 35, 50])
        XCTAssertEqual(WarmupRamp.dumbbellRamp(workingLb: 60).map(\.reps), [10, 5, 2])
        XCTAssertTrue(WarmupRamp.dumbbellRamp(workingLb: 5).isEmpty)
    }

    // MARK: - Authored slot order (mirrors core.test.mjs)

    func testAuthoredSlotOrdersRescueTheDegenerateTie() {
        // Every order tied → the tie carries no information; the array
        // position the author wrote the slots in is their order. Without this
        // the display fallback hands the day to the alphabet.
        XCTAssertEqual(ProgramEngine.authoredSlotOrders([0, 0, 0]), [0, 1, 2])
        XCTAssertEqual(ProgramEngine.authoredSlotOrders([7, 7]), [0, 1],
                       "any shared value is the same degenerate case as all zeros")
        // Distinct or even partially distinct orders are the author's numbers.
        XCTAssertEqual(ProgramEngine.authoredSlotOrders([2, 0, 1]), [2, 0, 1])
        XCTAssertEqual(ProgramEngine.authoredSlotOrders([0, 0, 2]), [0, 0, 2],
                       "a partial tie is a real (if sloppy) authored ordering, kept verbatim")
        XCTAssertEqual(ProgramEngine.authoredSlotOrders([5]), [5], "a single slot has nothing to disambiguate")
        XCTAssertEqual(ProgramEngine.authoredSlotOrders([]), [])
    }

    // MARK: - Deload intensity knob (mirrors core.test.mjs)

    func testWaveDeloadHonoursTheSlotsOwnMultiplier() {
        func deload(_ configuration: LiftPrescriptionConfiguration) -> SessionPlan {
            ProgramEngine.plan(for: CycleState(baseWeightLb: 200, nextPhase: .deload),
                               roundingLb: 5, style: .automatic, configuration: configuration)
        }
        XCTAssertEqual(deload(.init()).weightLb, 155,
                       "default stays the historical 0.775 — nobody's deload moves uninvited")
        XCTAssertEqual(deload(.init(deloadMultiplier: 0.85)).weightLb, 170,
                       "a slot that finds 77.5% unproductively light raises intensity, not volume")
        let raised = deload(.init(deloadMultiplier: 0.85))
        XCTAssertEqual([raised.sets, raised.reps], [3, 5], "the volume cut is not negotiable through this knob")
        // Only the deload listens: the working rotations keep the wave shape.
        let peak = ProgramEngine.plan(for: CycleState(baseWeightLb: 200, nextPhase: .peak),
                                      roundingLb: 5, style: .automatic,
                                      configuration: .init(deloadMultiplier: 0.85))
        XCTAssertEqual(peak.weightLb, 235)
        // Zero is "unset", never "lift nothing" — the shared engine guards it
        // itself (mirroring core.js), not only the app-layer config builder.
        XCTAssertEqual(deload(.init(deloadMultiplier: 0)).weightLb, 155,
                       "a zero multiplier falls back to the historical 0.775")
        let offsetZero = ProgramEngine.plan(for: CycleState(baseWeightLb: 200, nextPhase: .deload),
                                            roundingLb: 5, style: .offsetWave,
                                            configuration: .init(loadOffsetLb: 10, peakOffsetLb: 25,
                                                                 deloadMultiplier: 0))
        XCTAssertEqual(offsetZero.weightLb, 155, "offsetWave shares the same zero-is-unset rescue")
    }

    // MARK: - Methodology styles (mirrors core.test.mjs)

    func testFiveThreeOnePlansTheWaveOffTheTrainingMax() {
        func top(_ phase: CyclePhase) -> SessionPlan {
            ProgramEngine.plan(for: CycleState(baseWeightLb: 300, nextPhase: phase),
                               roundingLb: 5, style: .fiveThreeOne)
        }
        XCTAssertEqual([top(.volume).weightLb, top(.load).weightLb, top(.peak).weightLb, top(.deload).weightLb],
                       [255, 270, 285, 180])
        XCTAssertEqual([top(.volume).reps, top(.load).reps, top(.peak).reps, top(.deload).reps], [5, 3, 1, 5])
        XCTAssertEqual(top(.peak).sets, 1)
    }

    func testFiveThreeOneSessionEmitsRampThenTopSet() {
        let prescription = ProgramEngine.sessionPrescription(
            for: CycleState(baseWeightLb: 300, nextPhase: .peak),
            programRoundingLb: 5, exerciseType: "barbell", movementGroup: "squat",
            prescriptionStyle: .fiveThreeOne)
        // The top set is the "+" set — the AMRAP is 5/3/1's progression engine,
        // and shipping the percentages without it was the template's one real
        // infidelity. Mirrors the block in web/tests/core.test.mjs.
        XCTAssertEqual(prescription.blocks.map(\.kind), [.ramp, .ramp, .amrap])
        XCTAssertEqual(prescription.blocks.map(\.weightLb), [225, 255, 285])
        XCTAssertEqual(prescription.blocks.map(\.reps), [5, 3, 1])
        XCTAssertEqual(prescription.mainWork.weightLb, 285)

        // Wendler's deload week has no "+" set.
        let deload = ProgramEngine.sessionPrescription(
            for: CycleState(baseWeightLb: 300, nextPhase: .deload),
            programRoundingLb: 5, exerciseType: "barbell", movementGroup: "squat",
            prescriptionStyle: .fiveThreeOne)
        XCTAssertEqual(deload.blocks.map(\.kind), [.ramp, .ramp, .work])

        // An AMRAP set is graded work. Filtering to `work` alone made it
        // invisible: uncounted for completion, ineligible as the top set,
        // unable to reach the e1RM sample — the entire point of the block.
        XCTAssertTrue(PrescriptionBlockKind.amrap.countsAsPrescribedWork)
        XCTAssertTrue(PrescriptionBlockKind.work.countsAsPrescribedWork)
        for kind in [PrescriptionBlockKind.warmup, .primer, .ramp, .topSingle, .backoff] {
            XCTAssertFalse(kind.countsAsPrescribedWork, "\(kind) is not the prescription being graded")
        }

        // A 5/3/1 day is ALL ramp and amrap — it has no ordinary `work` set at
        // all, so a gate asking "is this `work`" answered no for the whole day
        // and the schedule never advanced. Conditioning is an instruction the
        // athlete owes but is graded in minutes, so it joins this gate and not
        // the lifting one.
        XCTAssertTrue(PrescriptionBlockKind.amrap.countsAsProgramInstruction)
        XCTAssertTrue(PrescriptionBlockKind.conditioning.countsAsProgramInstruction)
        XCTAssertFalse(PrescriptionBlockKind.conditioning.countsAsPrescribedWork)
        for kind in [PrescriptionBlockKind.warmup, .primer, .ramp, .topSingle, .backoff] {
            XCTAssertFalse(kind.countsAsProgramInstruction)
        }
    }

    func testMaxEffortTopSingleWithBackoffTriplesAndDeload() {
        let prescription = ProgramEngine.sessionPrescription(
            for: CycleState(baseWeightLb: 315, nextPhase: .volume),
            programRoundingLb: 5, exerciseType: "barbell", movementGroup: "squat",
            prescriptionStyle: .maxEffort)
        XCTAssertEqual(prescription.mainWork.weightLb, 315)
        XCTAssertEqual(prescription.blocks.map(\.kind), [.work, .backoff])
        XCTAssertEqual(prescription.blocks.last?.weightLb, 250)
        let deload = ProgramEngine.plan(for: CycleState(baseWeightLb: 315, nextPhase: .deload),
                                        roundingLb: 5, style: .maxEffort)
        XCTAssertEqual([deload.weightLb, Double(deload.sets), Double(deload.reps)], [220, 3, 3])
    }

    func testDynamicEffortSpeedSchemesByMovementPattern() {
        let squat = ProgramEngine.plan(for: CycleState(baseWeightLb: 150, nextPhase: .load),
                                       roundingLb: 5, style: .dynamicEffort, movementGroup: "squat")
        XCTAssertEqual([squat.weightLb, Double(squat.sets), Double(squat.reps)], [165, 10, 2])
        let pull = ProgramEngine.plan(for: CycleState(baseWeightLb: 185, nextPhase: .volume),
                                      roundingLb: 5, style: .dynamicEffort, movementGroup: "hinge")
        XCTAssertEqual([Double(pull.sets), Double(pull.reps)], [6, 1])
        let bench = ProgramEngine.plan(for: CycleState(baseWeightLb: 100, nextPhase: .peak),
                                       roundingLb: 5, style: .dynamicEffort, movementGroup: "press")
        XCTAssertEqual([bench.weightLb, Double(bench.sets), Double(bench.reps)], [120, 9, 3])
    }

    func testLinearFivesSetsAcrossIgnoresThePhaseWave() {
        for phase in CyclePhase.allCases {
            let plan = ProgramEngine.plan(for: CycleState(baseWeightLb: 205, nextPhase: phase),
                                          roundingLb: 5, style: .linearFives,
                                          configuration: .init(workingSets: 3))
            XCTAssertEqual([plan.weightLb, Double(plan.sets), Double(plan.reps)], [205, 3, 5],
                           "phase \(phase.rawValue) must not reshape linear fives")
        }
    }

    func testMethodologyStyleHelpers() {
        XCTAssertTrue(PrescriptionStyle.texasVolume.advancesPerExposure)
        XCTAssertTrue(PrescriptionStyle.linearFives.advancesPerExposure)
        XCTAssertFalse(PrescriptionStyle.fiveThreeOne.advancesPerExposure)
        XCTAssertFalse(PrescriptionStyle.wave.advancesPerExposure)
        XCTAssertTrue(PrescriptionStyle.dynamicEffort.buildsOwnSessionShape)
        XCTAssertFalse(PrescriptionStyle.wave.buildsOwnSessionShape)
        XCTAssertEqual(PrescriptionStyle.fiveThreeOne.defaultStartFraction, 0.90)
        XCTAssertEqual(PrescriptionStyle.dynamicEffort.defaultStartFraction, 0.50)
        XCTAssertEqual(PrescriptionStyle.wave.defaultStartFraction, 0)
    }

    /// `offsetWave`'s movement-aware defaults live in one place so both clients
    /// agree. The JS mirror used to resolve them in `sessionPrescription` only,
    /// so a squat reaching `planForStyle` got the upper-body pair instead.
    func testResolvedOffsetsAreMovementAwareAndRespectExplicitValues() {
        func offsets(_ load: Double, _ peak: Double, _ group: String?) -> [Double] {
            let r = ProgramEngine.resolvedOffsets(loadOffsetLb: load, peakOffsetLb: peak, movementGroup: group)
            return [r.load, r.peak]
        }
        XCTAssertEqual(offsets(0, 0, "squat"), [25, 33], "lower body")
        XCTAssertEqual(offsets(0, 0, "hinge"), [25, 33], "hinge counts as lower body")
        XCTAssertEqual(offsets(0, 0, "press"), [10, 15], "everything else")
        XCTAssertEqual(offsets(0, 0, nil), [10, 15], "an unknown group is treated as upper body")
        XCTAssertEqual(offsets(40, 60, "squat"), [40, 60], "an explicit offset stays user-owned")
        XCTAssertEqual(offsets(40, 0, "squat"), [40, 33], "each offset defaults independently")

        // The behaviour the divergence broke: a squat's peak week.
        let plan = ProgramEngine.plan(
            for: CycleState(baseWeightLb: 200, nextPhase: .peak), roundingLb: 5, style: .offsetWave,
            configuration: .init(loadOffsetLb: 25, peakOffsetLb: 33), movementGroup: "squat"
        )
        XCTAssertEqual(plan.weightLb, 235, accuracy: 1e-9)
    }

    /// A peak single seeds from a training max, so it follows the program's
    /// focus rather than a hardcoded 0.90.
    func testPeakSingleSeedFollowsTheProgramFocus() {
        func single(_ focus: TrainingFocus) -> Double? {
            ProgramEngine.sessionPrescription(
                for: CycleState(baseWeightLb: 100, nextPhase: .peak),
                programRoundingLb: 5, exerciseType: "barbell", movementGroup: "press",
                role: .main, focus: focus, prescriptionStyle: .wave,
                configuration: .init(peakSingleEnabled: true, phasePrimerEnabled: false),
                estimatedMaxLb: 200
            ).blocks.first { $0.kind == .topSingle }?.weightLb
        }
        XCTAssertEqual(single(.strength), 180, "strength seeds at its own 0.90 ceiling")
        XCTAssertEqual(single(.hypertrophy), 155, "hypertrophy seeds at 0.78, not 0.90")
    }

    /// offsetWave is retired from the pickers but NOT deleted: its raw value is
    /// persisted in programs, backups and program files, so a slot already on
    /// it has to keep working and keep appearing in its own picker.
    /// Mirrors the block in web/tests/core.test.mjs.
    func testRetiredStylesStayAvailableToSlotsAlreadyUsingThem() {
        let fresh = PrescriptionStyle.selectable(current: .wave)
        XCTAssertFalse(fresh.contains(.offsetWave),
                       "a new slot is never offered the retired style")
        XCTAssertEqual(fresh.count, PrescriptionStyle.allCases.count - 1,
                       "and nothing else is hidden")

        let existing = PrescriptionStyle.selectable(current: .offsetWave)
        XCTAssertTrue(existing.contains(.offsetWave),
                      "a slot already on it still sees it, so opening the picker cannot silently rewrite the slot")
        XCTAssertEqual(existing.count, PrescriptionStyle.allCases.count)
    }
}
