import Foundation
import SwiftData
import CadenceCore

/// Equipment is a boundary on the program, including existing authored slots.
/// Applying it changes only the plan; performed sessions keep their identities.
enum ProgramEquipmentService {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func assertAllowed(_ program: Program, exercises: [Exercise]) throws {
        guard program.equipmentPolicy != .any else { return }
        let byName = exercises.indexedByName()
        let names = program.orderedDays.flatMap { $0.orderedLifts.map(\.exerciseName) + $0.orderedAccessories.map(\.exerciseName) }
        let blocked = names.filter { !program.equipmentPolicy.allows(exerciseType: byName[$0]?.typeRaw ?? "") }
        guard blocked.isEmpty else {
            throw Failure(message: "Equipment restriction excludes \(blocked.joined(separator: ", ")). Apply the restriction in program settings to remove those slots.")
        }
    }

    @discardableResult
    static func apply(_ policy: EquipmentPolicy, to program: Program, context: ModelContext) throws -> [String] {
        let byName = try context.fetch(FetchDescriptor<Exercise>()).indexedByName()
        let names = program.orderedDays.flatMap { $0.orderedLifts.map(\.exerciseName) + $0.orderedAccessories.map(\.exerciseName) }
        let missing = policy == .any ? [] : names.filter { byName[$0] == nil }
        guard missing.isEmpty else {
            throw Failure(message: "The exercise library is missing \(missing.joined(separator: ", ")). Restore its definition before changing equipment.")
        }
        func allowed(_ name: String) -> Bool { policy.allows(exerciseType: byName[name]?.typeRaw ?? "") }
        let lifts = program.orderedDays.flatMap(\.orderedLifts).filter { !allowed($0.exerciseName) }
        let accessories = program.orderedDays.flatMap(\.orderedAccessories).filter { !allowed($0.exerciseName) }
        let removed = lifts.map(\.exerciseName) + accessories.map(\.exerciseName)
        // Validate before any mutation. Open sessions must retain the plan
        // they were created from; TFH layout changes require a new cohort.
        if !removed.isEmpty {
            guard program.tfhPolicyData == nil else {
                throw Failure(message: "This changes the TFH layout. Remove the blocked exercises and review TFH setup before applying the equipment restriction.")
            }
            let open = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { !$0.isCompleted }))
            guard !open.contains(where: { $0.programID == program.id || ($0.programID == nil && $0.programName == program.name) }) else {
                throw Failure(message: "Finish the current workout before removing program exercises. Its recorded sets will be kept.")
            }
        }
        for day in program.orderedDays {
            for lift in day.orderedLifts where allowed(lift.exerciseName) {
                if let original = lift.revertToExerciseName, !allowed(original) { lift.revertToExerciseName = nil }
            }
            for accessory in day.orderedAccessories where allowed(accessory.exerciseName) {
                if let original = accessory.revertToExerciseName, !allowed(original) { accessory.revertToExerciseName = nil }
            }
        }
        for lift in lifts { context.delete(lift) }
        for accessory in accessories { context.delete(accessory) }
        program.equipmentPolicy = policy
        return removed
    }
}
