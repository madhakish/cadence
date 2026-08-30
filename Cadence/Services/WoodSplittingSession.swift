import Foundation
import SwiftData
import CadenceCore

/// Builds the canonical standalone wood-splitting session shape (#166): one
/// completed, off-program `WorkoutSession` holding one canonical
/// `Wood Splitting` conditioning entry with one completed duration set, plus
/// the typed `WoodSplittingDetail`. Duration and maul weight live only on the
/// set — the detail record never duplicates them
/// (INV-WOOD-WORK-DOES-NOT-GUESS keeps every optional user-entered).
enum WoodSplittingSession {
    static let exerciseName = "Wood Splitting"

    struct Input {
        var startDate: Date
        var durationSeconds: Int
        var sessionRPE: Double?
        var maulWeightLb: Double?
        var rounds: Int?
        var splitPieces: Int?
        var estimatedStrikes: Int?
        var cordVolume: Double?
        var notes: String
    }

    enum Error: LocalizedError {
        case invalidDuration
        case missingExercise

        var errorDescription: String? {
            switch self {
            case .invalidDuration: return "Duration must be greater than zero."
            case .missingExercise: return "The exercise library is missing Wood Splitting."
            }
        }
    }

    static func create(
        input: Input,
        exercises: [Exercise],
        context: ModelContext
    ) throws -> WorkoutSession {
        guard input.durationSeconds > 0 else { throw Error.invalidDuration }
        guard let exercise = exercises.first(where: { $0.name == exerciseName }) else {
            throw Error.missingExercise
        }

        // Banked already complete: quick logging never opens the set-by-set
        // logger, and it must never advance program state, so no program
        // fields are stamped (INV-WOOD-WORK-STANDS-ALONE).
        let session = WorkoutSession(date: input.startDate, notes: input.notes)
        session.isCompleted = true
        session.completedAt = input.startDate.addingTimeInterval(TimeInterval(input.durationSeconds))
        context.insert(session)

        // Insert-then-append, touching only the parent collection of each
        // inverse pair — mirrors ProgramSession; assigning the child inverse
        // as well can persist aliased rows (see normalizeRelationshipAliases).
        let entry = SessionExercise(order: 0, exercise: exercise)
        entry.exerciseID = exercise.id
        context.insert(entry)
        session.exercises.append(entry)

        let set = SetEntry(
            order: 0,
            weightLb: input.maulWeightLb ?? 0,
            reps: 0,
            status: .completed,
            durationSeconds: input.durationSeconds,
            loadBasis: exercise.loadBasis,
            implementCount: exercise.resolvedImplementCount,
            prescriptionBlock: .conditioning
        )
        context.insert(set)
        entry.sets.append(set)

        let detail = WoodSplittingDetail(
            sessionRPE: input.sessionRPE,
            rounds: input.rounds,
            splitPieces: input.splitPieces,
            estimatedStrikes: input.estimatedStrikes,
            cordVolume: input.cordVolume
        )
        context.insert(detail)
        session.woodSplittingDetail = detail
        return session
    }

    /// Session-RPE workload (arbitrary units), derivable only when both the
    /// canonical duration set and a recorded RPE exist. Mirrors web
    /// `C.woodSplittingWorkload`.
    static func workload(for session: WorkoutSession) -> WoodSplittingWorkload? {
        guard let detail = session.woodSplittingDetail else { return nil }
        let duration = session.orderedExercises
            .first { $0.exercise?.name == exerciseName }?
            .workingSets.first?.durationSeconds
        return WoodSplittingWorkload(durationSeconds: duration, sessionRPE: detail.sessionRPE)
    }
}
