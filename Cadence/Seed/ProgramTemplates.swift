import Foundation
import SwiftData
import CadenceCore

/// Instantiates a program style from ProgramTemplateData (CadenceCore — the
/// data lives there so the Linux test job can enforce parity with the web
/// copy against the shared fixture). Mirrors web createProgramFromTemplate.
enum ProgramTemplates {

    /// Ensure the template's (non-seeded) exercises exist, then create the
    /// program — active only when it's the first, and under a name no other
    /// program holds: Program.name is a unique attribute, so a fixed name
    /// would silently UPSERT into an existing program, resetting its wave
    /// state and doubling its days.
    @discardableResult
    static func instantiate(_ template: ProgramTemplateData.Template, context: ModelContext) throws -> Program {
        // One fetch for the whole library (the Seeder.syncLibrary idiom). If
        // the fetch itself fails we must NOT insert: Exercise.name is unique,
        // and inserting over an unverifiable library would upsert-overwrite
        // the user's records. Throw so Settings can roll back and surface it.
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let have = Set(existing.map(\.name))
        for e in template.exercises where !have.contains(e.name) {
            context.insert(Exercise(
                name: e.name,
                category: ExerciseCategory(rawValue: e.category) ?? .accessory,
                type: ExerciseType(rawValue: e.type) ?? .bodyweight,
                movementGroup: e.group,
                isUnilateral: e.isUnilateral,
                defaultRestSeconds: e.rest
            ))
        }

        let existingPrograms = try context.fetch(FetchDescriptor<Program>())
        let recordedMaxes = try recordedE1RMs(
            for: Set(template.days.flatMap { $0.lifts.map(\.exercise) + $0.accessories.map(\.exercise) }),
            context: context
        )
        let program = Program(
            name: uniqueProgramName(template.name, existing: existingPrograms.map(\.name)),
            focus: TrainingFocus(rawValue: template.focus) ?? .strength,
            roundingLb: template.roundingLb,
            isActive: existingPrograms.isEmpty
        )
        context.insert(program)
        for (i, d) in template.days.enumerated() {
            let day = ProgramDay(name: d.name, order: i)
            context.insert(day)   // insert before appending children (Seeder pattern)
            // Mutate one side of each SwiftData relationship only. Setting the
            // inverse and appending as well stores the same model reference
            // more than once, which makes editor rows mirror one another.
            program.days.append(day)
            for (slotOrder, l) in d.lifts.enumerated() {
                var base = l.baseWeightLb
                var max = l.estimatedMaxLb
                let style = PrescriptionStyle(rawValue: l.prescription) ?? .automatic
                let fraction = l.startFraction > 0 ? l.startFraction : style.defaultStartFraction
                if fraction > 0, let e1RM = recordedMaxes[l.exercise], e1RM > 0 {
                    base = Swift.max(45, floorTo(fraction * e1RM, step: template.roundingLb))
                    max = (e1RM).rounded()
                }
                let lift = ProgramLift(exerciseName: l.exercise,
                                       role: LiftRole(rawValue: l.role) ?? .main,
                                       order: slotOrder,
                                       baseWeightLb: base, estimatedMaxLb: max)
                lift.prescription = style
                if l.sets > 0 { lift.doubleProgressionSets = l.sets }
                context.insert(lift)
                day.lifts.append(lift)
            }
            for (slotOrder, a) in d.accessories.enumerated() {
                var weight = a.weightLb
                if a.startFraction > 0, let e1RM = recordedMaxes[a.exercise], e1RM > 0 {
                    weight = Swift.max(45, floorTo(a.startFraction * e1RM, step: template.roundingLb))
                }
                let acc = ProgramAccessory(exerciseName: a.exercise, order: slotOrder, sets: a.sets, minReps: a.minReps,
                                           maxReps: a.maxReps, currentReps: a.minReps,
                                           weightLb: weight, incrementLb: a.incrementLb)
                context.insert(acc)
                day.accessories.append(acc)
            }
        }
        return program
    }

    /// Best recorded e1RM per exercise from completed, banked working sets —
    /// the lifter's known history, used to compute methodology starting
    /// weights. Mirrors web recordedE1RMs.
    private static func recordedE1RMs(for names: Set<String>, context: ModelContext) throws -> [String: Double] {
        guard !names.isEmpty else { return [:] }
        var best: [String: Double] = [:]
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        for session in sessions where session.isCompleted {
            for entry in session.exercises {
                guard let name = entry.exercise?.name, names.contains(name) else { continue }
                for set in entry.workingSets where set.weightLb > 0 && set.reps >= 1 {
                    let sample = ProgramProgression.epleyE1RM(weightLb: set.weightLb, reps: set.reps)
                    if sample > best[name] ?? 0 { best[name] = sample }
                }
            }
        }
        return best
    }

    /// Round DOWN to the plate step: methodology guidance is to err light when
    /// deriving starting weights from an estimated max.
    private static func floorTo(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step + 1e-9).rounded(.down) * step
    }

    /// First free name in "base", "base 2", "base 3"… — shared by the
    /// template and blank-program paths (both must respect name uniqueness).
    static func uniqueProgramName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
