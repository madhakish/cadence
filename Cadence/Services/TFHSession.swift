import Foundation
import SwiftData
import CadenceCore

enum TFHSession {
    static func practice(exercise: Exercise, weight: Double, sets: Int, seconds: Int?, rotation: Int) throws
        -> (weightLb: Double, sets: Int, seconds: Int) {
        guard let seconds, seconds > 0, sets > 0, weight.isFinite, weight >= 0 else {
            throw TFHProgramService.Failure.invalid("\(exercise.name) needs an authored duration and load.")
        }
        let load = exercise.type == .conditioning && CardioFormat.carriesLoad(exerciseName: exercise.name)
            ? (weight > 0 ? weight : (CardioFormat.defaultLoadLb(exerciseName: exercise.name) ?? 0)) : weight
        return (load, rotation == 4 ? 1 : sets, rotation == 4 ? max(1, seconds / 2) : seconds)
    }

    static func achieved(_ plan: TFHPrescription, exercise: Exercise, program: Program, gym: Gym?) -> Double {
        return ProgramSession.achievableWeight(plan.weightLb, exercise: exercise, isMain: true,
            gym: gym, bar: gym?.defaultBar ?? .bar45lb, stepLb: program.roundingLb,
            phase: plan.state == "recover" ? .deload : .volume)
    }

    static func make(program: Program, context: ModelContext) throws -> WorkoutSession {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        guard let p = try TFHProgramService.policy(program),
              let next = try TFHProgramService.synchronize(program, sessions: sessions),
              let day = program.day(order: next.dayOrder) else { throw TFHProgramService.Failure.invalid("No next training day.") }
        let open = sessions.filter { !$0.isCompleted && $0.programID == program.id }
        if let existing = open.first {
            guard open.count == 1, existing.tfhPolicyID == p.id,
                  existing.programCycleNumber == next.cycle, existing.programWeek == next.rotation,
                  existing.programDayIndex == next.dayOrder else {
                throw TFHProgramService.Failure.invalid("Finish or discard the existing session before starting another.")
            }
            return existing
        }
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let gyms = try context.fetch(FetchDescriptor<Gym>())
        let gym = gyms.first { $0.isDefault } ?? gyms.first
        let unit = try context.fetch(FetchDescriptor<AppSettings>()).first?.unitDisplay.primaryUnit ?? .lb
        let session = WorkoutSession(gymID: gym?.id, gymName: gym?.name)
        session.programID = program.id; session.programName = program.name
        session.programTemplateID = program.templateID; session.programCycleNumber = next.cycle
        session.programWeek = next.rotation; session.programDayIndex = next.dayOrder
        session.programPlanNames = day.orderedLifts.map(\.exerciseName) + day.orderedAccessories.map(\.exerciseName)
        session.tfhPolicyID = p.id
        context.insert(session)
        func add(id: String, name: String, role: String, weight: Double, sets: Int, seconds: Int?) throws {
            guard let ex = exercises.first(where: { $0.name == name }), let exID = ex.id else {
                throw TFHProgramService.Failure.invalid("\(name) is missing from the exercise library.")
            }
            let projected = try TFHProgramService.prescription(program, slotID: id, sessions: sessions)
            guard projected != nil || ex.type == .timed || ex.type == .conditioning else {
                throw TFHProgramService.Failure.invalid("\(name) has no TFH anchor. Review setup.")
            }
            if let a = projected?.0 {
                guard a.exerciseId == exID, a.loadBasis == ex.loadBasis,
                      a.implementCount == ex.resolvedImplementCount, a.isPerSide == ex.isUnilateral else {
                    throw TFHProgramService.Failure.invalid("\(name)'s load convention changed. Review setup.")
                }
            }
            let entry = SessionExercise(order: session.exercises.count, exercise: ex)
            entry.exerciseID = exID; entry.programSlotID = id; entry.programRole = role
            entry.stampBarID(for: ex, bar: gym?.defaultBar ?? .bar45lb)
            entry.phase = CyclePhase(rawValue: next.rotation)
            entry.tfhAnchorData = try TFHProgramService.encode(projected?.0)
            let timed = projected == nil ? try practice(exercise: ex, weight: weight, sets: sets,
                                                         seconds: seconds, rotation: next.rotation) : nil
            let load = projected.map { achieved($0.1, exercise: ex, program: program, gym: gym) } ?? timed?.weightLb ?? weight
            let duration = timed?.seconds
            let targets = projected?.1.reps ?? Array(repeating: 1, count: timed?.sets ?? 1)
            entry.targetWeightLb = projected?.1.weightLb ?? load
            entry.plannedWeightLb = load; entry.plannedSets = targets.count; entry.plannedReps = targets.first
            entry.plannedDurationSeconds = duration
            entry.prescriptionStyleRaw = "doubleProgression"
            context.insert(entry); session.exercises.append(entry)
            if role != "accessory" && ex.type == .barbell {
                let bar = gym?.defaultBar ?? .bar45lb
                let ramp = WarmupRamp.ramp(workingLb: load, barLb: bar.lb, roundingLb: program.roundingLb,
                                          includeEmptyBar: ProgramSession.includesEmptyBarWarmup(for: ex))
                for wu in ProgramSession.achievableWarmups(ramp, workingLb: load, gym: gym, bar: bar, exercise: ex) {
                    let set = SetEntry(order: entry.sets.count, weightLb: wu.weightLb, reps: wu.reps,
                        isWarmup: true, enteredUnit: unit, loadBasis: ex.loadBasis,
                        implementCount: ex.resolvedImplementCount, targetWeightLb: wu.weightLb,
                        plannedWeightLb: wu.weightLb, plannedReps: wu.reps, prescriptionBlock: .warmup)
                    context.insert(set); entry.sets.append(set)
                }
            }
            for (index, reps) in targets.enumerated() {
                let benchmark = projected?.1.benchmark == true && index == targets.count - 1
                let set = SetEntry(order: entry.sets.count, weightLb: load, reps: reps,
                    isPerSide: ex.isUnilateral, enteredUnit: unit, durationSeconds: duration,
                    loadBasis: ex.loadBasis, implementCount: ex.resolvedImplementCount,
                    targetWeightLb: entry.targetWeightLb, plannedWeightLb: load,
                    plannedReps: reps, plannedDurationSeconds: duration,
                    prescriptionBlock: seconds != nil ? .conditioning : (benchmark ? .amrap : .work))
                if benchmark { set.tfhBenchmarkData = try TFHProgramService.encode(TFHBenchmarkResult()) }
                context.insert(set); entry.sets.append(set)
            }
        }
        for l in day.orderedLifts { try add(id: l.id, name: l.exerciseName, role: l.roleRaw,
                                           weight: l.baseWeightLb, sets: l.doubleProgressionSets, seconds: nil) }
        for a in day.orderedAccessories {
            let ex = exercises.first { $0.name == a.exerciseName }
            try add(id: a.id, name: a.exerciseName, role: "accessory", weight: a.weightLb, sets: a.sets,
                    seconds: ex?.type == .timed || ex?.type == .conditioning ? a.targetSeconds : nil)
        }
        return session
    }
}
