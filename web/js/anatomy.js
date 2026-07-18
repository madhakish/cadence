// Muscle anatomy for the exercise detail view: a stylized two-view figure
// (front + back) with per-muscle polygon regions, and the exercise → muscles
// map that drives the highlighting (primary movers red, supporting blue).
//
// DATA is ported 1:1 from CadenceCore/Sources/CadenceCore/AnatomyData.swift;
// parity is ENFORCED against web/tests/fixtures/anatomy.json by both test
// suites — regenerate with web/tools/generate-anatomy-fixture.mjs after edits.
// The SVG rendering at the bottom is web-only (native draws the same polygons
// with SwiftUI Path).

// Region display names (also the blurb vocabulary).
export const MUSCLE_NAMES = {
  traps: "Traps", delts: "Shoulders", chest: "Chest", biceps: "Biceps",
  triceps: "Triceps", forearms: "Forearms", abs: "Abs", obliques: "Obliques",
  lats: "Lats", lowerback: "Lower back", glutes: "Glutes", quads: "Quads",
  hamstrings: "Hamstrings", calves: "Calves",
};

// Figure geometry, coordinate space 100×220 per view. `body` is the neutral
// silhouette (both views); `regions` are the highlightable muscle polygons.
export const ANATOMY_BODY = [
  // head (octagon)
  [[46, 4], [54, 4], [59, 9], [59, 17], [54, 22], [46, 22], [41, 17], [41, 9]],
  // torso
  [[42, 24], [58, 24], [70, 30], [72, 44], [66, 52], [64, 88], [62, 104], [38, 104], [36, 88], [34, 52], [28, 44], [30, 30]],
  // arms
  [[28, 32], [34, 36], [32, 56], [30, 72], [27, 92], [20, 90], [22, 70], [24, 52], [24, 38]],
  [[72, 32], [66, 36], [68, 56], [70, 72], [73, 92], [80, 90], [78, 70], [76, 52], [76, 38]],
  // legs
  [[38, 104], [49, 104], [49, 120], [48, 146], [46, 178], [44, 196], [38, 196], [36, 170], [35, 140], [36, 118]],
  [[62, 104], [51, 104], [51, 120], [52, 146], [54, 178], [56, 196], [62, 196], [64, 170], [65, 140], [64, 118]],
];

export const ANATOMY_REGIONS = [
  // ---- front view ----
  { id: "traps", view: "front", points: [[42, 26], [58, 26], [54, 32], [46, 32]] },
  { id: "delts", view: "front", points: [[27, 32], [35, 35], [34, 44], [25, 42]] },
  { id: "delts", view: "front", points: [[73, 32], [65, 35], [66, 44], [75, 42]] },
  { id: "chest", view: "front", points: [[37, 34], [63, 34], [64, 50], [50, 54], [36, 50]] },
  { id: "biceps", view: "front", points: [[24, 46], [32, 48], [30, 66], [23, 64]] },
  { id: "biceps", view: "front", points: [[76, 46], [68, 48], [70, 66], [77, 64]] },
  { id: "forearms", view: "front", points: [[22, 68], [29, 70], [27, 90], [20, 88]] },
  { id: "forearms", view: "front", points: [[78, 68], [71, 70], [73, 90], [80, 88]] },
  { id: "obliques", view: "front", points: [[36, 54], [41, 56], [42, 86], [37, 84]] },
  { id: "obliques", view: "front", points: [[64, 54], [59, 56], [58, 86], [63, 84]] },
  { id: "abs", view: "front", points: [[42, 56], [58, 56], [57, 88], [43, 88]] },
  { id: "quads", view: "front", points: [[37, 106], [48, 106], [48, 142], [44, 148], [38, 140]] },
  { id: "quads", view: "front", points: [[63, 106], [52, 106], [52, 142], [56, 148], [62, 140]] },
  // ---- back view ----
  { id: "traps", view: "back", points: [[50, 24], [60, 30], [50, 46], [40, 30]] },
  { id: "delts", view: "back", points: [[27, 32], [35, 35], [34, 44], [25, 42]] },
  { id: "delts", view: "back", points: [[73, 32], [65, 35], [66, 44], [75, 42]] },
  { id: "lats", view: "back", points: [[36, 46], [47, 50], [46, 74], [38, 70], [34, 54]] },
  { id: "lats", view: "back", points: [[64, 46], [53, 50], [54, 74], [62, 70], [66, 54]] },
  { id: "triceps", view: "back", points: [[24, 46], [32, 48], [30, 66], [23, 64]] },
  { id: "triceps", view: "back", points: [[76, 46], [68, 48], [70, 66], [77, 64]] },
  { id: "forearms", view: "back", points: [[22, 68], [29, 70], [27, 90], [20, 88]] },
  { id: "forearms", view: "back", points: [[78, 68], [71, 70], [73, 90], [80, 88]] },
  { id: "lowerback", view: "back", points: [[43, 72], [57, 72], [56, 90], [44, 90]] },
  { id: "glutes", view: "back", points: [[38, 92], [62, 92], [60, 108], [50, 112], [40, 108]] },
  { id: "hamstrings", view: "back", points: [[37, 112], [48, 112], [48, 144], [44, 150], [38, 142]] },
  { id: "hamstrings", view: "back", points: [[63, 112], [52, 112], [52, 144], [56, 150], [62, 142]] },
  { id: "calves", view: "back", points: [[38, 152], [47, 152], [46, 178], [43, 182], [39, 176]] },
  { id: "calves", view: "back", points: [[62, 152], [53, 152], [54, 178], [57, 182], [61, 176]] },
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
  "Face Pulls": { primary: ["delts", "traps"], secondary: ["biceps"] },
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
const poly = (points, fill, stroke, opacity) => {
  const p = document.createElementNS(NS, "polygon");
  p.setAttribute("points", points.map(([x, y]) => `${x},${y}`).join(" "));
  if (fill) p.setAttribute("fill", fill);
  if (opacity != null) p.setAttribute("fill-opacity", String(opacity));
  p.setAttribute("stroke", stroke || "none");
  p.setAttribute("stroke-width", "0.8");
  return p;
};

/// Two figures side by side (front left, back right), primary regions red,
/// supporting blue, everything else neutral outline.
export function figureSVG(profile) {
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", "0 0 210 220");
  svg.setAttribute("class", "anatomy");
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", profile ? muscleBlurb(profile) : "Body diagram");
  for (const [view, dx] of [["front", 0], ["back", 105]]) {
    const g = document.createElementNS(NS, "g");
    g.setAttribute("transform", `translate(${dx},0)`);
    for (const b of ANATOMY_BODY) g.append(poly(b, "currentColor", "currentColor", 0.08));
    for (const r of ANATOMY_REGIONS) {
      if (r.view !== view) continue;
      const isP = profile && profile.primary.includes(r.id);
      const isS = profile && !isP && profile.secondary.includes(r.id);
      if (isP) g.append(poly(r.points, PRIMARY_COLOR, PRIMARY_COLOR, 0.85));
      else if (isS) g.append(poly(r.points, SECONDARY_COLOR, SECONDARY_COLOR, 0.7));
      else g.append(poly(r.points, "currentColor", "none", 0.06));
    }
    svg.append(g);
  }
  return svg;
}
