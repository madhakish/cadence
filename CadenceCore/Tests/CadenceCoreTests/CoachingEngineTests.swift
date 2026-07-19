import XCTest
@testable import CadenceCore

final class CoachingEngineTests: XCTestCase {
    private let day = 86_400.0

    func testMovementTaxonomySeparatesRowsPulldownsAndHamstringIsolation() {
        XCTAssertEqual(MovementTaxonomy.pattern(exerciseName: "Barbell Row", movementGroup: "pull"), .horizontalPull)
        XCTAssertEqual(MovementTaxonomy.pattern(exerciseName: "Lat Pulldown", movementGroup: "pull"), .verticalPull)
        XCTAssertEqual(MovementTaxonomy.pattern(exerciseName: "Seated Leg Curl", movementGroup: "hinge"), .kneeFlexion)
        XCTAssertEqual(MovementTaxonomy.pattern(exerciseName: "Back Extension", movementGroup: "hinge"), .hipExtension)
        XCTAssertEqual(MovementTaxonomy.pattern(exerciseName: "Overhead Press", movementGroup: "press"), .verticalPress)
    }

    func testIncompleteRotationIsUnknownAndNeverAddsVolume() {
        let report = CoachingEngine.evaluate(
            program: program(),
            sessions: [session(cycle: 1, rotation: 1, day: 0, date: 0)]
        )
        XCTAssertEqual(report.currentReadiness, .unknown)
        XCTAssertTrue(report.recommendations.isEmpty)
        XCTAssertFalse(report.rotations[0].isComplete)
    }

    func testTwoGreenRotationsProposeSixTargetedSets() throws {
        var sessions: [CoachingSessionSnapshot] = []
        for rotation in 1...3 {
            for dayIndex in 0...3 {
                sessions.append(session(
                    cycle: 1, rotation: rotation, day: dayIndex,
                    date: Double((rotation - 1) * 4 + dayIndex) * 3 * day,
                    weight: 100 + Double(rotation - 1) * 5
                ))
            }
        }
        let report = CoachingEngine.evaluate(program: program(), sessions: sessions)
        XCTAssertEqual(report.currentReadiness, .green)
        XCTAssertEqual(report.greenRotationStreak, 2, "the first complete rotation establishes the baseline")
        let plan = try XCTUnwrap(report.recommendations.first { recommendation in
            if case .capacityPlan(_) = recommendation.change { return true }
            return false
        })
        guard case .capacityPlan(let additions) = plan.change else {
            return XCTFail("Expected one bundled capacity plan")
        }
        XCTAssertEqual(additions.reduce(0) { $0 + $1.setCount }, 6)
        XCTAssertTrue(plan.explanation.localizedCaseInsensitiveContains("vertical pull"))
        XCTAssertTrue(plan.explanation.localizedCaseInsensitiveContains("hamstring"))
    }

    func testAdjustedLowerWorkMakesRotationYellow() {
        var sessions = (0...3).map { session(cycle: 1, rotation: 1, day: $0, date: Double($0) * 3 * day) }
        sessions += (0...3).map {
            session(cycle: 1, rotation: 2, day: $0, date: Double(12 + $0 * 3) * day,
                    actualWeight: $0 == 0 ? 90 : 105, weight: 105)
        }
        let report = CoachingEngine.evaluate(program: program(), sessions: sessions)
        XCTAssertEqual(report.currentReadiness, .yellow)
        XCTAssertEqual(report.recommendations.first?.change, .hold)
    }

    func testRepeatedLargePerformanceDropsAcrossLiftsAreRed() {
        var sessions = (0...3).map {
            session(cycle: 1, rotation: 1, day: $0, date: Double($0) * 3 * day, weight: 100)
        }
        sessions += (0...3).map {
            session(cycle: 1, rotation: 2, day: $0, date: Double(12 + $0 * 3) * day,
                    actualWeight: 90, weight: 90)
        }
        let report = CoachingEngine.evaluate(program: program(), sessions: sessions)
        XCTAssertEqual(report.currentReadiness, .red)
        XCTAssertEqual(report.recommendations.first?.change, .reduceAccessoryVolume(percent: 25))
    }

    func testHardStopRecoveryCheckInMakesCompleteRotationRed() {
        var sessions = (0...3).map {
            session(cycle: 1, rotation: 1, day: $0, date: Double($0) * 3 * day)
        }
        sessions[2].hasHardStopCheckIn = true
        let report = CoachingEngine.evaluate(program: program(), sessions: sessions)
        XCTAssertEqual(report.currentReadiness, .red)
        XCTAssertTrue(report.rotations[0].reasons.contains { $0.contains("check-in") })
    }

    func testHamstringGapTargetsSquatLedDay() throws {
        var sessions: [CoachingSessionSnapshot] = []
        for rotation in 1...3 {
            for dayIndex in 0...3 {
                sessions.append(session(cycle: 1, rotation: rotation, day: dayIndex,
                                        date: Double((rotation - 1) * 12 + dayIndex * 3) * day,
                                        weight: 100 + Double(rotation - 1) * 5))
            }
        }
        let recommendation = try XCTUnwrap(CoachingEngine.evaluate(program: program(), sessions: sessions)
            .recommendations.first { if case .capacityPlan(_) = $0.change { return true }; return false })
        guard case .capacityPlan(let additions) = recommendation.change,
              let dayIndex = additions.compactMap({ adjustment -> Int? in
                  if case .addPattern(.kneeFlexion, let dayIndex, _) = adjustment { return dayIndex }
                  return nil
              }).first else { return XCTFail("Expected a knee-flexion addition") }
        XCTAssertEqual(dayIndex, 0, "hamstring isolation belongs on the squat-led lower day")
    }

    func testConditioningMinutesStayOutOfLiftingSetCompletion() {
        var sessions = (0...3).map {
            session(cycle: 1, rotation: 1, day: $0, date: Double($0) * 3 * day)
        }
        sessions[1].exercises.append(CoachingExerciseSnapshot(
            slotID: "bike", programRole: "accessory",
            exerciseName: "Bike", pattern: .easyAerobic, plannedSets: 1,
            sets: [CoachingSetSnapshot(
                actualWeightLb: 0, actualReps: 0, plannedReps: 0,
                durationSeconds: 1_200
            )]
        ))
        sessions[0].exercises[0].sets.append(CoachingSetSnapshot(
            actualWeightLb: 120, actualReps: 1, plannedWeightLb: 120,
            plannedReps: 1, prescriptionBlock: .topSingle
        ))
        sessions[0].exercises[0].sets.append(CoachingSetSnapshot(
            actualWeightLb: 500, actualReps: 20, plannedWeightLb: 500,
            plannedReps: 20
        ))
        sessions[0].exercises.append(CoachingExerciseSnapshot(
            exerciseName: "Back Squat", pattern: .squat, plannedSets: 1,
            sets: [CoachingSetSnapshot(actualWeightLb: 500, actualReps: 20)]
        ))
        let rotation = CoachingEngine.evaluate(program: program(), sessions: sessions).rotations[0]
        XCTAssertEqual(rotation.plannedWorkingSets, 12)
        XCTAssertEqual(rotation.completedWorkingSets, 12)
        XCTAssertEqual(rotation.conditioningMinutes, 20)
        XCTAssertEqual(rotation.patternSets[.squat], 3,
                       "top singles, added sets, and slotless exercises are not program distribution")
    }

    func testSameExerciseOnTwoDaysIsComparedByProgramSlot() {
        let snapshot = CoachingProgramSnapshot(
            id: "program", expectedDayIndexes: [0, 1], slots: [
                CoachingProgramSlot(id: "lower-b-main", exerciseName: "Back Squat", dayIndex: 0,
                                    pattern: .squat, plannedSets: 3, role: "main", isMain: true),
                CoachingProgramSlot(id: "lower-a-complementary", exerciseName: "Back Squat", dayIndex: 1,
                                    pattern: .squat, plannedSets: 3, role: "complementary"),
            ]
        )
        func exposure(rotation: Int, dayIndex: Int, slotID: String, role: String,
                      weight: Double) -> CoachingSessionSnapshot {
            CoachingSessionSnapshot(
                id: "\(rotation)-\(dayIndex)",
                date: Date(timeIntervalSince1970: Double(rotation * 10 + dayIndex) * day),
                programID: "program", cycleNumber: 1, rotation: rotation, dayIndex: dayIndex,
                exercises: [CoachingExerciseSnapshot(
                    slotID: slotID, programRole: role, exerciseName: "Back Squat", pattern: .squat,
                    plannedSets: 3, plannedWeightLb: weight, plannedReps: 3,
                    sets: (0..<3).map { _ in CoachingSetSnapshot(
                        actualWeightLb: weight, actualReps: 3,
                        plannedWeightLb: weight, plannedReps: 3
                    ) }
                )]
            )
        }
        let sessions = [
            exposure(rotation: 1, dayIndex: 0, slotID: "lower-b-main", role: "main", weight: 225),
            exposure(rotation: 1, dayIndex: 1, slotID: "lower-a-complementary", role: "complementary", weight: 175),
            exposure(rotation: 2, dayIndex: 0, slotID: "lower-b-main", role: "main", weight: 225),
            exposure(rotation: 2, dayIndex: 1, slotID: "lower-a-complementary", role: "complementary", weight: 140),
        ]

        let report = CoachingEngine.evaluate(program: snapshot, sessions: sessions)
        XCTAssertEqual(report.currentReadiness, .yellow,
                       "the complementary slot drop must not hide behind the same-name main slot")
    }

    private func program() -> CoachingProgramSnapshot {
        CoachingProgramSnapshot(
            id: "program",
            expectedDayIndexes: Set(0...3),
            slots: [
                CoachingProgramSlot(id: "squat", exerciseName: "Back Squat", dayIndex: 0,
                                    pattern: .squat, plannedSets: 3, role: "main", isMain: true),
                CoachingProgramSlot(id: "press-a", exerciseName: "Overhead Press", dayIndex: 1,
                                    pattern: .verticalPress, plannedSets: 3, role: "main", isMain: true),
                CoachingProgramSlot(id: "deadlift", exerciseName: "Deadlift", dayIndex: 2,
                                    pattern: .hipHinge, plannedSets: 3, role: "main", isMain: true),
                CoachingProgramSlot(id: "press-b", exerciseName: "Incline DB Press", dayIndex: 3,
                                    pattern: .horizontalPress, plannedSets: 3, role: "main", isMain: true),
                CoachingProgramSlot(id: "row", exerciseName: "Chest-supported Row", dayIndex: 3,
                                    pattern: .horizontalPull, plannedSets: 6, role: "accessory"),
                CoachingProgramSlot(id: "bike", exerciseName: "Bike", dayIndex: 1,
                                    pattern: .easyAerobic, plannedSets: 1, role: "accessory"),
            ]
        )
    }

    private func session(
        cycle: Int,
        rotation: Int,
        day dayIndex: Int,
        date: TimeInterval,
        actualWeight: Double? = nil,
        weight: Double = 100
    ) -> CoachingSessionSnapshot {
        let actual = actualWeight ?? weight
        let names = ["Back Squat", "Overhead Press", "Deadlift", "Incline DB Press"]
        let slotIDs = ["squat", "press-a", "deadlift", "press-b"]
        let patterns: [MovementPattern] = [.squat, .verticalPress, .hipHinge, .horizontalPress]
        let work = (0..<3).map { _ in
            CoachingSetSnapshot(actualWeightLb: actual, actualReps: 5,
                                plannedWeightLb: weight, plannedReps: 5)
        }
        return CoachingSessionSnapshot(
            id: "\(cycle)-\(rotation)-\(dayIndex)",
            date: Date(timeIntervalSince1970: date),
            programID: "program", cycleNumber: cycle, rotation: rotation, dayIndex: dayIndex,
            exercises: [CoachingExerciseSnapshot(
                slotID: slotIDs[dayIndex], programRole: "main",
                exerciseName: names[dayIndex], pattern: patterns[dayIndex],
                plannedSets: 3, plannedWeightLb: weight, plannedReps: 5, sets: work
            )]
        )
    }
}
