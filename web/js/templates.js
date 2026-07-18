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
import { Exercises, Programs } from "./db.js";
import { ex } from "./seed.js";

const lift = (exercise, role, baseWeightLb, estimatedMaxLb) =>
  ({ exerciseName: exercise, role, baseWeightLb, estimatedMaxLb, stallCount: 0, lastIncrementLb: 0 });
const acc = (exercise, sets, minReps, maxReps, weightLb = 0, incrementLb = 0) =>
  ({ exerciseName: exercise, sets, minReps, maxReps, currentReps: minReps, weightLb, incrementLb, stallCount: 0 });

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

/// Instantiate a template: ensure its exercises exist in the library (one
/// read, never overwriting an existing record), then create the program —
/// active only when it's the first. Returns the new program's id.
export async function createProgramFromTemplate(template) {
  const have = new Set((await Exercises.all()).map((e) => e.name));
  for (const e of template.exercises) {
    if (!have.has(e.name)) await Exercises.save({ ...e, createdAt: new Date().toISOString() });
  }
  const programs = await Programs.all();
  return Programs.save({
    name: uniqueName(template.name, new Set(programs.map((p) => p.name))),
    focus: template.focus, cycleNumber: 1, currentWeek: 1,
    nextDayIndex: 0, roundingLb: template.roundingLb, isActive: programs.length === 0,
    days: template.days.map((d, i) => ({
      name: d.name, order: i,
      lifts: d.lifts.map((l) => ({ ...l })),
      accessories: d.accessories.map((a) => ({ ...a })),
    })),
  });
}
