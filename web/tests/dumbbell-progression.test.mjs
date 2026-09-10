import assert from "node:assert/strict";
import test from "node:test";
import * as C from "../app/js/core.js";
import { coachingReport, applyCoachingRecommendation, coachingDecision } from "../app/js/coaching-adapter.js";

// Synthetic rack and history. Loads are per implement, never a personal log.
const exercise = { name: "Fixture DB Press", type: "dumbbell", category: "Main",
  movementGroup: "press", loadBasis: "perImplement", implementCount: 2 };
const exercises = [exercise];
const exMap = new Map(exercises.map((item) => [item.name, item]));
function fixture() {
  const lift = { id: "db-slot", exerciseName: exercise.name, role: "main", order: 0,
    baseWeightLb: 80, estimatedMaxLb: 110, prescription: "automatic", capacityManaged: true,
    maximumSets: 6, doubleProgressionSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 5,
    stallCount: 1, lastIncrementLb: 5, pending: { state: { baseWeightLb: 90, stallCount: 0 } } };
  const program = { id: 1, uuid: "fixture-program", focus: "strength", currentWeek: 3,
    cycleNumber: 1, nextDayIndex: 0, roundingLb: 5,
    days: [{ name: "Upper", order: 0, lifts: [lift], accessories: [] }] };
  const history = [{ id: 11, date: "2026-01-01T12:00:00Z", isCompleted: true,
    programTag: { programId: program.uuid, cycleNumber: 1, week: 2, dayIndex: 0 },
    exercises: [{ exerciseName: exercise.name, programSlotId: lift.id, programRole: "main",
      prescriptionStyle: "wave", plannedSets: 5, plannedReps: 3, plannedWeightLb: 85,
      sets: Array.from({ length: 5 }, (_, i) => ({ id: i, weightLb: 85, reps: 3,
        plannedWeightLb: 85, plannedReps: 3, status: "completed", flags: ["clean"],
        loadBasis: "perImplement", prescriptionBlock: "work" })) }] }];
  return { program, lift, history };
}
function suggestion(program, history) {
  return coachingReport(program, history, exMap).recommendations
    .find((item) => item.change.type === "useDumbbellRepProgression");
}

test("conversion preserves completed work within the three-set rep window", () => {
  for (const [sets, reps, expected] of [[3, 3, 4], [4, 3, 4], [5, 3, 5], [6, 3, 6], [3, 6, 6], [5, 4, null]]) {
    const { program, history } = fixture();
    const entry = history[0].exercises[0];
    entry.plannedSets = sets;
    entry.sets = Array.from({ length: sets }, () => ({ ...entry.sets[0], reps }));
    const result = suggestion(program, history);
    assert.equal(result?.change.currentReps ?? null, expected, `${sets}×${reps} transition`);
    if (result) assert.ok(3 * result.change.currentReps >= sets * reps, "conversion cannot discard completed volume");
  }
});

test("collapsed wave offers an earned rep target at the performed dumbbell load", () => {
  const { program, history } = fixture();
  const before = JSON.stringify({ program, history });
  const result = suggestion(program, history);
  assert.ok(result, "the repeated load/peak target needs an actionable rep-progression proposal");
  assert.equal(result.change.weightLb, 85);
  assert.equal(result.change.currentReps, 5);
  assert.match(result.explanation, /3–6/);
  assert.equal(JSON.stringify({ program, history }), before, "evaluation is read-only");
});

test("detection uses actual rounded prescriptions and preserves authored styles", () => {
  const detect = (base = 80, rounding = 5, type = "dumbbell", role = "main", style = "automatic") =>
    C.collapsedDumbbellWaveLoad(base, rounding, type, "press", role, "strength", style);
  assert.equal(detect(), 85);
  assert.equal(detect(80, 10), 85, "program-wide rounding does not become a ten-pound per-hand jump");
  assert.equal(detect(30, 2.5), null, "distinct load/peak targets need no conversion");
  assert.equal(detect(82.5, 5), null, "do not seed an off-grid base that would round up after conversion");
  for (const type of ["barbell", "machine", "kettlebell"]) assert.equal(detect(80, 5, type), null);
  assert.equal(detect(80, 5, "dumbbell", "complementary"), null);
  for (const style of ["doubleProgression", "linearFives", "fiveThreeOne", "technique", "dynamicEffort"])
    assert.equal(detect(80, 5, "dumbbell", "main", style), null);
  const wave = [2, 3].map((nextPhase) => C.programPlanFor({ baseWeightLb: 80, nextPhase }, 5, "dumbbell"));
  assert.deepEqual(wave.map((p) => [p.sets, p.reps, p.weightLb]), [[5, 3, 85], [3, 3, 85]],
    "an authored wave changes only after the proposal is accepted");
});

for (const [name, alter] of [
  ["missing slot identity", (p, h) => { delete h[0].exercises[0].programSlotId; }],
  ["different program", (p, h) => { h[0].programTag.programId = "another-program"; }],
  ["different slot", (p, h) => { h[0].exercises[0].programSlotId = "another-slot"; }],
  ["different role", (p, h) => { h[0].exercises[0].programRole = "complementary"; }],
  ["different movement", (p, h) => { h[0].exercises[0].exerciseName = "Fixture DB Row"; }],
  ["missing style stamp", (p, h) => { delete h[0].exercises[0].prescriptionStyle; }],
  ["recovery work", (p, h) => { h[0].programTag.week = 4; }],
  ["recovery phase", (p) => { p.currentWeek = 4; }],
  ["protected technique day", (p) => { p.days[0].trainingIntent = "technique"; }],
  ["coaching disabled for slot", (p) => { p.days[0].lifts[0].capacityManaged = false; }],
  ["set ceiling", (p) => { p.days[0].lifts[0].maximumSets = 2; }],
  ["temporary exercise swap", (p) => { p.days[0].lifts[0].revertToExerciseName = "Prior movement"; }],
  ["missing prescribed set", (p, h) => { h[0].exercises[0].sets.pop(); }],
  ["skipped prescribed set", (p, h) => { h[0].exercises[0].sets[0].status = "skipped"; }],
  ["dropped load", (p, h) => { h[0].exercises[0].sets[0].weightLb = 80; }],
  ["missed rep", (p, h) => { h[0].exercises[0].sets[0].reps = 2; }],
  ["body signal", (p, h) => { h[0].exercises[0].sets[0].bodyFlagSite = "shoulder"; }],
  ["stopped early", (p, h) => { h[0].exercises[0].sets[0].flags.push("stopped early"); }],
  ["multiple difficult sets", (p, h) => { h[0].exercises[0].sets.slice(0, 2).forEach((s) => { s.flags = ["grindy"]; }); }],
  ["unknown historical load basis", (p, h) => { delete h[0].exercises[0].sets[0].loadBasis; }],
  ["historical total load", (p, h) => { h[0].exercises[0].sets[0].loadBasis = "externalTotal"; }],
  ["open workout", (p, h) => { h.push({ ...structuredClone(h[0]), id: 12, isCompleted: false }); }],
]) {
  test(`no rep progression from ${name}`, () => {
    const { program, history } = fixture();
    alter(program, history);
    assert.equal(suggestion(program, history), undefined);
  });
}

test("latest failure blocks older success; bonus reps cannot inflate the conversion", () => {
  const { program, history } = fixture();
  const bad = structuredClone(history[0]);
  bad.id = 12; bad.date = "2026-01-02T12:00:00Z";
  bad.exercises[0].sets[0].reps = 2;
  assert.equal(suggestion(program, [...history, bad]), undefined);
  history[0].exercises[0].sets.push({ ...history[0].exercises[0].sets[0], reps: 10 });
  assert.equal(suggestion(program, history).change.currentReps, 5);
});

test("open workouts guard conversion without entering readiness history", () => {
  const { program, history } = fixture();
  const before = coachingReport(program, history, exMap);
  const open = structuredClone(history[0]);
  open.id = 12; open.date = "2026-01-02T12:00:00Z"; open.isCompleted = false;
  open.programTag.week = 3;
  open.exercises[0].sets.forEach((set) => { set.status = "planned"; });
  const after = coachingReport(program, [...history, open], exMap);
  assert.deepEqual(after.rotations, before.rotations);
  assert.equal(after.currentReadiness, before.currentReadiness);
  assert.equal(after.greenRotationStreak, before.greenRotationStreak);
  assert.equal(suggestion(program, [...history, open]), undefined);
});

test("recommendation identity survives replacement of a local session key by a portable UUID", () => {
  const { program, history } = fixture();
  const before = suggestion(program, history);
  history[0].id = "efb7de65-3dc5-4e80-a79f-f07379c2e912";
  assert.equal(suggestion(program, history).id, before.id);
});

test("newer ambiguous slot history blocks an older exact-slot success", () => {
  const { program, history } = fixture();
  const newer = structuredClone(history[0]);
  newer.id = 12; newer.date = "2026-01-02T12:00:00Z";
  delete newer.exercises[0].programSlotId;
  newer.exercises[0].sets[0].reps = 2;
  assert.equal(suggestion(program, [...history, newer]), undefined);
});

test("acceptance changes one slot, clears wave pending state, and preserves history and cursor", async () => {
  const { program, lift, history } = fixture();
  const other = { ...lift, id: "other-slot", exerciseName: "Fixture Other Press" };
  program.days[0].lifts.push(other);
  const originalHistory = JSON.stringify(history), originalOther = JSON.stringify(other);
  const recommendation = suggestion(program, history);
  const before = structuredClone(program);
  const message = await applyCoachingRecommendation(program, recommendation, exercises, history);
  assert.match(message, /3×5 at 85 lb each/);
  assert.deepEqual([lift.prescription, lift.baseWeightLb, lift.doubleProgressionSets, lift.minimumReps,
    lift.maximumReps, lift.currentReps], ["doubleProgression", 85, 3, 3, 6, 5]);
  assert.equal(lift.pending, undefined);
  assert.equal(lift.stallCount, 0); assert.equal(lift.lastIncrementLb, 0);
  assert.equal(JSON.stringify(history), originalHistory);
  assert.equal(JSON.stringify(other), originalOther);
  assert.deepEqual([program.cycleNumber, program.currentWeek, program.nextDayIndex], [1, 3, 0]);
  assert.equal(coachingDecision(program, recommendation, "accepted", [], before).afterValue,
    "dumbbellReps:slot:db-slot:3x5@85:range:3-6");
  assert.equal(suggestion(program, history), undefined);
  await assert.rejects(applyCoachingRecommendation(program, recommendation, exercises, history));
});

for (const [name, alter] of [
  ["edited base", (p) => { p.days[0].lifts[0].baseWeightLb += 5; }],
  ["edited style", (p) => { p.days[0].lifts[0].prescription = "linearFives"; }],
  ["corrected history", (p, h) => { h[0].exercises[0].sets[0].reps = 2; }],
  ["opened workout", (p, h) => { h.push({ ...structuredClone(h[0]), id: 12, isCompleted: false }); }],
]) {
  test(`apply refuses ${name} without mutation`, async () => {
    const { program, history } = fixture();
    const recommendation = suggestion(program, history);
    alter(program, history);
    const before = JSON.stringify(program);
    await assert.rejects(applyCoachingRecommendation(program, recommendation, exercises, history));
    assert.equal(JSON.stringify(program), before);
  });
}

test("converted slot earns reps, holds a miss, earns one rack step, and preserves recovery", async () => {
  const { program, lift, history } = fixture();
  await applyCoachingRecommendation(program, suggestion(program, history), exercises, history);
  let state = { sets: 3, minReps: 3, maxReps: 6, currentReps: lift.currentReps,
    weightLb: lift.baseWeightLb, incrementLb: C.programLoadStep(program.roundingLb, exercise.type), stallCount: 0 };
  const perf = (reps) => ({ completedSets: 3, minRepsAchieved: reps, anyStoppedEarly: false,
    performedAtPlannedLoad: true, grindyOrWobbleSets: 0, bodyFlagSets: 0 });
  const held = C.advanceAccessory(state, perf(3));
  assert.deepEqual([held.currentReps, held.weightLb], [5, 85]);
  const sequence = [];
  for (let i = 0; i < 4; i++) {
    const work = C.programPlanFor({ baseWeightLb: state.weightLb, nextPhase: 3 }, 5,
      "dumbbell", "press", "main", "strength", "doubleProgression",
      { workingSets: 3, minimumReps: 3, maximumReps: 6, currentReps: state.currentReps });
    sequence.push([work.sets, work.reps, work.weightLb]);
    state = C.advanceAccessory(state, perf(work.reps));
  }
  assert.deepEqual(sequence, [[3, 5, 85], [3, 6, 85], [3, 3, 90], [3, 4, 90]]);
  const recovery = C.programPlanFor({ baseWeightLb: 85, nextPhase: 4 }, 5,
    "dumbbell", "press", "main", "strength", "doubleProgression",
    { workingSets: 3, minimumReps: 3, maximumReps: 6, currentReps: 4 });
  assert.deepEqual([recovery.sets, recovery.reps, recovery.weightLb], [1, 3, 70]);
  const preview = C.exposurePreview({ count: 5, baseWeightLb: 85, rotation: 3,
    programRoundingLb: 5, exerciseType: "dumbbell", movementGroup: "press",
    role: "main", focus: "strength", prescriptionStyle: "doubleProgression",
    configuration: { workingSets: 3, minimumReps: 3, maximumReps: 6, currentReps: 4 } });
  assert.deepEqual(preview.map((item) => {
    const p = item.prescription.mainWork; return [p.sets, p.reps, p.weightLb];
  }), [[3, 4, 85], [1, 3, 70], [3, 5, 85], [3, 6, 85], [3, 3, 90]]);
});
