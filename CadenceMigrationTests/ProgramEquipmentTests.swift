import CadenceCore
import Foundation
import SwiftData
import XCTest

@MainActor
final class ProgramEquipmentTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV16.self)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    func testExplicitRackPolicyUsesOriginalWorkingAndWarmupTargets() {
        let gym = Gym(name: "Synthetic pound rack")
        gym.plateToggles = Plate.standardLb.map { PlateToggle(plate: $0) }
        let lift = Exercise(name: "Synthetic squat", category: .main, type: .barbell, movementGroup: "squat")
        let examples: [(LoadingPolicy, Double, CyclePhase, Double)] = [
            (.under, 132, .volume, 130), (.over, 138, .deload, 140), (.exact, 130, .volume, 130)
        ]
        for (policy, target, phase, expected) in examples {
            gym.loadingPolicy = policy
            for main in [true, false] {
                XCTAssertEqual(ProgramSession.achievableWeight(
                    target, exercise: lift, isMain: main, gym: gym, bar: .bar45lb,
                    stepLb: 5, phase: phase
                ), expected)
            }
            let ramp = ProgramSession.achievableWarmups(
                [WarmupSet(weightLb: target, reps: 3)], workingLb: 185,
                gym: gym, bar: .bar45lb, exercise: lift
            )
            XCTAssertEqual(ramp, [WarmupSet(weightLb: expected, reps: 3)])
        }
    }

    func testFiveThreeOneWarmupsFinishBelowFirstPrescribedRamp() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let squat = Exercise(name: "Back Squat", category: .main, type: .barbell, movementGroup: "squat")
        let program = Program(name: "Synthetic 531")
        let day = ProgramDay(name: "Lower", order: 0)
        let lift = ProgramLift(exerciseName: squat.name, role: .main, prescription: .fiveThreeOne,
                               baseWeightLb: 300, estimatedMaxLb: 340)
        context.insert(squat)
        context.insert(program)
        context.insert(day)
        context.insert(lift)
        program.days.append(day)
        day.lifts.append(lift)
        let session = try ProgramSession.make(program: program, day: day, context: context)
        let entry = try XCTUnwrap(session.exercises.first)
        let sets = entry.orderedSets
        let opener = try XCTUnwrap(sets.first { $0.prescriptionBlock == .ramp })
        let warmups = sets.filter(\.isWarmup)
        XCTAssertFalse(warmups.isEmpty)
        XCTAssertTrue(warmups.allSatisfy { $0.weightLb < opener.weightLb })

        let prescribedLoads = sets.filter { !$0.isWarmup }.map(\.weightLb)
        XCTAssertGreaterThan(try XCTUnwrap(entry.plannedWeightLb), opener.weightLb)
        entry.barID = Bar.bar35lb.id
        synchronizeWarmups(entry, bar: .bar35lb, gym: nil, enteredUnit: .lb, context: context)
        let rebuilt = entry.orderedSets.filter(\.isWarmup)
        XCTAssertFalse(rebuilt.isEmpty)
        XCTAssertTrue(rebuilt.allSatisfy { $0.weightLb < opener.weightLb })
        XCTAssertEqual(entry.orderedSets.filter { !$0.isWarmup }.map(\.weightLb), prescribedLoads)
    }

    func testRestrictionRemovesMachineSlotsWithoutRewritingHistoryOrProgress() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let row = Exercise(name: "Single-arm DB Row", category: .main, type: .dumbbell, movementGroup: "pull")
        let machine = Exercise(name: "Face Pulls", category: .accessory, type: .machine, movementGroup: "pull")
        let oldRow = Exercise(name: "Chest-supported Row", category: .accessory, type: .machine, movementGroup: "pull")
        for exercise in [row, machine, oldRow] { context.insert(exercise) }
        let program = Program(name: "Synthetic restriction", cycleNumber: 4, currentWeek: 2)
        context.insert(program)
        let day = ProgramDay(name: "Upper", order: 0)
        context.insert(day); program.days.append(day)
        let lift = ProgramLift(exerciseName: row.name, role: .main, baseWeightLb: 35, estimatedMaxLb: 45)
        lift.revertToExerciseName = oldRow.name
        lift.stallCount = 1
        context.insert(lift); day.lifts.append(lift)
        let accessory = ProgramAccessory(exerciseName: machine.name, sets: 3, minReps: 8, maxReps: 12, currentReps: 8, weightLb: 25, incrementLb: 5)
        context.insert(accessory); day.accessories.append(accessory)
        let history = WorkoutSession()
        history.isCompleted = true; history.programID = program.id
        context.insert(history)
        let entry = SessionExercise(order: 0, exercise: machine)
        entry.programSlotID = accessory.id
        context.insert(entry); history.exercises.append(entry)
        let set = SetEntry(order: 0, weightLb: 25, reps: 8, status: .completed)
        context.insert(set); entry.sets.append(set)
        try context.save()
        let slotID = lift.id

        XCTAssertEqual(try ProgramEquipmentService.apply(.freeWeightsOnly, to: program, context: context), [machine.name])
        try context.save()
        XCTAssertTrue(day.accessories.isEmpty)
        XCTAssertEqual(day.lifts.first?.id, slotID)
        XCTAssertNil(lift.revertToExerciseName)
        XCTAssertEqual(lift.baseWeightLb, 35)
        XCTAssertEqual(lift.stallCount, 1)
        XCTAssertEqual(program.cycleNumber, 4)
        XCTAssertEqual(program.currentWeek, 2)
        XCTAssertEqual(entry.exercise?.id, machine.id)
        XCTAssertEqual(entry.sets.first?.weightLb, 25)
        XCTAssertEqual(entry.sets.first?.status, .completed)
        XCTAssertNoThrow(try ProgramEquipmentService.assertAllowed(program, exercises: [row, machine, oldRow]))
        XCTAssertTrue(try ProgramEquipmentService.apply(.freeWeightsOnly, to: program, context: context).isEmpty)
    }

    func testOpenWorkoutPreventsPartialProgramMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let machine = Exercise(name: "Face Pulls", category: .accessory, type: .machine, movementGroup: "pull")
        context.insert(machine)
        let program = Program(name: "Synthetic open workout")
        context.insert(program)
        let day = ProgramDay(name: "Upper", order: 0)
        context.insert(day); program.days.append(day)
        let accessory = ProgramAccessory(exerciseName: machine.name, sets: 3, minReps: 8, maxReps: 12, currentReps: 8, weightLb: 25, incrementLb: 5)
        context.insert(accessory); day.accessories.append(accessory)
        let session = WorkoutSession()
        session.programID = program.id
        context.insert(session)
        try context.save()
        program.name = "Unsaved renamed program"
        program.roundingLb = 2.5
        XCTAssertThrowsError(try ProgramEquipmentService.applyAndSave(.freeWeightsOnly, to: program, context: context))
        XCTAssertEqual(program.name, "Unsaved renamed program", "refused equipment changes preserve other form edits")
        XCTAssertEqual(program.roundingLb, 2.5)
        XCTAssertEqual(program.equipmentPolicy, .any)
        XCTAssertEqual(day.accessories.count, 1)
        program.equipmentPolicy = .freeWeightsOnly
        XCTAssertThrowsError(try ProgramEquipmentService.assertAllowed(program, exercises: [machine]))
    }
}
