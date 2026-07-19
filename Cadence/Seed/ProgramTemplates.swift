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
                let lift = ProgramLift(exerciseName: l.exercise,
                                       role: LiftRole(rawValue: l.role) ?? .main,
                                       order: slotOrder,
                                       baseWeightLb: l.baseWeightLb, estimatedMaxLb: l.estimatedMaxLb)
                context.insert(lift)
                day.lifts.append(lift)
            }
            for (slotOrder, a) in d.accessories.enumerated() {
                let acc = ProgramAccessory(exerciseName: a.exercise, order: slotOrder, sets: a.sets, minReps: a.minReps,
                                           maxReps: a.maxReps, currentReps: a.minReps,
                                           weightLb: a.weightLb, incrementLb: a.incrementLb)
                context.insert(acc)
                day.accessories.append(acc)
            }
        }
        return program
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
