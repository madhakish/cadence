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

public enum WorkoutClassification {
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
