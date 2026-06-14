// First-launch seed: exercise library, gym, program state, and the real
// training history so charts, PRs, and suggestions work on day one.
// Ported verbatim from Comeback/Seed/Seeder.swift — don't casually regenerate.
import * as C from "./core.js";

const D = (y, m, d, h = 17) => new Date(y, m - 1, d, h).toISOString();

const ex = (name, category, type, o = {}) => ({
  name, category, type,
  isUnilateral: !!o.isUnilateral,
  defaultRestSeconds: o.defaultRestSeconds ?? 90,
  notes: o.notes || "",
  isShelved: !!o.isShelved,
  shelvedNote: o.shelvedNote || "",
  watchSite: o.watchSite || null,
  createdAt: D(2026, 1, 1),
});

const exercises = [
  ex("Deadlift", "Main", "barbell", { defaultRestSeconds: 300 }),
  ex("Back Squat", "Main", "barbell", { defaultRestSeconds: 300, watchSite: "Left hip" }),
  ex("Barbell Bench", "Main", "barbell", { defaultRestSeconds: 300, isShelved: true,
    shelvedNote: "Shelved — left shoulder. Re-entry test: symmetric DB pressing, no 'not there' feeling.",
    watchSite: "Left shoulder" }),
  ex("Incline DB Press", "Main", "dumbbell", { defaultRestSeconds: 300, watchSite: "Left shoulder" }),
  ex("Flat DB Press", "Main", "dumbbell", { defaultRestSeconds: 300, watchSite: "Left shoulder" }),
  ex("Seated Upright DB Press", "Main", "dumbbell", { defaultRestSeconds: 300, watchSite: "Left shoulder" }),
  ex("Overhead DB Press", "Main", "dumbbell", { defaultRestSeconds: 300, watchSite: "Left shoulder" }),
  ex("Push Press", "Main", "barbell", { defaultRestSeconds: 300, watchSite: "Left shoulder" }),
  ex("Turkish Get-up", "Accessory", "kettlebell", { isUnilateral: true }),
  ex("Single-arm DB Row", "Accessory", "dumbbell", { isUnilateral: true }),
  ex("Lat Pulldown", "Accessory", "machine"),
  ex("Chest-supported Row", "Accessory", "machine"),
  ex("Ring Row", "Accessory", "bodyweight", { notes: "Face-pull style" }),
  ex("Band Pull-aparts", "Accessory", "band", { defaultRestSeconds: 60 }),
  ex("Face Pulls", "Accessory", "machine"),
  ex("Y-T-W Raises", "Accessory", "dumbbell", { defaultRestSeconds: 60 }),
  ex("Band External Rotation", "Accessory", "band", { isUnilateral: true, defaultRestSeconds: 60, watchSite: "Left shoulder" }),
  ex("DB Curls", "Accessory", "dumbbell"),
  ex("DB Overhead Triceps Extension", "Accessory", "dumbbell"),
  ex("Walking Lunges", "Accessory", "bodyweight", { isUnilateral: true, watchSite: "Left hip" }),
  ex("GHD Sit-up", "Accessory", "bodyweight"),
  ex("Plank", "Accessory", "timed", { defaultRestSeconds: 60 }),
  ex("Side Plank", "Accessory", "timed", { isUnilateral: true, defaultRestSeconds: 60 }),
  ex("KB Swing", "Accessory", "kettlebell"),
  ex("KB Clean", "Accessory", "kettlebell", { isUnilateral: true }),
  ex("Dips", "Accessory", "bodyweight", { watchSite: "Left shoulder" }),
  ex("Walk", "Conditioning", "conditioning", { defaultRestSeconds: 0, notes: "Distance / time / incline" }),
  ex("Run-Walk Intervals", "Conditioning", "conditioning", { defaultRestSeconds: 0, notes: "Jog min / walk min × rounds", watchSite: "Right knee" }),
  ex("Bike", "Conditioning", "conditioning", { defaultRestSeconds: 0 }),
  ex("Ruck", "Conditioning", "conditioning", { defaultRestSeconds: 0 }),
];

const gyms = [{
  name: "Main Gym", isDefault: true, defaultBarId: C.barId(C.BARS.bar45lb),
  plateToggles: C.ALL_STANDARD.map((p) => ({ value: p.value, unit: p.unit, enabled: true })),
  barcodeImage: null, barcodeLabel: "Membership tag",
}];

const tracks = [
  { exerciseName: "Deadlift", mode: "cycle", cycleNumber: 1, baseWeightLb: 210, nextPhase: 3, incrementLb: 10, roundingLb: 5, lastCompletedAt: null },
  { exerciseName: "Back Squat", mode: "cycle", cycleNumber: 1, baseWeightLb: 175, nextPhase: 2, incrementLb: 10, roundingLb: 5, lastCompletedAt: null },
  { exerciseName: "Incline DB Press", mode: "linear", cycleNumber: 1, baseWeightLb: 45, nextPhase: 1, incrementLb: 5, roundingLb: 5, lastCompletedAt: null },
];

const bodyweight = [
  { date: D(2026, 1, 10), weightLb: 168, bodyFatPercent: null, milestoneLabel: "Discharge" },
  { date: D(2026, 5, 12), weightLb: 190, bodyFatPercent: null, milestoneLabel: null },
  { date: D(2026, 6, 7), weightLb: 194, bodyFatPercent: null, milestoneLabel: null },
];

const milestones = [
  { date: D(2026, 6, 1), exerciseName: "Back Squat", kind: "heaviestSet", label: "175×5×5 — Wk1 Volume banked" },
  { date: D(2026, 6, 7), exerciseName: "Deadlift", kind: "heaviestSet", label: "232×5×3 — heaviest pull of the comeback" },
];

// ---- Session history builder ----
const S = (m, d, note = "") => ({ date: D(2026, m, d), notes: note, isCompleted: true, gymName: "Main Gym", exercises: [] });
const E = (s, name, note = "") => {
  const e = { order: s.exercises.length, exerciseName: name, notes: note, phase: null, plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] };
  s.exercises.push(e); return e;
};
const A = (e, w, r, o = {}) => {
  const n = o.sets ?? 1;
  for (let i = 0; i < n; i += 1) {
    e.sets.push({
      order: e.sets.length, weightLb: w, reps: r, isWarmup: !!o.warm, isPerSide: !!o.perSide,
      enteredUnit: "lb", flags: [...(o.flags || [])], bodyFlagSite: o.site || null, bodyFlagNote: o.siteNote || null,
      durationSeconds: null, distanceMiles: null, autoregReason: null,
    });
  }
  return e;
};

function buildSessions() {
  const out = [];
  let s, e;

  s = S(5, 9); out.push(s);
  e = E(s, "Deadlift");
  A(e, 133, 5, { warm: true }); A(e, 155, 5, { warm: true }); A(e, 177, 5, { warm: true }); A(e, 199, 3, { warm: true }); A(e, 221, 3);
  A(E(s, "Push Press"), 88, 3, { sets: 3 });

  s = S(5, 12); out.push(s);
  e = E(s, "Back Squat"); A(e, 145, 3); A(e, 155, 3, { sets: 2 });
  A(E(s, "Barbell Bench"), 135, 5);
  e = E(s, "Incline DB Press"); A(e, 35, 5); A(e, 40, 5); A(e, 45, 3, { sets: 2, flags: ["wobble", "stopped early"] });

  s = S(5, 15); out.push(s);
  A(E(s, "Deadlift"), 221, 3);
  A(E(s, "Turkish Get-up"), 35, 3, { perSide: true });
  A(E(s, "GHD Sit-up"), 0, 5, { sets: 3 });
  A(E(s, "Incline DB Press"), 40, 5, { sets: 3 });

  s = S(5, 19); out.push(s);
  e = E(s, "Back Squat"); A(e, 165, 3, { sets: 2 }); A(e, 175, 3);
  e = E(s, "Barbell Bench", "Autoregulated from 140 plan"); e.plannedWeightLb = 140; A(e, 135, 5, { sets: 2 });

  s = S(5, 22); out.push(s);
  e = E(s, "Deadlift"); A(e, 210, 5, { sets: 3 }); A(e, 221, 2, { sets: 3 });
  A(E(s, "Incline DB Press"), 45, 5, { sets: 3 });
  A(E(s, "DB Overhead Triceps Extension"), 45, 10, { sets: 3 });

  s = S(5, 26); out.push(s);
  A(E(s, "Back Squat"), 155, 5, { sets: 5 });
  A(E(s, "Seated Upright DB Press"), 40, 5, { sets: 5 });
  A(E(s, "Single-arm DB Row"), 60, 8, { sets: 3, perSide: true });
  A(E(s, "Walking Lunges"), 0, 8, { perSide: true });

  s = S(5, 29, "90°F gym, cut short"); out.push(s);
  e = E(s, "Deadlift"); e.phase = 1; A(e, 210, 5, { sets: 5 });
  A(E(s, "Overhead DB Press"), 35, 6, { sets: 3 });
  A(E(s, "Turkish Get-up"), 45, 3, { perSide: true });

  s = S(6, 1); out.push(s);
  e = E(s, "Back Squat"); e.phase = 1; A(e, 175, 5, { sets: 5 });
  A(E(s, "Overhead DB Press"), 30, 10, { sets: 3 });
  A(E(s, "DB Curls"), 35, 5, { sets: 3 });
  A(E(s, "Walking Lunges"), 0, 10, { perSide: true });

  s = S(6, 4, "Left shoulder 'not there' on barbell bench — shelved. DB pressing from here."); out.push(s);
  e = E(s, "Barbell Bench"); A(e, 135, 3, { sets: 4, site: "Left shoulder", siteNote: "'Not there' feeling — shelving barbell bench" });
  A(E(s, "Flat DB Press", "Switched after shelving barbell"), 45, 5, { sets: 3 });
  A(E(s, "Single-arm DB Row"), 65, 8, { sets: 5, perSide: true });
  A(E(s, "GHD Sit-up"), 0, 5, { sets: 4 });

  s = S(6, 7); out.push(s);
  e = E(s, "Deadlift"); e.phase = 2; A(e, 232, 3, { sets: 5 });
  A(E(s, "Turkish Get-up"), 45, 3, { perSide: true });
  A(E(s, "Incline DB Press"), 45, 5, { sets: 3 });

  return out;
}

export const SEED = { exercises, gyms, tracks, bodyweight, milestones, sessions: buildSessions() };
