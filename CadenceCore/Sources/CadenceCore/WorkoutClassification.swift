import Foundation

public enum WorkoutModality: String, Codable, Hashable, Sendable {
    case traditionalStrength, crossTraining, running, walking, hiking, cycling, rowing, swimming
}

public struct CompletedExerciseKind: Hashable, Codable, Sendable {
    public let name: String
    public let type: String
    public let category: String

    public init(name: String, type: String, category: String) {
        self.name = name
        self.type = type
        self.category = category
    }
}

/// Which distance quantity a modality's miles belong to. Health keeps foot and
/// wheel distance in separate types, and the rest either cover no ground or
/// cover it in water — filing a swim under walking distance would be a lie.
public enum DistanceBasis: String, Codable, Hashable, Sendable {
    case foot, wheel
}

public enum WorkoutClassification {

    /// The distance type a modality contributes to, or nil when it contributes
    /// none.
    ///
    /// Deliberately per-exercise rather than per-session: a session's *overall*
    /// modality is `.crossTraining` the moment it mixes lifting with anything,
    /// which is the ordinary case for a strength day that ends with a walk.
    /// Deriving the distance type from that overall modality would silently
    /// discard the walk's miles.
    public static func distanceBasis(_ modality: WorkoutModality) -> DistanceBasis? {
        switch modality {
        case .running, .walking, .hiking: return .foot
        case .cycling: return .wheel
        case .traditionalStrength, .crossTraining, .rowing, .swimming: return nil
        }
    }

    /// The distance basis for a single completed exercise.
    public static func distanceBasis(for exercise: CompletedExerciseKind) -> DistanceBasis? {
        distanceBasis(modality(exercise))
    }

    public static func classify(_ exercises: [CompletedExerciseKind]) -> WorkoutModality {
        guard !exercises.isEmpty else { return .traditionalStrength }
        let conditioning = exercises.filter {
            $0.type.lowercased() == "conditioning" || $0.category.lowercased() == "conditioning"
        }
        let hasStrength = conditioning.count != exercises.count
        guard !conditioning.isEmpty else { return .traditionalStrength }
        if hasStrength { return .crossTraining }

        let modalities = Set(conditioning.map(modality))
        return modalities.count == 1 ? modalities.first! : .crossTraining
    }

    private static func modality(_ exercise: CompletedExerciseKind) -> WorkoutModality {
        let name = exercise.name.lowercased()
        if name.contains("swim") { return .swimming }
        if name.contains("row erg") || name == "rowing" { return .rowing }
        if name.contains("bike") || name.contains("cycle") { return .cycling }
        if name.contains("ruck") || name.contains("hike") { return .hiking }
        if name.contains("run") { return .running }
        if name.contains("walk") { return .walking }
        return .crossTraining
    }
}
