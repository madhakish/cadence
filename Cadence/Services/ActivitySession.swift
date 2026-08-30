import Foundation
import SwiftData
import CadenceCore

/// Builds the canonical ad-hoc activity session shape (#166): one completed,
/// off-program `WorkoutSession` holding the kind's canonical conditioning
/// entry with one completed duration set, plus the typed `ActivityDetail`.
/// Wood splitting is the first registered kind. Duration and implement load
/// live only on the set — the detail record never duplicates them
/// (INV-WOOD-WORK-DOES-NOT-GUESS keeps every optional user-entered).
enum ActivitySession {

    /// Wood-splitting facts (kind `woodSplitting`). A future kind carries
    /// its own typed facts struct rather than widening this one.
    struct WoodSplittingFacts {
        var rounds: Int?
        var splitPieces: Int?
        var estimatedStrikes: Int?
        var cordVolume: Double?
    }

    struct Input {
        var kind: ActivityKind
        var startDate: Date
        var durationSeconds: Int
        var sessionRPE: Double?
        /// Weight of the implement carried through the work (the splitting
        /// maul), recorded on the canonical set when supplied.
        var loadLb: Double?
        var notes: String
        var woodSplitting: WoodSplittingFacts?
    }

    enum Error: LocalizedError {
        case invalidDuration
        case missingExercise(String)

        var errorDescription: String? {
            switch self {
            case .invalidDuration: return "Duration must be greater than zero."
            case .missingExercise(let name): return "The exercise library is missing \(name)."
            }
        }
    }

    static func create(
        input: Input,
        exercises: [Exercise],
        context: ModelContext
    ) throws -> WorkoutSession {
        guard input.durationSeconds > 0 else { throw Error.invalidDuration }
        let exerciseName = input.kind.exerciseName
        guard let exercise = exercises.first(where: { $0.name == exerciseName }) else {
            throw Error.missingExercise(exerciseName)
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
            weightLb: input.loadLb ?? 0,
            reps: 0,
            status: .completed,
            durationSeconds: input.durationSeconds,
            loadBasis: exercise.loadBasis,
            implementCount: exercise.resolvedImplementCount,
            prescriptionBlock: .conditioning
        )
        context.insert(set)
        entry.sets.append(set)

        // Kind-specific facts attach only for their own kind, so a stray
        // field can never masquerade as another activity's data.
        let wood = input.kind == .woodSplitting ? input.woodSplitting : nil
        let detail = ActivityDetail(
            kindRaw: input.kind.rawValue,
            sessionRPE: input.sessionRPE,
            rounds: wood?.rounds,
            splitPieces: wood?.splitPieces,
            estimatedStrikes: wood?.estimatedStrikes,
            cordVolume: wood?.cordVolume
        )
        context.insert(detail)
        session.activityDetail = detail
        return session
    }

    /// Session-RPE workload (arbitrary units), derivable only when both the
    /// canonical duration set and a recorded RPE exist. Mirrors web
    /// `C.activityWorkload`.
    static func workload(for session: WorkoutSession) -> ActivityWorkload? {
        guard let detail = session.activityDetail, let kind = detail.kind else { return nil }
        let duration = session.orderedExercises
            .first { $0.exercise?.name == kind.exerciseName }?
            .workingSets.first?.durationSeconds
        return ActivityWorkload(durationSeconds: duration, sessionRPE: detail.sessionRPE)
    }
}
