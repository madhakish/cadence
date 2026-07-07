import Foundation
import SwiftData
import CadenceCore

/// Builds a workout session from a program day: main + complementary lifts
/// (planned at the program's current week, barbell mains get a warmup ramp)
/// plus accessories, all tagged so completion advances PROGRAM state.
/// Mirrors web `createSessionFromProgramDay`.
enum ProgramSession {

    static func make(program: Program, day: ProgramDay, context: ModelContext) -> WorkoutSession {
        let gymName = (try? context.fetch(FetchDescriptor<Gym>()))?.first(where: { $0.isDefault })?.name
        let session = WorkoutSession(gymName: gymName)
        session.programName = program.name
        session.programCycleNumber = program.cycleNumber
        session.programWeek = program.currentWeek
        session.programDayIndex = day.order
        context.insert(session)

        let phase = CyclePhase(rawValue: program.currentWeek) ?? .volume
        var order = 0

        for lift in day.orderedLifts {
            let plan = ProgramEngine.plan(
                for: CycleState(cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: phase, incrementLb: 0),
                roundingLb: program.roundingLb
            )
            let exercise = findExercise(named: lift.exerciseName, context: context)
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = lift.role.rawValue
            entry.plannedWeightLb = plan.weightLb
            entry.plannedSets = plan.sets
            entry.plannedReps = plan.reps
            entry.phase = phase
            entry.session = session
            context.insert(entry)
            session.exercises.append(entry)

            var so = 0
            if exercise?.type == .barbell {
                for wu in WarmupRamp.ramp(workingLb: plan.weightLb, roundingLb: program.roundingLb) {
                    insertSet(entry, order: so, weight: wu.weightLb, reps: wu.reps, warmup: true, perSide: false, context: context)
                    so += 1
                }
            }
            for _ in 0..<plan.sets {
                insertSet(entry, order: so, weight: plan.weightLb, reps: plan.reps, warmup: false, perSide: exercise?.isUnilateral ?? false, context: context)
                so += 1
            }
            order += 1
        }

        for acc in day.orderedAccessories {
            let exercise = findExercise(named: acc.exerciseName, context: context)
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = "accessory"
            entry.plannedWeightLb = acc.weightLb
            entry.plannedSets = acc.sets
            entry.plannedReps = acc.currentReps
            entry.session = session
            context.insert(entry)
            session.exercises.append(entry)
            for i in 0..<acc.sets {
                insertSet(entry, order: i, weight: acc.weightLb, reps: acc.currentReps, warmup: false, perSide: exercise?.isUnilateral ?? false, context: context)
            }
            order += 1
        }

        return session
    }

    private static func insertSet(_ entry: SessionExercise, order: Int, weight: Double, reps: Int, warmup: Bool, perSide: Bool, context: ModelContext) {
        let set = SetEntry(order: order, weightLb: weight, reps: reps, isWarmup: warmup, isPerSide: perSide)
        set.sessionExercise = entry
        context.insert(set)
        entry.sets.append(set)
    }

    private static func findExercise(named name: String, context: ModelContext) -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
        return try? context.fetch(descriptor).first
    }
}
