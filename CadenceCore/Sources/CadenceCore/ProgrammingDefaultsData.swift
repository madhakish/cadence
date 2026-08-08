import Foundation

/// Conservative, nonpersonal bootstrap loads for program construction.
///
/// This is reference data, not athlete state: it is never persisted, exported,
/// or mixed with body measurements. Program creation replaces these values
/// with completed workout history whenever that history exists.
public enum ProgrammingDefaultsData {

    public struct Recommendation: Codable, Equatable {
        public let exerciseName: String?
        public let slotCategory: String
        public let exerciseType: String
        public let weightLb: Double
        public let estimatedMaxLb: Double
        public let incrementLb: Double

        public init(
            exerciseName: String? = nil,
            slotCategory: String,
            exerciseType: String,
            weightLb: Double,
            estimatedMaxLb: Double,
            incrementLb: Double
        ) {
            self.exerciseName = exerciseName
            self.slotCategory = slotCategory
            self.exerciseType = exerciseType
            self.weightLb = weightLb
            self.estimatedMaxLb = estimatedMaxLb
            self.incrementLb = incrementLb
        }
    }

    /// Exact movement overrides precede equipment fallbacks. Values are
    /// intentionally unambitious: the first recorded workout becomes the
    /// user's real starting point, and subsequent programs reuse it.
    public static let all: [Recommendation] = [
        // Main-lift overrides where an empty 45 lb bar is not the most useful
        // universal first exposure.
        Recommendation(exerciseName: "Deadlift", slotCategory: "Main", exerciseType: "barbell", weightLb: 65, estimatedMaxLb: 95, incrementLb: 5),
        Recommendation(exerciseName: "Snatch", slotCategory: "Main", exerciseType: "barbell", weightLb: 35, estimatedMaxLb: 55, incrementLb: 5),
        Recommendation(exerciseName: "Overhead Squat", slotCategory: "Main", exerciseType: "barbell", weightLb: 35, estimatedMaxLb: 55, incrementLb: 5),
        Recommendation(exerciseName: "Clean & Jerk", slotCategory: "Main", exerciseType: "barbell", weightLb: 45, estimatedMaxLb: 65, incrementLb: 5),
        Recommendation(exerciseName: "Incline DB Press", slotCategory: "Main", exerciseType: "dumbbell", weightLb: 10, estimatedMaxLb: 20, incrementLb: 5),

        // Loaded accessories in the bundled templates. Dumbbell values are
        // per implement under Cadence's load semantics.
        Recommendation(exerciseName: "Y-T-W Raises", slotCategory: "Accessory", exerciseType: "dumbbell", weightLb: 5, estimatedMaxLb: 8, incrementLb: 2.5),
        Recommendation(exerciseName: "Rear Delt Fly", slotCategory: "Accessory", exerciseType: "dumbbell", weightLb: 5, estimatedMaxLb: 8, incrementLb: 2.5),
        Recommendation(exerciseName: "DB Overhead Triceps Extension", slotCategory: "Accessory", exerciseType: "dumbbell", weightLb: 5, estimatedMaxLb: 10, incrementLb: 2.5),
        Recommendation(exerciseName: "KB Swing", slotCategory: "Accessory", exerciseType: "kettlebell", weightLb: 15, estimatedMaxLb: 25, incrementLb: 5),
        Recommendation(exerciseName: "Goblet Squat", slotCategory: "Accessory", exerciseType: "kettlebell", weightLb: 15, estimatedMaxLb: 25, incrementLb: 5),
        Recommendation(exerciseName: "Skull Crusher", slotCategory: "Accessory", exerciseType: "barbell", weightLb: 20, estimatedMaxLb: 30, incrementLb: 5),
        Recommendation(exerciseName: "Barbell Row", slotCategory: "Accessory", exerciseType: "barbell", weightLb: 45, estimatedMaxLb: 65, incrementLb: 5),
        Recommendation(exerciseName: "Snatch Pull", slotCategory: "Accessory", exerciseType: "barbell", weightLb: 45, estimatedMaxLb: 65, incrementLb: 5),
        Recommendation(exerciseName: "Clean Pull", slotCategory: "Accessory", exerciseType: "barbell", weightLb: 45, estimatedMaxLb: 65, incrementLb: 5),
        Recommendation(exerciseName: "Overhead Press", slotCategory: "Accessory", exerciseType: "barbell", weightLb: 45, estimatedMaxLb: 65, incrementLb: 5),
        Recommendation(exerciseName: "Barbell Bench", slotCategory: "Accessory", exerciseType: "barbell", weightLb: 45, estimatedMaxLb: 65, incrementLb: 5),
        Recommendation(exerciseName: "Back Squat", slotCategory: "Accessory", exerciseType: "barbell", weightLb: 45, estimatedMaxLb: 65, incrementLb: 5),
        Recommendation(exerciseName: "Deadlift", slotCategory: "Accessory", exerciseType: "barbell", weightLb: 65, estimatedMaxLb: 95, incrementLb: 5),
        Recommendation(exerciseName: "Face Pulls", slotCategory: "Accessory", exerciseType: "machine", weightLb: 10, estimatedMaxLb: 20, incrementLb: 5),
        Recommendation(exerciseName: "Triceps Pushdown", slotCategory: "Accessory", exerciseType: "machine", weightLb: 10, estimatedMaxLb: 20, incrementLb: 5),
        Recommendation(exerciseName: "Lat Pulldown", slotCategory: "Accessory", exerciseType: "machine", weightLb: 20, estimatedMaxLb: 35, incrementLb: 5),
        Recommendation(exerciseName: "Lying Leg Curl", slotCategory: "Accessory", exerciseType: "machine", weightLb: 20, estimatedMaxLb: 35, incrementLb: 5),

        // Slot/equipment fallbacks cover imported and user-created exercises.
        Recommendation(slotCategory: "Main", exerciseType: "barbell", weightLb: 45, estimatedMaxLb: 65, incrementLb: 5),
        Recommendation(slotCategory: "Main", exerciseType: "dumbbell", weightLb: 10, estimatedMaxLb: 20, incrementLb: 5),
        Recommendation(slotCategory: "Main", exerciseType: "kettlebell", weightLb: 15, estimatedMaxLb: 25, incrementLb: 5),
        Recommendation(slotCategory: "Main", exerciseType: "machine", weightLb: 20, estimatedMaxLb: 35, incrementLb: 5),
        Recommendation(slotCategory: "Main", exerciseType: "bodyweight", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
        Recommendation(slotCategory: "Main", exerciseType: "band", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
        Recommendation(slotCategory: "Main", exerciseType: "timed", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
        Recommendation(slotCategory: "Main", exerciseType: "conditioning", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
        Recommendation(slotCategory: "Accessory", exerciseType: "barbell", weightLb: 20, estimatedMaxLb: 30, incrementLb: 5),
        Recommendation(slotCategory: "Accessory", exerciseType: "dumbbell", weightLb: 5, estimatedMaxLb: 10, incrementLb: 2.5),
        Recommendation(slotCategory: "Accessory", exerciseType: "kettlebell", weightLb: 10, estimatedMaxLb: 20, incrementLb: 5),
        Recommendation(slotCategory: "Accessory", exerciseType: "machine", weightLb: 10, estimatedMaxLb: 20, incrementLb: 5),
        Recommendation(slotCategory: "Accessory", exerciseType: "bodyweight", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
        Recommendation(slotCategory: "Accessory", exerciseType: "band", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
        Recommendation(slotCategory: "Accessory", exerciseType: "timed", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
        Recommendation(slotCategory: "Accessory", exerciseType: "conditioning", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
        Recommendation(slotCategory: "Conditioning", exerciseType: "conditioning", weightLb: 0, estimatedMaxLb: 0, incrementLb: 0),
    ]

    public static func recommendation(
        exerciseName: String,
        slotCategory: String,
        exerciseType: String
    ) -> Recommendation {
        if let exact = all.first(where: {
            $0.exerciseName == exerciseName
                && $0.slotCategory == slotCategory
                && $0.exerciseType == exerciseType
        }) {
            return exact
        }
        if let fallback = all.first(where: {
            $0.exerciseName == nil
                && $0.slotCategory == slotCategory
                && $0.exerciseType == exerciseType
        }) {
            return fallback
        }
        // Unknown imported types should still start conservatively instead of
        // creating a blank. Treat them like a light dumbbell unless the slot
        // is explicitly conditioning.
        let safeCategory = slotCategory == "Conditioning" ? "Conditioning" : slotCategory
        return all.first(where: {
            $0.exerciseName == nil
                && $0.slotCategory == safeCategory
                && $0.exerciseType == (safeCategory == "Conditioning" ? "conditioning" : "dumbbell")
        }) ?? Recommendation(slotCategory: slotCategory, exerciseType: exerciseType,
                             weightLb: 5, estimatedMaxLb: 10, incrementLb: 2.5)
    }
}
