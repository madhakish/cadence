import XCTest
@testable import CadenceCore

final class DumbbellRepProgressionTests: XCTestCase {
    // Synthetic values shared with web/tests/dumbbell-progression.test.mjs.
    private func fixture() -> (program: CoachingProgramSnapshot, sessions: [CoachingSessionSnapshot]) {
        let slot = CoachingProgramSlot(
            id: "db-slot", exerciseName: "Fixture DB Press", dayIndex: 0,
            pattern: .horizontalPress, plannedSets: 3, isMain: true,
            prescriptionStyle: .wave, baseWeightLb: 80,
            collapsedDumbbellWaveLoadLb: detect()
        )
        let entry = CoachingExerciseSnapshot(
            slotID: slot.id, programRole: "main", exerciseName: slot.exerciseName,
            pattern: slot.pattern, plannedSets: 5, plannedWeightLb: 85, plannedReps: 3,
            prescriptionStyle: .wave,
            sets: (0..<5).map { _ in CoachingSetSnapshot(
                actualWeightLb: 85, actualReps: 3, plannedWeightLb: 85, plannedReps: 3,
                quality: .clean, loadBasis: .perImplement
            ) }
        )
        return (CoachingProgramSnapshot(id: "fixture-program", expectedDayIndexes: [0], slots: [slot]),
                [CoachingSessionSnapshot(id: "11", date: Date(timeIntervalSince1970: 100),
                    programID: "fixture-program", cycleNumber: 1, rotation: 2, dayIndex: 0, exercises: [entry])])
    }

    private func detect(base: Double = 80, rounding: Double = 5, type: String = "dumbbell",
                        role: LiftRole = .main, style: PrescriptionStyle = .automatic) -> Double? {
        ProgramEngine.collapsedDumbbellWaveLoad(
            baseWeightLb: base, programRoundingLb: rounding, exerciseType: type,
            movementGroup: "press", role: role, focus: .strength, prescriptionStyle: style
        )
    }

    private func suggestion(_ program: CoachingProgramSnapshot, _ sessions: [CoachingSessionSnapshot]) -> CoachingRecommendation? {
        CoachingEngine.evaluate(program: program, sessions: sessions).recommendations.first {
            if case .useDumbbellRepProgression = $0.change { return true }
            return false
        }
    }

    func testDetectionUsesTheRoundedWaveAndPreservesOtherStyles() {
        XCTAssertEqual(detect(), 85)
        XCTAssertEqual(detect(rounding: 10), 85)
        XCTAssertNil(detect(base: 30, rounding: 2.5))
        XCTAssertNil(detect(base: 82.5))
        for type in ["barbell", "machine", "kettlebell"] { XCTAssertNil(detect(type: type)) }
        XCTAssertNil(detect(role: .complementary))
        for style in [PrescriptionStyle.doubleProgression, .linearFives, .fiveThreeOne, .technique, .dynamicEffort] {
            XCTAssertNil(detect(style: style))
        }
        let peak = ProgramEngine.programPlan(for: CycleState(baseWeightLb: 80, nextPhase: .peak),
                                             programRoundingLb: 5, exerciseType: "dumbbell")
        XCTAssertEqual(peak.weightLb, 85, "authored waves are not silently rewritten")
        XCTAssertEqual(peak.sets, 3)
    }

    func testConversionPreservesCompletedWorkWithinTheRepWindow() {
        let cases: [(Int, Int, Int?)] = [(3, 3, 4), (4, 3, 4), (5, 3, 5), (6, 3, 6), (3, 6, 6), (5, 4, nil)]
        for (sets, reps, expected) in cases {
            let (program, original) = fixture()
            var sessions = original
            var set = sessions[0].exercises[0].sets[0]
            set.actualReps = reps
            sessions[0].exercises[0].plannedSets = sets
            sessions[0].exercises[0].sets = Array(repeating: set, count: sets)
            let proposed = suggestion(program, sessions)
            if let expected {
                XCTAssertEqual(proposed?.change, .useDumbbellRepProgression(slotID: "db-slot",
                    exerciseName: "Fixture DB Press", expectedBaseWeightLb: 80, weightLb: 85, currentReps: expected))
                XCTAssertGreaterThanOrEqual(3 * expected, sets * reps)
            } else {
                XCTAssertNil(proposed, "do not compress more work than the rep window can hold")
            }
        }
    }

    func testFiveTriplesBecomeThreeFivesAtThePerformedLoad() throws {
        let (program, sessions) = fixture()
        let proposed = try XCTUnwrap(suggestion(program, sessions))
        XCTAssertEqual(proposed.change, .useDumbbellRepProgression(slotID: "db-slot",
            exerciseName: "Fixture DB Press", expectedBaseWeightLb: 80, weightLb: 85, currentReps: 5))
        XCTAssertEqual(proposed.id, "program.slot.dumbbell-reps.v1:db-slot:c1-r2-d0:80:3x5@85")
        XCTAssertTrue(proposed.explanation.contains("3–6"))
        XCTAssertEqual(sessions[0].exercises[0].sets[0].actualReps, 3)
    }

    func testMissingIdentityOrIncompatibleHistoryCannotEarnAConversion() {
        let (program, original) = fixture()
        let changes: [(inout CoachingSessionSnapshot) -> Void] = [
            { $0.programID = "another-program" },
            { $0.dayIndex = 1 },
            { $0.rotation = 4 },
            { $0.hasHardStopCheckIn = true },
            { $0.exercises[0].slotID = nil },
            { $0.exercises[0].slotID = "another-slot" },
            { $0.exercises[0].programRole = "complementary" },
            { $0.exercises[0].exerciseName = "Fixture DB Row" },
            { $0.exercises[0].prescriptionStyle = nil },
            { $0.exercises[0].sets.removeLast() },
            { $0.exercises[0].sets[0].completed = false },
            { $0.exercises[0].sets[0].actualWeightLb = 80 },
            { $0.exercises[0].sets[0].actualReps = 2 },
            { $0.exercises[0].sets[0].hasBodyFlag = true },
            { $0.exercises[0].sets[0].stoppedEarly = true },
            { $0.exercises[0].sets[0].loadBasis = nil },
            { $0.exercises[0].sets[0].loadBasis = .externalTotal },
            { $0.exercises[0].sets[0].quality = .grindy; $0.exercises[0].sets[1].quality = .wobble },
        ]
        for (index, change) in changes.enumerated() {
            var sessions = original
            change(&sessions[0])
            XCTAssertNil(suggestion(program, sessions), "history gate \(index)")
        }
    }

    func testProtectedSlotsCannotBeConverted() {
        let (original, sessions) = fixture()
        let changes: [(inout CoachingProgramSlot) -> Void] = [
            { $0.collapsedDumbbellWaveLoadLb = nil },
            { $0.capacityManaged = false },
            { $0.maximumSets = 2 },
            { $0.isMain = false },
            { $0.exerciseIsShelved = true },
            { $0.trainingIntent = .technique },
            { $0.trainingIntent = .explosive },
            { $0.prescriptionStyle = .doubleProgression },
        ]
        for (index, change) in changes.enumerated() {
            var program = original
            change(&program.slots[0])
            XCTAssertNil(suggestion(program, sessions), "slot gate \(index)")
        }
    }

    func testNewestFailureBlocksOldSuccessAndAddedRepsDoNotEarnTheTarget() {
        let (program, original) = fixture()
        var sessions = original
        var bad = sessions[0]
        bad.id = "12"; bad.date = Date(timeIntervalSince1970: 200)
        bad.exercises[0].sets[0].actualReps = 2
        XCTAssertNil(suggestion(program, sessions + [bad]))
        var bonus = sessions[0].exercises[0].sets[0]
        bonus.actualReps = 10
        sessions[0].exercises[0].sets.append(bonus)
        XCTAssertEqual(suggestion(program, sessions)?.change, .useDumbbellRepProgression(slotID: "db-slot",
            exerciseName: "Fixture DB Press", expectedBaseWeightLb: 80, weightLb: 85, currentReps: 5))
    }

    func testNewerIdentitylessHistoryBlocksAnOlderExactSlotSuccess() {
        let (program, sessions) = fixture()
        var newer = sessions[0]
        newer.id = "12"; newer.date = Date(timeIntervalSince1970: 200)
        newer.exercises[0].slotID = nil
        newer.exercises[0].sets[0].actualReps = 2
        XCTAssertNil(suggestion(program, sessions + [newer]))
    }

    func testRecommendationIdentityUsesPortableEvidence() {
        let (program, original) = fixture()
        var restored = original
        restored[0].id = "efb7de65-3dc5-4e80-a79f-f07379c2e912"
        XCTAssertEqual(suggestion(program, original)?.id, suggestion(program, restored)?.id)
    }

    func testRepWindowPreviewPreservesRecoveryAndEarnsOneRackStep() {
        let entries = ProgramEngine.exposurePreview(count: 5, baseWeightLb: 85, rotation: 3,
            programRoundingLb: 5, exerciseType: "dumbbell", movementGroup: "press",
            prescriptionStyle: .doubleProgression,
            configuration: LiftPrescriptionConfiguration(workingSets: 3, minimumReps: 3, maximumReps: 6, currentReps: 4))
        XCTAssertEqual(entries.map { $0.prescription.mainWork.sets }, [3, 1, 3, 3, 3])
        XCTAssertEqual(entries.map { $0.prescription.mainWork.reps }, [4, 3, 5, 6, 3])
        XCTAssertEqual(entries.map { $0.prescription.mainWork.weightLb }, [85, 70, 85, 85, 90])
        let state = AccessoryState(sets: 3, minReps: 3, maxReps: 6, currentReps: 4, weightLb: 85, incrementLb: 5)
        let held = ProgramProgression.advanceAccessory(state,
            perf: AccessoryPerformance(completedSets: 3, minRepsAchieved: 3, anyStoppedEarly: false))
        XCTAssertEqual(held.currentReps, 4)
        XCTAssertEqual(held.weightLb, 85)
    }
}
