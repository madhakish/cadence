import Foundation

private func mirrorAnatomy(_ points: [[Double]]) -> [[Double]] {
    points.map { [$0[0] == 105 ? 105 : 210 - $0[0], $0[1]] }
}

/// Muscle anatomy for the exercise detail view: the stylized two-view figure
/// geometry (front + back smooth regions) and the exercise → muscles map
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

    /// Neutral Vitruvian silhouette (both views), coordinate space 210×224.
    /// Arms and legs reach the construction circle; the renderer rounds these
    /// control loops into continuous anatomical contours.
    public static let body: [[[Double]]] = [
        [[105, 6], [113, 8], [118, 14], [118, 23], [113, 30], [105, 33],
         [97, 30], [92, 23], [92, 14], [97, 8]],
        [[97, 31], [113, 31], [119, 35], [133, 38], [139, 46], [138, 57],
         [132, 69], [129, 89], [133, 105], [126, 114], [116, 120], [94, 120],
         [84, 114], [77, 105], [81, 89], [78, 69], [72, 57], [71, 46], [77, 38], [91, 35]],
        [[76, 39], [70, 39], [61, 46], [51, 53], [42, 60], [31, 66], [20, 72],
         [10, 80], [7, 88], [13, 93], [22, 86], [34, 79], [46, 71], [57, 63], [68, 55], [78, 48]],
        mirrorAnatomy([[76, 39], [70, 39], [61, 46], [51, 53], [42, 60], [31, 66], [20, 72],
                       [10, 80], [7, 88], [13, 93], [22, 86], [34, 79], [46, 71], [57, 63], [68, 55], [78, 48]]),
        [[84, 108], [103, 113], [103, 128], [97, 145], [90, 163], [82, 183],
         [73, 207], [62, 214], [54, 211], [59, 201], [66, 181], [71, 160], [75, 141], [77, 121]],
        mirrorAnatomy([[84, 108], [103, 113], [103, 128], [97, 145], [90, 163], [82, 183],
                       [73, 207], [62, 214], [54, 211], [59, 201], [66, 181], [71, 160], [75, 141], [77, 121]]),
    ]

    public static let regions: [Region] = [
        // front
        Region("traps", "front", [[92, 33], [118, 33], [122, 38], [114, 47], [105, 50], [96, 47], [88, 38]]),
        Region("delts", "front", [[75, 39], [85, 38], [91, 44], [88, 53], [79, 58], [69, 54], [69, 46]]),
        Region("delts", "front", mirrorAnatomy([[75, 39], [85, 38], [91, 44], [88, 53], [79, 58], [69, 54], [69, 46]])),
        Region("chest", "front", [[84, 44], [103, 47], [103, 65], [94, 68], [82, 63], [77, 53]]),
        Region("chest", "front", mirrorAnatomy([[84, 44], [103, 47], [103, 65], [94, 68], [82, 63], [77, 53]])),
        Region("biceps", "front", [[67, 53], [78, 56], [72, 65], [61, 73], [52, 72], [56, 63]]),
        Region("biceps", "front", mirrorAnatomy([[67, 53], [78, 56], [72, 65], [61, 73], [52, 72], [56, 63]])),
        Region("forearms", "front", [[49, 70], [57, 76], [45, 83], [33, 90], [22, 97], [14, 92], [24, 84], [37, 77]]),
        Region("forearms", "front", mirrorAnatomy([[49, 70], [57, 76], [45, 83], [33, 90], [22, 97], [14, 92], [24, 84], [37, 77]])),
        Region("obliques", "front", [[81, 64], [92, 67], [95, 89], [93, 105], [84, 109], [77, 96]]),
        Region("obliques", "front", mirrorAnatomy([[81, 64], [92, 67], [95, 89], [93, 105], [84, 109], [77, 96]])),
        Region("abs", "front", [[94, 66], [116, 66], [120, 87], [117, 106], [105, 113], [93, 106], [90, 87]]),
        Region("quads", "front", [[80, 112], [101, 117], [99, 137], [92, 159], [82, 177], [73, 171], [74, 151], [77, 132]]),
        Region("quads", "front", mirrorAnatomy([[80, 112], [101, 117], [99, 137], [92, 159], [82, 177], [73, 171], [74, 151], [77, 132]])),
        Region("adductors", "front", [[93, 116], [103, 118], [100, 141], [91, 160], [83, 162], [88, 142]]),
        Region("adductors", "front", mirrorAnatomy([[93, 116], [103, 118], [100, 141], [91, 160], [83, 162], [88, 142]])),
        // back
        Region("traps", "back", [[105, 32], [123, 37], [128, 43], [119, 55], [111, 66],
                                   [105, 72], [99, 66], [91, 55], [82, 43], [87, 37]]),
        Region("delts", "back", [[75, 39], [85, 38], [92, 44], [89, 54], [79, 59], [69, 54], [69, 46]]),
        Region("delts", "back", mirrorAnatomy([[75, 39], [85, 38], [92, 44], [89, 54], [79, 59], [69, 54], [69, 46]])),
        Region("reardelts", "back", [[78, 40], [91, 43], [93, 50], [85, 57], [76, 54], [71, 48]]),
        Region("reardelts", "back", mirrorAnatomy([[78, 40], [91, 43], [93, 50], [85, 57], [76, 54], [71, 48]])),
        Region("lats", "back", [[83, 52], [103, 58], [101, 83], [94, 101], [82, 105], [78, 91], [79, 70]]),
        Region("lats", "back", mirrorAnatomy([[83, 52], [103, 58], [101, 83], [94, 101], [82, 105], [78, 91], [79, 70]])),
        Region("triceps", "back", [[67, 53], [78, 57], [72, 68], [60, 77], [51, 73], [56, 63]]),
        Region("triceps", "back", mirrorAnatomy([[67, 53], [78, 57], [72, 68], [60, 77], [51, 73], [56, 63]])),
        Region("forearms", "back", [[49, 70], [57, 76], [45, 83], [33, 90], [22, 97], [14, 92], [24, 84], [37, 77]]),
        Region("forearms", "back", mirrorAnatomy([[49, 70], [57, 76], [45, 83], [33, 90], [22, 97], [14, 92], [24, 84], [37, 77]])),
        Region("lowerback", "back", [[93, 82], [117, 82], [121, 103], [114, 116], [105, 120], [96, 116], [89, 103]]),
        Region("glutes", "back", [[80, 104], [103, 108], [103, 126], [94, 136], [80, 133], [76, 120]]),
        Region("glutes", "back", mirrorAnatomy([[80, 104], [103, 108], [103, 126], [94, 136], [80, 133], [76, 120]])),
        Region("hamstrings", "back", [[79, 130], [98, 132], [95, 153], [87, 178], [76, 184], [70, 175], [75, 153]]),
        Region("hamstrings", "back", mirrorAnatomy([[79, 130], [98, 132], [95, 153], [87, 178], [76, 184], [70, 175], [75, 153]])),
        Region("calves", "back", [[71, 175], [84, 181], [78, 203], [70, 211], [61, 208], [63, 196]]),
        Region("calves", "back", mirrorAnatomy([[71, 175], [84, 181], [78, 203], [70, 211], [61, 208], [63, 196]])),
    ]

    /// Visible front-view washes aligned to the Vitruvian weightlifting ape's
    /// 210×210 square. Both superimposed limb poses highlight together, while
    /// the exercise → muscle data contract above stays unchanged.
    public static let vitruvianFrontRegions: [Region] = [
        Region("traps", "front", [[80, 67], [91, 63], [100, 68], [98, 78], [89, 84], [79, 76]]),
        Region("traps", "front", mirrorAnatomy([[80, 67], [91, 63], [100, 68], [98, 78], [89, 84], [79, 76]])),
        Region("delts", "front", [[68, 61], [82, 58], [91, 64], [87, 76], [76, 81], [65, 73]]),
        Region("delts", "front", mirrorAnatomy([[68, 61], [82, 58], [91, 64], [87, 76], [76, 81], [65, 73]])),
        Region("chest", "front", [[79, 74], [103, 73], [103, 94], [92, 98], [78, 91], [75, 82]]),
        Region("chest", "front", mirrorAnatomy([[79, 74], [103, 73], [103, 94], [92, 98], [78, 91], [75, 82]])),
        Region("biceps", "front", [[76, 69], [63, 67], [49, 71], [47, 80], [61, 84], [75, 78]]),
        Region("biceps", "front", mirrorAnatomy([[76, 69], [63, 67], [49, 71], [47, 80], [61, 84], [75, 78]])),
        Region("biceps", "front", [[70, 48], [61, 43], [48, 38], [43, 45], [53, 55], [65, 60]]),
        Region("biceps", "front", mirrorAnatomy([[70, 48], [61, 43], [48, 38], [43, 45], [53, 55], [65, 60]])),
        Region("forearms", "front", [[50, 70], [36, 69], [21, 72], [16, 78], [24, 84], [39, 82], [51, 78]]),
        Region("forearms", "front", mirrorAnatomy([[50, 70], [36, 69], [21, 72], [16, 78], [24, 84], [39, 82], [51, 78]])),
        Region("forearms", "front", [[48, 39], [40, 31], [32, 27], [29, 34], [36, 44], [45, 49], [54, 54]]),
        Region("forearms", "front", mirrorAnatomy([[48, 39], [40, 31], [32, 27], [29, 34], [36, 44], [45, 49], [54, 54]])),
        Region("obliques", "front", [[80, 91], [94, 94], [96, 113], [92, 122], [83, 119], [78, 105]]),
        Region("obliques", "front", mirrorAnatomy([[80, 91], [94, 94], [96, 113], [92, 122], [83, 119], [78, 105]])),
        Region("abs", "front", [[94, 87], [116, 87], [121, 112], [114, 126], [105, 130], [96, 126], [89, 112]]),
        Region("quads", "front", [[78, 123], [101, 126], [100, 145], [94, 161], [82, 169], [72, 161], [73, 143]]),
        Region("quads", "front", mirrorAnatomy([[78, 123], [101, 126], [100, 145], [94, 161], [82, 169], [72, 161], [73, 143]])),
        Region("adductors", "front", [[92, 125], [104, 128], [102, 151], [96, 159], [89, 149], [88, 135]]),
        Region("adductors", "front", mirrorAnatomy([[92, 125], [104, 128], [102, 151], [96, 159], [89, 149], [88, 135]])),
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
        "Face Pulls": Profile(primary: ["reardelts", "traps"], secondary: ["biceps"]),
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
