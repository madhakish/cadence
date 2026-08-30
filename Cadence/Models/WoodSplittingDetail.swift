import Foundation
import SwiftData

/// Typed wood-splitting facts attached one-to-one to a `WorkoutSession`
/// (schema V12, #166). Duration and maul weight are NOT here — their one
/// canonical location is the session's conditioning `SetEntry`. Every field
/// is user-entered and optional; absence is preserved, never estimated
/// (INV-WOOD-WORK-DOES-NOT-GUESS).
@Model
final class WoodSplittingDetail {
    @Attribute(.unique) var id: String = UUID().uuidString
    /// Session RPE, 1.0–10.0, half steps supported.
    var sessionRPE: Double?
    var rounds: Int?
    var splitPieces: Int?
    var estimatedStrikes: Int?
    /// Cords split; fractional values are valid. Never derived from rounds,
    /// pieces, duration, or strikes.
    var cordVolume: Double?
    /// Inverse of `WorkoutSession.woodSplittingDetail`. Deliberately not an
    /// init parameter: creation sites set only the session side, per the
    /// one-side-of-an-inverse rule.
    var session: WorkoutSession?

    init(
        sessionRPE: Double? = nil,
        rounds: Int? = nil,
        splitPieces: Int? = nil,
        estimatedStrikes: Int? = nil,
        cordVolume: Double? = nil
    ) {
        self.sessionRPE = sessionRPE
        self.rounds = rounds
        self.splitPieces = splitPieces
        self.estimatedStrikes = estimatedStrikes
        self.cordVolume = cordVolume
    }
}
