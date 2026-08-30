import Foundation
import SwiftData
import CadenceCore

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

        let session = WorkoutSession(date: input.startDate, notes: input.notes)
        session.programID = nil
        session.programName = nil
        session.isCompleted = true
        session.completedAt = input.startDate.addingTimeInterval(TimeInterval(input.durationSeconds))

        let sessionExercise = SessionExercise(order: 0, exercise: exercise)
        let set = SetEntry(
            order: 0,
            weightLb: input.maulWeightLb ?? 0,
            reps: 0,
            status: .completed,
            durationSeconds: input.durationSeconds,
            loadBasis: .externalTotal
        )
        set.sessionExercise = sessionExercise
        sessionExercise.sets = [set]
        sessionExercise.session = session
        session.exercises = [sessionExercise]

        let detail = WoodSplittingDetail(
            sessionRPE: input.sessionRPE,
            rounds: input.rounds,
            splitPieces: input.splitPieces,
            estimatedStrikes: input.estimatedStrikes,
            cordVolume: input.cordVolume,
            session: session
        )
        session.woodSplittingDetail = detail

        context.insert(session)
        context.insert(sessionExercise)
        context.insert(set)
        context.insert(detail)
        return session
    }

    static func workload(for session: WorkoutSession) -> WoodSplittingWorkload? {
        guard let detail = session.woodSplittingDetail,
              let duration = session.orderedExercises.first?.workingSets.first?.durationSeconds else { return nil }
        return WoodSplittingWorkload(durationSeconds: duration, sessionRPE: detail.sessionRPE)
    }
}
