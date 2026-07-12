// Pre-programmed starting points for "+ Add program" (issue: style picker).
// Each template is DATA: a focus, days of lifts/accessories, and the library
// exercises it needs (created only if missing — an existing exercise is never
// overwritten). Baselines start deliberately light: the docs walk through
// setting rotation-1 bases before the first session. Ported 1:1 to
// Cadence/Seed/ProgramTemplates.swift — keep the two in lockstep.
import { Exercises, Programs } from "./db.js";

// Same record shape the seed uses (see seed.js `ex`).
const ex = (name, category, type, group, o = {}) => ({
  name, category, type, movementGroup: group,
  isUnilateral: !!o.isUnilateral,
  defaultRestSeconds: o.defaultRestSeconds ?? 90,
  notes: o.notes || "", isShelved: false, shelvedNote: "", watchSite: null,
  createdAt: new Date().toISOString(),
});
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
      ex("Overhead Press", "Main", "barbell", "press", { defaultRestSeconds: 300 }),
      ex("Push Press", "Main", "barbell", "press", { defaultRestSeconds: 300 }),
      ex("Incline DB Press", "Main", "dumbbell", "press", { defaultRestSeconds: 180 }),
      ex("Back Squat", "Main", "barbell", "squat", { defaultRestSeconds: 300 }),
      ex("Front Squat", "Main", "barbell", "squat", { defaultRestSeconds: 300 }),
      ex("Deadlift", "Main", "barbell", "hinge", { defaultRestSeconds: 300 }),
      ex("Romanian Deadlift", "Main", "barbell", "hinge", { defaultRestSeconds: 180 }),
      ex("Chin-ups", "Accessory", "bodyweight", "pull", { defaultRestSeconds: 120 }),
      ex("One-arm DB Row", "Accessory", "dumbbell", "pull", { isUnilateral: true, defaultRestSeconds: 90 }),
      ex("Walking Lunges", "Accessory", "bodyweight", "squat", { isUnilateral: true }),
      ex("Back Extension", "Accessory", "bodyweight", "hinge"),
      ex("Hanging Knee Raise", "Accessory", "bodyweight", "core"),
      ex("Push-ups", "Accessory", "bodyweight", "press"),
    ],
    days: [
      { name: "Upper A", lifts: [lift("Overhead Press", "main", 65, 95), lift("Incline DB Press", "complementary", 50, 80)],
        accessories: [acc("Chin-ups", 3, 5, 10), acc("One-arm DB Row", 3, 8, 12, 40, 5)] },
      { name: "Lower A", lifts: [lift("Back Squat", "main", 135, 205), lift("Romanian Deadlift", "complementary", 95, 165)],
        accessories: [acc("Walking Lunges", 3, 10, 20), acc("Hanging Knee Raise", 3, 8, 15)] },
      { name: "Upper B", lifts: [lift("Push Press", "main", 75, 115), lift("Incline DB Press", "complementary", 50, 80)],
        accessories: [acc("Push-ups", 3, 10, 25), acc("One-arm DB Row", 3, 8, 12, 40, 5)] },
      { name: "Lower B", lifts: [lift("Deadlift", "main", 155, 245), lift("Front Squat", "complementary", 95, 155)],
        accessories: [acc("Back Extension", 3, 10, 15), acc("Hanging Knee Raise", 3, 8, 15)] },
    ],
  },
  {
    id: "olympic-weightlifting",
    name: "Olympic Weightlifting",
    tagline: "3 days · snatch, clean & jerk, strength base",
    focus: "strength", roundingLb: 5,
    exercises: [
      ex("Snatch", "Main", "barbell", "olympic", { defaultRestSeconds: 300 }),
      ex("Clean and Jerk", "Main", "barbell", "olympic", { defaultRestSeconds: 300 }),
      ex("Overhead Squat", "Main", "barbell", "squat", { defaultRestSeconds: 300 }),
      ex("Front Squat", "Main", "barbell", "squat", { defaultRestSeconds: 300 }),
      ex("Back Squat", "Main", "barbell", "squat", { defaultRestSeconds: 300 }),
      ex("Snatch Pull", "Accessory", "barbell", "olympic", { defaultRestSeconds: 180 }),
      ex("Clean Pull", "Accessory", "barbell", "olympic", { defaultRestSeconds: 180 }),
      ex("Overhead Press", "Main", "barbell", "press", { defaultRestSeconds: 300 }),
      ex("Pull-ups", "Accessory", "bodyweight", "pull", { defaultRestSeconds: 120 }),
      ex("Back Extension", "Accessory", "bodyweight", "hinge"),
      ex("Hanging Knee Raise", "Accessory", "bodyweight", "core"),
    ],
    days: [
      { name: "Snatch Day", lifts: [lift("Snatch", "main", 65, 115), lift("Overhead Squat", "complementary", 65, 115)],
        accessories: [acc("Snatch Pull", 3, 3, 5, 95, 10), acc("Hanging Knee Raise", 3, 8, 15)] },
      { name: "Clean & Jerk Day", lifts: [lift("Clean and Jerk", "main", 85, 145), lift("Front Squat", "complementary", 115, 185)],
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
      ex("Kettlebell Swing", "Conditioning", "kettlebell", "hinge", { defaultRestSeconds: 60 }),
      ex("Goblet Squat", "Accessory", "kettlebell", "squat", { defaultRestSeconds: 60 }),
      ex("Burpees", "Conditioning", "bodyweight", "conditioning", { defaultRestSeconds: 60 }),
      ex("Push-ups", "Accessory", "bodyweight", "press", { defaultRestSeconds: 60 }),
      ex("Inverted Row", "Accessory", "bodyweight", "pull", { defaultRestSeconds: 60 }),
      ex("Walking Lunges", "Accessory", "bodyweight", "squat", { isUnilateral: true, defaultRestSeconds: 60 }),
      ex("Mountain Climbers", "Conditioning", "bodyweight", "conditioning", { defaultRestSeconds: 45 }),
      ex("Sit-ups", "Accessory", "bodyweight", "core", { defaultRestSeconds: 45 }),
      ex("Box Jumps", "Conditioning", "bodyweight", "conditioning", { defaultRestSeconds: 60 }),
    ],
    days: [
      { name: "Engine A", lifts: [],
        accessories: [acc("Kettlebell Swing", 5, 10, 20, 35), acc("Burpees", 4, 8, 15), acc("Mountain Climbers", 4, 20, 40)] },
      { name: "Engine B", lifts: [],
        accessories: [acc("Push-ups", 4, 10, 25), acc("Inverted Row", 4, 8, 15), acc("Sit-ups", 4, 15, 30)] },
      { name: "Engine C", lifts: [],
        accessories: [acc("Box Jumps", 4, 8, 15), acc("Goblet Squat", 4, 10, 20, 35), acc("Walking Lunges", 4, 12, 24)] },
    ],
  },
];

/// Instantiate a template: ensure its exercises exist in the library (never
/// overwriting an existing record), then create the program inactive unless
/// it's the first. Returns the new program's id.
export async function createProgramFromTemplate(template, { makeActive = false } = {}) {
  for (const e of template.exercises) {
    if (!(await Exercises.byName(e.name))) await Exercises.save(e);
  }
  return Programs.save({
    name: template.name, focus: template.focus, cycleNumber: 1, currentWeek: 1,
    nextDayIndex: 0, roundingLb: template.roundingLb, isActive: makeActive,
    days: template.days.map((d, i) => ({
      name: d.name, order: i,
      lifts: d.lifts.map((l) => ({ ...l })),
      accessories: d.accessories.map((a) => ({ ...a })),
    })),
  });
}
