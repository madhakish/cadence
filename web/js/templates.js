// Pre-programmed starting points for "+ Add program" (the style picker).
// Each template is DATA: a focus, days of lifts/accessories, and compatibility
// definitions that may now also exist in the expanded seed. Instantiation
// never overwrites an existing library record. Baselines start deliberately
// light: the docs walk through setting rotation-1 bases before the first session.
//
// Ported 1:1 from CadenceCore/Sources/CadenceCore/ProgramTemplateData.swift;
// parity is ENFORCED against the shared fixture
// web/tests/fixtures/program-templates.json by both test suites — regenerate
// it with web/tools/generate-template-fixture.mjs when templates change.
import { Exercises, Programs, Sessions } from "./db.js";
import { ex } from "./seed.js";
import * as C from "./core.js";

const lift = (exercise, role, baseWeightLb, estimatedMaxLb, options = {}) =>
  ({ exerciseName: exercise, role, baseWeightLb, estimatedMaxLb, stallCount: 0, lastIncrementLb: 0,
     prescription: options.prescription || "automatic", sets: options.sets || 0,
     startFraction: options.startFraction || 0 });
const acc = (exercise, sets, minReps, maxReps, weightLb = 0, incrementLb = 0, startFraction = 0) =>
  ({ exerciseName: exercise, sets, minReps, maxReps, currentReps: minReps, weightLb, incrementLb,
     stallCount: 0, startFraction });

export const PROGRAM_TEMPLATES = [
  {
    id: "strength-upper-lower",
    name: "Strength — Upper/Lower",
    tagline: "4 days · barbell strength · A/B split over a 4-week wave",
    focus: "strength", roundingLb: 5,
    exercises: [
      ex("Back Extension", "Accessory", "bodyweight", "hinge"),
      ex("Hanging Knee Raise", "Accessory", "bodyweight", "core"),
    ],
    // The upper days alternate the two presses (A: overhead emphasis, B:
    // incline emphasis); each day's accessories support THAT press, and every
    // day carries core work.
    days: [
      { name: "Upper A", lifts: [lift("Overhead Press", "main", 65, 95), lift("Incline DB Press", "complementary", 50, 80)],
        accessories: [acc("DB Overhead Triceps Extension", 3, 8, 12, 20, 5), acc("Y-T-W Raises", 3, 10, 15, 10), acc("GHD Sit-up", 3, 8, 15)] },
      { name: "Lower A", lifts: [lift("Back Squat", "main", 135, 205), lift("Romanian Deadlift", "complementary", 95, 165)],
        accessories: [acc("Walking Lunges", 3, 10, 20), acc("Hanging Knee Raise", 3, 8, 15)] },
      { name: "Upper B", lifts: [lift("Incline DB Press", "main", 50, 80), lift("Overhead Press", "complementary", 65, 95)],
        accessories: [acc("Dips", 3, 5, 12), acc("Band Pull-aparts", 3, 15, 25), acc("Hanging Knee Raise", 3, 8, 15)] },
      { name: "Lower B", lifts: [lift("Deadlift", "main", 155, 245), lift("Front Squat", "complementary", 95, 155)],
        accessories: [acc("Back Extension", 3, 10, 15), acc("GHD Sit-up", 3, 8, 15)] },
    ],
  },
  {
    id: "olympic-weightlifting",
    name: "Olympic Weightlifting",
    tagline: "3 days · snatch, clean & jerk, strength base",
    focus: "strength", roundingLb: 5,
    exercises: [
      ex("Pull-ups", "Accessory", "bodyweight", "pull", { defaultRestSeconds: 120 }),
      ex("Back Extension", "Accessory", "bodyweight", "hinge"),
      ex("Hanging Knee Raise", "Accessory", "bodyweight", "core"),
    ],
    days: [
      { name: "Snatch Day", lifts: [lift("Snatch", "main", 65, 115), lift("Overhead Squat", "complementary", 65, 115)],
        accessories: [acc("Snatch Pull", 3, 3, 5, 95, 10), acc("Hanging Knee Raise", 3, 8, 15)] },
      { name: "Clean & Jerk Day", lifts: [lift("Clean & Jerk", "main", 85, 145), lift("Front Squat", "complementary", 115, 185)],
        accessories: [acc("Clean Pull", 3, 3, 5, 115, 10), acc("Pull-ups", 3, 5, 10)] },
      { name: "Strength Day", lifts: [lift("Back Squat", "main", 135, 225), lift("Overhead Press", "complementary", 65, 105)],
        accessories: [acc("Back Extension", 3, 10, 15), acc("Hanging Knee Raise", 3, 8, 15)] },
    ],
  },
  {
    id: "metabolic-conditioning",
    name: "Metabolic Conditioning",
    tagline: "3 days · circuits & engine work · reps climb, loads hold",
    // maintain: mains never add load; accessories double-progress reps, which
    // is the progression that makes sense for engine work.
    focus: "maintain", roundingLb: 5,
    exercises: [
      ex("Goblet Squat", "Accessory", "kettlebell", "squat", { defaultRestSeconds: 60 }),
      ex("Burpees", "Conditioning", "bodyweight", "conditioning", { defaultRestSeconds: 60 }),
      ex("Push-ups", "Accessory", "bodyweight", "press", { defaultRestSeconds: 60 }),
      ex("Mountain Climbers", "Conditioning", "bodyweight", "conditioning", { defaultRestSeconds: 45 }),
      ex("Sit-ups", "Accessory", "bodyweight", "core", { defaultRestSeconds: 45 }),
      ex("Box Jumps", "Conditioning", "bodyweight", "conditioning", { defaultRestSeconds: 60 }),
    ],
    days: [
      { name: "Engine A", lifts: [],
        accessories: [acc("KB Swing", 5, 10, 20, 35), acc("Burpees", 4, 8, 15), acc("Mountain Climbers", 4, 20, 40)] },
      { name: "Engine B", lifts: [],
        accessories: [acc("Push-ups", 4, 10, 25), acc("Ring Row", 4, 8, 15), acc("Sit-ups", 4, 15, 30)] },
      { name: "Engine C", lifts: [],
        accessories: [acc("Box Jumps", 4, 8, 15), acc("Goblet Squat", 4, 10, 20, 35), acc("Walking Lunges", 4, 12, 24)] },
    ],
  },
  // Novice linear progression in Rippetoe's canonical 3×5-across shape: squat
  // every session, presses alternate by day, deadlift one heavy set. Weight
  // moves every completed session, not per 4-week rotation.
  {
    id: "novice-linear-3x5",
    name: "Novice Linear — 3×5",
    tagline: "3 days/wk · Starting Strength-style A/B · weight every session",
    focus: "strength", roundingLb: 5,
    exercises: [],
    days: [
      { name: "Day A",
        lifts: [lift("Back Squat", "main", 95, 150, { prescription: "linearFives", sets: 3, startFraction: 0.74 }),
                lift("Overhead Press", "complementary", 65, 95, { prescription: "linearFives", sets: 3, startFraction: 0.74 }),
                lift("Deadlift", "complementary", 135, 205, { prescription: "linearFives", sets: 1, startFraction: 0.74 })],
        accessories: [] },
      { name: "Day B",
        lifts: [lift("Back Squat", "main", 95, 150, { prescription: "linearFives", sets: 3, startFraction: 0.74 }),
                lift("Barbell Bench", "complementary", 85, 125, { prescription: "linearFives", sets: 3, startFraction: 0.74 }),
                lift("Deadlift", "complementary", 135, 205, { prescription: "linearFives", sets: 1, startFraction: 0.74 })],
        accessories: [acc("Chin-ups", 3, 5, 10)] },
    ],
  },
  // The 5×5-across novice variant (Bill Starr lineage, popularized as
  // StrongLifts) — offered separately because 5×5 across is NOT the Starting
  // Strength prescription.
  {
    id: "novice-linear-5x5",
    name: "Novice Linear — 5×5",
    tagline: "3 days/wk · StrongLifts-style A/B · squat every session",
    focus: "strength", roundingLb: 5,
    exercises: [],
    days: [
      { name: "Day A",
        lifts: [lift("Back Squat", "main", 95, 150, { prescription: "linearFives", sets: 5, startFraction: 0.74 }),
                lift("Barbell Bench", "complementary", 85, 125, { prescription: "linearFives", sets: 5, startFraction: 0.74 }),
                lift("Barbell Row", "complementary", 95, 135, { prescription: "linearFives", sets: 5, startFraction: 0.74 })],
        accessories: [] },
      { name: "Day B",
        lifts: [lift("Back Squat", "main", 95, 150, { prescription: "linearFives", sets: 5, startFraction: 0.74 }),
                lift("Overhead Press", "complementary", 65, 95, { prescription: "linearFives", sets: 5, startFraction: 0.74 }),
                lift("Deadlift", "complementary", 135, 205, { prescription: "linearFives", sets: 1, startFraction: 0.74 })],
        accessories: [acc("Chin-ups", 3, 5, 10)] },
    ],
  },
  // Texas Method week as six slots over a two-week A/B pass so the presses
  // alternate weekly. Each slot starts at the published ratio of the lift's
  // 5RM (volume 90%, light 80% of volume, intensity = the 5RM PR set); twin
  // A/B slots share one synchronized progression at +5 per completion,
  // landing on the published +5 lb/week per lift.
  {
    id: "texas-method",
    name: "Texas Method",
    tagline: "3 days/wk · volume, light, intensity · presses alternate weekly",
    focus: "strength", roundingLb: 5,
    exercises: [],
    days: [
      { name: "Volume A",
        lifts: [lift("Back Squat", "main", 135, 205, { prescription: "texasVolume", sets: 5, startFraction: 0.77 }),
                lift("Barbell Bench", "complementary", 85, 125, { prescription: "texasVolume", sets: 5, startFraction: 0.77 })],
        accessories: [acc("Back Extension", 3, 10, 15)] },
      { name: "Light A",
        lifts: [lift("Back Squat", "main", 110, 205, { prescription: "texasLight", sets: 2, startFraction: 0.62 }),
                lift("Overhead Press", "complementary", 55, 95, { prescription: "texasLight", sets: 3, startFraction: 0.69 })],
        accessories: [acc("Chin-ups", 3, 5, 10)] },
      { name: "Intensity A",
        lifts: [lift("Back Squat", "main", 150, 205, { prescription: "texasIntensity", sets: 1, startFraction: 0.86 }),
                lift("Barbell Bench", "complementary", 95, 125, { prescription: "texasIntensity", sets: 1, startFraction: 0.86 }),
                lift("Deadlift", "complementary", 185, 245, { prescription: "texasIntensity", sets: 1, startFraction: 0.86 })],
        accessories: [] },
      { name: "Volume B",
        lifts: [lift("Back Squat", "main", 135, 205, { prescription: "texasVolume", sets: 5, startFraction: 0.77 }),
                lift("Overhead Press", "complementary", 65, 95, { prescription: "texasVolume", sets: 5, startFraction: 0.77 })],
        accessories: [acc("Back Extension", 3, 10, 15)] },
      { name: "Light B",
        lifts: [lift("Back Squat", "main", 110, 205, { prescription: "texasLight", sets: 2, startFraction: 0.62 }),
                lift("Barbell Bench", "complementary", 75, 125, { prescription: "texasLight", sets: 3, startFraction: 0.69 })],
        accessories: [acc("Chin-ups", 3, 5, 10)] },
      { name: "Intensity B",
        lifts: [lift("Back Squat", "main", 150, 205, { prescription: "texasIntensity", sets: 1, startFraction: 0.86 }),
                lift("Overhead Press", "complementary", 80, 95, { prescription: "texasIntensity", sets: 1, startFraction: 0.86 }),
                lift("Deadlift", "complementary", 185, 245, { prescription: "texasIntensity", sets: 1, startFraction: 0.86 })],
        accessories: [] },
    ],
  },
  // Wendler 5/3/1 with the original 90% training max, the three-week
  // 5s/3s/531 wave plus deload, and Boring-But-Big volume after the main
  // work. The slot base IS the training max.
  {
    id: "five-three-one",
    name: "5/3/1 — Wendler",
    tagline: "4 days/wk · training-max waves · top set is as many quality reps as you have",
    focus: "strength", roundingLb: 5,
    exercises: [],
    days: [
      { name: "Press Day",
        lifts: [lift("Overhead Press", "main", 85, 95, { prescription: "fiveThreeOne", startFraction: 0.90 })],
        accessories: [acc("Overhead Press", 5, 10, 10, 45, 5, 0.45), acc("Chin-ups", 5, 5, 10)] },
      { name: "Deadlift Day",
        lifts: [lift("Deadlift", "main", 220, 245, { prescription: "fiveThreeOne", startFraction: 0.90 })],
        accessories: [acc("Deadlift", 5, 10, 10, 115, 5, 0.45), acc("Hanging Knee Raise", 5, 10, 15)] },
      { name: "Bench Day",
        lifts: [lift("Barbell Bench", "main", 115, 125, { prescription: "fiveThreeOne", startFraction: 0.90 })],
        accessories: [acc("Barbell Bench", 5, 10, 10, 55, 5, 0.45), acc("Barbell Row", 5, 10, 10, 95, 5)] },
      { name: "Squat Day",
        lifts: [lift("Back Squat", "main", 185, 205, { prescription: "fiveThreeOne", startFraction: 0.90 })],
        accessories: [acc("Back Squat", 5, 10, 10, 95, 5, 0.45), acc("Lying Leg Curl", 5, 10, 12, 70, 5)] },
    ],
  },
  // Westside-style conjugate: max-effort top singles with repetition
  // accessories, and dynamic-effort speed waves at ~50–60%. Rotate the
  // max-effort variation with the existing swap gesture — rotation, not
  // grinding, is the methodology's stall answer. Straight bar weight only;
  // bands/chains are a coach's call the app does not fake.
  {
    id: "conjugate",
    name: "Conjugate — Westside-style",
    tagline: "4 days/wk · max-effort singles + speed work · rotate variations by swapping",
    focus: "strength", roundingLb: 5,
    exercises: [],
    days: [
      { name: "Max Effort Lower",
        lifts: [lift("Back Squat", "main", 185, 205, { prescription: "maxEffort", startFraction: 0.90 })],
        accessories: [acc("Nordic Hamstring Curl", 4, 6, 10), acc("Back Extension", 4, 10, 15), acc("Hanging Knee Raise", 4, 10, 15)] },
      { name: "Max Effort Upper",
        lifts: [lift("Barbell Bench", "main", 115, 125, { prescription: "maxEffort", startFraction: 0.90 })],
        accessories: [acc("Skull Crusher", 4, 8, 12, 30, 5), acc("Barbell Row", 4, 8, 12, 95, 5), acc("Face Pulls", 3, 12, 15, 25, 5)] },
      { name: "Dynamic Effort Lower",
        lifts: [lift("Back Squat", "main", 95, 205, { prescription: "dynamicEffort", startFraction: 0.50 }),
                lift("Deadlift", "complementary", 145, 245, { prescription: "dynamicEffort", startFraction: 0.60 })],
        accessories: [acc("Walking Lunges", 3, 10, 20), acc("Back Extension", 3, 10, 15)] },
      { name: "Dynamic Effort Upper",
        lifts: [lift("Barbell Bench", "main", 65, 125, { prescription: "dynamicEffort", startFraction: 0.50 })],
        accessories: [acc("Triceps Pushdown", 4, 10, 15, 40, 5), acc("Lat Pulldown", 4, 8, 12, 80, 5), acc("Rear Delt Fly", 3, 12, 15, 15, 5)] },
    ],
  },
];

// Program names must stay distinct: the native mirror's Program.name is a
// unique attribute (a fixed name would silently upsert into an in-progress
// program there), and duplicate rows are ambiguous everywhere.
const uniqueName = (base, taken) => {
  if (!taken.has(base)) return base;
  let n = 2;
  while (taken.has(`${base} ${n}`)) n += 1;
  return `${base} ${n}`;
};

/// Best recorded e1RM per exercise from completed, banked working sets — the
/// lifter's known history, used to compute methodology starting weights.
async function recordedE1RMs(names) {
  const wanted = new Set(names);
  const best = new Map();
  for (const session of await Sessions.all()) {
    if (!session.isCompleted) continue;
    for (const entry of session.exercises || []) {
      if (!wanted.has(entry.exerciseName)) continue;
      for (const set of entry.sets || []) {
        if (set.isWarmup || set.status !== "completed") continue;
        if (!(set.weightLb > 0) || !(set.reps >= 1)) continue;
        const sample = C.epleyE1RM(set.weightLb, set.reps);
        if (sample > (best.get(entry.exerciseName) || 0)) best.set(entry.exerciseName, sample);
      }
    }
  }
  return best;
}

// Round DOWN to the plate step: methodology guidance is to err light when
// deriving starting weights from an estimated max.
const floorTo = (x, step) => Math.floor(x / step + 1e-9) * step;

/// Instantiate a template: ensure its exercises exist in the library (one
/// read, never overwriting an existing record), then create the program —
/// active only when it's the first. Slots with a start fraction derive their
/// base weight from the lifter's recorded e1RM history; without history the
/// template's deliberately light hand-set base stands. Returns the new
/// program's id.
export async function createProgramFromTemplate(template) {
  const have = new Set((await Exercises.all()).map((e) => e.name));
  for (const e of template.exercises) {
    if (!have.has(e.name)) await Exercises.save({ ...e, createdAt: new Date().toISOString() });
  }
  const known = await recordedE1RMs(template.days.flatMap((d) =>
    [...(d.lifts || []).map((l) => l.exerciseName), ...(d.accessories || []).map((a) => a.exerciseName)]));
  const programs = await Programs.all();
  return Programs.save({
    name: uniqueName(template.name, new Set(programs.map((p) => p.name))),
    focus: template.focus, cycleNumber: 1, currentWeek: 1,
    nextDayIndex: 0, roundingLb: template.roundingLb, isActive: programs.length === 0,
    days: template.days.map((d, i) => ({
      name: d.name, order: i,
      lifts: d.lifts.map((l) => {
        const { startFraction = 0, sets = 0, ...record } = l;
        record.prescription = l.prescription || "automatic";
        if (sets > 0) record.doubleProgressionSets = sets;
        const fraction = startFraction || C.defaultStartFraction(record.prescription);
        const e1RM = known.get(l.exerciseName) || 0;
        if (fraction > 0 && e1RM > 0) {
          record.baseWeightLb = Math.max(45, floorTo(fraction * e1RM, template.roundingLb));
          record.estimatedMaxLb = Math.round(e1RM);
        }
        return record;
      }),
      accessories: d.accessories.map((a) => {
        const { startFraction = 0, ...record } = a;
        const e1RM = known.get(a.exerciseName) || 0;
        if (startFraction > 0 && e1RM > 0) {
          record.weightLb = Math.max(45, floorTo(startFraction * e1RM, template.roundingLb));
        }
        return record;
      }),
    })),
  });
}
