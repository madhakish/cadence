import Foundation
import SwiftData
import CadenceCore

/// Builds a workout session from a program day: main + complementary lifts
/// (planned at the program's current week, barbell mains get a warmup ramp)
/// plus accessories, all tagged so completion advances PROGRAM state.
/// Mirrors web `createSessionFromProgramDay`.
enum ProgramSession {

    static func make(program: Program, day: ProgramDay, context: ModelContext) -> WorkoutSession {
        // Resume, don't duplicate (mirrors web createSessionFromProgramDay):
        // while a session for this program is open, Start returns it instead of
        // minting a second copy that would later try to advance the same
        // schedule position again (issue 17). The name is hoisted into a local
        // because a Predicate can't reference a captured object's property.
        let programName = program.name
        let openDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { !$0.isCompleted && $0.programName == programName }
        )
        if let existing = (try? context.fetch(openDescriptor))?.first { return existing }

        let defaultGym = (try? context.fetch(FetchDescriptor<Gym>()))?.first(where: { $0.isDefault })
        let session = WorkoutSession(gymName: defaultGym?.name)
        let barLb = (defaultGym?.defaultBar ?? .bar45lb).lb
        func neat(_ weightLb: Double, _ exercise: Exercise?, isMain: Bool) -> Double {
            neatWeight(weightLb, isBarbell: exercise?.type == .barbell, isMain: isMain, barLb: barLb, stepLb: program.roundingLb)
        }
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
            let weightLb = neat(plan.weightLb, exercise, isMain: lift.role.rawValue == "main")
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = lift.role.rawValue
            entry.plannedWeightLb = weightLb
            entry.plannedSets = plan.sets
            entry.plannedReps = plan.reps
            entry.phase = phase
            entry.session = session
            context.insert(entry)
            session.exercises.append(entry)

            var so = 0
            if exercise?.type == .barbell {
                for wu in WarmupRamp.ramp(workingLb: weightLb, barLb: barLb, roundingLb: program.roundingLb) {
                    insertSet(entry, order: so, weight: wu.weightLb, reps: wu.reps, warmup: true, perSide: false, context: context)
                    so += 1
                }
            }
            for _ in 0..<plan.sets {
                insertSet(entry, order: so, weight: weightLb, reps: plan.reps, warmup: false, perSide: exercise?.isUnilateral ?? false, context: context)
                so += 1
            }
            order += 1
        }

        for acc in day.orderedAccessories {
            let exercise = findExercise(named: acc.exerciseName, context: context)
            let weightLb = neat(acc.weightLb, exercise, isMain: false)
            let entry = SessionExercise(order: order, exercise: exercise)
            entry.programRole = "accessory"
            entry.plannedWeightLb = weightLb
            entry.plannedSets = acc.sets
            entry.plannedReps = acc.currentReps
            entry.session = session
            context.insert(entry)
            session.exercises.append(entry)
            for i in 0..<acc.sets {
                insertSet(entry, order: i, weight: weightLb, reps: acc.currentReps, warmup: false, perSide: exercise?.isUnilateral ?? false, context: context)
            }
            order += 1
        }

        return session
    }

    /// Secondary/accessory barbell prescriptions snap to a neat bar-loadable
    /// weight; mains and non-barbell work are left as-is. Shared with HomeView's
    /// preview so the card and the started session agree. Mirrors web `neatProgramWeight`.
    static func neatWeight(_ weightLb: Double, isBarbell: Bool, isMain: Bool, barLb: Double, stepLb: Double) -> Double {
        (!isMain && isBarbell) ? Weight.barLoadable(weightLb, barLb: barLb, stepLb: stepLb) : weightLb
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
