import Foundation

public struct WoodSplittingWorkload: Equatable, Sendable {
    public let durationMinutes: Double
    public let sessionRPE: Double

    public init?(durationSeconds: Int?, sessionRPE: Double?) {
        guard let durationSeconds, durationSeconds > 0,
              let sessionRPE, sessionRPE > 0, sessionRPE <= 10 else { return nil }
        self.durationMinutes = Double(durationSeconds) / 60.0
        self.sessionRPE = sessionRPE
    }

    public var arbitraryUnits: Double { durationMinutes * sessionRPE }
}
