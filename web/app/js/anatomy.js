// Muscle anatomy for the exercise detail view: a weightlifting gorilla in Da
// Vinci's Vitruvian construction, plus the exercise → muscles map that drives
// the highlighting (primary movers red, supporting blue).
//
// DATA is ported 1:1 from CadenceCore/Sources/CadenceCore/AnatomyData.swift;
// parity is ENFORCED against web/tests/fixtures/anatomy.json by both test
// suites — regenerate with web/tools/generate-anatomy-fixture.mjs after edits.
// The SVG rendering at the bottom is web-only (native draws the same contours
// with SwiftUI Path).

// Region display names (also the blurb vocabulary).
export const MUSCLE_NAMES = {
  traps: "Traps", delts: "Shoulders", chest: "Chest", biceps: "Biceps",
  triceps: "Triceps", forearms: "Forearms", abs: "Abs", obliques: "Obliques",
  lats: "Lats", lowerback: "Lower back", glutes: "Glutes", quads: "Quads",
  hamstrings: "Hamstrings", calves: "Calves",
  adductors: "Adductors", reardelts: "Rear delts",
};

const mirror = (points) => points.map(([x, y]) => [x === 105 ? 105 : 210 - x, y]);

// Figure geometry, coordinate space 210×224 per view. Arms and legs reach the
// construction circle; the renderer rounds these control loops into continuous
// anatomical contours.
export const ANATOMY_BODY = [
  // head
  [[105, 6], [113, 8], [118, 14], [118, 23], [113, 30], [105, 33], [97, 30], [92, 23], [92, 14], [97, 8]],
  // torso
  [[97, 31], [113, 31], [119, 35], [133, 38], [139, 46], [138, 57], [132, 69], [129, 89], [133, 105],
    [126, 114], [116, 120], [94, 120], [84, 114], [77, 105], [81, 89], [78, 69], [72, 57], [71, 46], [77, 38], [91, 35]],
  // arms
  [[76, 39], [70, 39], [61, 46], [51, 53], [42, 60], [31, 66], [20, 72], [10, 80],
    [7, 88], [13, 93], [22, 86], [34, 79], [46, 71], [57, 63], [68, 55], [78, 48]],
  mirror([[76, 39], [70, 39], [61, 46], [51, 53], [42, 60], [31, 66], [20, 72], [10, 80],
    [7, 88], [13, 93], [22, 86], [34, 79], [46, 71], [57, 63], [68, 55], [78, 48]]),
  // legs
  [[84, 108], [103, 113], [103, 128], [97, 145], [90, 163], [82, 183], [73, 207],
    [62, 214], [54, 211], [59, 201], [66, 181], [71, 160], [75, 141], [77, 121]],
  mirror([[84, 108], [103, 113], [103, 128], [97, 145], [90, 163], [82, 183], [73, 207],
    [62, 214], [54, 211], [59, 201], [66, 181], [71, 160], [75, 141], [77, 121]]),
];

export const ANATOMY_REGIONS = [
  // ---- front view ----
  { id: "traps", view: "front", points: [[92, 33], [118, 33], [122, 38], [114, 47], [105, 50], [96, 47], [88, 38]] },
  { id: "delts", view: "front", points: [[75, 39], [85, 38], [91, 44], [88, 53], [79, 58], [69, 54], [69, 46]] },
  { id: "delts", view: "front", points: mirror([[75, 39], [85, 38], [91, 44], [88, 53], [79, 58], [69, 54], [69, 46]]) },
  { id: "chest", view: "front", points: [[84, 44], [103, 47], [103, 65], [94, 68], [82, 63], [77, 53]] },
  { id: "chest", view: "front", points: mirror([[84, 44], [103, 47], [103, 65], [94, 68], [82, 63], [77, 53]]) },
  { id: "biceps", view: "front", points: [[67, 53], [78, 56], [72, 65], [61, 73], [52, 72], [56, 63]] },
  { id: "biceps", view: "front", points: mirror([[67, 53], [78, 56], [72, 65], [61, 73], [52, 72], [56, 63]]) },
  { id: "forearms", view: "front", points: [[49, 70], [57, 76], [45, 83], [33, 90], [22, 97], [14, 92], [24, 84], [37, 77]] },
  { id: "forearms", view: "front", points: mirror([[49, 70], [57, 76], [45, 83], [33, 90], [22, 97], [14, 92], [24, 84], [37, 77]]) },
  { id: "obliques", view: "front", points: [[81, 64], [92, 67], [95, 89], [93, 105], [84, 109], [77, 96]] },
  { id: "obliques", view: "front", points: mirror([[81, 64], [92, 67], [95, 89], [93, 105], [84, 109], [77, 96]]) },
  { id: "abs", view: "front", points: [[94, 66], [116, 66], [120, 87], [117, 106], [105, 113], [93, 106], [90, 87]] },
  { id: "quads", view: "front", points: [[80, 112], [101, 117], [99, 137], [92, 159], [82, 177], [73, 171], [74, 151], [77, 132]] },
  { id: "quads", view: "front", points: mirror([[80, 112], [101, 117], [99, 137], [92, 159], [82, 177], [73, 171], [74, 151], [77, 132]]) },
  { id: "adductors", view: "front", points: [[93, 116], [103, 118], [100, 141], [91, 160], [83, 162], [88, 142]] },
  { id: "adductors", view: "front", points: mirror([[93, 116], [103, 118], [100, 141], [91, 160], [83, 162], [88, 142]]) },
  // ---- back view ----
  { id: "traps", view: "back", points: [[105, 32], [123, 37], [128, 43], [119, 55], [111, 66], [105, 72], [99, 66], [91, 55], [82, 43], [87, 37]] },
  { id: "delts", view: "back", points: [[75, 39], [85, 38], [92, 44], [89, 54], [79, 59], [69, 54], [69, 46]] },
  { id: "delts", view: "back", points: mirror([[75, 39], [85, 38], [92, 44], [89, 54], [79, 59], [69, 54], [69, 46]]) },
  { id: "reardelts", view: "back", points: [[78, 40], [91, 43], [93, 50], [85, 57], [76, 54], [71, 48]] },
  { id: "reardelts", view: "back", points: mirror([[78, 40], [91, 43], [93, 50], [85, 57], [76, 54], [71, 48]]) },
  { id: "lats", view: "back", points: [[83, 52], [103, 58], [101, 83], [94, 101], [82, 105], [78, 91], [79, 70]] },
  { id: "lats", view: "back", points: mirror([[83, 52], [103, 58], [101, 83], [94, 101], [82, 105], [78, 91], [79, 70]]) },
  { id: "triceps", view: "back", points: [[67, 53], [78, 57], [72, 68], [60, 77], [51, 73], [56, 63]] },
  { id: "triceps", view: "back", points: mirror([[67, 53], [78, 57], [72, 68], [60, 77], [51, 73], [56, 63]]) },
  { id: "forearms", view: "back", points: [[49, 70], [57, 76], [45, 83], [33, 90], [22, 97], [14, 92], [24, 84], [37, 77]] },
  { id: "forearms", view: "back", points: mirror([[49, 70], [57, 76], [45, 83], [33, 90], [22, 97], [14, 92], [24, 84], [37, 77]]) },
  { id: "lowerback", view: "back", points: [[93, 82], [117, 82], [121, 103], [114, 116], [105, 120], [96, 116], [89, 103]] },
  { id: "glutes", view: "back", points: [[80, 104], [103, 108], [103, 126], [94, 136], [80, 133], [76, 120]] },
  { id: "glutes", view: "back", points: mirror([[80, 104], [103, 108], [103, 126], [94, 136], [80, 133], [76, 120]]) },
  { id: "hamstrings", view: "back", points: [[79, 130], [98, 132], [95, 153], [87, 178], [76, 184], [70, 175], [75, 153]] },
  { id: "hamstrings", view: "back", points: mirror([[79, 130], [98, 132], [95, 153], [87, 178], [76, 184], [70, 175], [75, 153]]) },
  { id: "calves", view: "back", points: [[71, 175], [84, 181], [78, 203], [70, 211], [61, 208], [63, 196]] },
  { id: "calves", view: "back", points: mirror([[71, 175], [84, 181], [78, 203], [70, 211], [61, 208], [63, 196]]) },
];

// Rendering contours tuned to the Vitruvian weightlifting ape's 210×210 square.
// These are deliberately separate from the legacy fixture geometry above:
// the data/map parity contract stays stable while the visible wash follows both
// superimposed arm and leg poses in the engraved source art.
export const VITRUVIAN_FRONT_REGIONS = [
  { id: "traps", points: [[80, 67], [91, 63], [100, 68], [98, 78], [89, 84], [79, 76]] },
  { id: "traps", points: mirror([[80, 67], [91, 63], [100, 68], [98, 78], [89, 84], [79, 76]]) },
  { id: "delts", points: [[68, 61], [82, 58], [91, 64], [87, 76], [76, 81], [65, 73]] },
  { id: "delts", points: mirror([[68, 61], [82, 58], [91, 64], [87, 76], [76, 81], [65, 73]]) },
  { id: "chest", points: [[79, 74], [103, 73], [103, 94], [92, 98], [78, 91], [75, 82]] },
  { id: "chest", points: mirror([[79, 74], [103, 73], [103, 94], [92, 98], [78, 91], [75, 82]]) },
  { id: "biceps", points: [[76, 69], [63, 67], [49, 71], [47, 80], [61, 84], [75, 78]] },
  { id: "biceps", points: mirror([[76, 69], [63, 67], [49, 71], [47, 80], [61, 84], [75, 78]]) },
  { id: "biceps", points: [[70, 48], [61, 43], [48, 38], [43, 45], [53, 55], [65, 60]] },
  { id: "biceps", points: mirror([[70, 48], [61, 43], [48, 38], [43, 45], [53, 55], [65, 60]]) },
  { id: "forearms", points: [[50, 70], [36, 69], [21, 72], [16, 78], [24, 84], [39, 82], [51, 78]] },
  { id: "forearms", points: mirror([[50, 70], [36, 69], [21, 72], [16, 78], [24, 84], [39, 82], [51, 78]]) },
  { id: "forearms", points: [[48, 39], [40, 31], [32, 27], [29, 34], [36, 44], [45, 49], [54, 54]] },
  { id: "forearms", points: mirror([[48, 39], [40, 31], [32, 27], [29, 34], [36, 44], [45, 49], [54, 54]]) },
  { id: "obliques", points: [[80, 91], [94, 94], [96, 113], [92, 122], [83, 119], [78, 105]] },
  { id: "obliques", points: mirror([[80, 91], [94, 94], [96, 113], [92, 122], [83, 119], [78, 105]]) },
  { id: "abs", points: [[94, 87], [116, 87], [121, 112], [114, 126], [105, 130], [96, 126], [89, 112]] },
  { id: "quads", points: [[78, 123], [101, 126], [100, 145], [94, 161], [82, 169], [72, 161], [73, 143]] },
  { id: "quads", points: mirror([[78, 123], [101, 126], [100, 145], [94, 161], [82, 169], [72, 161], [73, 143]]) },
  { id: "adductors", points: [[92, 125], [104, 128], [102, 151], [96, 159], [89, 149], [88, 135]] },
  { id: "adductors", points: mirror([[92, 125], [104, 128], [102, 151], [96, 159], [89, 149], [88, 135]]) },
];

// Exercise → { primary, secondary } by canonical library name.
export const MUSCLE_MAP = {
  "Deadlift": { primary: ["hamstrings", "glutes", "lowerback"], secondary: ["lats", "traps", "forearms", "quads"] },
  "Snatch-grip Deadlift": { primary: ["hamstrings", "glutes", "lowerback"], secondary: ["traps", "lats", "forearms"] },
  "Romanian Deadlift": { primary: ["hamstrings", "glutes"], secondary: ["lowerback", "forearms"] },
  "Good Morning": { primary: ["hamstrings", "lowerback"], secondary: ["glutes"] },
  "Back Squat": { primary: ["quads", "glutes"], secondary: ["hamstrings", "lowerback", "abs"] },
  "Front Squat": { primary: ["quads", "abs"], secondary: ["glutes", "lowerback"] },
  "Overhead Squat": { primary: ["quads", "delts"], secondary: ["abs", "glutes", "traps"] },
  "Goblet Squat": { primary: ["quads", "glutes"], secondary: ["abs"] },
  "Walking Lunges": { primary: ["quads", "glutes"], secondary: ["hamstrings", "abs"] },
  "Barbell Bench": { primary: ["chest", "triceps"], secondary: ["delts"] },
  "Flat DB Press": { primary: ["chest", "triceps"], secondary: ["delts"] },
  "Incline DB Press": { primary: ["chest", "delts"], secondary: ["triceps"] },
  "Overhead Press": { primary: ["delts", "triceps"], secondary: ["traps", "abs"] },
  "Push Press": { primary: ["delts", "triceps"], secondary: ["quads", "abs"] },
  "Push Jerk": { primary: ["delts", "triceps"], secondary: ["quads", "abs"] },
  "Split Jerk": { primary: ["delts", "triceps"], secondary: ["quads", "glutes", "abs"] },
  "Overhead DB Press": { primary: ["delts", "triceps"], secondary: ["traps"] },
  "Seated Upright DB Press": { primary: ["delts", "triceps"], secondary: ["traps"] },
  "Snatch": { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"] },
  "Power Snatch": { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"] },
  "Hang Power Snatch": { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"] },
  "Clean": { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "lowerback", "forearms"] },
  "Power Clean": { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "lowerback", "forearms"] },
  "Hang Power Clean": { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "lowerback", "forearms"] },
  "KB Clean": { primary: ["hamstrings", "glutes", "traps"], secondary: ["forearms", "abs"] },
  "Clean & Jerk": { primary: ["hamstrings", "glutes", "delts"], secondary: ["quads", "traps", "triceps", "lowerback"] },
  "Clean Pull": { primary: ["hamstrings", "glutes", "traps"], secondary: ["lowerback", "forearms"] },
  "Snatch Pull": { primary: ["hamstrings", "glutes", "traps"], secondary: ["lowerback", "forearms"] },
  "KB Swing": { primary: ["glutes", "hamstrings"], secondary: ["lowerback", "abs", "delts"] },
  "Turkish Get-up": { primary: ["abs", "delts"], secondary: ["glutes", "obliques"] },
  "Single-arm DB Row": { primary: ["lats"], secondary: ["biceps", "forearms", "obliques"] },
  "Chest-supported Row": { primary: ["lats", "traps"], secondary: ["biceps"] },
  "Ring Row": { primary: ["lats", "biceps"], secondary: ["abs"] },
  "Lat Pulldown": { primary: ["lats"], secondary: ["biceps"] },
  "Chin-ups": { primary: ["lats", "biceps"], secondary: ["abs", "forearms"] },
  "Pull-ups": { primary: ["lats"], secondary: ["biceps", "abs", "forearms"] },
  // Adding a belt loads the same movement — the muscles worked do not change.
  "Weighted Chin-up": { primary: ["lats", "biceps"], secondary: ["abs", "forearms"] },
  "Weighted Pull-up": { primary: ["lats"], secondary: ["biceps", "abs", "forearms"] },
  "Face Pulls": { primary: ["reardelts", "traps"], secondary: ["biceps"] },
  "Band Pull-aparts": { primary: ["delts", "traps"], secondary: [] },
  "Y-T-W Raises": { primary: ["delts", "traps"], secondary: [] },
  "Band External Rotation": { primary: ["delts"], secondary: [] },
  "DB Curls": { primary: ["biceps"], secondary: ["forearms"] },
  "DB Overhead Triceps Extension": { primary: ["triceps"], secondary: [] },
  "Dips": { primary: ["chest", "triceps"], secondary: ["delts"] },
  "Push-ups": { primary: ["chest", "triceps"], secondary: ["delts", "abs"] },
  "Back Extension": { primary: ["lowerback", "glutes"], secondary: ["hamstrings"] },
  "GHD Sit-up": { primary: ["abs"], secondary: ["obliques"] },
  "Sit-ups": { primary: ["abs"], secondary: ["obliques"] },
  "Plank": { primary: ["abs"], secondary: ["obliques", "delts"] },
  "Side Plank": { primary: ["obliques"], secondary: ["abs", "delts"] },
  "Hanging Knee Raise": { primary: ["abs"], secondary: ["obliques", "forearms"] },
  "Burpees": { primary: ["chest", "quads"], secondary: ["abs", "delts"] },
  "Mountain Climbers": { primary: ["abs"], secondary: ["quads", "delts"] },
  "Box Jumps": { primary: ["quads", "glutes"], secondary: ["calves"] },
  "Bike": { primary: ["quads", "calves"], secondary: ["hamstrings", "glutes"] },
  "Run-Walk Intervals": { primary: ["quads", "calves"], secondary: ["hamstrings", "glutes"] },
  "Ruck": { primary: ["quads", "calves"], secondary: ["traps", "abs"] },
  "Walk": { primary: ["quads", "calves"], secondary: ["hamstrings"] },

  // Previously these fell through to the coarse movement-group default,
  // which was merely vague for some and plainly wrong for others: a leg
  // curl inherited "hinge" and so claimed glutes, hip adduction inherited
  // "squat" and claimed quads.
  "Copenhagen Plank": { primary: ["adductors"], secondary: ["obliques", "abs"] },
  "Cable Hip Adduction": { primary: ["adductors"], secondary: ["glutes"] },
  "Monster Walk": { primary: ["glutes"], secondary: ["quads"] },
  "Seated Leg Curl": { primary: ["hamstrings"], secondary: ["calves"] },
  "Lying Leg Curl": { primary: ["hamstrings"], secondary: ["calves"] },
  "Nordic Hamstring Curl": { primary: ["hamstrings"], secondary: ["glutes", "calves"] },
  "Trap Bar Deadlift": { primary: ["quads", "glutes", "hamstrings"], secondary: ["traps", "lowerback", "forearms"] },
  "Sumo Deadlift": { primary: ["glutes", "quads", "adductors"], secondary: ["hamstrings", "lowerback", "traps", "forearms"] },
  "Barbell Hip Thrust": { primary: ["glutes"], secondary: ["hamstrings"] },
  "DB Romanian Deadlift": { primary: ["hamstrings", "glutes"], secondary: ["lowerback", "forearms"] },
  "Glute Bridge": { primary: ["glutes"], secondary: ["hamstrings"] },
  "Cable Pull-through": { primary: ["glutes", "hamstrings"], secondary: ["lowerback"] },
  "GHD Back Extension": { primary: ["lowerback", "glutes"], secondary: ["hamstrings"] },
  "Hack Squat": { primary: ["quads"], secondary: ["glutes"] },
  "Leg Press": { primary: ["quads", "glutes"], secondary: ["hamstrings"] },
  "Leg Extension": { primary: ["quads"], secondary: [] },
  "Bulgarian Split Squat": { primary: ["quads", "glutes"], secondary: ["hamstrings", "adductors", "abs"] },
  "Reverse Lunge": { primary: ["quads", "glutes"], secondary: ["hamstrings", "abs"] },
  "Forward Lunge": { primary: ["quads", "glutes"], secondary: ["hamstrings", "abs"] },
  "Step-up": { primary: ["quads", "glutes"], secondary: ["hamstrings", "calves"] },
  "Incline Barbell Bench Press": { primary: ["chest", "delts"], secondary: ["triceps"] },
  "Close-Grip Bench Press": { primary: ["triceps", "chest"], secondary: ["delts"] },
  "Low Box Squat": { primary: ["glutes", "hamstrings"], secondary: ["quads", "lowerback", "adductors"] },
  "Front Box Squat": { primary: ["quads", "glutes"], secondary: ["hamstrings", "abs"] },
  "Paused Box Squat": { primary: ["glutes", "quads"], secondary: ["hamstrings", "lowerback"] },
  "Floor Press": { primary: ["chest", "triceps"], secondary: ["delts"] },
  "Close-Grip Floor Press": { primary: ["triceps", "chest"], secondary: ["delts"] },
  "Speed Box Squat": { primary: ["glutes", "quads"], secondary: ["hamstrings", "lowerback"] },
  "Speed Deadlift": { primary: ["hamstrings", "glutes"], secondary: ["lowerback", "traps", "forearms"] },
  "Speed Bench Press": { primary: ["chest", "triceps"], secondary: ["delts"] },
  "Machine Chest Press": { primary: ["chest", "triceps"], secondary: ["delts"] },
  "Landmine Press": { primary: ["delts", "chest"], secondary: ["triceps", "abs"] },
  "Arnold Press": { primary: ["delts"], secondary: ["triceps", "traps"] },
  "DB Floor Press": { primary: ["chest", "triceps"], secondary: ["delts"] },
  "Cable Chest Fly": { primary: ["chest"], secondary: ["delts"] },
  "Pec Deck": { primary: ["chest"], secondary: ["delts"] },
  "Incline Push-ups": { primary: ["chest", "triceps"], secondary: ["delts", "abs"] },
  "Decline Push-ups": { primary: ["chest", "delts"], secondary: ["triceps", "abs"] },
  "Diamond Push-ups": { primary: ["triceps", "chest"], secondary: ["delts", "abs"] },
  "Close-Grip Push-ups": { primary: ["triceps", "chest"], secondary: ["delts", "abs"] },
  "KB Press": { primary: ["delts", "triceps"], secondary: ["traps", "abs"] },
  "Banded Chest Press": { primary: ["chest", "triceps"], secondary: ["delts"] },
  "Barbell Row": { primary: ["lats", "traps"], secondary: ["biceps", "lowerback", "forearms"] },
  "Pendlay Row": { primary: ["lats", "traps"], secondary: ["biceps", "lowerback", "forearms"] },
  "T-Bar Row": { primary: ["lats", "traps"], secondary: ["biceps", "forearms"] },
  "Assisted Pull-up": { primary: ["lats"], secondary: ["biceps", "forearms"] },
  "Seated Cable Row": { primary: ["lats", "traps"], secondary: ["biceps", "forearms"] },
  "One-arm Cable Row": { primary: ["lats"], secondary: ["biceps", "obliques", "forearms"] },
  "Bent-over DB Row": { primary: ["lats", "traps"], secondary: ["biceps", "lowerback", "forearms"] },
  "Incline Bench DB Row": { primary: ["lats", "traps"], secondary: ["biceps", "forearms"] },
  "Straight-arm Pulldown": { primary: ["lats"], secondary: ["triceps", "abs"] },
  "KB Row": { primary: ["lats"], secondary: ["biceps", "forearms", "obliques"] },
  "Banded Row": { primary: ["lats", "traps"], secondary: ["biceps", "forearms"] },
  "Rear Delt Fly": { primary: ["reardelts"], secondary: ["traps"] },
  "Reverse Pec Deck": { primary: ["reardelts"], secondary: ["traps"] },
  "DB Lateral Raise": { primary: ["delts"], secondary: ["traps"] },
  "Cable Lateral Raise": { primary: ["delts"], secondary: ["traps"] },
  "DB Front Raise": { primary: ["delts"], secondary: ["chest"] },
  "Barbell Curl": { primary: ["biceps"], secondary: ["forearms"] },
  "Hammer Curl": { primary: ["biceps", "forearms"], secondary: [] },
  "Incline DB Curl": { primary: ["biceps"], secondary: ["forearms"] },
  "Preacher Curl": { primary: ["biceps"], secondary: ["forearms"] },
  "Cable Curl": { primary: ["biceps"], secondary: ["forearms"] },
  "Triceps Pushdown": { primary: ["triceps"], secondary: [] },
  "Skull Crusher": { primary: ["triceps"], secondary: [] },
  "Cable Overhead Triceps Extension": { primary: ["triceps"], secondary: [] },
  "Standing Calf Raise": { primary: ["calves"], secondary: [] },
  "Seated Calf Raise": { primary: ["calves"], secondary: [] },
  "Ab Wheel Rollout": { primary: ["abs"], secondary: ["lats", "obliques", "delts"] },
  "Dead Bug": { primary: ["abs"], secondary: ["obliques"] },
  "Bird Dog": { primary: ["lowerback", "glutes"], secondary: ["abs", "delts"] },
  "Pallof Press": { primary: ["obliques", "abs"], secondary: ["delts"] },
  "Cable Crunch": { primary: ["abs"], secondary: ["obliques"] },
  "Reverse Crunch": { primary: ["abs"], secondary: ["obliques"] },
  "Hollow Hold": { primary: ["abs"], secondary: ["obliques"] },
  "Farmer Carry": { primary: ["forearms", "traps"], secondary: ["abs", "obliques", "quads"] },
  "Suitcase Carry": { primary: ["obliques", "forearms"], secondary: ["traps", "abs"] },
  "Hang Clean": { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "lowerback", "forearms"] },
  "Hang Snatch": { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"] },
  "Muscle Clean": { primary: ["traps", "delts"], secondary: ["hamstrings", "glutes", "forearms"] },
  "Muscle Snatch": { primary: ["traps", "delts"], secondary: ["hamstrings", "glutes", "forearms"] },
  "Clean High Pull": { primary: ["traps", "hamstrings", "glutes"], secondary: ["lowerback", "forearms"] },
  "Snatch High Pull": { primary: ["traps", "hamstrings", "glutes"], secondary: ["lowerback", "forearms", "delts"] },
  "Jump Rope": { primary: ["calves"], secondary: ["quads", "forearms"] },
  "Row Erg": { primary: ["lats", "quads"], secondary: ["biceps", "lowerback", "hamstrings"] },
  "Ski Erg": { primary: ["lats", "triceps"], secondary: ["abs", "delts"] },
  "Elliptical": { primary: ["quads", "glutes"], secondary: ["hamstrings", "calves"] },
  "Stair Climber": { primary: ["quads", "glutes"], secondary: ["calves", "hamstrings"] },
  "Sled Push": { primary: ["quads", "glutes"], secondary: ["calves", "delts"] },
  "Sled Pull": { primary: ["hamstrings", "glutes"], secondary: ["lats", "biceps", "calves"] },
  "Battle Ropes": { primary: ["delts", "forearms"], secondary: ["abs", "lats"] },
  "Swimming": { primary: ["lats", "delts"], secondary: ["triceps", "abs", "glutes"] },
  "Front-rack Carry": { primary: ["abs", "forearms"], secondary: ["traps", "delts", "quads"] },
  "Overhead Carry": { primary: ["delts", "obliques"], secondary: ["traps", "abs", "forearms"] },
  "KB Snatch": { primary: ["glutes", "hamstrings", "delts"], secondary: ["traps", "forearms", "abs"] },
  "Thruster": { primary: ["quads", "delts"], secondary: ["glutes", "triceps", "abs"] },
  "Wall Sit": { primary: ["quads"], secondary: ["glutes", "calves"] },
  "Run": { primary: ["quads", "calves"], secondary: ["hamstrings", "glutes"] },
  "Bear Crawl": { primary: ["delts", "abs"], secondary: ["quads", "triceps"] },
  "Wood Splitting": { primary: ["lats", "abs"], secondary: ["obliques", "delts", "forearms"] },
};

// Movement-group fallback for exercises the map doesn't know (user-created).
export const MUSCLE_GROUP_DEFAULTS = {
  squat: { primary: ["quads", "glutes"], secondary: ["abs", "lowerback"] },
  hinge: { primary: ["hamstrings", "glutes"], secondary: ["lowerback"] },
  press: { primary: ["delts", "chest", "triceps"], secondary: ["abs"] },
  pull: { primary: ["lats", "biceps"], secondary: ["forearms"] },
  olympic: { primary: ["hamstrings", "glutes", "traps"], secondary: ["quads", "delts", "lowerback"] },
  shoulder: { primary: ["delts"], secondary: ["traps"] },
  arms: { primary: ["biceps", "triceps"], secondary: ["forearms"] },
  core: { primary: ["abs"], secondary: ["obliques"] },
  calves: { primary: ["calves"], secondary: ["hamstrings"] },
  carry: { primary: ["forearms", "traps"], secondary: ["abs", "obliques"] },
  conditioning: { primary: ["quads", "calves"], secondary: ["abs"] },
};

// Exact name first, then the movement-group default, else null (no figure).
export function muscleProfile(name, movementGroup) {
  return MUSCLE_MAP[name] || MUSCLE_GROUP_DEFAULTS[movementGroup] || null;
}

// "Primary: Shoulders, Triceps · Supporting: Traps, Abs"
export function muscleBlurb(profile) {
  if (!profile) return "";
  const names = (ids) => ids.map((r) => MUSCLE_NAMES[r] || r).join(", ");
  const parts = [`Primary: ${names(profile.primary)}`];
  if (profile.secondary.length) parts.push(`Supporting: ${names(profile.secondary)}`);
  return parts.join(" · ");
}

// ---- web-only SVG rendering ------------------------------------------------
const NS = "http://www.w3.org/2000/svg";
const PRIMARY_COLOR = "#e0453a";   // red — primary movers
const SECONDARY_COLOR = "#3a7bd5"; // blue — supporting
const smoothPath = (points) => {
  if (points.length < 3) return "";
  const midpoint = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  const start = midpoint(points.at(-1), points[0]);
  let d = `M${start[0]} ${start[1]}`;
  points.forEach((point, index) => {
    const end = midpoint(point, points[(index + 1) % points.length]);
    d += ` Q${point[0]} ${point[1]} ${end[0]} ${end[1]}`;
  });
  return `${d} Z`;
};
const shape = (points, fill, stroke, opacity, className) => {
  const p = document.createElementNS(NS, "path");
  p.setAttribute("d", smoothPath(points));
  if (className) p.setAttribute("class", className);
  if (fill) p.setAttribute("fill", fill);
  if (opacity != null) p.setAttribute("fill-opacity", String(opacity));
  p.setAttribute("stroke", stroke || "none");
  p.setAttribute("stroke-width", "0.7");
  p.setAttribute("vector-effect", "non-scaling-stroke");
  return p;
};

const BACK_REGION_ASSET = {
  traps: "traps", delts: "delts", reardelts: "delts", lats: "lats",
  triceps: "triceps", lowerback: "lowerback", forearms: "forearms",
  glutes: "glutes", hamstrings: "hamstrings", calves: "calves",
};

const referenceImage = (href, className = "anatomy-reference") => {
  const image = document.createElementNS(NS, "image");
  image.setAttribute("class", className);
  image.setAttribute("href", href);
  image.setAttribute("x", "0");
  image.setAttribute("y", "0");
  image.setAttribute("width", "210");
  image.setAttribute("height", "210");
  image.setAttribute("preserveAspectRatio", "xMidYMid meet");
  return image;
};

const appendBackMask = (g, id, role) => {
  const asset = BACK_REGION_ASSET[id];
  if (!asset) return;
  if (g.querySelector(`image[data-role="${role}"][data-asset="${asset}"]`)) return;
  const image = referenceImage(`assets/vitruvian-back-${asset}.svg`, `anatomy-region-mask ${role}`);
  image.setAttribute("data-role", role);
  image.setAttribute("data-asset", asset);
  image.setAttribute("data-muscle", id);
  g.append(image);
};

/// Front and back figures side by side. The exact reference drawings remain
/// intact while translucent muscle colour multiplies over their ink detail.
export function figureSVG(profile) {
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", "0 0 430 230");
  svg.setAttribute("class", "anatomy");
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", profile ? muscleBlurb(profile) : "Body diagram");
  for (const [view, dx] of [["front", 0], ["back", 220]]) {
    const g = document.createElementNS(NS, "g");
    g.setAttribute("class", "anatomy-figure-panel");
    g.setAttribute("transform", `translate(${dx},0)`);
    const image = referenceImage(`assets/vitruvian-${view}.jpeg`);
    image.setAttribute("data-species", "gorilla");
    image.setAttribute("data-source", "exact-reference");
    g.append(image);
    if (view === "front") {
      const regions = document.createElementNS(NS, "g");
      regions.setAttribute("class", "anatomy-highlight-layer");
      for (const r of VITRUVIAN_FRONT_REGIONS) {
        const isP = profile && profile.primary.includes(r.id);
        const isS = profile && !isP && profile.secondary.includes(r.id);
        if (isP) regions.append(shape(r.points, PRIMARY_COLOR, "none", 0.46, "anatomy-region primary"));
        else if (isS) regions.append(shape(r.points, SECONDARY_COLOR, "none", 0.30, "anatomy-region supporting"));
      }
      g.append(regions);
    } else if (profile) {
      for (const id of profile.secondary) appendBackMask(g, id, "supporting");
      for (const id of profile.primary) appendBackMask(g, id, "primary");
    }
    svg.append(g);
  }
  for (const [label, x] of [["Ape front", 105], ["Ape back", 325]]) {
    const text = document.createElementNS(NS, "text");
    text.setAttribute("class", "anatomy-view-label");
    text.setAttribute("x", String(x));
    text.setAttribute("y", "226");
    text.setAttribute("text-anchor", "middle");
    text.textContent = label;
    svg.append(text);
  }
  return svg;
}

/// Visible muscle grouping for the exercise detail. The body colours are much
/// faster to scan when their exact names sit beside the same colour key.
export function muscleLegend(profile) {
  const wrap = document.createElement("div");
  wrap.className = "anatomy-legend";
  if (!profile) return wrap;
  const row = (role, ids) => {
    const line = document.createElement("div");
    line.className = `muscle-key ${role}`;
    line.dataset.role = role;
    const dot = document.createElement("i");
    dot.setAttribute("aria-hidden", "true");
    const label = document.createElement("strong");
    label.textContent = role === "primary" ? "Primary" : "Supporting";
    const names = document.createElement("span");
    names.textContent = ids.map((id) => MUSCLE_NAMES[id] || id).join(", ");
    line.append(dot, label, names);
    return line;
  };
  wrap.append(row("primary", profile.primary));
  if (profile.secondary.length) wrap.append(row("supporting", profile.secondary));
  return wrap;
}
