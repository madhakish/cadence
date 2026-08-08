import Foundation

/// Muscle anatomy for the exercise detail view: the stylized two-view figure
/// geometry (front + back polygon regions) and the exercise → muscles map
/// (primary movers red, supporting blue — colors are applied app-side).
/// Ported 1:1 from web/app/js/anatomy.js; parity is ENFORCED against
/// web/tests/fixtures/anatomy.json by both test suites — regenerate with
/// web/tools/generate-anatomy-fixture.mjs after edits.
public enum AnatomyData {

    public struct Profile: Codable, Equatable {
        public let primary: [String]
        public let secondary: [String]
        public init(primary: [String], secondary: [String]) {
            self.primary = primary; self.secondary = secondary
        }
    }
    public struct Region: Codable, Equatable {
        public let id: String
        public let view: String   // "front" | "back"
        public let points: [[Double]]
        init(_ id: String, _ view: String, _ points: [[Double]]) {
            self.id = id; self.view = view; self.points = points
        }
    }

    public static let muscleNames: [String: String] = [
        "traps": "Traps", "delts": "Shoulders", "chest": "Chest", "biceps": "Biceps",
        "triceps": "Triceps", "forearms": "Forearms", "abs": "Abs", "obliques": "Obliques",
        "lats": "Lats", "lowerback": "Lower back", "glutes": "Glutes", "quads": "Quads",
        "hamstrings": "Hamstrings", "calves": "Calves",
        "adductors": "Adductors", "reardelts": "Rear delts",
    ]

    /// Neutral silhouette polygons (both views), coordinate space 100×220.
    public static let body: [[[Double]]] = [
        [[46, 4], [54, 4], [59, 9], [59, 17], [54, 22], [46, 22], [41, 17], [41, 9]],
        [[42, 24], [58, 24], [70, 30], [72, 44], [66, 52], [64, 88], [62, 104], [38, 104], [36, 88], [34, 52], [28, 44], [30, 30]],
        [[28, 32], [34, 36], [32, 56], [30, 72], [27, 92], [20, 90], [22, 70], [24, 52], [24, 38]],
        [[72, 32], [66, 36], [68, 56], [70, 72], [73, 92], [80, 90], [78, 70], [76, 52], [76, 38]],
        [[38, 104], [49, 104], [49, 120], [48, 146], [46, 178], [44, 196], [38, 196], [36, 170], [35, 140], [36, 118]],
        [[62, 104], [51, 104], [51, 120], [52, 146], [54, 178], [56, 196], [62, 196], [64, 170], [65, 140], [64, 118]],
    ]

    public static let regions: [Region] = [
        // front
        Region("traps", "front", [[42, 26], [58, 26], [54, 32], [46, 32]]),
        Region("delts", "front", [[27, 32], [35, 35], [34, 44], [25, 42]]),
        Region("delts", "front", [[73, 32], [65, 35], [66, 44], [75, 42]]),
        Region("chest", "front", [[37, 34], [63, 34], [64, 50], [50, 54], [36, 50]]),
        Region("biceps", "front", [[24, 46], [32, 48], [30, 66], [23, 64]]),
        Region("biceps", "front", [[76, 46], [68, 48], [70, 66], [77, 64]]),
        Region("forearms", "front", [[22, 68], [29, 70], [27, 90], [20, 88]]),
        Region("forearms", "front", [[78, 68], [71, 70], [73, 90], [80, 88]]),
        Region("obliques", "front", [[36, 54], [41, 56], [42, 86], [37, 84]]),
        Region("obliques", "front", [[64, 54], [59, 56], [58, 86], [63, 84]]),
        Region("abs", "front", [[42, 56], [58, 56], [57, 88], [43, 88]]),
        Region("quads", "front", [[37, 106], [48, 106], [48, 142], [44, 148], [38, 140]]),
        Region("quads", "front", [[63, 106], [52, 106], [52, 142], [56, 148], [62, 140]]),
        Region("adductors", "front", [[44, 108], [48, 108], [48, 138], [46, 143], [44, 136]]),
        Region("adductors", "front", [[56, 108], [52, 108], [52, 138], [54, 143], [56, 136]]),
        // back
        Region("traps", "back", [[50, 24], [60, 30], [50, 46], [40, 30]]),
        Region("delts", "back", [[27, 32], [35, 35], [34, 44], [25, 42]]),
        Region("delts", "back", [[73, 32], [65, 35], [66, 44], [75, 42]]),
        Region("reardelts", "back", [[31, 34], [38, 37], [37, 45], [30, 43]]),
        Region("reardelts", "back", [[69, 34], [62, 37], [63, 45], [70, 43]]),
        Region("lats", "back", [[36, 46], [47, 50], [46, 74], [38, 70], [34, 54]]),
        Region("lats", "back", [[64, 46], [53, 50], [54, 74], [62, 70], [66, 54]]),
        Region("triceps", "back", [[24, 46], [32, 48], [30, 66], [23, 64]]),
        Region("triceps", "back", [[76, 46], [68, 48], [70, 66], [77, 64]]),
        Region("forearms", "back", [[22, 68], [29, 70], [27, 90], [20, 88]]),
        Region("forearms", "back", [[78, 68], [71, 70], [73, 90], [80, 88]]),
        Region("lowerback", "back", [[43, 72], [57, 72], [56, 90], [44, 90]]),
        Region("glutes", "back", [[38, 92], [62, 92], [60, 108], [50, 112], [40, 108]]),
        Region("hamstrings", "back", [[37, 112], [48, 112], [48, 144], [44, 150], [38, 142]]),
        Region("hamstrings", "back", [[63, 112], [52, 112], [52, 144], [56, 150], [62, 142]]),
        Region("calves", "back", [[38, 152], [47, 152], [46, 178], [43, 182], [39, 176]]),
        Region("calves", "back", [[62, 152], [53, 152], [54, 178], [57, 182], [61, 176]]),
    ]

    public static let map: [String: Profile] = [
        "Deadlift": Profile(primary: ["hamstrings", "glutes", "lowerback"], secondary: ["lats", "traps", "forearms", "quads"]),
        "Snatch-grip Deadlift": Profile(primary: ["hamstrings", "glutes", "lowerback"], secondary: ["traps", "lats", "forearms"]),
        "Romanian Deadlift": Profile(primary: ["hamstrings", "glutes"], secondary: ["lowerback", "forearms"]),
        "Good Morning": Profile(primary: ["hamstrings", "lowerback"], secondary: ["glutes"]),
        "Back Squat": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings", "lowerback", "abs"]),
        "Front Squat": Profile(primary: ["quads", "abs"], secondary: ["glutes", "lowerback"]),
        "Overhead Squat": Profile(primary: ["quads", "delts"], secondary: ["abs", "glutes", "traps"]),
        "Goblet Squat": Profile(primary: ["quads", "glutes"], secondary: ["abs"]),
        "Walking Lunges": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings", "abs"]),
        "Barbell Bench": Profile(primary: ["chest", "triceps"], secondary: ["delts"]),
        "Flat DB Press": Profile(primary: ["chest", "triceps"], secondary: ["delts"]),
        "Incline DB Press": Profile(primary: ["chest", "delts"], secondary: ["triceps"]),
        "Overhead Press": Profile(primary: ["delts", "triceps"], secondary: ["traps", "abs"]),
        "Push Press": Profile(primary: ["delts", "triceps"], secondary: ["quads", "abs"]),
        "Push Jerk": Profile(primary: ["delts", "triceps"], secondary: ["quads", "abs"]),
        "Split Jerk": Profile(primary: ["delts", "triceps"], secondary: ["quads", "glutes", "abs"]),
        "Overhead DB Press": Profile(primary: ["delts", "triceps"], secondary: ["traps"]),
        "Seated Upright DB Press": Profile(primary: ["delts", "triceps"], secondary: ["traps"]),
        "Snatch": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"]),
        "Power Snatch": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"]),
        "Hang Power Snatch": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"]),
        "Clean": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "lowerback", "forearms"]),
        "Power Clean": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "lowerback", "forearms"]),
        "Hang Power Clean": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "lowerback", "forearms"]),
        "KB Clean": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["forearms", "abs"]),
        "Clean & Jerk": Profile(primary: ["hamstrings", "glutes", "delts"], secondary: ["quads", "traps", "triceps", "lowerback"]),
        "Clean Pull": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["lowerback", "forearms"]),
        "Snatch Pull": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["lowerback", "forearms"]),
        "KB Swing": Profile(primary: ["glutes", "hamstrings"], secondary: ["lowerback", "abs", "delts"]),
        "Turkish Get-up": Profile(primary: ["abs", "delts"], secondary: ["glutes", "obliques"]),
        "Single-arm DB Row": Profile(primary: ["lats"], secondary: ["biceps", "forearms", "obliques"]),
        "Chest-supported Row": Profile(primary: ["lats", "traps"], secondary: ["biceps"]),
        "Ring Row": Profile(primary: ["lats", "biceps"], secondary: ["abs"]),
        "Lat Pulldown": Profile(primary: ["lats"], secondary: ["biceps"]),
        "Chin-ups": Profile(primary: ["lats", "biceps"], secondary: ["abs", "forearms"]),
        "Pull-ups": Profile(primary: ["lats"], secondary: ["biceps", "abs", "forearms"]),
        // Adding a belt loads the same movement — the muscles worked do not change.
        "Weighted Chin-up": Profile(primary: ["lats", "biceps"], secondary: ["abs", "forearms"]),
        "Weighted Pull-up": Profile(primary: ["lats"], secondary: ["biceps", "abs", "forearms"]),
        "Face Pulls": Profile(primary: ["delts", "traps"], secondary: ["biceps"]),
        "Band Pull-aparts": Profile(primary: ["delts", "traps"], secondary: []),
        "Y-T-W Raises": Profile(primary: ["delts", "traps"], secondary: []),
        "Band External Rotation": Profile(primary: ["delts"], secondary: []),
        "DB Curls": Profile(primary: ["biceps"], secondary: ["forearms"]),
        "DB Overhead Triceps Extension": Profile(primary: ["triceps"], secondary: []),
        "Dips": Profile(primary: ["chest", "triceps"], secondary: ["delts"]),
        "Push-ups": Profile(primary: ["chest", "triceps"], secondary: ["delts", "abs"]),
        "Back Extension": Profile(primary: ["lowerback", "glutes"], secondary: ["hamstrings"]),
        "GHD Sit-up": Profile(primary: ["abs"], secondary: ["obliques"]),
        "Sit-ups": Profile(primary: ["abs"], secondary: ["obliques"]),
        "Plank": Profile(primary: ["abs"], secondary: ["obliques", "delts"]),
        "Side Plank": Profile(primary: ["obliques"], secondary: ["abs", "delts"]),
        "Hanging Knee Raise": Profile(primary: ["abs"], secondary: ["obliques", "forearms"]),
        "Burpees": Profile(primary: ["chest", "quads"], secondary: ["abs", "delts"]),
        "Mountain Climbers": Profile(primary: ["abs"], secondary: ["quads", "delts"]),
        "Box Jumps": Profile(primary: ["quads", "glutes"], secondary: ["calves"]),
        "Bike": Profile(primary: ["quads", "calves"], secondary: ["hamstrings", "glutes"]),
        "Run-Walk Intervals": Profile(primary: ["quads", "calves"], secondary: ["hamstrings", "glutes"]),
        "Ruck": Profile(primary: ["quads", "calves"], secondary: ["traps", "abs"]),
        "Walk": Profile(primary: ["quads", "calves"], secondary: ["hamstrings"]),

        // Previously these fell through to the coarse movement-group default,
        // which was merely vague for some and plainly wrong for others: a
        // leg curl inherited "hinge" and so claimed glutes, hip adduction
        // inherited "squat" and claimed quads.
        "Copenhagen Plank": Profile(primary: ["adductors"], secondary: ["obliques", "abs"]),
        "Cable Hip Adduction": Profile(primary: ["adductors"], secondary: ["glutes"]),
        "Monster Walk": Profile(primary: ["glutes"], secondary: ["quads"]),
        "Seated Leg Curl": Profile(primary: ["hamstrings"], secondary: ["calves"]),
        "Lying Leg Curl": Profile(primary: ["hamstrings"], secondary: ["calves"]),
        "Nordic Hamstring Curl": Profile(primary: ["hamstrings"], secondary: ["glutes", "calves"]),
        "Trap Bar Deadlift": Profile(primary: ["quads", "glutes", "hamstrings"], secondary: ["traps", "lowerback", "forearms"]),
        "Sumo Deadlift": Profile(primary: ["glutes", "quads", "adductors"], secondary: ["hamstrings", "lowerback", "traps", "forearms"]),
        "Barbell Hip Thrust": Profile(primary: ["glutes"], secondary: ["hamstrings"]),
        "DB Romanian Deadlift": Profile(primary: ["hamstrings", "glutes"], secondary: ["lowerback", "forearms"]),
        "Glute Bridge": Profile(primary: ["glutes"], secondary: ["hamstrings"]),
        "Cable Pull-through": Profile(primary: ["glutes", "hamstrings"], secondary: ["lowerback"]),
        "GHD Back Extension": Profile(primary: ["lowerback", "glutes"], secondary: ["hamstrings"]),
        "Hack Squat": Profile(primary: ["quads"], secondary: ["glutes"]),
        "Leg Press": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings"]),
        "Leg Extension": Profile(primary: ["quads"], secondary: []),
        "Bulgarian Split Squat": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings", "adductors", "abs"]),
        "Reverse Lunge": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings", "abs"]),
        "Forward Lunge": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings", "abs"]),
        "Step-up": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings", "calves"]),
        "Incline Barbell Bench Press": Profile(primary: ["chest", "delts"], secondary: ["triceps"]),
        "Close-Grip Bench Press": Profile(primary: ["triceps", "chest"], secondary: ["delts"]),
        "Low Box Squat": Profile(primary: ["glutes", "hamstrings"], secondary: ["quads", "lowerback", "adductors"]),
        "Front Box Squat": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings", "abs"]),
        "Paused Box Squat": Profile(primary: ["glutes", "quads"], secondary: ["hamstrings", "lowerback"]),
        "Floor Press": Profile(primary: ["chest", "triceps"], secondary: ["delts"]),
        "Close-Grip Floor Press": Profile(primary: ["triceps", "chest"], secondary: ["delts"]),
        "Speed Box Squat": Profile(primary: ["glutes", "quads"], secondary: ["hamstrings", "lowerback"]),
        "Speed Deadlift": Profile(primary: ["hamstrings", "glutes"], secondary: ["lowerback", "traps", "forearms"]),
        "Speed Bench Press": Profile(primary: ["chest", "triceps"], secondary: ["delts"]),
        "Machine Chest Press": Profile(primary: ["chest", "triceps"], secondary: ["delts"]),
        "Landmine Press": Profile(primary: ["delts", "chest"], secondary: ["triceps", "abs"]),
        "Arnold Press": Profile(primary: ["delts"], secondary: ["triceps", "traps"]),
        "DB Floor Press": Profile(primary: ["chest", "triceps"], secondary: ["delts"]),
        "Cable Chest Fly": Profile(primary: ["chest"], secondary: ["delts"]),
        "Pec Deck": Profile(primary: ["chest"], secondary: ["delts"]),
        "Incline Push-ups": Profile(primary: ["chest", "triceps"], secondary: ["delts", "abs"]),
        "Decline Push-ups": Profile(primary: ["chest", "delts"], secondary: ["triceps", "abs"]),
        "Diamond Push-ups": Profile(primary: ["triceps", "chest"], secondary: ["delts", "abs"]),
        "Close-Grip Push-ups": Profile(primary: ["triceps", "chest"], secondary: ["delts", "abs"]),
        "KB Press": Profile(primary: ["delts", "triceps"], secondary: ["traps", "abs"]),
        "Banded Chest Press": Profile(primary: ["chest", "triceps"], secondary: ["delts"]),
        "Barbell Row": Profile(primary: ["lats", "traps"], secondary: ["biceps", "lowerback", "forearms"]),
        "Pendlay Row": Profile(primary: ["lats", "traps"], secondary: ["biceps", "lowerback", "forearms"]),
        "T-Bar Row": Profile(primary: ["lats", "traps"], secondary: ["biceps", "forearms"]),
        "Assisted Pull-up": Profile(primary: ["lats"], secondary: ["biceps", "forearms"]),
        "Seated Cable Row": Profile(primary: ["lats", "traps"], secondary: ["biceps", "forearms"]),
        "One-arm Cable Row": Profile(primary: ["lats"], secondary: ["biceps", "obliques", "forearms"]),
        "Bent-over DB Row": Profile(primary: ["lats", "traps"], secondary: ["biceps", "lowerback", "forearms"]),
        "Incline Bench DB Row": Profile(primary: ["lats", "traps"], secondary: ["biceps", "forearms"]),
        "Straight-arm Pulldown": Profile(primary: ["lats"], secondary: ["triceps", "abs"]),
        "KB Row": Profile(primary: ["lats"], secondary: ["biceps", "forearms", "obliques"]),
        "Banded Row": Profile(primary: ["lats", "traps"], secondary: ["biceps", "forearms"]),
        "Rear Delt Fly": Profile(primary: ["reardelts"], secondary: ["traps"]),
        "Reverse Pec Deck": Profile(primary: ["reardelts"], secondary: ["traps"]),
        "DB Lateral Raise": Profile(primary: ["delts"], secondary: ["traps"]),
        "Cable Lateral Raise": Profile(primary: ["delts"], secondary: ["traps"]),
        "DB Front Raise": Profile(primary: ["delts"], secondary: ["chest"]),
        "Barbell Curl": Profile(primary: ["biceps"], secondary: ["forearms"]),
        "Hammer Curl": Profile(primary: ["biceps", "forearms"], secondary: []),
        "Incline DB Curl": Profile(primary: ["biceps"], secondary: ["forearms"]),
        "Preacher Curl": Profile(primary: ["biceps"], secondary: ["forearms"]),
        "Cable Curl": Profile(primary: ["biceps"], secondary: ["forearms"]),
        "Triceps Pushdown": Profile(primary: ["triceps"], secondary: []),
        "Skull Crusher": Profile(primary: ["triceps"], secondary: []),
        "Cable Overhead Triceps Extension": Profile(primary: ["triceps"], secondary: []),
        "Standing Calf Raise": Profile(primary: ["calves"], secondary: []),
        "Seated Calf Raise": Profile(primary: ["calves"], secondary: []),
        "Ab Wheel Rollout": Profile(primary: ["abs"], secondary: ["lats", "obliques", "delts"]),
        "Dead Bug": Profile(primary: ["abs"], secondary: ["obliques"]),
        "Bird Dog": Profile(primary: ["lowerback", "glutes"], secondary: ["abs", "delts"]),
        "Pallof Press": Profile(primary: ["obliques", "abs"], secondary: ["delts"]),
        "Cable Crunch": Profile(primary: ["abs"], secondary: ["obliques"]),
        "Reverse Crunch": Profile(primary: ["abs"], secondary: ["obliques"]),
        "Hollow Hold": Profile(primary: ["abs"], secondary: ["obliques"]),
        "Farmer Carry": Profile(primary: ["forearms", "traps"], secondary: ["abs", "obliques", "quads"]),
        "Suitcase Carry": Profile(primary: ["obliques", "forearms"], secondary: ["traps", "abs"]),
        "Hang Clean": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "lowerback", "forearms"]),
        "Hang Snatch": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"]),
        "Muscle Clean": Profile(primary: ["traps", "delts"], secondary: ["hamstrings", "glutes", "forearms"]),
        "Muscle Snatch": Profile(primary: ["traps", "delts"], secondary: ["hamstrings", "glutes", "forearms"]),
        "Clean High Pull": Profile(primary: ["traps", "hamstrings", "glutes"], secondary: ["lowerback", "forearms"]),
        "Snatch High Pull": Profile(primary: ["traps", "hamstrings", "glutes"], secondary: ["lowerback", "forearms", "delts"]),
        "Jump Rope": Profile(primary: ["calves"], secondary: ["quads", "forearms"]),
        "Row Erg": Profile(primary: ["lats", "quads"], secondary: ["biceps", "lowerback", "hamstrings"]),
        "Ski Erg": Profile(primary: ["lats", "triceps"], secondary: ["abs", "delts"]),
        "Elliptical": Profile(primary: ["quads", "glutes"], secondary: ["hamstrings", "calves"]),
        "Stair Climber": Profile(primary: ["quads", "glutes"], secondary: ["calves", "hamstrings"]),
        "Sled Push": Profile(primary: ["quads", "glutes"], secondary: ["calves", "delts"]),
        "Sled Pull": Profile(primary: ["hamstrings", "glutes"], secondary: ["lats", "biceps", "calves"]),
        "Battle Ropes": Profile(primary: ["delts", "forearms"], secondary: ["abs", "lats"]),
        "Swimming": Profile(primary: ["lats", "delts"], secondary: ["triceps", "abs", "glutes"]),
    ]

    public static let groupDefaults: [String: Profile] = [
        "squat": Profile(primary: ["quads", "glutes"], secondary: ["abs", "lowerback"]),
        "hinge": Profile(primary: ["hamstrings", "glutes"], secondary: ["lowerback"]),
        "press": Profile(primary: ["delts", "chest", "triceps"], secondary: ["abs"]),
        "pull": Profile(primary: ["lats", "biceps"], secondary: ["forearms"]),
        "olympic": Profile(primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"]),
        "shoulder": Profile(primary: ["delts"], secondary: ["traps"]),
        "arms": Profile(primary: ["biceps", "triceps"], secondary: ["forearms"]),
        "core": Profile(primary: ["abs"], secondary: ["obliques"]),
        "calves": Profile(primary: ["calves"], secondary: ["hamstrings"]),
        "carry": Profile(primary: ["forearms", "traps"], secondary: ["abs", "obliques"]),
        "conditioning": Profile(primary: ["quads", "calves"], secondary: ["abs"]),
    ]

    /// Exact name first, then the movement-group default, else nil (no figure).
    public static func muscleProfile(name: String, movementGroup: String) -> Profile? {
        map[name] ?? groupDefaults[movementGroup]
    }

    /// "Primary: Shoulders, Triceps · Supporting: Traps, Abs" — mirrors web muscleBlurb.
    public static func blurb(_ profile: Profile) -> String {
        func names(_ ids: [String]) -> String {
            ids.map { muscleNames[$0] ?? $0 }.joined(separator: ", ")
        }
        var parts = ["Primary: \(names(profile.primary))"]
        if !profile.secondary.isEmpty { parts.append("Supporting: \(names(profile.secondary))") }
        return parts.joined(separator: " · ")
    }
}
