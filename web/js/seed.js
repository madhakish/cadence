// First-launch seed for non-personal reference data only. Workout history,
// body metrics, signals, programs, and progression state always start empty.
import * as C from "./core.js";

// Exported: templates.js builds its additional exercise records with this
// same helper so native and web keep the same shape.
export const ex = (name, category, type, group, o = {}) => ({
  name, category, type, movementGroup: group,
  isUnilateral: !!o.isUnilateral,
  defaultRestSeconds: o.defaultRestSeconds ?? 0,
  notes: o.notes || "",
  isShelved: false,
  shelvedNote: "",
  watchSite: null,
  createdAt: o.createdAt || "2000-01-01T00:00:00.000Z",
});

// Generic exercise definitions only. Watch sites and shelving are user-owned
// health choices and are intentionally not present in source defaults.
const exercises = [
  ex("Deadlift", "Main", "barbell", "hinge"),
  ex("Back Squat", "Main", "barbell", "squat"),
  ex("Front Squat", "Main", "barbell", "squat"),
  ex("Overhead Squat", "Main", "barbell", "squat"),
  ex("Barbell Bench", "Main", "barbell", "press"),
  ex("Overhead Press", "Main", "barbell", "press", { notes: "Strict barbell press" }),
  ex("Push Press", "Main", "barbell", "press"),
  ex("Push Jerk", "Main", "barbell", "press"),
  ex("Split Jerk", "Main", "barbell", "press"),
  ex("Incline DB Press", "Main", "dumbbell", "press"),
  ex("Flat DB Press", "Main", "dumbbell", "press"),
  ex("Seated Upright DB Press", "Main", "dumbbell", "press"),
  ex("Overhead DB Press", "Main", "dumbbell", "press"),
  ex("Snatch", "Main", "barbell", "olympic"),
  ex("Clean & Jerk", "Main", "barbell", "olympic"),
  ex("Clean", "Main", "barbell", "olympic"),
  ex("Power Clean", "Main", "barbell", "olympic"),
  ex("Power Snatch", "Main", "barbell", "olympic"),
  ex("Hang Power Clean", "Accessory", "barbell", "olympic", { defaultRestSeconds: 180 }),
  ex("Hang Power Snatch", "Accessory", "barbell", "olympic", { defaultRestSeconds: 180 }),
  ex("Clean Pull", "Accessory", "barbell", "olympic", { defaultRestSeconds: 180 }),
  ex("Snatch Pull", "Accessory", "barbell", "olympic", { defaultRestSeconds: 180 }),
  ex("Romanian Deadlift", "Accessory", "barbell", "hinge", { defaultRestSeconds: 180 }),
  ex("Snatch-grip Deadlift", "Accessory", "barbell", "hinge", { defaultRestSeconds: 180 }),
  ex("Good Morning", "Accessory", "barbell", "hinge", { defaultRestSeconds: 120 }),
  ex("Turkish Get-up", "Accessory", "kettlebell", "core", { isUnilateral: true }),
  ex("Single-arm DB Row", "Accessory", "dumbbell", "pull", { isUnilateral: true }),
  ex("Lat Pulldown", "Accessory", "machine", "pull"),
  ex("Chest-supported Row", "Accessory", "machine", "pull"),
  ex("Ring Row", "Accessory", "bodyweight", "pull", { notes: "Face-pull style" }),
  ex("Band Pull-aparts", "Accessory", "band", "pull", { defaultRestSeconds: 60 }),
  ex("Face Pulls", "Accessory", "machine", "pull"),
  ex("Y-T-W Raises", "Accessory", "dumbbell", "shoulder", { defaultRestSeconds: 60 }),
  ex("Band External Rotation", "Accessory", "band", "shoulder", { isUnilateral: true, defaultRestSeconds: 60 }),
  ex("DB Curls", "Accessory", "dumbbell", "arms"),
  ex("DB Overhead Triceps Extension", "Accessory", "dumbbell", "arms"),
  ex("Walking Lunges", "Accessory", "bodyweight", "squat", { isUnilateral: true }),
  ex("GHD Sit-up", "Accessory", "bodyweight", "core"),
  ex("Plank", "Accessory", "timed", "core", { defaultRestSeconds: 60 }),
  ex("Side Plank", "Accessory", "timed", "core", { isUnilateral: true, defaultRestSeconds: 60 }),
  ex("KB Swing", "Accessory", "kettlebell", "hinge"),
  ex("KB Clean", "Accessory", "kettlebell", "olympic", { isUnilateral: true }),
  ex("Dips", "Accessory", "bodyweight", "press"),
  ex("Walk", "Conditioning", "conditioning", "conditioning", { notes: "Distance / time / incline" }),
  ex("Run-Walk Intervals", "Conditioning", "conditioning", "conditioning", { notes: "Jog min / walk min × rounds" }),
  ex("Bike", "Conditioning", "conditioning", "conditioning"),
  ex("Ruck", "Conditioning", "conditioning", "conditioning"),
];

const gyms = [{
  name: "Main Gym", isDefault: true, defaultBarId: C.barId(C.BARS.bar45lb),
  plateToggles: C.ALL_STANDARD.map((plate) => ({ value: plate.value, unit: plate.unit, enabled: true })),
  barcodeImage: null, barcodeLabel: "Membership tag",
}];

export const SEED = {
  exercises,
  gyms,
  tracks: [],
  bodyweight: [],
  milestones: [],
  programs: [],
  sessions: [],
};
