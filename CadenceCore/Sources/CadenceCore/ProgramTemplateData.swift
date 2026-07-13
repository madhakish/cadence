import Foundation

/// Pre-programmed program styles (the "+ Add program" picker), as pure data.
/// String-typed so the core stays app-model-agnostic. Ported 1:1 from
/// web/js/templates.js; parity is ENFORCED against the shared fixture
/// web/tests/fixtures/program-templates.json — the node smoke suite asserts
/// the JS copy matches it and ProgramTemplateDataTests asserts this copy
/// matches it, so either side drifting fails CI. Regenerate the fixture with
/// web/tools/generate-template-fixture.mjs when templates change.
///
/// Only exercises the seed does NOT provide are declared; seeded names
/// (Back Squat, Clean & Jerk, KB Swing, Ring Row…) are guaranteed by the
/// first-launch seed on both platforms and must be referenced by their
/// canonical seeded names — a variant spelling would fork the library.
public enum ProgramTemplateData {

    public struct TemplateExercise: Codable, Equatable {
        public let name: String
        public let category: String   // "Main" | "Accessory" | "Conditioning"
        public let type: String       // barbell | dumbbell | kettlebell | bodyweight | …
        public let group: String      // movement group (swap pool)
        public let isUnilateral: Bool
        /// Explicit per-exercise rest; 0 = none — the timer falls to the
        /// configurable rest buckets (mirrors seed `ex()`).
        public let rest: Int
        init(_ name: String, _ category: String, _ type: String, _ group: String,
             isUnilateral: Bool = false, rest: Int = 0) {
            self.name = name; self.category = category; self.type = type
            self.group = group; self.isUnilateral = isUnilateral; self.rest = rest
        }
    }
    public struct TemplateLift: Codable, Equatable {
        public let exercise: String
        public let role: String       // "main" | "complementary"
        public let baseWeightLb: Double
        public let estimatedMaxLb: Double
        init(_ exercise: String, _ role: String, _ base: Double, _ max: Double) {
            self.exercise = exercise; self.role = role; self.baseWeightLb = base; self.estimatedMaxLb = max
        }
    }
    public struct TemplateAccessory: Codable, Equatable {
        public let exercise: String
        public let sets: Int
        public let minReps: Int
        public let maxReps: Int
        public let weightLb: Double
        public let incrementLb: Double
        init(_ exercise: String, _ sets: Int, _ minReps: Int, _ maxReps: Int,
             weightLb: Double = 0, incrementLb: Double = 0) {
            self.exercise = exercise; self.sets = sets; self.minReps = minReps
            self.maxReps = maxReps; self.weightLb = weightLb; self.incrementLb = incrementLb
        }
    }
    public struct TemplateDay: Codable, Equatable {
        public let name: String
        public let lifts: [TemplateLift]
        public let accessories: [TemplateAccessory]
        init(_ name: String, lifts: [TemplateLift], accessories: [TemplateAccessory]) {
            self.name = name; self.lifts = lifts; self.accessories = accessories
        }
    }
    public struct Template: Codable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let tagline: String
        public let focus: String      // TrainingFocus rawValue
        public let roundingLb: Double
        public let exercises: [TemplateExercise]
        public let days: [TemplateDay]
    }

    public static let all: [Template] = [
        Template(
            id: "strength-upper-lower",
            name: "Strength — Upper/Lower",
            tagline: "4 days · barbell strength · A/B split over a 4-week wave",
            focus: "strength", roundingLb: 5,
            exercises: [
                TemplateExercise("Back Extension", "Accessory", "bodyweight", "hinge"),
                TemplateExercise("Hanging Knee Raise", "Accessory", "bodyweight", "core"),
            ],
            // The upper days alternate the two presses (A: overhead emphasis,
            // B: incline emphasis); each day's accessories support THAT press,
            // and every day carries core work.
            days: [
                TemplateDay("Upper A",
                            lifts: [TemplateLift("Overhead Press", "main", 65, 95),
                                    TemplateLift("Incline DB Press", "complementary", 50, 80)],
                            accessories: [TemplateAccessory("DB Overhead Triceps Extension", 3, 8, 12, weightLb: 20, incrementLb: 5),
                                          TemplateAccessory("Y-T-W Raises", 3, 10, 15, weightLb: 10),
                                          TemplateAccessory("GHD Sit-up", 3, 8, 15)]),
                TemplateDay("Lower A",
                            lifts: [TemplateLift("Back Squat", "main", 135, 205),
                                    TemplateLift("Romanian Deadlift", "complementary", 95, 165)],
                            accessories: [TemplateAccessory("Walking Lunges", 3, 10, 20),
                                          TemplateAccessory("Hanging Knee Raise", 3, 8, 15)]),
                TemplateDay("Upper B",
                            lifts: [TemplateLift("Incline DB Press", "main", 50, 80),
                                    TemplateLift("Overhead Press", "complementary", 65, 95)],
                            accessories: [TemplateAccessory("Dips", 3, 5, 12),
                                          TemplateAccessory("Band Pull-aparts", 3, 15, 25),
                                          TemplateAccessory("Hanging Knee Raise", 3, 8, 15)]),
                TemplateDay("Lower B",
                            lifts: [TemplateLift("Deadlift", "main", 155, 245),
                                    TemplateLift("Front Squat", "complementary", 95, 155)],
                            accessories: [TemplateAccessory("Back Extension", 3, 10, 15),
                                          TemplateAccessory("GHD Sit-up", 3, 8, 15)]),
            ]
        ),
        Template(
            id: "olympic-weightlifting",
            name: "Olympic Weightlifting",
            tagline: "3 days · snatch, clean & jerk, strength base",
            focus: "strength", roundingLb: 5,
            exercises: [
                TemplateExercise("Pull-ups", "Accessory", "bodyweight", "pull", rest: 120),
                TemplateExercise("Back Extension", "Accessory", "bodyweight", "hinge"),
                TemplateExercise("Hanging Knee Raise", "Accessory", "bodyweight", "core"),
            ],
            days: [
                TemplateDay("Snatch Day",
                            lifts: [TemplateLift("Snatch", "main", 65, 115),
                                    TemplateLift("Overhead Squat", "complementary", 65, 115)],
                            accessories: [TemplateAccessory("Snatch Pull", 3, 3, 5, weightLb: 95, incrementLb: 10),
                                          TemplateAccessory("Hanging Knee Raise", 3, 8, 15)]),
                TemplateDay("Clean & Jerk Day",
                            lifts: [TemplateLift("Clean & Jerk", "main", 85, 145),
                                    TemplateLift("Front Squat", "complementary", 115, 185)],
                            accessories: [TemplateAccessory("Clean Pull", 3, 3, 5, weightLb: 115, incrementLb: 10),
                                          TemplateAccessory("Pull-ups", 3, 5, 10)]),
                TemplateDay("Strength Day",
                            lifts: [TemplateLift("Back Squat", "main", 135, 225),
                                    TemplateLift("Overhead Press", "complementary", 65, 105)],
                            accessories: [TemplateAccessory("Back Extension", 3, 10, 15),
                                          TemplateAccessory("Hanging Knee Raise", 3, 8, 15)]),
            ]
        ),
        Template(
            id: "metabolic-conditioning",
            name: "Metabolic Conditioning",
            tagline: "3 days · circuits & engine work · reps climb, loads hold",
            // maintain: mains never add load; accessories double-progress reps.
            focus: "maintain", roundingLb: 5,
            exercises: [
                TemplateExercise("Goblet Squat", "Accessory", "kettlebell", "squat", rest: 60),
                TemplateExercise("Burpees", "Conditioning", "bodyweight", "conditioning", rest: 60),
                TemplateExercise("Push-ups", "Accessory", "bodyweight", "press", rest: 60),
                TemplateExercise("Mountain Climbers", "Conditioning", "bodyweight", "conditioning", rest: 45),
                TemplateExercise("Sit-ups", "Accessory", "bodyweight", "core", rest: 45),
                TemplateExercise("Box Jumps", "Conditioning", "bodyweight", "conditioning", rest: 60),
            ],
            days: [
                TemplateDay("Engine A", lifts: [],
                            accessories: [TemplateAccessory("KB Swing", 5, 10, 20, weightLb: 35),
                                          TemplateAccessory("Burpees", 4, 8, 15),
                                          TemplateAccessory("Mountain Climbers", 4, 20, 40)]),
                TemplateDay("Engine B", lifts: [],
                            accessories: [TemplateAccessory("Push-ups", 4, 10, 25),
                                          TemplateAccessory("Ring Row", 4, 8, 15),
                                          TemplateAccessory("Sit-ups", 4, 15, 30)]),
                TemplateDay("Engine C", lifts: [],
                            accessories: [TemplateAccessory("Box Jumps", 4, 8, 15),
                                          TemplateAccessory("Goblet Squat", 4, 10, 20, weightLb: 35),
                                          TemplateAccessory("Walking Lunges", 4, 12, 24)]),
            ]
        ),
    ]
}
