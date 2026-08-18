import Foundation

/// The training quality a program day is authored to emphasize. The intent is
/// explicit data because a mixed day cannot be classified reliably from its
/// display name or from whichever prescription happens to appear first.
public enum DayTrainingIntent: String, Codable, CaseIterable, Sendable {
    case general
    case heavy
    case volume
    case technique
    case explosive

    public var name: String {
        switch self {
        case .general: return "General"
        case .heavy: return "Heavy"
        case .volume: return "Volume"
        case .technique: return "Technique"
        case .explosive: return "Explosive"
        }
    }
}

/// Program-level boundary for automatic exercise selection. Manual library
/// edits remain available; this policy prevents an evolving free-weight plan
/// from silently acquiring machine work later.
public enum EquipmentPolicy: String, Codable, CaseIterable, Sendable {
    case any
    case freeWeightsOnly

    public var name: String {
        switch self {
        case .any: return "Any equipment"
        case .freeWeightsOnly: return "Free weights + bodyweight"
        }
    }

    public func allows(exerciseType: String) -> Bool {
        guard self == .freeWeightsOnly else { return true }
        // "timed" is a LOGGING type, not equipment: every timed movement in
        // the catalog is a bodyweight isometric (planks, holds). Excluding it
        // made the adductor volume floor permanently unfillable under this
        // policy — a blocked notice no in-app action could ever satisfy.
        return ["barbell", "dumbbell", "kettlebell", "bodyweight", "timed"]
            .contains(exerciseType.lowercased())
    }
}
