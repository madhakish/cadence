// Generates web/tests/fixtures/synthetic-backup.json — a broad-coverage
// fictional dataset for exercising EVERY feature: three programs (one per
// training focus) in different wave states including mid-peak pending grades,
// stalls and an auto-deload, standalone tracks in both modes at every cycle
// phase, ~100 completed sessions touching every library exercise, all set
// flags, drop-loads, kg-entered sets, per-side work, conditioning
// duration/distance, bodyweight sets, body signals, bodyweight/protein/
// check-in logs, and a second (kg-plate) gym. None of the values originate
// from a user's training, health history, or exported app data.
//
// The output is a normal Cadence backup bundle, so the SAME file restores
// into the web app (Settings → Import) and the iOS app (ImportService) —
// it is also the cross-platform schema regression fixture used by
// tests/smoke.test.mjs.
//
// Deterministic by construction: sessions are built by the app's REAL
// machinery (createSessionFromProgramDay/createSessionFromTrack +
// completeSession) under fake-indexeddb, driven by a seeded PRNG, with all
// dates anchored to ANCHOR rather than the wall clock. Re-running produces
// the same bytes. Run: node tools/generate-synthetic-backup.mjs
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";
import fs from "node:fs";

const dom = new JSDOM("<!doctype html><html><body><div id='overlays'></div><div id='toast'></div></body></html>");
global.window = dom.window;
global.document = dom.window.document;
global.Node = dom.window.Node;

const db = await import("../js/db.js");
const C = await import("../js/core.js");
const session = await import("../js/views/session.js");
const completeAll = async (workout) => {
  for (const exercise of workout.exercises || []) for (const set of exercise.sets || []) if (!set.isWarmup) set.status = "completed";
  return session.completeSession(workout);
};

// ---- deterministic helpers ----
function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rng = mulberry32(0xCADE11CE);
const ANCHOR = new Date("2026-07-01T12:00:00.000Z");
const ANCHOR_ISO = ANCHOR.toISOString();
const day = (offset) => new Date(ANCHOR.getTime() + offset * 86400000);

const workingSets = (s, name) =>
  (s.exercises.find((e) => e.exerciseName === name)?.sets ?? []).filter((x) => !x.isWarmup);
const flagSets = (s, name, flag, n) =>
  workingSets(s, name).slice(0, n).forEach((x) => { x.flags = [flag, ...(x.flags || []).filter((f) => f === "stopped early")]; });

// Bank one session of a program day (whatever day is next), backdated,
// optionally mutated (flags/drops/signals) before completion so the adaptive
// engine grades something other than a clean pass.
async function bankProgramDay(programId, date, mutate) {
  const prog = (await db.Programs.all()).find((p) => p.id === programId);
  const d = prog.days.find((x) => x.order === prog.nextDayIndex);
  const id = await session.createSessionFromProgramDay(prog, d);
  const s = await db.Sessions.get(id);
  s.date = db.iso(date);
  if (mutate) mutate(s);
  await db.Sessions.save(s);
  await completeAll(s);
}

async function bankTrackSession(track, date) {
  const id = await session.createSessionFromTrack(track);
  const s = await db.Sessions.get(id);
  s.date = db.iso(date);
  await db.Sessions.save(s);
  await completeAll(s);
}

const mkSet = (order, w, r, o = {}) => ({
  order, weightLb: w, reps: r, isWarmup: !!o.warm, isPerSide: !!o.perSide,
  enteredUnit: o.unit || "lb", status: "completed", flags: o.flags ? [...o.flags] : ["clean"],
  bodyFlagSite: o.site || null, bodyFlagNote: o.siteNote || null,
  durationSeconds: o.duration ?? null, distanceMiles: o.distance ?? null,
  autoregReason: o.drop || null,
});

// ---- 0. seed the generic library and empty stores ----
await db.ensureSeeded();
const lib = await db.Exercises.all();

// ---- 1. a second gym: kg plates only (stresses kg plate math + gym switching) ----
await db.Gyms.save({
  name: "Hotel Gym", isDefault: false, defaultBarId: "20-kg",
  plateToggles: C.ALL_STANDARD.filter((p) => p.unit === "kg").map((p) => ({ value: p.value, unit: p.unit, enabled: p.value <= 20 })),
  barcodeImage: null, barcodeLabel: null,
});

// ---- 2. two more programs: hypertrophy (double-progression showcase) + maintain ----
const cyc = (exerciseName, role, baseWeightLb, estimatedMaxLb) =>
  ({ exerciseName, role, baseWeightLb, estimatedMaxLb, stallCount: 0, lastIncrementLb: 0 });
const acc = (exerciseName, weightLb, incrementLb = 5, sets = 3, minReps = 8, maxReps = 12) =>
  ({ exerciseName, sets, minReps, maxReps, currentReps: minReps, weightLb, incrementLb, stallCount: 0 });

await db.Programs.save({
  name: "Fixture Strength 4-Day", focus: "strength", cycleNumber: 1, currentWeek: 1,
  nextDayIndex: 0, roundingLb: 5, isActive: true,
  days: [
    { name: "Lower A", order: 0,
      lifts: [cyc("Back Squat", "main", 100, 125), cyc("Deadlift", "complementary", 110, 140)],
      accessories: [acc("Walking Lunges", 0, 0), acc("GHD Sit-up", 0, 0), acc("Plank", 0, 0)] },
    { name: "Upper A", order: 1,
      lifts: [cyc("Incline DB Press", "main", 30, 40), cyc("Single-arm DB Row", "complementary", 40, 55)],
      accessories: [acc("Face Pulls", 25), acc("DB Curls", 20), acc("Band Pull-aparts", 0, 0)] },
    { name: "Lower B", order: 2,
      lifts: [cyc("Deadlift", "main", 120, 150), cyc("Back Squat", "complementary", 90, 125)],
      accessories: [acc("KB Swing", 35), acc("Side Plank", 0, 0), acc("Walking Lunges", 0, 0)] },
    { name: "Upper B", order: 3,
      lifts: [cyc("Overhead DB Press", "main", 25, 35), cyc("Chest-supported Row", "complementary", 50, 65)],
      accessories: [acc("Y-T-W Raises", 5), acc("DB Overhead Triceps Extension", 25), acc("Band External Rotation", 0, 0)] },
  ],
});
await db.Programs.save({
  name: "Fixture Push/Pull 3-Day", focus: "hypertrophy", cycleNumber: 1, currentWeek: 1,
  nextDayIndex: 0, roundingLb: 5, isActive: false,
  days: [
    { name: "Push", order: 0,
      lifts: [cyc("Flat DB Press", "main", 50, 62), cyc("Seated Upright DB Press", "complementary", 40, 50)],
      accessories: [acc("Y-T-W Raises", 10, 5, 3, 10, 15), acc("DB Overhead Triceps Extension", 40, 5, 3, 8, 12)] },
    { name: "Pull", order: 1,
      lifts: [cyc("Chest-supported Row", "main", 90, 110), cyc("Single-arm DB Row", "complementary", 60, 75)],
      accessories: [acc("DB Curls", 30, 5, 3, 8, 12), acc("Face Pulls", 40, 5, 3, 12, 20)] },
    { name: "Legs", order: 2,
      lifts: [cyc("Front Squat", "main", 135, 165), cyc("Romanian Deadlift", "complementary", 155, 190)],
      accessories: [acc("Walking Lunges", 0, 0, 3, 10, 16), acc("Side Plank", 0, 0, 3, 1, 1)] },
  ],
});
await db.Programs.save({
  name: "Fixture Maintain 2-Day", focus: "maintain", cycleNumber: 1, currentWeek: 1,
  nextDayIndex: 0, roundingLb: 5, isActive: false,
  days: [
    { name: "Full A", order: 0,
      lifts: [cyc("KB Clean", "main", 53, 70)],
      accessories: [acc("Ring Row", 0, 0, 3, 12, 20), acc("Dips", 0, 0, 3, 8, 15)] },
    { name: "Full B", order: 1,
      lifts: [cyc("Overhead DB Press", "main", 35, 45)],
      accessories: [acc("Plank", 0, 0, 3, 1, 1), acc("Band Pull-aparts", 0, 0, 3, 15, 25)] },
  ],
});

const programs = await db.Programs.all();
const strength = programs.find((p) => p.focus === "strength");
const hyper = programs.find((p) => p.focus === "hypertrophy");
const maintain = programs.find((p) => p.focus === "maintain");

// Fictional standalone tracks provide state-machine coverage without shipping
// a first-launch training prescription.
await db.Tracks.save({ exerciseName: "Deadlift", mode: "cycle", cycleNumber: 1, baseWeightLb: 120, nextPhase: 3, incrementLb: 10, roundingLb: 5, lastCompletedAt: null });
await db.Tracks.save({ exerciseName: "Back Squat", mode: "cycle", cycleNumber: 1, baseWeightLb: 100, nextPhase: 2, incrementLb: 10, roundingLb: 5, lastCompletedAt: null });
await db.Tracks.save({ exerciseName: "Incline DB Press", mode: "linear", cycleNumber: 1, baseWeightLb: 30, nextPhase: 1, incrementLb: 5, roundingLb: 5, lastCompletedAt: null });
// Guard: names above must exist in the library, or sessions would carry ghosts.
{
  const names = new Set(lib.map((e) => e.name));
  const wanted = programs.flatMap((p) => p.days.flatMap((d) => [
    ...(d.lifts || []).map((l) => l.exerciseName), ...(d.accessories || []).map((a) => a.exerciseName)]));
  const missing = wanted.filter((n) => !names.has(n));
  if (missing.length) throw new Error(`program references unknown exercises: ${missing.join(", ")}`);
}

// ---- 3. hypertrophy block (Feb): 1 full cycle + 2 sessions into cycle 2 ----
// Accessories double-progress every bank; 16 banks of each day walks DB
// Lateral Raises across its rep range and forces a weight bump + reset.
let cursor = -150;
for (let i = 0; i < 14; i++) {
  await bankProgramDay(hyper.id, day(cursor), (s) => {
    if (i === 4) flagSets(s, "Flat DB Press", "grindy", 1); // within tolerance — still SUCCESS
    if (i % 5 === 2) {
      const w = workingSets(s, s.exercises[0].exerciseName);
      if (w[0]) { w[0].bodyFlagSite = "Shoulder"; w[0].bodyFlagNote = "Fictional fixture signal."; }
    }
  });
  cursor += i % 3 === 2 ? 3 : 2;
}

// ---- 4. maintain block (early March): 4 sessions, never increments ----
cursor = -115;
for (let i = 0; i < 4; i++) { await bankProgramDay(maintain.id, day(cursor)); cursor += 3; }

// ---- 5. strength block (Mar–Jun): 2 full cycles + into cycle 3, week 3 ----
// Cycle 1 peak: Back Squat too grindy → HOLD (stall 1).
// Cycle 2 peak: Back Squat grindy again → stall hits the limit → AUTO-DELOAD
// note at rollover; Deadlift drop-load at peak → FAIL (stall 1).
// Cycle 3: banked through week 2 + two week-3 days → pending grades mid-wave.
cursor = -100;
const strengthMutate = (cycle, week, dayIdx) => (s) => {
  if (week === 3 && dayIdx === 0 && (cycle === 1 || cycle === 2)) flagSets(s, "Back Squat", "grindy", 2);
  if (week === 3 && dayIdx === 2 && cycle === 2) {
    const w = workingSets(s, "Deadlift");
    if (w[2]) { w[2].autoregReason = "fatigue"; w[2].weightLb = C.roundTo(w[2].weightLb * 0.9, 5); }
  }
  if (week === 2 && dayIdx === 1 && cycle === 2) flagSets(s, "Incline DB Press", "wobble", 1);
  if (week === 1 && dayIdx === 3 && cycle === 2) {
    const w = workingSets(s, "Overhead DB Press");
    if (w[1]) w[1].flags = ["stopped early"];
  }
  if (week === 4) { // deload week: log lighter RPE via a note, keep sets clean
    s.notes = "Deload — everything moved fast.";
  }
};
for (let cycle = 1; cycle <= 2; cycle++) {
  for (let week = 1; week <= 4; week++) {
    for (let d = 0; d < 4; d++) {
      await bankProgramDay(strength.id, day(cursor), strengthMutate(cycle, week, d));
      cursor += d === 3 ? 1 : 2;
    }
  }
}
for (let week = 1; week <= 2; week++) {
  for (let d = 0; d < 4; d++) { await bankProgramDay(strength.id, day(cursor)); cursor += d === 3 ? 1 : 2; }
}
for (let d = 0; d < 2; d++) { await bankProgramDay(strength.id, day(cursor)); cursor += 2; } // week 3, mid-peak

// ---- 6. standalone tracks at every cycle phase + a second linear one ----
await db.Tracks.save({ exerciseName: "Push Press", mode: "cycle", cycleNumber: 2, baseWeightLb: 115, nextPhase: 4, incrementLb: 5, roundingLb: 5, lastCompletedAt: null });
await db.Tracks.save({ exerciseName: "Power Clean", mode: "cycle", cycleNumber: 1, baseWeightLb: 135, nextPhase: 1, incrementLb: 5, roundingLb: 5, lastCompletedAt: null });
await db.Tracks.save({ exerciseName: "Turkish Get-up", mode: "linear", cycleNumber: 1, baseWeightLb: 45, nextPhase: 1, incrementLb: 5, roundingLb: 5, lastCompletedAt: null });
cursor = -40;
// Banked counts chosen so the final states land on varied phases: Push
// Press wraps its deload into a new cycle (p4→p1), Power Clean walks p1→p3.
for (const [name, n] of [["Push Press", 1], ["Power Clean", 2], ["Turkish Get-up", 2]]) {
  for (let i = 0; i < n; i++) {
    const track = (await db.Tracks.all()).find((t) => t.exerciseName === name);
    await bankTrackSession(track, day(cursor));
    cursor += 2;
  }
}

// ---- 7. GPP sweep: every library exercise not yet in the log gets real sets ----
const used = new Set();
for (const s of await db.Sessions.completed()) for (const e of s.exercises) used.add(e.exerciseName);
const leftovers = lib.filter((e) => !used.has(e.name)).sort((a, b) => a.name.localeCompare(b.name));
cursor = -26;
for (let i = 0; i < leftovers.length; i += 6) {
  const chunk = leftovers.slice(i, i + 6);
  const id = await session.createBlankSession();
  const s = await db.Sessions.get(id);
  s.date = db.iso(day(cursor));
  s.notes = "GPP / odds & ends";
  s.exercises = chunk.map((ex, order) => {
    const sets = [];
    if (ex.category === "Conditioning") {
      sets.push(mkSet(0, 0, 1, { duration: 900, distance: /run|walk/i.test(ex.name) ? 1.5 : null }));
    } else if (/plank|hold|carr/i.test(ex.name)) {
      for (let k = 0; k < 3; k++) sets.push(mkSet(k, 0, 1, { duration: 60, perSide: ex.isUnilateral }));
    } else if (ex.type === "bodyweight" || /pull-up|push-up|dip|raise/i.test(ex.name)) {
      for (let k = 0; k < 3; k++) sets.push(mkSet(k, 0, 8 + Math.floor(rng() * 5), { perSide: ex.isUnilateral }));
    } else if (order === 1) {
      // kg-entered work regardless of implement (unit-boundary coverage)
      const kg = [12.5, 15, 17.5, 20, 40, 60][Math.floor(rng() * 6)];
      for (let k = 0; k < 3; k++) sets.push(mkSet(k, C.toLb(kg, "kg"), 10, { unit: "kg", perSide: ex.isUnilateral }));
    } else {
      const w = ex.type === "barbell" ? 95 + 10 * Math.floor(rng() * 6) : 25 + 5 * Math.floor(rng() * 6);
      for (let k = 0; k < 3; k++) sets.push(mkSet(k, w, 8, { perSide: ex.isUnilateral, flags: k === 2 && rng() < 0.3 ? ["grindy"] : ["clean"] }));
    }
    return { order, exerciseName: ex.name, notes: "", phase: null,
      barId: ex.type === "barbell" && order === 0 ? "35-lb" : null,
      plannedWeightLb: null, plannedSets: null, plannedReps: null, programRole: null, sets };
  });
  await db.Sessions.save(s);
  await completeAll(s);
  cursor += 3;
}

// ---- 8. fictional body-log records for storage and chart coverage ----
for (let w = 0; w < 26; w++) {
  const d = day(-175 + w * 7);
  const weightLb = Math.round((150 + Math.sin(w / 3) * 2 + (rng() - 0.5)) * 10) / 10;
  await db.Bodyweight.add({ date: db.iso(d), weightLb, bodyFatPercent: w % 8 === 0 ? 20 : null, milestoneLabel: w === 7 ? "Fixture checkpoint A" : w === 21 ? "Fixture checkpoint B" : null });
}
for (let d = -13; d <= 0; d++) {
  await db.Protein.add({ date: day(d).toISOString(), grams: 40, label: "Fixture entry A" });
  await db.Protein.add({ date: day(d).toISOString(), grams: 50, label: "Fixture entry B" });
  if (rng() < 0.6) await db.Protein.add({ date: day(d).toISOString(), grams: 25 + Math.floor(rng() * 3) * 5, label: "Fixture entry C" });
}
const RESPONSES = ["All clear", "Mild stiffness", "Flagged", "Comfortable"];
for (const site of ["Shoulder", "Hip", "Knee"]) {
  for (let m = 0; m < 4; m++) {
    await db.Checkins.add({ date: day(-140 + m * 40).toISOString(), site, response: RESPONSES[(m + site.length) % RESPONSES.length], note: m === 2 ? "Fictional fixture note." : "" });
  }
}

// ---- 9. settings variations (units both, non-default rest buckets, theme) ----
const settings = await db.Settings.get();
settings.unitDisplay = "both";
settings.theme = "slate";
settings.rest = { ...C.REST_DEFAULTS, secondarySeconds: 150, accessorySeconds: 75 };
settings.accessoryRestSeconds = 75;
settings.autoStartRest = true;
await db.Settings.save(settings);

// ---- export, normalize the few wall-clock stamps, write ----
const bundle = await db.exportBundle();
bundle.exportedAt = ANCHOR_ISO;
bundle.appVersion = "synthetic";
for (const t of bundle.tracks) if (t.lastCompletedAt) t.lastCompletedAt = ANCHOR_ISO;
bundle.settings.seededAt = ANCHOR_ISO; // the only other wall-clock stamp

const out = new URL("../tests/fixtures/synthetic-backup.json", import.meta.url).pathname;
fs.mkdirSync(new URL("../tests/fixtures/", import.meta.url).pathname, { recursive: true });
fs.writeFileSync(out, JSON.stringify(bundle));

const kb = Math.round(fs.statSync(out).size / 1024);
console.log(`wrote ${out} (${kb} KB): ${bundle.sessions.length} sessions, ${bundle.programs.length} programs, ${bundle.tracks.length} tracks, ${bundle.milestones.length} milestones, ${bundle.exercises.length} exercises`);
