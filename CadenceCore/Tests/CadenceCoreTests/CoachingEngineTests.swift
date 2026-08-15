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

    func testFirstIncompleteRotationIsUnknownAndNeverAddsVolume() {
        let report = CoachingEngine.evaluate(
            program: program(),
            sessions: [session(cycle: 1, rotation: 1, day: 0, date: 0)]
        )
        XCTAssertEqual(report.currentReadiness, .unknown)
        XCTAssertTrue(report.recommendations.isEmpty)
        XCTAssertFalse(report.rotations[0].isComplete)
    }

    func testIncompleteRotationReportsProvisionalReadinessAfterBaseline() {
        var sessions = (0...3).map {
            session(cycle: 1, rotation: 1, day: $0, date: Double($0) * 3 * day)
        }
        sessions += (0...1).map {
            session(cycle: 1, rotation: 2, day: $0,
                    date: Double(12 + $0 * 3) * day, weight: 105)
        }
        let report = CoachingEngine.evaluate(program: program(), sessions: sessions)
        XCTAssertEqual(report.currentReadiness, .green)
        XCTAssertFalse(report.rotations.last?.isComplete ?? true)
        XCTAssertTrue(report.rotations.last?.reasons.first?.contains("2/4 days banked") ?? false)
        XCTAssertTrue(report.recommendations.isEmpty,
                      "provisional readiness must not mutate an incomplete rotation")
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

    func testTwoConsecutiveRedRotationsEscalateToARecoveryRotation() {
        var sessions = (0...3).map {
            session(cycle: 1, rotation: 1, day: $0, date: Double($0) * 3 * day, weight: 100)
        }
        sessions += (0...3).map {
            session(cycle: 1, rotation: 2, day: $0, date: Double(12 + $0 * 3) * day,
                    actualWeight: 90, weight: 90)
        }
        sessions += (0...3).map {
            session(cycle: 1, rotation: 3, day: $0, date: Double(24 + $0 * 3) * day,
                    actualWeight: 81, weight: 81)
        }
        let report = CoachingEngine.evaluate(program: program(), sessions: sessions)
        XCTAssertEqual(report.currentReadiness, .red)
        let first = report.recommendations.first
        XCTAssertEqual(first?.ruleID, "readiness.red.persistent.recovery-rotation.v\(CoachingEngine.ruleVersion)")
        XCTAssertEqual(first?.change, .reduceAccessoryVolume(percent: 50),
                       "a red that survives the 25% cut escalates to a recovery rotation")
        XCTAssertFalse(
            report.recommendations.contains { $0.change == .reduceAccessoryVolume(percent: 25) },
            "the escalation replaces the single-red rule rather than stacking with it"
        )
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

    // MARK: - Rotation suggestions

    func testSlotPrescribingAShelvedExerciseIsSurfaced() throws {
        let report = CoachingEngine.evaluate(
            program: program(patching: "squat") { $0.exerciseIsShelved = true },
            sessions: greenRotations()
        )
        let suggestion = try XCTUnwrap(report.recommendations.first { rotationSlotID($0) != nil })
        XCTAssertEqual(suggestion.ruleID, "program.slot.rotate.shelved.v\(CoachingEngine.ruleVersion)")
        XCTAssertEqual(rotationSlotID(suggestion), "squat",
                       "the suggestion names the slot; resolving a replacement needs the exercise library")
        XCTAssertTrue(suggestion.id.hasSuffix("-squat"),
                      "one suggestion per slot, so two stuck slots do not collide on one id")
    }

    func testOneNonSuccessCycleOnALiftSlotProposesARotation() throws {
        let report = CoachingEngine.evaluate(
            program: program(patching: "squat") { $0.stallCount = 1 },
            sessions: greenRotations()
        )
        let suggestion = try XCTUnwrap(report.recommendations.first { rotationSlotID($0) != nil })
        XCTAssertEqual(suggestion.ruleID, "program.slot.rotate.stalled.v\(CoachingEngine.ruleVersion)")
    }

    func testStallSuggestionSurvivesARedRotationButNeverLeadsIt() {
        var sessions = (0...3).map {
            session(cycle: 1, rotation: 1, day: $0, date: Double($0) * 3 * day, weight: 100)
        }
        sessions += (0...3).map {
            session(cycle: 1, rotation: 2, day: $0, date: Double(12 + $0 * 3) * day,
                    actualWeight: 90, weight: 90)
        }
        let report = CoachingEngine.evaluate(
            program: program(patching: "squat") { $0.stallCount = 1 }, sessions: sessions
        )
        XCTAssertEqual(report.recommendations.first?.change, .reduceAccessoryVolume(percent: 25),
                       "readiness still leads the list")
        XCTAssertTrue(report.recommendations.contains { rotationSlotID($0) == "squat" },
                      "a red rotation does not suppress program hygiene")
    }

    func testAccessoryStallsNeedARealPlateauAndConditioningIsNeverRotated() {
        let onceStuck = CoachingEngine.evaluate(
            program: program(patching: "row") { $0.stallCount = 1 }, sessions: greenRotations()
        )
        XCTAssertFalse(onceStuck.recommendations.contains { rotationSlotID($0) != nil },
                       "one missed accessory exposure is not a plateau")

        let plateaued = CoachingEngine.evaluate(
            program: program(patching: "row") { $0.stallCount = 3 }, sessions: greenRotations()
        )
        XCTAssertEqual(plateaued.recommendations.compactMap(rotationSlotID), ["row"])

        let conditioning = CoachingEngine.evaluate(
            program: program(patching: "bike") {
                $0.stallCount = 5
                $0.exerciseIsShelved = true
            },
            sessions: greenRotations()
        )
        XCTAssertFalse(conditioning.recommendations.contains { rotationSlotID($0) != nil },
                       "conditioning slots are never rotated by this rule")
    }

    // MARK: - Adaptive linear stage

    func testRebuiltUpperLinearSlotProposesTriplesForThatSlotOnly() throws {
        var sessions = greenRotations()
        for index in sessions.indices where sessions[index].dayIndex == 1 {
            sessions[index].exercises[0].prescriptionStyle = .linearFives
            sessions[index].exercises[0].plannedWeightLb = 100
            sessions[index].exercises[0].sets = (0..<3).map { _ in
                CoachingSetSnapshot(
                    actualWeightLb: 100, actualReps: 4,
                    plannedWeightLb: 100, plannedReps: 5
                )
            }
        }
        let report = CoachingEngine.evaluate(
            program: program(patching: "press-a") {
                $0.prescriptionStyle = .linearFives
                $0.baseWeightLb = 90
                $0.workingSets = 3
                $0.workingReps = 5
            },
            sessions: sessions
        )
        let suggestion = try XCTUnwrap(report.recommendations.first {
            if case .useLinearTriples(let slotID, _, _) = $0.change { return slotID == "press-a" }
            return false
        })
        XCTAssertEqual(suggestion.ruleID, "program.slot.linear-triples.v1")
        XCTAssertTrue(suggestion.explanation.contains("100 to 90 lb"))
    }

    func testLinearTriplesRequiresHistoricalThreeByFiveEvidence() {
        var sessions = greenRotations()
        for index in sessions.indices where sessions[index].dayIndex == 1 {
            sessions[index].exercises[0].prescriptionStyle = .linearFives
            sessions[index].exercises[0].plannedSets = 5
            sessions[index].exercises[0].plannedWeightLb = 100
            sessions[index].exercises[0].plannedReps = 5
            sessions[index].exercises[0].sets = (0..<5).map { _ in
                CoachingSetSnapshot(
                    actualWeightLb: 100, actualReps: 4,
                    plannedWeightLb: 100, plannedReps: 5
                )
            }
        }

        let report = CoachingEngine.evaluate(
            program: program(patching: "press-a") {
                $0.prescriptionStyle = .linearFives
                $0.baseWeightLb = 90
                $0.workingSets = 3
                $0.workingReps = 5
            },
            sessions: sessions
        )
        XCTAssertFalse(report.recommendations.contains {
            if case .useLinearTriples = $0.change { return true }
            return false
        }, "failed 5x5 history must not be described as a failed 3x5 prescription")
    }

    func testLinearTriplesNeedsARebuildAndDoesNotGuessAtLowerBodyTransitions() throws {
        var sessions = greenRotations()
        for index in sessions.indices where sessions[index].dayIndex == 1 {
            sessions[index].exercises[0].prescriptionStyle = .linearFives
            sessions[index].exercises[0].plannedWeightLb = 100
            sessions[index].exercises[0].sets = (0..<3).map { _ in
                CoachingSetSnapshot(
                    actualWeightLb: 100, actualReps: 4,
                    plannedWeightLb: 100, plannedReps: 5
                )
            }
        }

        let noRebuild = CoachingEngine.evaluate(
            program: program(patching: "press-a") {
                $0.prescriptionStyle = .linearFives
                $0.baseWeightLb = 100
                $0.workingSets = 3
                $0.workingReps = 5
            }, sessions: sessions
        )
        XCTAssertFalse(noRebuild.recommendations.contains {
            if case .useLinearTriples = $0.change { return true }
            return false
        }, "three misses without the load rebuild are not a strategy transition")

        let coachingDisabled = CoachingEngine.evaluate(
            program: program(patching: "press-a") {
                $0.prescriptionStyle = .linearFives
                $0.baseWeightLb = 90
                $0.workingSets = 3
                $0.workingReps = 5
                $0.capacityManaged = false
            }, sessions: sessions
        )
        XCTAssertFalse(coachingDisabled.recommendations.contains {
            if case .useLinearTriples = $0.change { return true }
            return false
        }, "a slot that disallows coached sets must not propose five sets")

        let cappedSets = CoachingEngine.evaluate(
            program: program(patching: "press-a") {
                $0.prescriptionStyle = .linearFives
                $0.baseWeightLb = 90
                $0.workingSets = 3
                $0.workingReps = 5
                $0.maximumSets = 4
            }, sessions: sessions
        )
        XCTAssertFalse(cappedSets.recommendations.contains {
            if case .useLinearTriples = $0.change { return true }
            return false
        }, "a four-set slot cap must not propose five sets")

        var oneMiss = greenRotations()
        let latestPress = try XCTUnwrap(oneMiss.lastIndex { $0.rotation == 3 && $0.dayIndex == 1 })
        oneMiss[latestPress].exercises[0].prescriptionStyle = .linearFives
        oneMiss[latestPress].exercises[0].plannedWeightLb = 100
        oneMiss[latestPress].exercises[0].sets[0].actualReps = 4
        let manualReduction = CoachingEngine.evaluate(
            program: program(patching: "press-a") {
                $0.prescriptionStyle = .linearFives
                $0.baseWeightLb = 90
                $0.workingSets = 3
                $0.workingReps = 5
            }, sessions: oneMiss
        )
        XCTAssertFalse(manualReduction.recommendations.contains {
            if case .useLinearTriples = $0.change { return true }
            return false
        }, "a manual base reduction after one miss must not masquerade as the three-miss reset")

        var recoveredSessions = sessions
        var latestSuccess = session(
            cycle: 1, rotation: 4, day: 1, date: 48 * day, weight: 100
        )
        latestSuccess.exercises[0].prescriptionStyle = .linearFives
        recoveredSessions.append(latestSuccess)
        let recovered = CoachingEngine.evaluate(
            program: program(patching: "press-a") {
                $0.prescriptionStyle = .linearFives
                $0.baseWeightLb = 90
                $0.workingSets = 3
                $0.workingReps = 5
            }, sessions: recoveredSessions
        )
        XCTAssertFalse(recovered.recommendations.contains {
            if case .useLinearTriples = $0.change { return true }
            return false
        }, "a newer success makes an older three-miss run stale")

        for index in sessions.indices where sessions[index].dayIndex == 0 {
            sessions[index].exercises[0].prescriptionStyle = .linearFives
            sessions[index].exercises[0].plannedWeightLb = 100
            sessions[index].exercises[0].sets = (0..<3).map { _ in
                CoachingSetSnapshot(
                    actualWeightLb: 100, actualReps: 4,
                    plannedWeightLb: 100, plannedReps: 5
                )
            }
        }
        let lower = CoachingEngine.evaluate(
            program: program(patching: "squat") {
                $0.prescriptionStyle = .linearFives
                $0.baseWeightLb = 90
                $0.workingSets = 3
                $0.workingReps = 5
            }, sessions: sessions
        )
        XCTAssertFalse(lower.recommendations.contains {
            if case .useLinearTriples = $0.change { return true }
            return false
        }, "squat and pull transitions need authored light-day/frequency semantics")
    }

    private func rotationSlotID(_ recommendation: CoachingRecommendation) -> String? {
        if case .rotateExercise(let slotID, _) = recommendation.change { return slotID }
        return nil
    }

    private func greenRotations() -> [CoachingSessionSnapshot] {
        var sessions: [CoachingSessionSnapshot] = []
        for rotation in 1...3 {
            for dayIndex in 0...3 {
                sessions.append(session(cycle: 1, rotation: rotation, day: dayIndex,
                                        date: Double((rotation - 1) * 12 + dayIndex * 3) * day,
                                        weight: 100 + Double(rotation - 1) * 5))
            }
        }
        return sessions
    }

    private func program(
        patching slotID: String, _ patch: (inout CoachingProgramSlot) -> Void
    ) -> CoachingProgramSnapshot {
        var snapshot = program()
        guard let index = snapshot.slots.firstIndex(where: { $0.id == slotID }) else { return snapshot }
        patch(&snapshot.slots[index])
        return snapshot
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
    // [INV-ROTATION-JUDGED-AS-RUN]
    func testClosedRotationsAreJudgedByTheDaysTheyRan() {
        // A program that gains days had today's day list read back over every
        // earlier rotation, so finished work reported "1/4 days banked" forever.
        func session(_ cycle: Int, _ rotation: Int, _ day: Int, _ dayOffset: Int) -> CoachingSessionSnapshot {
            CoachingSessionSnapshot(
                id: "s\(cycle)-\(rotation)-\(day)",
                date: Date(timeIntervalSince1970: 1_780_000_000 + Double(dayOffset) * 86_400),
                programID: "p1", cycleNumber: cycle, rotation: rotation, dayIndex: day,
                exercises: []
            )
        }
        let program = CoachingProgramSnapshot(id: "p1", expectedDayIndexes: [0, 1, 2, 3], slots: [])
        let report = CoachingEngine.evaluate(program: program, sessions: [
            session(1, 1, 0, 0), session(1, 1, 1, 3),
            session(1, 2, 0, 6), session(1, 2, 1, 9),
            session(2, 1, 0, 40),
        ])
        XCTAssertEqual(report.rotations.count, 3)
        let closed = report.rotations.dropLast()
        XCTAssertTrue(closed.allSatisfy { $0.isComplete && $0.judgedAsRun },
                      "a closed rotation is complete against the days it ran")
        guard let live = report.rotations.last else {
            return XCTFail("expected a live rotation")
        }
        XCTAssertEqual(live.expectedDayIndexes, [0, 1, 2, 3],
                       "the live rotation is still measured against the current program")
        XCTAssertFalse(live.judgedAsRun)
        XCTAssertFalse(live.isComplete)
        // As-run rotations are complete by construction, so they must not seed
        // the green streak that unlocks capacity recommendations.
        XCTAssertEqual(report.greenRotationStreak, 0)
    }

    // One vocabulary and one window on both clients — a word added to one
    // copy and not the other flips rotation readiness per platform.
    // Mirrors the core.test.mjs hard-stop attribution block.
    func testHardStopVocabularyAndAttributionWindowAreShared() {
        XCTAssertEqual(CoachingEngine.checkInAttributionWindow, 36 * 60 * 60)
        for response in ["flagged the knee", "PAIN in the elbow", "swelling", "took the day off"] {
            XCTAssertTrue(CoachingEngine.isHardStopResponse(response), "\"\(response)\" is a hard stop")
        }
        for response in ["felt great", "a bit tired", ""] {
            XCTAssertFalse(CoachingEngine.isHardStopResponse(response), "\"\(response)\" is not a hard stop")
        }
    }

    // Mirrors the core.test.mjs shared-catalog block: the coach's defaults
    // and preferred-exercise names must be the same catalog on both clients.
    func testSharedCoachingCatalogsMatchTheWebMirror() {
        XCTAssertEqual(CoachingEngine.defaultMaximumSets, 6)
        XCTAssertEqual(CoachingEngine.defaultRepRange(for: .adductor).minReps, 8)
        XCTAssertEqual(CoachingEngine.defaultRepRange(for: .core).maxReps, 12)
        XCTAssertEqual(CoachingEngine.defaultRepRange(for: .verticalPull).minReps, 6)
        XCTAssertEqual(CoachingEngine.defaultRepRange(for: .verticalPull).maxReps, 10)
        XCTAssertEqual(CoachingEngine.preferredExerciseNames[.verticalPull]?.first, "Lat Pulldown")
        XCTAssertEqual(CoachingEngine.preferredExerciseNames[.core]?.contains("Plank"), true)
    }
}
