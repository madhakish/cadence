import Foundation

/// Session-RPE workload for standalone wood-splitting sessions (#166):
/// `duration minutes × session RPE`, in arbitrary units. This is a relative
/// session-load value, never barbell tonnage
/// (INV-WOOD-WORK-IS-NOT-LIFTING-VOLUME). It exists only when both inputs
/// were recorded — a missing duration or RPE yields nil, not an estimate.
/// Mirrors web `C.woodSplittingWorkload`.
public struct WoodSplittingWorkload: Equatable, Sendable {
    public let durationMinutes: Double
    public let sessionRPE: Double

    /// RPE follows the recorded contract, 1.0–10.0 inclusive; anything
    /// outside is invalid input, not a clampable value.
    public init?(durationSeconds: Int?, sessionRPE: Double?) {
        guard let durationSeconds, durationSeconds > 0,
              let sessionRPE, sessionRPE >= 1, sessionRPE <= 10 else { return nil }
        self.durationMinutes = Double(durationSeconds) / 60.0
        self.sessionRPE = sessionRPE
    }

    public var arbitraryUnits: Double { durationMinutes * sessionRPE }
}
