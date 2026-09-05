import Foundation
import SwiftData
import CadenceCore

/// Typed facts for an ad-hoc activity session, attached one-to-one to a
/// `WorkoutSession` (schema V12, #166). The kind says which activity this
/// is (wood splitting first; more are added deliberately) and `sessionRPE`
/// applies to every kind. Kind-specific facts live here as their own typed
/// optional columns — nil for every other kind — never in notes or an
/// untyped blob. Duration and any implement load are NOT here: their one
/// canonical location is the session's conditioning `SetEntry`. Every field
/// is user-entered and optional; absence is preserved, never estimated
/// (INV-WOOD-WORK-DOES-NOT-GUESS).
@Model
final class ActivityDetail {
    @Attribute(.unique) var id: String = UUID().uuidString
    /// `ActivityKind` raw value: the persisted discriminator, read through
    /// `kind`, which is nil for anything unregistered. The importers reject
    /// an unregistered value before any write (a newer kind arrives with a
    /// newer backup version, which the version gate refuses first); the model
    /// itself does not validate, so readers must still treat `kind` as
    /// optional rather than assume this column holds a registered value.
    var kindRaw: String = ""
    /// Session RPE, 1.0–10.0, half steps supported. Applies to every kind.
    var sessionRPE: Double?
    // Wood-splitting facts (kind `woodSplitting`).
    var rounds: Int?
    var splitPieces: Int?
    var estimatedStrikes: Int?
    /// Cords split; fractional values are valid. Never derived from rounds,
    /// pieces, duration, or strikes.
    var cordVolume: Double?
    /// Inverse of `WorkoutSession.activityDetail`. Deliberately not an
    /// init parameter: creation sites set only the session side, per the
    /// one-side-of-an-inverse rule.
    var session: WorkoutSession?

    init(
        kindRaw: String,
        sessionRPE: Double? = nil,
        rounds: Int? = nil,
        splitPieces: Int? = nil,
        estimatedStrikes: Int? = nil,
        cordVolume: Double? = nil
    ) {
        self.kindRaw = kindRaw
        self.sessionRPE = sessionRPE
        self.rounds = rounds
        self.splitPieces = splitPieces
        self.estimatedStrikes = estimatedStrikes
        self.cordVolume = cordVolume
    }

    var kind: ActivityKind? { ActivityKind(rawValue: kindRaw) }
}
