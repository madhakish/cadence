import Foundation
import SwiftData

@Model
final class WoodSplittingDetail {
    @Attribute(.unique) var id: String = UUID().uuidString
    var sessionRPE: Double?
    var rounds: Int?
    var splitPieces: Int?
    var estimatedStrikes: Int?
    var cordVolume: Double?
    var session: WorkoutSession?

    init(
        sessionRPE: Double? = nil,
        rounds: Int? = nil,
        splitPieces: Int? = nil,
        estimatedStrikes: Int? = nil,
        cordVolume: Double? = nil,
        session: WorkoutSession? = nil
    ) {
        self.sessionRPE = sessionRPE
        self.rounds = rounds
        self.splitPieces = splitPieces
        self.estimatedStrikes = estimatedStrikes
        self.cordVolume = cordVolume
        self.session = session
    }
}
