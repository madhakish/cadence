import Foundation

/// Pre-programmed program styles (the "+ Add program" picker), as pure data.
/// String-typed so the core stays app-model-agnostic. Ported 1:1 from
/// web/js/templates.js; parity is ENFORCED against the shared fixture
/// web/tests/fixtures/program-templates.json — the node smoke suite asserts
/// the JS copy matches it and ProgramTemplateDataTests asserts this copy
/// matches it, so either side drifting fails CI. Regenerate the fixture with
/// web/tools/generate-template-fixture.mjs when templates change.
///
/// Templates may retain compatibility definitions for exercises that are now
/// part of the expanded seed. Instantiation never overwrites an existing
/// library record, and canonical names must stay aligned across both clients.
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
        /// PrescriptionStyle rawValue driving the slot ("automatic" = classic wave).
        public let prescription: String
        /// Working sets for sets-across styles (0 = the style's own default).
        public let sets: Int
        /// Starting base as a fraction of the lifter's recorded e1RM; 0 keeps
        /// the template's hand-set base. Instantiation uses this to compute
        /// real starting weights from logged history.
        public let startFraction: Double
        init(_ exercise: String, _ role: String, _ base: Double, _ max: Double,
             prescription: String = "automatic", sets: Int = 0, startFraction: Double = 0) {
            self.exercise = exercise; self.role = role; self.baseWeightLb = base; self.estimatedMaxLb = max
            self.prescription = prescription; self.sets = sets; self.startFraction = startFraction
        }
    }
    public struct TemplateAccessory: Codable, Equatable {
        public let exercise: String
        public let sets: Int
        public let minReps: Int
        public let maxReps: Int
        public let weightLb: Double
        public let incrementLb: Double
        /// Starting weight as a fraction of the matching exercise's recorded
        /// e1RM (e.g. Boring-But-Big volume at ~45% ≈ 50% of the training max).
        public let startFraction: Double
        init(_ exercise: String, _ sets: Int, _ minReps: Int, _ maxReps: Int,
             weightLb: Double = 0, incrementLb: Double = 0, startFraction: Double = 0) {
            self.exercise = exercise; self.sets = sets; self.minReps = minReps
            self.maxReps = maxReps; self.weightLb = weightLb; self.incrementLb = incrementLb
            self.startFraction = startFraction
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
        // Novice linear progression in Rippetoe's canonical 3×5-across shape:
        // squat every session, presses alternate by day, deadlift one heavy
        // set. Weight moves every completed session, not per 4-week rotation.
        Template(
            id: "novice-linear-3x5",
            name: "Novice Linear — 3×5",
            tagline: "3 days/wk · Starting Strength-style A/B · weight every session",
            focus: "strength", roundingLb: 5,
            exercises: [],
            days: [
                TemplateDay("Day A",
                            lifts: [TemplateLift("Back Squat", "main", 95, 150,
                                                 prescription: "linearFives", sets: 3, startFraction: 0.74),
                                    TemplateLift("Overhead Press", "complementary", 65, 95,
                                                 prescription: "linearFives", sets: 3, startFraction: 0.74),
                                    TemplateLift("Deadlift", "complementary", 135, 205,
                                                 prescription: "linearFives", sets: 1, startFraction: 0.74)],
                            accessories: []),
                TemplateDay("Day B",
                            lifts: [TemplateLift("Back Squat", "main", 95, 150,
                                                 prescription: "linearFives", sets: 3, startFraction: 0.74),
                                    TemplateLift("Barbell Bench", "complementary", 85, 125,
                                                 prescription: "linearFives", sets: 3, startFraction: 0.74),
                                    TemplateLift("Deadlift", "complementary", 135, 205,
                                                 prescription: "linearFives", sets: 1, startFraction: 0.74)],
                            accessories: [TemplateAccessory("Chin-ups", 3, 5, 10)]),
            ]
        ),
        // The 5×5-across novice variant (Bill Starr lineage, popularized as
        // StrongLifts) — offered separately because 5×5 across is NOT the
        // Starting Strength prescription.
        Template(
            id: "novice-linear-5x5",
            name: "Novice Linear — 5×5",
            tagline: "3 days/wk · StrongLifts-style A/B · squat every session",
            focus: "strength", roundingLb: 5,
            exercises: [],
            days: [
                TemplateDay("Day A",
                            lifts: [TemplateLift("Back Squat", "main", 95, 150,
                                                 prescription: "linearFives", sets: 5, startFraction: 0.74),
                                    TemplateLift("Barbell Bench", "complementary", 85, 125,
                                                 prescription: "linearFives", sets: 5, startFraction: 0.74),
                                    TemplateLift("Barbell Row", "complementary", 95, 135,
                                                 prescription: "linearFives", sets: 5, startFraction: 0.74)],
                            accessories: []),
                TemplateDay("Day B",
                            lifts: [TemplateLift("Back Squat", "main", 95, 150,
                                                 prescription: "linearFives", sets: 5, startFraction: 0.74),
                                    TemplateLift("Overhead Press", "complementary", 65, 95,
                                                 prescription: "linearFives", sets: 5, startFraction: 0.74),
                                    TemplateLift("Deadlift", "complementary", 135, 205,
                                                 prescription: "linearFives", sets: 1, startFraction: 0.74)],
                            accessories: [TemplateAccessory("Chin-ups", 3, 5, 10)]),
            ]
        ),
        // Texas Method week as six slots over a two-week A/B pass so the
        // presses alternate weekly. Each slot starts at the published ratio of
        // the lift's 5RM (volume 90%, light 80% of volume, intensity = the
        // 5RM PR set); twin A/B slots share one synchronized progression at
        // +5 per completion, landing on the published +5 lb/week per lift.
        Template(
            id: "texas-method",
            name: "Texas Method",
            tagline: "3 days/wk · volume, light, intensity · presses alternate weekly",
            focus: "strength", roundingLb: 5,
            exercises: [],
            days: [
                TemplateDay("Volume A",
                            lifts: [TemplateLift("Back Squat", "main", 135, 205,
                                                 prescription: "texasVolume", sets: 5, startFraction: 0.77),
                                    TemplateLift("Barbell Bench", "complementary", 85, 125,
                                                 prescription: "texasVolume", sets: 5, startFraction: 0.77)],
                            accessories: [TemplateAccessory("Back Extension", 3, 10, 15)]),
                TemplateDay("Light A",
                            lifts: [TemplateLift("Back Squat", "main", 110, 205,
                                                 prescription: "texasLight", sets: 2, startFraction: 0.62),
                                    TemplateLift("Overhead Press", "complementary", 55, 95,
                                                 prescription: "texasLight", sets: 3, startFraction: 0.69)],
                            accessories: [TemplateAccessory("Chin-ups", 3, 5, 10)]),
                TemplateDay("Intensity A",
                            lifts: [TemplateLift("Back Squat", "main", 150, 205,
                                                 prescription: "texasIntensity", sets: 1, startFraction: 0.86),
                                    TemplateLift("Barbell Bench", "complementary", 95, 125,
                                                 prescription: "texasIntensity", sets: 1, startFraction: 0.86),
                                    TemplateLift("Deadlift", "complementary", 185, 245,
                                                 prescription: "texasIntensity", sets: 1, startFraction: 0.86)],
                            accessories: []),
                TemplateDay("Volume B",
                            lifts: [TemplateLift("Back Squat", "main", 135, 205,
                                                 prescription: "texasVolume", sets: 5, startFraction: 0.77),
                                    TemplateLift("Overhead Press", "complementary", 65, 95,
                                                 prescription: "texasVolume", sets: 5, startFraction: 0.77)],
                            accessories: [TemplateAccessory("Back Extension", 3, 10, 15)]),
                TemplateDay("Light B",
                            lifts: [TemplateLift("Back Squat", "main", 110, 205,
                                                 prescription: "texasLight", sets: 2, startFraction: 0.62),
                                    TemplateLift("Barbell Bench", "complementary", 75, 125,
                                                 prescription: "texasLight", sets: 3, startFraction: 0.69)],
                            accessories: [TemplateAccessory("Chin-ups", 3, 5, 10)]),
                TemplateDay("Intensity B",
                            lifts: [TemplateLift("Back Squat", "main", 150, 205,
                                                 prescription: "texasIntensity", sets: 1, startFraction: 0.86),
                                    TemplateLift("Overhead Press", "complementary", 80, 95,
                                                 prescription: "texasIntensity", sets: 1, startFraction: 0.86),
                                    TemplateLift("Deadlift", "complementary", 185, 245,
                                                 prescription: "texasIntensity", sets: 1, startFraction: 0.86)],
                            accessories: []),
            ]
        ),
        // Wendler 5/3/1 with the original 90% training max, the three-week
        // 5s/3s/531 wave plus deload, and Boring-But-Big volume after the
        // main work. The slot base IS the training max.
        Template(
            id: "five-three-one",
            name: "5/3/1 — Wendler",
            tagline: "4 days/wk · training-max waves · top set is as many quality reps as you have",
            focus: "strength", roundingLb: 5,
            exercises: [],
            days: [
                TemplateDay("Press Day",
                            lifts: [TemplateLift("Overhead Press", "main", 85, 95,
                                                 prescription: "fiveThreeOne", startFraction: 0.90)],
                            accessories: [TemplateAccessory("Overhead Press", 5, 10, 10, weightLb: 45, incrementLb: 5, startFraction: 0.45),
                                          TemplateAccessory("Chin-ups", 5, 5, 10)]),
                TemplateDay("Deadlift Day",
                            lifts: [TemplateLift("Deadlift", "main", 220, 245,
                                                 prescription: "fiveThreeOne", startFraction: 0.90)],
                            accessories: [TemplateAccessory("Deadlift", 5, 10, 10, weightLb: 115, incrementLb: 5, startFraction: 0.45),
                                          TemplateAccessory("Hanging Knee Raise", 5, 10, 15)]),
                TemplateDay("Bench Day",
                            lifts: [TemplateLift("Barbell Bench", "main", 110, 125,
                                                 prescription: "fiveThreeOne", startFraction: 0.90)],
                            accessories: [TemplateAccessory("Barbell Bench", 5, 10, 10, weightLb: 55, incrementLb: 5, startFraction: 0.45),
                                          TemplateAccessory("Barbell Row", 5, 10, 10, weightLb: 95, incrementLb: 5)]),
                TemplateDay("Squat Day",
                            lifts: [TemplateLift("Back Squat", "main", 180, 205,
                                                 prescription: "fiveThreeOne", startFraction: 0.90)],
                            accessories: [TemplateAccessory("Back Squat", 5, 10, 10, weightLb: 95, incrementLb: 5, startFraction: 0.45),
                                          TemplateAccessory("Lying Leg Curl", 5, 10, 12, weightLb: 70, incrementLb: 5)]),
            ]
        ),
        // Westside-style conjugate: max-effort top singles with repetition
        // accessories, and dynamic-effort speed waves at ~50–60%. Rotate the
        // max-effort variation with the existing swap gesture — rotation, not
        // grinding, is the methodology's stall answer. Straight bar weight
        // only; bands/chains are a coach's call the app does not fake.
        Template(
            id: "conjugate",
            name: "Conjugate — Westside-style",
            tagline: "4 days/wk · max-effort singles + speed work · rotate variations by swapping",
            focus: "strength", roundingLb: 5,
            exercises: [],
            days: [
                TemplateDay("Max Effort Lower",
                            lifts: [TemplateLift("Back Squat", "main", 180, 205,
                                                 prescription: "maxEffort", startFraction: 0.90)],
                            accessories: [TemplateAccessory("Nordic Hamstring Curl", 4, 6, 10),
                                          TemplateAccessory("Back Extension", 4, 10, 15),
                                          TemplateAccessory("Hanging Knee Raise", 4, 10, 15)]),
                TemplateDay("Max Effort Upper",
                            lifts: [TemplateLift("Barbell Bench", "main", 110, 125,
                                                 prescription: "maxEffort", startFraction: 0.90)],
                            accessories: [TemplateAccessory("Skull Crusher", 4, 8, 12, weightLb: 30, incrementLb: 5),
                                          TemplateAccessory("Barbell Row", 4, 8, 12, weightLb: 95, incrementLb: 5),
                                          TemplateAccessory("Face Pulls", 3, 12, 15, weightLb: 25, incrementLb: 5)]),
                TemplateDay("Dynamic Effort Lower",
                            lifts: [TemplateLift("Back Squat", "main", 95, 205,
                                                 prescription: "dynamicEffort", startFraction: 0.50),
                                    TemplateLift("Deadlift", "complementary", 145, 245,
                                                 prescription: "dynamicEffort", startFraction: 0.60)],
                            accessories: [TemplateAccessory("Walking Lunges", 3, 10, 20),
                                          TemplateAccessory("Back Extension", 3, 10, 15)]),
                TemplateDay("Dynamic Effort Upper",
                            lifts: [TemplateLift("Barbell Bench", "main", 65, 125,
                                                 prescription: "dynamicEffort", startFraction: 0.50)],
                            accessories: [TemplateAccessory("Triceps Pushdown", 4, 10, 15, weightLb: 40, incrementLb: 5),
                                          TemplateAccessory("Lat Pulldown", 4, 8, 12, weightLb: 80, incrementLb: 5),
                                          TemplateAccessory("Rear Delt Fly", 3, 12, 15, weightLb: 15, incrementLb: 5)]),
            ]
        ),
    ]
}
