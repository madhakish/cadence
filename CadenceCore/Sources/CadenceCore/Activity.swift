import Foundation

/// The registered ad-hoc activity kinds — real physical work logged as one
/// completed, off-program conditioning `WorkoutSession` on the same timeline
/// as training (#166). Wood splitting is the first; a future kind (mountain
/// biking, hiking, climbing, portaging, …) is added here deliberately, with
/// its own typed facts, seeded exercise, and a backup-contract version bump —
/// never inferred from an exercise name.
public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case woodSplitting

    /// The canonical seeded conditioning exercise this kind logs against.
    /// One spelling on both clients; the quick-log flow resolves the library
    /// row BY THIS NAME. Mirrors web `C.activityExerciseName`.
    public var exerciseName: String {
        switch self {
        case .woodSplitting: return "Wood Splitting"
        }
    }
}

/// Session-RPE workload for ad-hoc activity sessions (#166):
/// `duration minutes × session RPE`, in arbitrary units. This is a relative
/// session-load value, never barbell tonnage
/// (INV-WOOD-WORK-IS-NOT-LIFTING-VOLUME). It exists only when both inputs
/// were recorded — a missing duration or RPE yields nil, not an estimate.
/// Mirrors web `C.activityWorkload`.
public struct ActivityWorkload: Equatable, Sendable {
    /// The recorded session-RPE contract, one spelling for every consumer:
    /// this initializer, the creator's write guard, and the backup
    /// validators on both clients (web mirrors it as
    /// `C.ACTIVITY_SESSION_RPE`).
    public static let sessionRPERange: ClosedRange<Double> = 1...10

    public let durationMinutes: Double
    public let sessionRPE: Double

    /// RPE follows the recorded contract, 1.0–10.0 inclusive; anything
    /// outside is invalid input, not a clampable value.
    public init?(durationSeconds: Int?, sessionRPE: Double?) {
        guard let durationSeconds, durationSeconds > 0,
              let sessionRPE, Self.sessionRPERange.contains(sessionRPE) else { return nil }
        self.durationMinutes = Double(durationSeconds) / 60.0
        self.sessionRPE = sessionRPE
    }

    public var arbitraryUnits: Double { durationMinutes * sessionRPE }
}
