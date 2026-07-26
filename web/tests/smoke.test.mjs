// Runtime smoke test under jsdom + fake-indexeddb: seeds, renders every view,
// and drives a real session-completion flow (PR detection + track advance) and
// an export/import round trip. Run: node tests/smoke.test.mjs
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";

const dom = new JSDOM(`<!doctype html><html><body>
  <header id="topbar"><h1 id="screen-title"></h1><div id="topbar-actions"></div></header>
  <main id="view"></main><button id="fab"></button><nav id="tabbar"></nav>
  <div id="overlays"></div><div id="toast"></div></body></html>`);
global.window = dom.window;
global.document = dom.window.document;
global.FileReader = dom.window.FileReader;
global.Node = dom.window.Node;

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.error("FAIL:", m); } };
const tick = () => new Promise((r) => setTimeout(r, 60));
const host = () => document.getElementById("view");

const db = await import("../app/js/db.js");
const home = await import("../app/js/views/home.js");
const history = await import("../app/js/views/history.js");
const body = await import("../app/js/views/body.js");
const signals = await import("../app/js/views/signals.js");
const settings = await import("../app/js/views/settings.js");
const session = await import("../app/js/views/session.js");
const plates = await import("../app/js/views/plates.js");
const barbell = await import("../app/js/barbell.js");
const C = await import("../app/js/core.js");
const coach = await import("../app/js/coaching-adapter.js");
const completeAll = async (workout) => {
  for (const exercise of workout.exercises || []) for (const set of exercise.sets || []) if (!set.isWarmup) set.status = "completed";
  return session.completeSession(workout);
};

{
  const program = { id: "temporary-program", cycleNumber: 2, currentWeek: 3 };
  const decision = { programId: program.id, action: "accepted", date: new Date().toISOString(),
    afterValue: coach.temporaryAccessoryValue(75, 2, 3) };
  ok(coach.effectiveAccessoryPercent(program, [decision]) === 75,
    "accepted red-readiness cut applies only to its target rotation");
  ok(coach.effectiveAccessoryPercent({ ...program, currentWeek: 4 }, [decision]) === 100,
    "temporary accessory cut expires at the next rotation");
}

// ---- privacy-safe first launch ----
await db.ensureSeeded();
const seededExercises = await db.Exercises.all();
ok(seededExercises.length === 141, "seeded 141 exercises");
ok(["Push-ups", "Pull-ups", "Barbell Row", "Bulgarian Split Squat", "Ab Wheel Rollout", "Row Erg"]
  .every((name) => seededExercises.some((exercise) => exercise.name === name)),
  "comprehensive seed covers common push, pull, lower, core, and conditioning movements");
ok(seededExercises.every((e) => e.movementGroup), "every seeded exercise has a movement group");
const nativeSeedSource = await (await import("node:fs/promises")).readFile(
  new URL("../../Cadence/Seed/Seeder.swift", import.meta.url), "utf8");
const nativeSeedNames = [...nativeSeedSource.matchAll(/Exercise\(name: "([^"]+)"/g)].map((match) => match[1]).sort();
ok(JSON.stringify(nativeSeedNames) === JSON.stringify(seededExercises.map((exercise) => exercise.name).sort()),
  "native and web comprehensive exercise catalogs stay in parity");
ok((await db.Sessions.completed()).length === 0, "fresh install has no workout history");
ok((await db.Tracks.all()).length === 0, "fresh install has no progression state");
ok((await db.Programs.all()).length === 0, "fresh install has no personal program");
ok((await db.Bodyweight.all()).length === 0 && (await db.Checkins.all()).length === 0,
  "fresh install has no body metrics or health signals");
await db.ensureSeeded(); // idempotent
ok((await db.Sessions.completed()).length === 0, "re-seed is a no-op");

// Recover an install missing its seed stamp without touching user-owned data.
{
  const sentinelId = await db.Sessions.save({
    date: "2000-01-01T00:00:00.000Z", notes: "Fictional seed-repair sentinel",
    isCompleted: true, gymName: "Main Gym", exercises: [],
  });
  const proteinId = await db.Protein.add({ date: "2000-01-01T00:00:00.000Z", grams: 10, label: "Fixture sentinel" });
  const s = await db.Settings.get(); s.seededAt = null; await db.Settings.save(s);
  await db.ensureSeeded();
  ok((await db.Sessions.all()).some((workout) => workout.id === sentinelId), "seed repair preserves workout history");
  ok((await db.Exercises.all()).length === 141, "seed repair does not duplicate exercises");
  ok((await db.Protein.all()).some((entry) => entry.id === proteinId), "seed repair preserves other user stores");
  await db.Sessions.del(sentinelId);
  await db.Protein.del(proteinId);
}

// Explicit fictional state for the remainder of the regression suite. This is
// test data, never a first-launch seed or exported user backup.
const cyc = (exerciseName, role, baseWeightLb, estimatedMaxLb) =>
  ({ exerciseName, role, baseWeightLb, estimatedMaxLb, stallCount: 0, lastIncrementLb: 0 });
const acc = (exerciseName, weightLb, incrementLb = 5) =>
  ({ exerciseName, sets: 3, minReps: 8, maxReps: 12, currentReps: 8, weightLb, incrementLb, stallCount: 0 });
await db.Programs.save({
  name: "Fixture Upper/Lower", focus: "strength", cycleNumber: 1, currentWeek: 1,
  nextDayIndex: 0, roundingLb: 5, isActive: true,
  days: [
    { name: "Lower A", order: 0,
      lifts: [cyc("Back Squat", "main", 175, 204), cyc("Deadlift", "complementary", 185, 255)],
      accessories: [acc("Walking Lunges", 0, 0), acc("GHD Sit-up", 0, 0), acc("Plank", 0, 0)] },
    { name: "Upper A", order: 1,
      lifts: [cyc("Incline DB Press", "main", 45, 52), cyc("Single-arm DB Row", "complementary", 65, 80)],
      accessories: [acc("Face Pulls", 40), acc("DB Curls", 35), acc("Band Pull-aparts", 0, 0)] },
    { name: "Lower B", order: 2,
      lifts: [cyc("Deadlift", "main", 210, 255), cyc("Back Squat", "complementary", 150, 204)],
      accessories: [acc("KB Swing", 53), acc("Side Plank", 0, 0), acc("Walking Lunges", 0, 0)] },
    { name: "Upper B", order: 3,
      lifts: [cyc("Overhead DB Press", "main", 35, 42), cyc("Chest-supported Row", "complementary", 90, 110)],
      accessories: [acc("Y-T-W Raises", 10), acc("DB Overhead Triceps Extension", 45), acc("Band External Rotation", 0, 0)] },
  ],
});
for (const track of [
  { exerciseName: "Deadlift", mode: "cycle", cycleNumber: 1, baseWeightLb: 210, nextPhase: 3, incrementLb: 10, roundingLb: 5, lastCompletedAt: null },
  { exerciseName: "Back Squat", mode: "cycle", cycleNumber: 1, baseWeightLb: 175, nextPhase: 2, incrementLb: 10, roundingLb: 5, lastCompletedAt: null },
  { exerciseName: "Incline DB Press", mode: "linear", cycleNumber: 1, baseWeightLb: 45, nextPhase: 1, incrementLb: 5, roundingLb: 5, lastCompletedAt: null },
]) await db.Tracks.save(track);

// Equipment truth: legacy gyms used [] for an inventory that had never been
// initialized. A nonempty all-disabled rack is the explicit bar-only state.
// Every stored warmup uses the same rack configuration as working sets.
{
  const squat = await db.Exercises.byName("Back Squat");
  const gym = await db.Gyms.default();
  const legacyRack = { ...gym, plateToggles: [], collarWeightLb: 5, loadingPolicy: "closest" };
  ok(session.neatProgramWeight(135, squat, true, 45, 5, legacyRack) === 135,
    "legacy empty plate inventory falls back to the standard rack");
  ok(barbell.stationPlates("lb", legacyRack).length === C.STANDARD_LB.length,
    "legacy empty inventory also renders the standard rack");
  const barOnlyRack = { ...legacyRack, plateToggles: [{ value: 45, unit: "lb", enabled: false }] };
  ok(session.neatProgramWeight(135, squat, true, 45, 5, barOnlyRack) === 50,
    "nonempty all-disabled inventory remains an intentional bar-only rack");
  ok(barbell.stationPlates("lb", barOnlyRack).length === 0,
    "bar-only intent survives in the loadout renderer");
  await db.Gyms.save(legacyRack);
  await db.syncLibrary();
  ok((await db.Gyms.default()).plateToggles.length === C.ALL_STANDARD.length,
    "library sync materializes a legacy rack for the gym editor");
  await db.Gyms.save(gym);

  const rack = { ...gym, collarWeightLb: 5, loadingPolicy: "closest" };
  const achieved = session.achievableWarmups(
    C.warmupRamp(135, 45, 5), 135, C.BARS.bar45lb, rack);
  ok(achieved.length > 0 && achieved[0].weightLb === 50,
    "warmup opener includes configured collars");
  // Stored warmups keep the neat programmed number whenever the rack lands
  // within the good-enough band (a kg clean stack is loading guidance, not a
  // new prescription); only unreachable targets store the achieved load.
  ok(achieved.every((set) => Math.abs(C.solve(set.weightLb, C.BARS.bar45lb,
    rack.plateToggles.filter((toggle) => toggle.enabled), 10, 5, "closest").totalLb - set.weightLb)
    <= C.TOLERANCE_LB + 1e-9),
    "every generated warmup is loadable within the good-enough band");
  ok(session.neatProgramWeight(220, squat, true, 45, 5, { ...gym, collarWeightLb: 0 }) === 220,
    "a near-miss kg clean stack never rewrites the neat programmed weight");
}

// Program changes and their audit records are one transaction. The adapter
// only mutates a proposed copy, and a bad audit row must roll the program back.
{
  const original = await db.Programs.active();
  const recommendation = { id: "atomic-recommendation", ruleID: "spacing", title: "Try two days",
    explanation: "Fixture recommendation", change: { type: "tryShorterSpacing", days: 2 } };
  const proposed = structuredClone(original);
  await coach.applyCoachingRecommendation(proposed, recommendation, seededExercises);
  ok((await db.Programs.active()).preferredSessionSpacingDays === original.preferredSessionSpacingDays,
    "coaching adapter does not persist before the audit transaction");
  let rolledBack = false;
  try { await db.Programs.saveWithDecision(proposed, { action: "accepted" }); }
  catch { rolledBack = true; }
  ok(rolledBack, "invalid audit row rejects the combined transaction");
  ok((await db.Programs.active()).preferredSessionSpacingDays === original.preferredSessionSpacingDays,
    "failed audit insert rolls the program mutation back");
  const decision = coach.coachingDecision(proposed, recommendation, "accepted", ["fixture"]);
  await db.Programs.saveWithDecision(proposed, decision);
  ok((await db.Programs.active()).preferredSessionSpacingDays === 2
      && (await db.CoachingDecisions.all()).some((item) => item.id === decision.id),
    "program mutation and accepted-decision audit commit together");
  await db.Programs.save(original);
  await db.CoachingDecisions.del(decision.id);
}

// A rotation suggestion resolves against the real library, keeps the slot's
// load, and drops the stall counter it was proposed to break.
{
  const original = await db.Programs.active();
  const proposed = structuredClone(original);
  const slot = proposed.days.flatMap((day) => day.lifts || [])[0];
  slot.stallCount = 1;
  const before = { name: slot.exerciseName, base: slot.baseWeightLb };
  const message = await coach.applyCoachingRecommendation(proposed, {
    id: "rotate-recommendation", ruleID: "program.slot.rotate.stalled", title: "Stuck",
    explanation: "Fixture recommendation",
    change: { type: "rotateExercise", slotID: slot.id, exerciseName: before.name },
  }, seededExercises);
  const rotated = proposed.days.flatMap((day) => day.lifts || []).find((item) => item.id === slot.id);
  ok(rotated.exerciseName !== before.name, "the slot is repointed at a different exercise");
  const from = seededExercises.find((item) => item.name === before.name);
  const to = seededExercises.find((item) => item.name === rotated.exerciseName);
  ok(C.swapCompatible(from, to), "the replacement passes the same swap rules as the manual gesture");
  ok(rotated.baseWeightLb === before.base,
    "a same-pattern, same-tier candidate keeps the slot's load as its starting prior");
  ok(rotated.stallCount === 0, "rotating clears the counter it was proposed to break");
  ok(message.includes(before.name) && message.includes(rotated.exerciseName),
    "the result names both sides of the swap");

  let refused = false;
  try {
    await coach.applyCoachingRecommendation(structuredClone(original), {
      id: "rotate-missing", ruleID: "program.slot.rotate.stalled", title: "Stuck",
      explanation: "Fixture recommendation",
      change: { type: "rotateExercise", slotID: slot.id, exerciseName: "Not In The Library" },
    }, seededExercises);
  } catch { refused = true; }
  ok(refused, "an exercise the library no longer has refuses rather than guessing a replacement");
}

const serviceWorkerSource = await (await import("node:fs/promises")).readFile(
  new URL("../app/sw.js", import.meta.url), "utf8");
ok(serviceWorkerSource.includes('"js/coaching-adapter.js"'),
  "offline shell precaches the eagerly imported coaching adapter");

// Historical and current volume must use the same load multiplier. Two
// identical two-dumbbell sessions are not a volume PR.
{
  const exerciseName = "Flat DB Press";
  const exercise = await db.Exercises.byName(exerciseName);
  const section = () => ({
    order: 0, exerciseName, notes: "", phase: null, programRole: null,
    plannedWeightLb: 50, plannedSets: 1, plannedReps: 5,
    sets: [{ order: 0, weightLb: 50, reps: 5, isWarmup: false, isPerSide: false,
      enteredUnit: "lb", loadBasis: "perImplement", implementCount: 2,
      status: "completed", flags: ["clean"], bodyFlagSite: null, bodyFlagNote: null,
      durationSeconds: null, distanceMiles: null, autoregReason: null }],
  });
  ok(exercise?.loadBasis === "perImplement", "DB fixture carries per-implement load semantics");
  const priorID = await db.Sessions.save({ date: "2020-01-01T12:00:00.000Z", notes: "", isCompleted: true,
    gymName: null, exercises: [section()] });
  const currentID = await db.Sessions.save({ date: "2020-01-02T12:00:00.000Z", notes: "", isCompleted: false,
    gymName: null, exercises: [section()] });
  const result = await session.completeSession(await db.Sessions.get(currentID));
  ok(!result.milestones.some((event) => event.kind === "volumePR"),
    "identical two-dumbbell history does not emit a false volume PR");
  await db.Sessions.del(priorID);
  await db.Sessions.del(currentID);
}

for (let i = 0; i < 10; i++) {
  await db.Sessions.save({
    date: new Date(Date.UTC(2000, 0, i + 1)).toISOString(), notes: "Fictional regression record",
    isCompleted: true, gymName: "Main Gym", exercises: [{
      order: 0, exerciseName: "Deadlift", notes: "", phase: null,
      plannedWeightLb: null, plannedSets: null, plannedReps: null,
      sets: [{ order: 0, weightLb: 50 + i, reps: 5, isWarmup: false, isPerSide: false,
        enteredUnit: "lb", status: "completed", flags: ["clean"], bodyFlagSite: null, bodyFlagNote: null }],
    }],
  });
}

// Stable IDs are added once and survive mutable display names.
{
  const p = await db.Programs.active(); const g = await db.Gyms.default();
  ok(typeof p.uuid === "string" && p.uuid.length === 36, "program has a stable portable id");
  ok(typeof g.id === "string" && g.id.length === 36, "gym has a stable portable id");
}

// ---- library sync tops up an already-seeded (older) install ----
{
  // Simulate an old install: blank a movement group and edit an exercise's
  // rest, then prove sync backfills the group WITHOUT clobbering the edit.
  const dl = await db.Exercises.byName("Deadlift");
  dl.movementGroup = ""; dl.defaultRestSeconds = 222; await db.Exercises.save(dl);
  await db.syncLibrary();
  ok((await db.Exercises.byName("Deadlift")).movementGroup === "hinge", "sync backfills a missing movement group");
  ok((await db.Exercises.byName("Deadlift")).defaultRestSeconds === 222, "sync does NOT clobber user edits");
  ok((await db.Exercises.all()).length === 141, "sync leaves the count whole (no dupes)");
}

// ---- retired rest stamps: one-shot clear un-freezes the rest buckets ----
{
  // Simulate a pre-bucket install: the old seed stamped every exercise with a
  // rest (which, as the per-exercise override, made the settings steppers
  // dead controls), and the migration flag doesn't exist yet.
  const squat = await db.Exercises.byName("Back Squat");
  const ohp = await db.Exercises.byName("Overhead Press");
  squat.defaultRestSeconds = 300; await db.Exercises.save(squat);   // = its retired stamp
  ohp.defaultRestSeconds = 240; await db.Exercises.save(ohp);       // user-edited (stamp was 300)
  let s = await db.Settings.get();
  delete s.restSeedStampsCleared;
  await db.Settings.save(s);
  await db.syncLibrary();
  ok((await db.Exercises.byName("Back Squat")).defaultRestSeconds === 0, "a value equal to its retired stamp is cleared to bucket-driven");
  ok((await db.Exercises.byName("Overhead Press")).defaultRestSeconds === 240, "a user-edited value survives the clear");
  ok((await db.Exercises.byName("Deadlift")).defaultRestSeconds === 222, "an earlier user edit also survives");
  ok((await db.Settings.get()).restSeedStampsCleared === true, "the clear marks itself done");
  // One-shot: re-stamping after the flag is set must stick.
  squat.defaultRestSeconds = 300; await db.Exercises.save(squat);
  await db.syncLibrary();
  ok((await db.Exercises.byName("Back Squat")).defaultRestSeconds === 300, "the clear never re-runs once flagged");
  squat.defaultRestSeconds = 0; await db.Exercises.save(squat);      // back to bucket-driven
  ohp.defaultRestSeconds = 0; await db.Exercises.save(ohp);
}

// ---- rest buckets are live: session rest follows settings, role, override ----
{
  const s = await db.Settings.get();
  const stockMain = s.rest.mainCompoundSeconds;
  s.rest.mainCompoundSeconds = 240; // turn the "Squat & deadlift mains" stepper
  await db.Settings.save(s);
  const prog = await db.Programs.active();
  const day = [...prog.days].sort((a, b) => a.order - b.order)[0]; // Lower A: Back Squat main, Deadlift complementary
  const sid = await session.createSessionFromProgramDay(prog, day);
  await session.openSession(sid); await tick();
  const restBtn = [...document.querySelectorAll("#session-bar button")].find((b) => b.textContent.startsWith("Rest "));
  ok(restBtn && restBtn.textContent === "Rest 4:00", `main squat rest follows the bucket stepper (got ${restBtn && restBtn.textContent})`);
  const chips = [...document.querySelectorAll("#overlays .overlay button")].filter((b) => b.textContent.startsWith("⏱"));
  ok(chips.some((b) => b.textContent === "⏱ 3:42"), "complementary Deadlift keeps its per-exercise 3:42 rest (override beats role)");
  ok(chips.some((b) => b.textContent === "⏱ 1:30"), "accessories fall to the accessory bucket");
  document.querySelector("#overlays .overlay .overlay-head button").click(); await tick(); // close without banking
  await db.Sessions.del(sid);
  s.rest.mainCompoundSeconds = stockMain;
  await db.Settings.save(s);
}

// ---- render every tab without throwing ----
for (const [name, view] of [["home", home], ["history", history], ["body", body], ["signals", signals], ["settings", settings]]) {
  try { await view.render(host()); ok(host().childElementCount > 0, `${name} rendered`); }
  catch (e) { ok(false, `${name} threw: ${e.message}`); }
}

// Today with no active program is the very first screen a new install shows.
// The coach section used to run on a null program and throw, leaving the tab
// blank — which is only reachable before any program exists, so every other
// case here missed it.
// `Programs.active()` falls back to the first stored program, so the only way
// to reach the genuine no-program state is an empty store.
{
  const stored = await db.Programs.all();
  for (const program of stored) await db.Programs.del(program.id);
  try {
    ok((await db.Programs.active()) === null, "the program store is empty for this case");
    await home.render(host());
    ok(host().childElementCount > 0, "Today renders on a fresh install with no active program");
    ok(!host().textContent.includes("Coach · per rotation"),
      "no program means no coach section rather than a crash");
  } catch (e) {
    ok(false, `home threw with no active program: ${e.message}`);
  } finally {
    for (const program of stored) await db.Programs.save(program);
  }
  const restored = await db.Programs.all();
  ok(restored.length === stored.length, "programs restored after the no-program render");
}

// exercise history charts mode (lineChart path)
await history.render(host());
const chartsBtn = [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "Charts");
chartsBtn.click(); await tick();
ok(host().querySelector("svg.chart") || host().querySelector(".empty"), "history charts mode renders");

// plate calculator overlay
await plates.openPlateCalculator(); await tick();
ok(document.querySelector("#overlays .overlay"), "plate calculator opened");
document.querySelector("#overlays .overlay .overlay-head button").click(); // close
await tick();

// ---- full session flow: start Deadlift (245 target snapped to achieved load), complete, expect PR + advance ----
// First prove untouched prescriptions are not performed work.
{
  const track = (await db.Tracks.all()).find((t) => t.exerciseName === "Incline DB Press");
  const before = track.baseWeightLb;
  const untouchedId = await session.createSessionFromTrack(track);
  const summary = await session.completeSession(await db.Sessions.get(untouchedId));
  ok(summary.lines.length === 0, "untouched planned sets produce no completion summary");
  ok((await db.Tracks.byName(track.exerciseName)).baseWeightLb === before, "untouched planned sets do not advance progression");
  await db.Sessions.del(untouchedId);
}

const dl = (await db.Tracks.all()).find((t) => t.exerciseName === "Deadlift");
const id = await session.createSessionFromTrack(dl);
const created = await db.Sessions.get(id);
const work = created.exercises[0].sets.filter((s) => !s.isWarmup);
const warm = created.exercises[0].sets.filter((s) => s.isWarmup);
const achievedDeadlift = created.exercises[0].plannedWeightLb;
ok(warm.length === 4 && warm[0].weightLb > 45
  && warm.every((set) => set.weightLb !== 45), "deadlift ramp omits the empty bar");
ok(work.length === 3 && work.every((s) => s.weightLb === achievedDeadlift && s.reps === 3)
  && Math.abs(achievedDeadlift - 245) <= 2, "3 working sets store the achievable 245-target load");
work.forEach((set) => { set.status = "completed"; });
await db.Sessions.save(created);

await session.openSession(id); await tick();
const overlayButtons = () => [...document.querySelectorAll("#overlays .overlay button")];
ok(overlayButtons().some((b) => b.textContent === "Rest"), "per-exercise Rest button present in logger");
ok(overlayButtons().some((b) => b.textContent.startsWith("⏱")), "per-exercise rest chip shows duration");
ok(document.querySelector("#overlays .overlay svg.barbell"), "barbell plate visualization renders for a barbell lift");
ok([...document.querySelectorAll("#overlays .overlay select.bar-select option")].some((o) => o.textContent.includes("45 lb")), "bar selector offers 45 lb");
const barSelect = document.querySelector("#overlays .overlay select.bar-select");
barSelect.value = "35-lb";
barSelect.dispatchEvent(new window.Event("change")); await tick();
const withBarOverride = await db.Sessions.get(id);
ok(withBarOverride.exercises[0].barId === "35-lb", "per-exercise bar override persists on the session");
ok(withBarOverride.exercises[0].sets.filter((s) => s.isWarmup).every((set) => set.weightLb !== 35),
  "deadlift bar override still omits the empty bar");
// Opening the logger is not the same act as starting the workout: a clock
// that starts itself on open reports elapsed time nobody trained, and until
// there was a way to reset it that time could not be taken back.
const clockEl = document.querySelector("#session-bar .clock");
const startBtn = document.querySelector("#session-bar button[aria-label^='Start the workout clock']");
ok(clockEl.textContent.includes("not started"), "[INV-OPEN-IS-NOT-START] opening a session does not start its clock");
ok(startBtn && startBtn.style.display !== "none", "an explicit Start workout control is offered");
startBtn.click(); await tick();
ok(clockEl.textContent.includes("session"), "starting explicitly runs the session clock");
const resetBtn = document.querySelector("#session-bar button[aria-label^='Reset this session']");
ok(resetBtn && resetBtn.style.display !== "none", "a reset control appears once started");
resetBtn.click(); await tick();
ok(clockEl.textContent.includes("not started"), "[INV-OPEN-IS-NOT-START] reset returns an accidentally started session to not started");
startBtn.click(); await tick();
ok([...document.querySelectorAll("#session-bar button")].some((b) => b.textContent.startsWith("Rest ")), "bottom-bar Rest button shows the current lift's rest");
const bank = overlayButtons().find((b) => b.textContent === "Bank it.");
ok(!!bank, "Bank it. button present");
bank.click(); await tick();

const completed = (await db.Sessions.completed()).length;
ok(completed === 11, `session banked (now ${completed} completed)`);
const dlAfter = await db.Tracks.byName("Deadlift");
ok(dlAfter.nextPhase === 4, `deadlift advanced peak→deload (nextPhase=${dlAfter.nextPhase})`);
const ms = await db.Milestones.all();
ok(ms.some((m) => m.exerciseName === "Deadlift" && m.kind === "heaviestSet"), "achieved deadlift heaviest-set milestone logged");

// ---- export / import round trip ----
const json = await db.exportJSON();
const parsed = JSON.parse(json);
ok(parsed.schemaVersion === db.BACKUP_SCHEMA_VERSION, "export declares the current backup schema");
ok(parsed.sessions.length === 11 && Array.isArray(parsed.milestones), "export bundle shape");
ok(Array.isArray(parsed.tracks) && parsed.tracks.length === 3, "export carries lift tracks");
ok(Array.isArray(parsed.gyms) && parsed.gyms.length > 0, "export carries gyms");
ok(Array.isArray(parsed.exercises) && parsed.exercises.length === 141, "export carries the exercise library");
ok(parsed.settings && parsed.settings.unitDisplay === "lbPrimary" && parsed.settings.id === undefined, "export carries settings (sans row id)");
ok(parsed.settings.theme === "carbon", "theme defaults to carbon and round-trips");
ok(parsed.settings.rest && parsed.settings.rest.mainCompoundSeconds === 300, "export carries the nested rest buckets");
ok(parsed.sessions.some((s) => s.exercises.some((e) => e.barId === "35-lb")), "export carries session-local bar overrides");
const csv = await db.exportCSV();
ok(csv.split("\n")[0].startsWith("date,exercise,set_index"), "csv header");

// Mutable non-log state must survive the round trip (the Safari-eviction
// recovery path): advance-then-restore must not reset the track.
{
  const dlTrack = await db.Tracks.byName("Deadlift");
  ok(dlTrack.nextPhase === 4, "deadlift track advanced pre-export");
  dlTrack.nextPhase = 1; dlTrack.baseWeightLb = 100; await db.Tracks.save(dlTrack); // simulate lost state
  await db.importBundle(parsed);
  ok((await db.Sessions.completed()).length === 11, "import round trip preserves sessions");
  const restored = await db.Tracks.byName("Deadlift");
  ok(restored.nextPhase === 4 && restored.baseWeightLb !== 100, "import restores live track progression");
  const sets = (await db.Sessions.completed())[0].exercises[0].sets;
  ok(sets.every((s) => s.enteredUnit === "lb" || s.enteredUnit === "kg"), "sets keep their entered unit through the round trip");

  const legacy = JSON.parse(JSON.stringify(parsed));
  delete legacy.schemaVersion;
  for (const s of legacy.sessions) delete s.isCompleted;
  await db.importBundle(legacy);
  ok((await db.Sessions.all()).every((s) => s.isCompleted), "legacy version-0 sessions still restore as completed");
  await db.importBundle(parsed);
}

// Version-1 web backups used numeric IndexedDB program IDs. They migrate to
// portable UUIDs, and name-tagged sessions are rebound without retaining the
// local integer as cross-platform linkage.
{
  const v1 = structuredClone(parsed);
  v1.schemaVersion = 1;
  v1.programs.forEach((program, index) => { program.id = index + 1; });
  const first = v1.programs[0];
  v1.sessions[0].programTag = {
    programId: first.id, programName: first.name, cycleNumber: first.cycleNumber,
    week: first.currentWeek, dayIndex: first.nextDayIndex, planNames: [],
  };
  for (const workout of v1.sessions) for (const exercise of workout.exercises) for (const set of exercise.sets) delete set.status;
  await db.importBundle(v1);
  const migratedPrograms = await db.Programs.all();
  const migratedSession = (await db.Sessions.all()).find((workout) => workout.programTag);
  ok(migratedPrograms.every((program) => typeof program.uuid === "string" && program.uuid.length === 36),
    "v1 numeric program IDs migrate to portable UUIDs");
  ok(migratedPrograms.some((program) => program.uuid === migratedSession.programTag.programId),
    "v1 session tags rebind to the migrated program UUID");
  await db.importBundle(parsed);
}

// Cross-platform settings: a native backup carries the rest buckets FLAT
// (mainCompoundRestSeconds…, no nested `rest`) — import must normalize them
// into settings.rest so the buckets survive an iOS → web restore. A partial
// nested rest must merge over defaults (no NaN holes).
{
  const nativeShaped = { ...parsed, settings: { ...parsed.settings, mainCompoundRestSeconds: 210, olympicRestSeconds: 195, mainUpperRestSeconds: 150, secondaryRestSeconds: 120, accessoryRestSeconds: 75 } };
  delete nativeShaped.settings.rest;
  await db.importBundle(nativeShaped);
  const s = await db.Settings.get();
  ok(s.rest && s.rest.mainCompoundSeconds === 210 && s.rest.secondarySeconds === 120 && s.rest.accessorySeconds === 75,
    "native flat rest keys normalize into settings.rest on import");
  const partialRest = { ...parsed, settings: { ...parsed.settings, rest: { secondarySeconds: 135 } } };
  await db.importBundle(partialRest);
  const s2 = await db.Settings.get();
  ok(s2.rest.secondarySeconds === 135 && s2.rest.mainCompoundSeconds === 300 && s2.accessoryRestSeconds === s2.rest.accessorySeconds,
    "partial nested rest merges over defaults and keeps the legacy key in sync");
  await db.importBundle(parsed); // restore the canonical settings for later blocks
}

// restSeedStampsCleared describes the exercise library's migration state, so
// it must follow the bundle only when the library itself was restored: a
// settings-only restore keeps the current marker (else the next syncLibrary
// would re-clear over an untouched library and could eat a user-set rest equal
// to a retired stamp), while a library restored without settings re-arms it.
{
  ok((await db.Settings.get()).restSeedStampsCleared === true, "marker is set before the partial-restore checks");
  const settingsOnly = { sessions: parsed.sessions, settings: { ...parsed.settings } };
  delete settingsOnly.settings.restSeedStampsCleared; // a pre-migration, exercise-less backup
  await db.importBundle(settingsOnly);
  ok((await db.Settings.get()).restSeedStampsCleared === true, "settings-only restore keeps the stamp-clear marker");
  await db.importBundle({ exercises: parsed.exercises });
  ok((await db.Settings.get()).restSeedStampsCleared === false, "library restore without settings re-arms the stamp check");
  await db.importBundle(parsed); // full post-migration bundle restores the marker
  ok((await db.Settings.get()).restSeedStampsCleared === true, "full post-migration restore carries the marker");
}

// A backup missing a store's key must leave that store untouched (old-format
// bundles), and a malformed bundle must not wipe anything.
{
  const progsBefore = (await db.Programs.all()).length;
  const partial = { sessions: parsed.sessions }; // no programs/tracks/gyms keys
  await db.importBundle(partial);
  ok((await db.Programs.all()).length === progsBefore, "import without a programs key leaves programs alone");
  let threw = false;
  try { await db.importBundle({ nonsense: true }); } catch { threw = true; }
  ok(threw, "importing a non-backup throws instead of wiping");
  ok((await db.Sessions.completed()).length === 11, "failed import left sessions intact");

  // A malformed record INSIDE a store array makes put() throw synchronously —
  // the transaction must abort wholesale, not commit the already-queued clears.
  const gymsBefore = await db.Gyms.all();
  ok(gymsBefore.length > 0, "have gyms before the poisoned import");
  let threwMid = false;
  try { await db.importBundle({ sessions: parsed.sessions, gyms: [{}] }); } catch { threwMid = true; }
  ok(threwMid, "poisoned record rejects the import");
  ok((await db.Sessions.completed()).length === 11, "poisoned import did not clear sessions");
  ok((await db.Gyms.all()).length === gymsBefore.length, "poisoned import did not clear gyms");

  // Schema 5 adds three values to enums the importer validates against
  // whitelists: the amrap block, the repPR milestone, and the rir* flags. A v4
  // bundle predates all three and has to keep restoring; a v5 bundle carrying
  // all three has to round-trip.
  {
    const v4 = structuredClone(parsed);
    v4.schemaVersion = 4;
    for (const session of v4.sessions) for (const entry of session.exercises || []) {
      for (const set of entry.sets || []) {
        set.flags = (set.flags || []).filter((flag) => !C.SET_RIRS.includes(flag));
        if (set.prescriptionBlock === "amrap") set.prescriptionBlock = "work";
      }
    }
    v4.milestones = (v4.milestones || []).filter((m) => m.kind !== "repPR");
    await db.importBundle(v4);
    ok((await db.Sessions.all()).length === v4.sessions.length, "a version-4 backup still restores under schema 5");
    ok((await db.Sessions.completed()).flatMap((s) => s.exercises).flatMap((e) => e.sets)
      .every((set) => !(set.flags || []).some((f) => C.SET_RIRS.includes(f))),
      "and it does not gain values it never carried");

    // Decorated explicitly rather than relying on the fixture's contents: this
    // is a contract test, and it should fail if the contract regresses even
    // when the fixture happens not to exercise a value.
    const v5 = structuredClone(parsed);
    const marked = v5.sessions.flatMap((session) => session.exercises || [])
      .flatMap((entry) => entry.sets || []).filter((set) => !set.isWarmup)[0];
    ok(!!marked, "the fixture bundle has a working set to decorate");
    marked.flags = ["clean", "rir1"];
    marked.prescriptionBlock = "amrap";
    v5.milestones = [...(v5.milestones || []), {
      date: v5.sessions[0].date, exerciseName: "Back Squat", kind: "repPR", label: "Rep PR — 235 × 3 back squat",
    }];
    await db.importBundle(v5);

    const roundTripped = (await db.Sessions.all()).flatMap((s) => s.exercises || []).flatMap((e) => e.sets || []);
    ok(roundTripped.some((set) => (set.flags || []).includes("rir1")),
      "reps-in-reserve survives import — the flag normalizer used to strip it on read");
    ok(roundTripped.some((set) => (set.flags || []).includes("clean") && (set.flags || []).includes("rir1")),
      "a set can be both clean and one rep from failure — the two groups do not exclude each other");
    ok(roundTripped.some((set) => set.prescriptionBlock === "amrap"), "the amrap block survives import");
    ok((await db.Milestones.all()).some((m) => m.kind === "repPR"), "rep PRs are announced, not just charted");

    // Re-exporting must not quietly drop any of them either.
    const reexported = await db.exportBundle();
    const reexportedSets = reexported.sessions.flatMap((s) => s.exercises || []).flatMap((e) => e.sets || []);
    ok(reexportedSets.some((set) => (set.flags || []).includes("rir1")), "and survives the next export");
    ok(reexportedSets.some((set) => set.prescriptionBlock === "amrap"), "and so does the amrap block");

    await db.importBundle(parsed);
  }

  const sessionsBeforeFuture = (await db.Sessions.all()).length;
  let threwFuture = false;
  try { await db.importBundle({ ...parsed, schemaVersion: db.BACKUP_SCHEMA_VERSION + 1 }); } catch { threwFuture = true; }
  ok(threwFuture, "a future backup schema is rejected before mutation");
  ok((await db.Sessions.all()).length === sessionsBeforeFuture, "future-schema rejection leaves sessions intact");

  const rejectBeforeMutation = async (mutate, label) => {
    const poisoned = structuredClone(parsed);
    mutate(poisoned);
    const before = (await db.Sessions.all()).length;
    let message = "";
    try { await db.importBundle(poisoned); } catch (error) { message = error.message; }
    ok(message.includes("Backup validation failed"), `${label} is rejected by preflight validation`);
    ok((await db.Sessions.all()).length === before, `${label} rejection leaves sessions intact`);
  };
  await rejectBeforeMutation((b) => { b.sessions[0].date = "yesterday-ish"; }, "invalid date");
  await rejectBeforeMutation((b) => { b.sessions[0].exercises[0].sets[0].enteredUnit = "stone"; }, "unknown set unit");
  await rejectBeforeMutation((b) => { delete b.sessions[0].exercises[0].sets[0].enteredUnit; }, "missing v1 set unit");
  await rejectBeforeMutation((b) => { delete b.sessions[0].exercises[0].sets[0].status; }, "missing v2 set status");
  await rejectBeforeMutation((b) => { b.programs[0].id = "1"; }, "non-portable program identifier");
  await rejectBeforeMutation((b) => { b.sessions[0].exercises[0].sets[0].flags = ["clean", "grindy"]; }, "multiple quality grades");
  await rejectBeforeMutation((b) => { delete b.programs[0].id; }, "missing stable program id");
  await rejectBeforeMutation((b) => { b.exercises[0].name = "   "; }, "blank exercise identifier");
  await rejectBeforeMutation((b) => { b.gyms.push(structuredClone(b.gyms[0])); }, "duplicate gym identifier");
  await rejectBeforeMutation((b) => { b.programs[0].nextDayIndex = b.programs[0].days.length; }, "out-of-range program day");
  await rejectBeforeMutation((b) => { b.sessions = { absolutely: "not an array" }; }, "wrong section shape");

  // nextDayIndex names a day's ORDER, not its position. Range-checking it
  // against the day COUNT rejected legitimate bundles: orders [0, 1, 5]
  // pointing at day 5 is exactly the sparse shape the schedule now handles,
  // and rejecting it left the user with no way to restore the backup at all.
  {
    const sparse = structuredClone(parsed);
    const days = sparse.programs[0].days;
    const highest = Math.max(...days.map((d) => d.order)) + 4;
    days[days.length - 1].order = highest;
    sparse.programs[0].nextDayIndex = highest;
    let message = "";
    try { await db.importBundle(sparse); } catch (error) { message = error.message; }
    ok(!message, `[INV-NEXTDAY-IS-AN-ORDER] a sparse day-order backup restores instead of being rejected (${message})`);
    const restored = (await db.Programs.all()).find((p) => p.name === sparse.programs[0].name);
    ok(restored.days.some((d) => d.order === highest), "the sparse day survives the round trip");
    ok(restored.nextDayIndex === highest, "[INV-NEXTDAY-IS-AN-ORDER] nextDayIndex still names the same day after import");
  }

  // [INV-SLOT-ID-IS-UNIQUE] Slot ids are validated within a program, so a
  // hand-edited bundle can carry one on two programs. A backup is the recovery
  // path of last resort, so this is REPAIRED rather than refused — the opposite
  // of the program-file importer, deliberately.
  {
    const clean = structuredClone(parsed);
    const cleanSummary = await db.importBundle(clean);
    ok((cleanSummary?.repairedSlotIDs || 0) === 0,
      "[INV-SLOT-ID-IS-UNIQUE] a clean backup reports no slot-id repairs");
    const untouched = await db.Programs.all();
    const untouchedIDs = untouched.flatMap((p) => (p.days || [])
      .flatMap((d) => [...(d.lifts || []), ...(d.accessories || [])].map((s) => s.id)));
    ok(new Set(untouchedIDs).size === untouchedIDs.length, "a clean backup restores with distinct slot ids");

    // Forking a program while keeping its slot ids is the reachable path — it
    // is what hand-editing an exported bundle produces.
    const forked = structuredClone(parsed);
    const fork = structuredClone(forked.programs[0]);
    fork.name = `${fork.name} (forked)`;
    fork.id = "dddddddd-0000-4000-8000-00000000000d";
    fork.isActive = false;
    forked.programs.push(fork);
    const donor = forked.programs[0].days.flatMap((d) => [...(d.lifts || []), ...(d.accessories || [])]);
    ok(donor.length > 0, "the donor program carries slots");
    const sharedID = donor[0].id;
    ok(sharedID != null, "the fixture's slots carry ids to collide on");

    let failure = "";
    let summary = null;
    try { summary = await db.importBundle(forked); } catch (error) { failure = error.message; }
    ok(!failure, `[INV-SLOT-ID-IS-UNIQUE] a backup with a cross-program duplicate still restores (${failure})`);
    ok(summary?.repairedSlotIDs === donor.length,
      `every duplicated slot is repaired and reported (${summary?.repairedSlotIDs} of ${donor.length})`);

    const after = await db.Programs.all();
    const liveIDs = after.flatMap((p) => (p.days || [])
      .flatMap((d) => [...(d.lifts || []), ...(d.accessories || [])].map((s) => s.id)));
    ok(new Set(liveIDs).size === liveIDs.length,
      "[INV-SLOT-ID-IS-UNIQUE] no two live slots share an id after the restore");
    ok(liveIDs.filter((id) => id === sharedID).length === 1,
      "the first occurrence keeps the id, so the most history stays bound");
    ok(after.length === forked.programs.length, "every program still restored");
  }
}

// ---- rotating local recovery checkpoints ----
{
  const before = await db.Tracks.byName("Deadlift");
  await db.Checkpoints.create("smoke-restore");
  before.baseWeightLb = 77; await db.Tracks.save(before);
  await db.Checkpoints.restoreLatest();
  ok((await db.Tracks.byName("Deadlift")).baseWeightLb !== 77, "latest local checkpoint restores the prior state");
  await db.Checkpoints.create("rotation-1");
  await db.Checkpoints.create("rotation-2");
  await db.Checkpoints.create("rotation-3");
  await db.Checkpoints.create("rotation-4");
  const checkpoints = await db.Checkpoints.all();
  ok(checkpoints.length === 3, "local checkpoint rotation keeps exactly three snapshots");
  ok(checkpoints.every((checkpoint) => checkpoint.bundle.schemaVersion === db.BACKUP_SCHEMA_VERSION), "local checkpoints use the portable backup contract");
}

// ---- cardio sets: distance/time/incline, not weight×reps ----
{
  // A fictional conditioning fixture exercises every cardio field.
  const sid = await session.createBlankSession();
  const s = await db.Sessions.get(sid);
  s.exercises.push({ order: 0, exerciseName: "Walk", notes: "", phase: null,
    plannedWeightLb: null, plannedSets: null, plannedReps: null,
    sets: [{ order: 0, weightLb: 0, reps: 1, isWarmup: false, isPerSide: false, enteredUnit: "lb",
      flags: [], bodyFlagSite: null, bodyFlagNote: null,
      durationSeconds: 2700, distanceMiles: 3, inclinePercent: 12, autoregReason: null }] });
  await db.Sessions.save(s);
  await session.openSession(sid); await tick();
  // Overlays from earlier blocks can still be mounted — anchor on the row.
  const walkRow = [...document.querySelectorAll("#overlays .overlay .setrow")]
    .find((r) => r.textContent.includes("45:00"));
  ok(walkRow && walkRow.textContent.includes("3 mi · 45:00 · 4 mph · 12%"), "cardio set row renders the shared conditioning label");
  ok(walkRow && walkRow.querySelectorAll(".flagbtn").length === 1, "cardio gets only the ✓ flag (no grindy/wobble)");

  // [INV-CARDIO-SOLVES-THE-THIRD] A treadmill or ruck is set by pace and time;
  // the distance has to fall out rather than be worked out mid-workout.
  {
    walkRow.querySelector("button.ghost").click(); await tick();
    const sheetEl = [...document.querySelectorAll("#overlays .sheet")].pop();
    const numbers = [...sheetEl.querySelectorAll("input[type=number]")];
    const rowLabel = (input) => input.closest(".row")?.textContent || "";
    const distField = numbers.find((i) => rowLabel(i).includes("Distance"));
    const speedField = numbers.find((i) => rowLabel(i).includes("Speed"));
    ok(distField && speedField, "the conditioning sheet offers both distance and speed");
    ok(speedField.value === "4", "speed opens as the readout derived from 3 mi in 45:00");

    // Typing a pace recomputes the distance, and leaves the time alone.
    speedField.value = "3.5";
    speedField.dispatchEvent(new window.Event("input", { bubbles: true }));
    ok(distField.value === "2.63",
      `[INV-CARDIO-SOLVES-THE-THIRD] 3.5 mph for 45:00 fills in 2.63 mi (got ${distField.value})`);

    // Typing a distance flips the derived side back to speed.
    distField.value = "3";
    distField.dispatchEvent(new window.Event("input", { bubbles: true }));
    ok(speedField.value === "4",
      `[INV-CARDIO-SOLVES-THE-THIRD] 3 mi in 45:00 reads back as 4 mph (got ${speedField.value})`);

    // Only distance and duration persist — there is no third stored value.
    [...sheetEl.querySelectorAll("button")].find((b) => b.textContent === "Done").click(); await tick();
    const saved = (await db.Sessions.get(sid)).exercises[0].sets[0];
    ok(saved.distanceMiles === 3 && saved.durationSeconds === 2700,
      "the conditioning set stores distance and duration only");
    ok(!("speedMph" in saved), "speed is never persisted as a third field");
  }

  // [INV-RUCK-CARRIES-ITS-LOAD] A ruck is born wearing its pack, and the next
  // leg inherits what the last one carried. This is asserted through the real
  // "+ Set" path rather than a hand-built record: the default previously lived
  // in the edit sheet behind a "nothing logged yet" guard that a conditioning
  // set — always created with a planned duration — could never satisfy, so the
  // 20 lb default was unreachable in every actual flow and no test noticed.
  {
    const rid = await session.createBlankSession();
    const r = await db.Sessions.get(rid);
    r.exercises.push({ order: 0, exerciseName: "Ruck", notes: "", phase: null,
      plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
    await db.Sessions.save(r);
    await session.openSession(rid); await tick();

    const overlay = [...document.querySelectorAll("#overlays .overlay")].pop();
    const addBtn = [...overlay.querySelectorAll("button")].find((b) => b.textContent === "+ Set");
    ok(addBtn, "the conditioning entry offers a + Set button");
    addBtn.click(); await tick();
    let ruck = (await db.Sessions.get(rid)).exercises[0].sets;
    ok(ruck.length === 1 && ruck[0].weightLb === 20,
      `[INV-RUCK-CARRIES-ITS-LOAD] a new ruck set is born at 20 lb (got ${ruck[0]?.weightLb})`);

    // A second leg inherits the load actually carried, not the default again.
    const stored = await db.Sessions.get(rid);
    stored.exercises[0].sets[0].weightLb = 40;
    await db.Sessions.save(stored);
    await session.openSession(rid); await tick();
    const overlay2 = [...document.querySelectorAll("#overlays .overlay")].pop();
    [...overlay2.querySelectorAll("button")].find((b) => b.textContent === "+ Set").click(); await tick();
    ruck = (await db.Sessions.get(rid)).exercises[0].sets;
    ok(ruck.length === 2 && ruck[1].weightLb === 40,
      `[INV-RUCK-CARRIES-ITS-LOAD] the next leg carries the same 40 lb (got ${ruck[1]?.weightLb})`);
  }

  // Unloaded conditioning stays unloaded — the load row is for carries only.
  // Uses Bike rather than Walk so the export assertion below still finds the
  // fixture Walk by name rather than this one.
  {
    const wid = await session.createBlankSession();
    const w = await db.Sessions.get(wid);
    w.exercises.push({ order: 0, exerciseName: "Bike", notes: "", phase: null,
      plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
    await db.Sessions.save(w);
    await session.openSession(wid); await tick();
    const ov = [...document.querySelectorAll("#overlays .overlay")].pop();
    [...ov.querySelectorAll("button")].find((b) => b.textContent === "+ Set").click(); await tick();
    const walk = (await db.Sessions.get(wid)).exercises[0].sets;
    ok(walk[0].weightLb === 0, "[INV-RUCK-CARRIES-ITS-LOAD] a bike carries nothing");
  }
  const overlays = document.querySelectorAll("#overlays .overlay");
  overlays[overlays.length - 1].querySelector(".overlay-head button").click(); await tick();

  // The incline key rides exports only when set — pre-incline records stay
  // byte-identical (the conditional-spread convention).
  s.isCompleted = true;
  await db.Sessions.save(s);
  const bundle = JSON.parse(await db.exportJSON());
  const exported = bundle.sessions.flatMap((x) => x.exercises).find((e) => e.name === "Walk");
  ok(exported && exported.sets[0].inclinePercent === 12 && exported.sets[0].distanceMiles === 3
    && exported.sets[0].durationSeconds === 2700, "export carries distance/time/incline");
  const liftSet = bundle.sessions.flatMap((x) => x.exercises).find((e) => e.name === "Deadlift").sets[0];
  ok(!("inclinePercent" in liftSet), "sets without incline don't grow the key (byte-stable exports)");
  await db.Sessions.del(sid); // leave the completed count as later blocks expect
}

// ---- completion is idempotent (double-tap backstop) ----
{
  const msBefore = (await db.Milestones.all()).length;
  const done = (await db.Sessions.completed())[0];
  const again = await completeAll(done);
  ok(again.lines.length === 0 && again.milestones.length === 0, "re-completing a banked session is a no-op");
  ok((await db.Milestones.all()).length === msBefore, "no duplicate milestones from re-completion");
}

// ---- the same tracked exercise in two sections is one exposure ----
{
  const adjustedTrack = await db.Tracks.byName("Incline DB Press");
  const heldBase = adjustedTrack.baseWeightLb;
  const adjustedId = await session.createSessionFromTrack(adjustedTrack);
  const adjustedSession = await db.Sessions.get(adjustedId);
  adjustedSession.exercises[0].sets.filter((set) => !set.isWarmup).forEach((set) => {
    set.weightLb -= 5;
    set.status = "completed";
  });
  const heldSummary = await session.completeSession(adjustedSession);
  const heldTrack = await db.Tracks.byName("Incline DB Press");
  ok(heldTrack.baseWeightLb === heldBase && heldTrack.lastCompletedAt,
    "performed weight below the immutable plan is saved but holds standalone progression");
  ok(heldSummary.coachingNotes.some((note) => note.startsWith("Held progression")),
    "completion explains why the adjusted standalone goal held");

  const before = (await db.Tracks.byName("Incline DB Press")).baseWeightLb; // linear, +5/session
  const sec = (order) => ({
    order, exerciseName: "Incline DB Press", notes: "", phase: null, programRole: null,
    plannedWeightLb: null, plannedSets: null, plannedReps: null,
    sets: [{ order: 0, weightLb: before, reps: 5, isWarmup: false, isPerSide: false, enteredUnit: "lb",
             flags: ["clean"], bodyFlagSite: null, bodyFlagNote: null, durationSeconds: null, distanceMiles: null, autoregReason: null }],
  });
  const sid = await db.Sessions.save({ date: db.iso(new Date()), notes: "", isCompleted: false, gymName: null, exercises: [sec(0), sec(1)] });
  await completeAll(await db.Sessions.get(sid));
  const after = (await db.Tracks.byName("Incline DB Press")).baseWeightLb;
  ok(after === before + 5, `duplicate sections advance the track only once (${before}→${after})`);
}

// ---- protein add reflects in today's total ----
await db.Protein.add({ date: new Date().toISOString(), grams: 45, label: "Shake" });
ok((await db.Protein.todayTotal()) >= 45, "protein logged for today");

// ---- program prescription integrity: DB steps, warmups, adjusted targets, slot identity ----
{
  const name = "Fixture Slot Identity";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 10, isActive: false,
    days: [{ name: "Upper", order: 0,
      lifts: [
        { exerciseName: "Incline DB Press", role: "main", baseWeightLb: 55, estimatedMaxLb: 80, stallCount: 0, lastIncrementLb: 0 },
        { exerciseName: "Incline DB Press", role: "main", baseWeightLb: 55, estimatedMaxLb: 80, stallCount: 0, lastIncrementLb: 0 },
      ], accessories: [{ exerciseName: "Plank", order: 0, sets: 3, minReps: 1, maxReps: 1,
        currentReps: 1, targetSeconds: 45, durationStepSeconds: 5, weightLb: 0, incrementLb: 0, stallCount: 0 }] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.days[0].lifts.every((lift) => lift.id) && new Set(program.days[0].lifts.map((lift) => lift.id)).size === 2,
    "duplicate exercise appearances receive distinct stable goal-slot IDs");

  const volumeId = await session.createSessionFromProgramDay(program, program.days[0]);
  const volume = await db.Sessions.get(volumeId);
  const volumeMain = volume.exercises[0];
  ok(volumeMain.plannedWeightLb === 55, "10 lb program rounding is capped to a 5 lb per-hand DB step");
  ok(volumeMain.sets.some((set) => set.isWarmup), "main dumbbell press receives warmup sets");
  const timedAccessory = volume.exercises.find((entry) => entry.exerciseName === "Plank");
  ok(timedAccessory.sets.every((set) => set.durationSeconds === 45 && set.reps === 1 && set.weightLb === 0),
    "timed program accessories carry seconds instead of fake repetition work");
  ok(volumeMain.programSlotId === program.days[0].lifts[0].id, "session entry retains its exact program goal slot");
  await db.Sessions.del(volumeId);

  program.currentWeek = 3;
  await db.Programs.save(program);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const peakId = await session.createSessionFromProgramDay(program, program.days[0]);
  const peak = await db.Sessions.get(peakId);
  const adjusted = peak.exercises[1];
  ok(adjusted.plannedWeightLb === 60, "55 lb DB base generates a 60 lb Peak, not 65 lb per hand");
  adjusted.plannedWeightLb = 55;
  const adjustedWork = adjusted.sets.filter((set) => !set.isWarmup);
  adjustedWork.forEach((set, index) => {
    // Mirrors accepting 60 after an already-completed 65: the completed row
    // stays historical while the remaining prescription changes to 60.
    set.weightLb = index === 0 ? 60 : 55;
    set.status = "completed";
  });
  await session.completeSession(peak);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(!program.days[0].lifts[0].pending, "unperformed duplicate slot is not graded by name collision");
  ok(program.days[0].lifts[1].pending?.grade === "success"
      && program.days[0].lifts[1].pending?.state.baseWeightLb === 60,
    "adjusted target, unchanged completed row, and actual work drive the correct goal slot");

  await db.importBundle(parsed);
}

// A capped AMRAP on the load rotation must reach the engine. Before the gate
// fix only week 3 touched estimatedMaxLb, so the extra reps were history and
// nothing else — and the ceiling that reads estimatedMaxLb stayed anchored to
// a fixed multiple of the base it is meant to bound.
{
  const name = "Fixture Load-Week AMRAP";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 2, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower", order: 0, accessories: [],
      lifts: [{ exerciseName: "Back Squat", role: "main", prescription: "wave",
        baseWeightLb: 190, estimatedMaxLb: 221.45, stallCount: 0, lastIncrementLb: 5 }] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const before = program.days[0].lifts[0];
  const loadId = await session.createSessionFromProgramDay(program, program.days[0]);
  const load = await db.Sessions.get(loadId);
  const entry = load.exercises[0];
  const work = entry.sets.filter((set) => !set.isWarmup);
  ok(work.length > 1 && work[0].weightLb === 210, `the load rotation prescribes 210 (got ${work[0].weightLb})`);
  work.forEach((set, index) => {
    set.status = "completed";
    // Capped AMRAP: the last set is taken past the prescription, stopping well
    // inside Epley's accurate band.
    if (index === work.length - 1) set.reps = 6;
  });
  await session.completeSession(load);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const after = program.days[0].lifts[0];
  ok(after.estimatedMaxLb > before.estimatedMaxLb,
    `earned reps on the load rotation raise the estimate (${before.estimatedMaxLb} -> ${after.estimatedMaxLb})`);
  ok(Math.abs(after.estimatedMaxLb - C.smoothE1RM(before.estimatedMaxLb, C.epleyE1RM(210, 6))) < 1e-9,
    "and they raise it by exactly one smoothing step toward the sample");
  ok(after.baseWeightLb === before.baseWeightLb && !after.pending,
    "an observation is not a grade — the base does not move outside the peak");
  ok(program.currentWeek === 3, "the load rotation still advances to the peak");

  await db.importBundle(parsed);
}

// A deload rotation must never drag the estimate down.
{
  const name = "Fixture Deload Observation";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 4, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower", order: 0, accessories: [],
      lifts: [{ exerciseName: "Back Squat", role: "main", prescription: "wave",
        baseWeightLb: 190, estimatedMaxLb: 221.45, stallCount: 0, lastIncrementLb: 5 }] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const deloadId = await session.createSessionFromProgramDay(program, program.days[0]);
  const deload = await db.Sessions.get(deloadId);
  for (const set of deload.exercises[0].sets) set.status = "completed";
  await session.completeSession(deload);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.days[0].lifts[0].estimatedMaxLb === 221.45,
    `light deload work is not evidence the max fell (got ${program.days[0].lifts[0].estimatedMaxLb})`);

  await db.importBundle(parsed);
}

// Rollover with no peak grade on record. The 10% rebuild belongs to the
// wave family, whose peak is the graded week; the methodology styles carry
// their own miss rules and must only hold. The two clients disagreed on which
// branch owned the rebuild, which is shared domain behaviour.
{
  const name = "Fixture Skipped Peak";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 4, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower", order: 0, accessories: [],
      lifts: [
        { exerciseName: "Back Squat", role: "main", prescription: "wave",
          baseWeightLb: 200, estimatedMaxLb: 260, stallCount: 1, lastIncrementLb: 5 },
        { exerciseName: "Deadlift", role: "main", prescription: "fiveThreeOne",
          baseWeightLb: 300, estimatedMaxLb: 380, stallCount: 2, lastIncrementLb: 10 },
      ] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const deloadId = await session.createSessionFromProgramDay(program, program.days[0]);
  const deload = await db.Sessions.get(deloadId);
  for (const entry of deload.exercises) {
    for (const set of entry.sets) set.status = "completed";
  }
  await session.completeSession(deload);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const [wave, methodology] = program.days[0].lifts;
  ok(wave.baseWeightLb === 180 && wave.stallCount === 0,
    `a wave slot's second skipped peak rebuilds at 90% (got ${wave.baseWeightLb}/${wave.stallCount})`);
  ok(methodology.baseWeightLb === 300 && methodology.stallCount === 2,
    `5/3/1 holds on a skipped graded week and keeps its own counter (got ${methodology.baseWeightLb}/${methodology.stallCount})`);
  ok(program.cycleNumber === 2 && program.currentWeek === 1, "the deload's last day rolls the cycle over");

  await db.importBundle(parsed);
}

// ---- program lifecycle: untouched vs partial completion ----
{
  let prog = await db.Programs.active();
  const day = prog.days.find((d) => d.order === prog.nextDayIndex);
  const initialDay = prog.nextDayIndex;
  const untouchedId = await session.createSessionFromProgramDay(prog, day);
  const untouched = await db.Sessions.get(untouchedId);
  const summary = await session.completeSession(untouched);
  prog = await db.Programs.active();
  ok(summary.lines.length === 0 && prog.nextDayIndex === initialDay,
    "untouched planned program session does not advance the schedule");
  await db.Sessions.del(untouchedId);

  await db.importBundle(parsed);
  prog = await db.Programs.active();
  const partialDay = prog.days.find((d) => d.order === prog.nextDayIndex);
  const untouchedAccessory = partialDay.accessories[0];
  const accessoryReps = untouchedAccessory.currentReps;
  const partialId = await session.createSessionFromProgramDay(prog, partialDay);
  const partial = await db.Sessions.get(partialId);
  partial.exercises[0].sets.filter((set) => !set.isWarmup).forEach((set) => { set.status = "completed"; });
  await session.completeSession(partial);
  prog = await db.Programs.active();
  const reloadedDay = prog.days.find((d) => d.order === partialDay.order);
  ok(prog.nextDayIndex !== initialDay, "partial program session advances after completed work");
  ok(reloadedDay.accessories.find((a) => a.exerciseName === untouchedAccessory.exerciseName).currentReps === accessoryReps,
    "planned-only accessory is not graded in a partial workout");
  await db.importBundle(parsed);
}

// ---- corrupted A/B mirror restores the exact day/slot matrix ----
{
  const name = "Fixture Program Day Matrix";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 4, currentWeek: 3, nextDayIndex: 2,
    roundingLb: 5, isActive: false,
    days: [
      { name: "Lower A", order: 0,
        lifts: [cyc("Back Squat", "main", 170, 230), cyc("Deadlift", "complementary", 140, 250)],
        accessories: [] },
      { name: "Upper A", order: 1, lifts: [], accessories: [] },
      { name: "Lower B", order: 2,
        lifts: [cyc("Back Squat", "main", 120, 220), cyc("Deadlift", "complementary", 200, 270)],
        accessories: [] },
      { name: "Upper B", order: 3, lifts: [], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  let day = program.days.find((candidate) => candidate.order === 2);
  const squatSlot = day.lifts.find((lift) => lift.exerciseName === "Back Squat");
  const deadliftSlot = day.lifts.find((lift) => lift.exerciseName === "Deadlift");
  const workSet = (order, weightLb, reps = 5, status = "completed") => ({
    order, weightLb, reps, plannedWeightLb: weightLb, plannedReps: reps,
    isWarmup: false, status, flags: [], bodyFlagSite: null,
    autoregReason: null, prescriptionBlock: "work",
  });
  const priorId = await db.Sessions.save({
    date: "2041-02-01T12:00:00.000Z", completedAt: "2041-02-01T13:00:00.000Z",
    notes: "Synthetic prior Lower B matrix", isCompleted: true,
    programTag: { programId: program.uuid, programName: name, cycleNumber: 4,
      week: 1, dayIndex: 2, planNames: ["Deadlift", "Back Squat"] },
    exercises: [
      { order: 0, exerciseName: "Deadlift", programRole: "main", programSlotId: null,
        plannedSets: 3, plannedReps: 5, plannedWeightLb: 200,
        sets: Array.from({ length: 3 }, (_, index) => workSet(index, 200)) },
      { order: 1, exerciseName: "Back Squat", programRole: "complementary", programSlotId: null,
        plannedSets: 3, plannedReps: 5, plannedWeightLb: 120,
        sets: Array.from({ length: 3 }, (_, index) => workSet(index, 120)) },
    ],
  });
  const extraId = await db.Sessions.save({
    date: "2041-02-02T12:00:00.000Z", completedAt: "2041-02-02T13:00:00.000Z",
    notes: "Synthetic unrelated extra work", isCompleted: true, programTag: null,
    exercises: [{ order: 0, exerciseName: "Back Squat", programRole: null, programSlotId: null,
      plannedSets: 3, plannedReps: 8, plannedWeightLb: 95,
      sets: Array.from({ length: 3 }, (_, index) => workSet(index, 95, 8)) }],
  });
  const staleOpenId = await db.Sessions.save({
    date: "2041-02-03T12:00:00.000Z", notes: "Synthetic mirrored Lower B preview", isCompleted: false,
    programTag: { programId: program.uuid, programName: name, cycleNumber: 4,
      week: 3, dayIndex: 2, planNames: ["Back Squat", "Deadlift"] },
    exercises: [
      { order: 0, exerciseName: "Back Squat", programRole: "main", programSlotId: squatSlot.id,
        targetWeightLb: 140, plannedWeightLb: 140, plannedSets: 3, plannedReps: 3,
        sets: Array.from({ length: 3 }, (_, index) => workSet(index, 140, 3, "planned")) },
      { order: 1, exerciseName: "Deadlift", programRole: "complementary", programSlotId: deadliftSlot.id,
        targetWeightLb: 220, plannedWeightLb: 220, plannedSets: 3, plannedReps: 3,
        sets: Array.from({ length: 3 }, (_, index) => workSet(index, 220, 3, "planned")) },
    ],
  });

  await db.syncLibrary();
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  day = program.days.find((candidate) => candidate.order === 2);
  const ordered = [...day.lifts].sort((left, right) => left.order - right.order);
  ok(ordered.map((lift) => `${lift.exerciseName}:${lift.role}`).join("|")
      === "Deadlift:main|Back Squat:complementary",
  "Lower B restores its tagged Deadlift/main and Back Squat/complementary matrix");
  ok(day.lifts.find((lift) => lift.exerciseName === "Deadlift").baseWeightLb === 200
      && day.lifts.find((lift) => lift.exerciseName === "Back Squat").baseWeightLb === 120,
  "matrix repair preserves each stable slot's programmed base");

  const repairedId = await session.createSessionFromProgramDay(program, day);
  const repaired = await db.Sessions.get(repairedId);
  const repairedDeadlift = repaired.exercises.find((entry) => entry.programRole === "main");
  const repairedSquat = repaired.exercises.find((entry) => entry.programRole === "complementary");
  ok(repairedId !== staleOpenId && repairedDeadlift.exerciseName === "Deadlift"
      && repairedSquat.exerciseName === "Back Squat",
  "the next session is rebuilt from the repaired Lower B slots");
  const deadliftPlan = C.programPlanFor({ cycleNumber: 4, baseWeightLb: 200, nextPhase: 3 },
    5, "barbell", "hinge", "main", "strength", "automatic");
  const squatPlan = C.programPlanFor({ cycleNumber: 4, baseWeightLb: 120, nextPhase: 3 },
    5, "barbell", "squat", "complementary", "strength", "automatic");
  ok(repairedDeadlift.targetWeightLb === deadliftPlan.weightLb
      && repairedSquat.targetWeightLb === squatPlan.weightLb,
  "targets come directly from each slot's base and current phase matrix");

  const stale = await db.Sessions.get(staleOpenId);
  for (const entry of stale.exercises) for (const set of entry.sets) set.status = "completed";
  await session.completeSession(stale);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.nextDayIndex === 2, "banking the stale mirrored session cannot advance the repaired schedule");

  await db.Sessions.del(priorId); await db.Sessions.del(extraId);
  await db.Sessions.del(staleOpenId); await db.Sessions.del(repairedId);
  await db.Programs.del(program.id);
}

// ---- complementary ordered first still ramps fully (nothing warmed the lifter) ----
{
  const name = "Fixture Cold Complementary";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower", order: 0,
      lifts: [
        { ...cyc("Deadlift", "complementary", 185, 255), order: 0 },
        { ...cyc("Back Squat", "main", 175, 204), order: 1 },
      ],
      accessories: [] }],
  });
  const prog = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const sId = await session.createSessionFromProgramDay(prog, prog.days[0]);
  const built = await db.Sessions.get(sId);
  const cold = built.exercises.find((entry) => entry.programRole === "complementary");
  ok(cold.sets.filter((set) => set.isWarmup).length > 2,
    "[INV-COMP-WARMUP-BRIDGE] a complementary lift with no earlier work keeps its full warmup ramp");
  await db.Sessions.del(sId);
  await db.Programs.del(prog.id);
}

// ---- a gap in day orders must not strand the schedule ----
// Day `order` addresses the rotation, but validation only requires uniqueness,
// so an imported bundle can carry [0, 1, 5]. Index-space arithmetic then never
// recognized the last day: the week stopped advancing, the cycle never rolled
// over, and the day past the gap became unreachable.
{
  const name = "Fixture Sparse Day Orders";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [
      { name: "A", order: 0, lifts: [cyc("Back Squat", "main", 175, 204)], accessories: [] },
      { name: "B", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
      { name: "C", order: 5, lifts: [cyc("Deadlift", "main", 205, 275)], accessories: [] },
    ],
  });
  let prog = (await db.Programs.all()).find((candidate) => candidate.name === name);
  // Orders are preserved, NOT renumbered: a day's order is the identity every
  // banked session's programTag.dayIndex refers to, so quietly renumbering
  // would strand those sessions. Reachability is solved in scheduleAdvance.
  ok(prog.days.map((d) => d.order).sort((a, b) => a - b).join(",") === "0,1,5",
    "[INV-DAY-ORDERS-PRESERVED] sparse day orders survive a save — tags stay valid");

  const banked = [];
  for (let i = 0; i < 3; i += 1) {
    prog = (await db.Programs.all()).find((candidate) => candidate.name === name);
    const day = prog.days.find((d) => d.order === prog.nextDayIndex);
    banked.push(day.name);
    const id = await session.createSessionFromProgramDay(prog, day);
    await completeAll(await db.Sessions.get(id));
  }
  ok(banked.join(",") === "A,B,C", "every day is reachable, including the one past the gap");
  prog = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(prog.currentWeek === 2, `banking the last day advances the rotation (wk=${prog.currentWeek})`);
  ok(prog.nextDayIndex === 0, `the schedule wraps back to the first day (next=${prog.nextDayIndex})`);
  await db.Programs.del(prog.id);
}

// ---- program: bank a full 4-week cycle, assert adaptive progression ----
{
  const sqTrackBase = (await db.Tracks.byName("Back Squat")).baseWeightLb; // standalone, must not move
  let prog = await db.Programs.active();
  ok(prog && prog.currentWeek === 1 && prog.cycleNumber === 1, "program starts wk1 cyc1");
  const squatBase0 = prog.days[0].lifts.find((l) => l.role === "main").baseWeightLb; // 175
  const accReps0 = prog.days[1].accessories[0].currentReps;

  const day0 = prog.days.find((d) => d.order === 0);
  const sId = await session.createSessionFromProgramDay(prog, day0);
  const built = await db.Sessions.get(sId);
  ok(built.programTag && built.programTag.week === 1, "program session is tagged");
  const roles = built.exercises.map((e) => e.programRole);
  ok(roles.includes("main") && roles.includes("complementary") && roles.includes("accessory"), "day has main+complementary+accessories");
  // The lifter is already warm from the main lift: a complementary barbell
  // slot bridges with exactly two warmups, then goes straight to volume work.
  const builtComp = built.exercises.find((e) => e.programRole === "complementary");
  ok(builtComp.sets.filter((set) => set.isWarmup).length === 2,
    "[INV-COMP-WARMUP-BRIDGE] complementary lift gets two bridging warmups, not a full ramp");
  ok(builtComp.plannedReps >= 5 && builtComp.plannedWeightLb <= 185,
    "complementary work is volume at/below its base, not a heavy mirror of the main wave");
  await completeAll(built); // i=0 banked (Lower A, week 1)

  for (let i = 1; i < 16; i++) {        // remaining of 4 weeks × 4 days
    prog = await db.Programs.active();
    const day = prog.days.find((d) => d.order === prog.nextDayIndex);
    const id = await session.createSessionFromProgramDay(prog, day);
    const sess = await db.Sessions.get(id);
    await completeAll(sess); // pre-filled working sets at target = a clean cycle
  }

  prog = await db.Programs.active();
  ok(prog.cycleNumber === 2, `cycle rolled over (cyc=${prog.cycleNumber})`);
  ok(prog.currentWeek === 1, `wave reset to week 1 (wk=${prog.currentWeek})`);
  const squatMain = prog.days[0].lifts.find((l) => l.role === "main");
  ok(squatMain.baseWeightLb === squatBase0 + 5, `clean cycle bumped squat ${squatBase0}→${squatMain.baseWeightLb}`);
  ok(squatMain.estimatedMaxLb > 204, "e1RM updated from the peak");
  ok(prog.days[1].accessories[0].currentReps > accReps0, "accessory reps progressed (double progression)");
  ok((await db.Tracks.byName("Back Squat")).baseWeightLb === sqTrackBase, "standalone Back Squat track NOT double-advanced");
}

// ---- program: a below-plan peak must not grade clean or bump the base (issue 18) ----
{
  // Advance the fresh cycle-2 wave to week 3 (2 weeks × 4 days, banked clean).
  for (let i = 0; i < 8; i++) {
    const prog = await db.Programs.active();
    const day = prog.days.find((d) => d.order === prog.nextDayIndex);
    const sess = await db.Sessions.get(await session.createSessionFromProgramDay(prog, day));
    await completeAll(sess);
  }
  let prog = await db.Programs.active();
  ok(prog.currentWeek === 3 && prog.nextDayIndex === 0, `at the peak week (wk=${prog.currentWeek} day=${prog.nextDayIndex})`);
  const day0 = prog.days.find((d) => d.order === 0);
  const base0 = day0.lifts.find((l) => l.role === "main").baseWeightLb;

  // Peak day: complete every prescribed rep of the main lift, but at 100 lb —
  // far below plan, with no flags and no autoreg reason (the issue-18 repro).
  const sess = await db.Sessions.get(await session.createSessionFromProgramDay(prog, day0));
  for (const e of sess.exercises) {
    if (e.programRole === "main") for (const s of e.sets) { if (!s.isWarmup) s.weightLb = 100; }
  }
  await completeAll(sess);
  prog = await db.Programs.active();
  const graded = prog.days.find((d) => d.order === 0).lifts.find((l) => l.role === "main");
  ok(graded.pending && graded.pending.grade === "fail", "below-plan peak graded fail, not success");

  // Day 1 of the same peak week: planned work done at plan, PLUS an extra
  // lighter back-off set — bonus volume must not fail the cycle.
  const day1 = prog.days.find((d) => d.order === prog.nextDayIndex);
  const sess1 = await db.Sessions.get(await session.createSessionFromProgramDay(prog, day1));
  const main1 = sess1.exercises.find((e) => e.programRole === "main");
  const working1 = main1.sets.filter((s) => !s.isWarmup);
  main1.sets.push({ ...working1[working1.length - 1], order: main1.sets.length, weightLb: working1[0].weightLb - 20 });
  await completeAll(sess1);
  prog = await db.Programs.active();
  const graded1 = prog.days.find((d) => d.order === day1.order).lifts.find((l) => l.role === "main");
  ok(graded1.pending && graded1.pending.grade === "success", "at-plan peak with a lighter back-off set still grades clean");

  // Bank the rest of the wave cleanly (2 more peak days + the 4 deload days);
  // rollover applies the stashed grades.
  for (let i = 0; i < 6; i++) {
    const p = await db.Programs.active();
    const day = p.days.find((d) => d.order === p.nextDayIndex);
    const s = await db.Sessions.get(await session.createSessionFromProgramDay(p, day));
    await completeAll(s);
  }
  prog = await db.Programs.active();
  ok(prog.currentWeek === 1, "wave rolled over after the below-plan cycle");
  const after = prog.days.find((d) => d.order === 0).lifts.find((l) => l.role === "main");
  ok(after.baseWeightLb === base0, `below-plan peak did not bump the base (${after.baseWeightLb} lb)`);
  ok(after.stallCount === 1, "below-plan peak counts as a stall, not a reset");
}

// ---- program: duplicate/stale sessions cannot advance the schedule twice (issue 17) ----
{
  // Walk the fresh week to its final day (bank days 0-2 cleanly).
  for (let i = 0; i < 3; i++) {
    const p = await db.Programs.active();
    const day = p.days.find((d) => d.order === p.nextDayIndex);
    await completeAll(await db.Sessions.get(await session.createSessionFromProgramDay(p, day)));
  }
  let prog = await db.Programs.active();
  const week0 = prog.currentWeek;
  ok(prog.nextDayIndex === 3, `at the week's final day (wk=${week0} day=${prog.nextDayIndex})`);
  const day3 = prog.days.find((d) => d.order === 3);

  // Start guard: a second Start while the day's session is open resumes it.
  const idA = await session.createSessionFromProgramDay(prog, day3);
  const idAgain = await session.createSessionFromProgramDay(await db.Programs.active(), day3);
  ok(idAgain === idA, "starting a program day with one already open resumes it");

  // Completion guard: force a true duplicate past the start guard, bank both.
  const dup = JSON.parse(JSON.stringify(await db.Sessions.get(idA)));
  delete dup.id;
  const idB = await db.Sessions.save(dup);
  await completeAll(await db.Sessions.get(idA));
  prog = await db.Programs.active();
  ok(prog.currentWeek === week0 + 1 && prog.nextDayIndex === 0, "first bank advances exactly one week");
  const accReps = prog.days[3].accessories.length ? prog.days[3].accessories[0].currentReps : null;
  await completeAll(await db.Sessions.get(idB));
  prog = await db.Programs.active();
  ok(prog.currentWeek === week0 + 1, `stale duplicate did not advance the week again (wk=${prog.currentWeek})`);
  ok(prog.nextDayIndex === 0, "stale duplicate did not move the day pointer");
  if (accReps != null) ok(prog.days[3].accessories[0].currentReps === accReps, "stale duplicate did not double-progress accessories");
  ok((await db.Sessions.get(idB)).isCompleted, "the stale session is still banked as history");
  const staleNotes = (await db.Milestones.all()).filter((m) => m.kind === "programNote" && /moved on/.test(m.label));
  ok(staleNotes.length === 1, "a program note explains the skipped advancement");
}

// ---- Start: resume vs rebuild by built-from plan snapshot ----
{
  let prog = await db.Programs.active();
  const day = prog.days.find((d) => d.order === prog.nextDayIndex);
  const comp = [...day.lifts].sort((a, b) => (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1))[1];
  const originalComp = comp.exerciseName;

  // Start once (session stamps the plan it was built from), then re-Start the
  // unedited day → resumes the same session.
  const id1 = await session.createSessionFromProgramDay(prog, day);
  const id2 = await session.createSessionFromProgramDay(await db.Programs.active(), day);
  ok(id1 === id2, "re-starting an unedited day resumes the open session");
  const built1 = await db.Sessions.get(id1);
  ok((built1.programTag.planNames || []).length > 0, "session records the plan it was built from");

  // Session-LOCAL edit (remove an exercise) — the program is unchanged, so the
  // built-from snapshot still matches: re-Start must RESUME the customized
  // session, not spawn a duplicate that brings the exercise back (Codex case).
  const s1 = await db.Sessions.get(id1);
  s1.exercises = s1.exercises.filter((e) => e.exerciseName !== originalComp);
  await db.Sessions.save(s1);
  const id2b = await session.createSessionFromProgramDay(await db.Programs.active(), day);
  ok(id2b === id1, "a session-local removal still resumes (snapshot unchanged)");
  ok(!(await db.Sessions.get(id2b)).exercises.some((e) => e.exerciseName === originalComp), "the removed exercise stays removed");

  // PROGRAM edit — change the day's complementary lift → the built-from
  // snapshot no longer matches the current plan → build FRESH.
  prog = await db.Programs.active();
  const liveDay = prog.days.find((d) => d.order === day.order);
  const liveComp = [...liveDay.lifts].sort((a, b) => (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1))[1];
  liveComp.exerciseName = "Face Pulls";
  await db.Programs.save(prog);

  const id3 = await session.createSessionFromProgramDay(await db.Programs.active(), liveDay);
  ok(id3 !== id1, "editing the program day builds a fresh session, not the stale one");
  const built3 = await db.Sessions.get(id3);
  ok(built3.exercises.some((e) => e.exerciseName === "Face Pulls"), "fresh session has the edited exercise");
  ok(!built3.exercises.some((e) => e.exerciseName === originalComp), "stale exercise is gone from the fresh session");
  const id4 = await session.createSessionFromProgramDay(await db.Programs.active(), liveDay);
  ok(id4 === id3, "the fresh session re-resumes on the next Start");
  await db.Sessions.del(id1); await db.Sessions.del(id3);
}

// ---- program templates: every style instantiates and banks cleanly ----
{
  const { PROGRAM_TEMPLATES, createProgramFromTemplate } = await import("../app/js/templates.js");
  ok(PROGRAM_TEMPLATES.length >= 3, "styles on offer: strength, oly, metcon");

  // Cross-language parity anchor: the JS templates must equal the shared
  // fixture byte-for-byte; ProgramTemplateDataTests holds Swift to the same
  // fixture, so either mirror drifting fails its own CI job.
  const { normalizedTemplates } = await import("./template-fixture.mjs");
  const fixture = JSON.parse(await (await import("node:fs/promises")).readFile(new URL("./fixtures/program-templates.json", import.meta.url), "utf8"));
  ok(JSON.stringify(await normalizedTemplates(), null, 2) === JSON.stringify(fixture, null, 2),
    "templates match the shared parity fixture (regenerate via web/tools/generate-template-fixture.mjs)");
  const squatBefore = await db.Exercises.byName("Back Squat"); // seeded — must never be overwritten
  for (const t of PROGRAM_TEMPLATES) {
    const id = await createProgramFromTemplate(t);
    const prog = await db.Programs.get(id);
    ok(prog && prog.days.length === t.days.length && prog.focus === t.focus, `${t.id}: program created with all days`);
    ok(!prog.isActive, `${t.id}: not activated over the existing program`);
    for (const e of t.exercises) ok(!!(await db.Exercises.byName(e.name)), `${t.id}: library has ${e.name}`);
    // A session from day 0 builds and banks without touching other programs.
    const sess = await db.Sessions.get(await session.createSessionFromProgramDay(prog, prog.days[0]));
    const roles = new Set(sess.exercises.map((x) => x.programRole));
    ok(t.days[0].lifts.length === 0 ? roles.has("accessory") : roles.has("main"), `${t.id}: day 0 session has its work`);
    await completeAll(sess);
    ok((await db.Programs.get(id)).nextDayIndex === 1, `${t.id}: banking advances the template program`);
    await db.Programs.del(id); // leave the world as we found it for later blocks
  }
  // Repeated instantiation mints a distinct name (the native mirror's
  // Program.name is unique — a fixed name would upsert there).
  const dupA = await createProgramFromTemplate(PROGRAM_TEMPLATES[0]);
  const dupB = await createProgramFromTemplate(PROGRAM_TEMPLATES[0]);
  const nameA = (await db.Programs.get(dupA)).name, nameB = (await db.Programs.get(dupB)).name;
  ok(nameA !== nameB && nameB.startsWith(nameA), `re-adding a style gets a distinct name (${nameB})`);
  await db.Programs.del(dupA); await db.Programs.del(dupB);
  const squatAfter = await db.Exercises.byName("Back Squat");
  ok(JSON.stringify(squatAfter) === JSON.stringify(squatBefore), "existing exercises never overwritten by templates");

  // History-driven starting weights: with a recorded 315×5 squat (e1RM 367.5),
  // a 5/3/1 program must open at TM = floor(0.90 × 367.5 → /5) = 330, and the
  // Boring-But-Big accessory at floor(0.45 × 367.5) = 165. No history → the
  // template's deliberately light hand-set bases stand (asserted above by the
  // fixture parity + instantiate/bank loop that ran before this history existed).
  await db.Sessions.save({
    date: new Date("2025-06-01T10:00:00Z").toISOString(), notes: "", isCompleted: true,
    exercises: [{ exerciseName: "Back Squat", sets: [
      { order: 0, weightLb: 315, reps: 5, isWarmup: false, status: "completed", flags: [] },
    ] }],
  });
  const t531 = PROGRAM_TEMPLATES.find((t) => t.id === "five-three-one");
  const p531 = await db.Programs.get(await createProgramFromTemplate(t531));
  const squatDay = p531.days.find((d) => d.name === "Squat Day");
  ok(squatDay.lifts[0].baseWeightLb === 330, `531 TM derives from recorded e1RM (got ${squatDay.lifts[0].baseWeightLb})`);
  ok(squatDay.lifts[0].estimatedMaxLb === 368, "531 slot e1RM captured from history");
  ok(squatDay.lifts[0].prescription === "fiveThreeOne", "531 slot carries its methodology style");
  ok(squatDay.accessories[0].weightLb === 165, `BBB volume at ~50% of TM (got ${squatDay.accessories[0].weightLb})`);
  await db.Programs.del(p531.id);
  // No recorded history for a slot → the template's hand-set base stands.
  const noHistory = await db.Programs.get(await createProgramFromTemplate({
    id: "test-fallback", name: "Fallback Check", tagline: "", focus: "strength", roundingLb: 5,
    exercises: [],
    days: [{ name: "Day", accessories: [], lifts: [{
      exerciseName: "Landmine Press", role: "main", baseWeightLb: 40, estimatedMaxLb: 60,
      stallCount: 0, lastIncrementLb: 0, prescription: "fiveThreeOne", sets: 0, startFraction: 0.90,
    }] }],
  }));
  ok(noHistory.days[0].lifts[0].baseWeightLb === 40, "no recorded history → template base stands");
  await db.Programs.del(noHistory.id);
  // Twin-slot synchronization: banking Day A's squat must advance Day B's
  // squat slot too — novice weight moves every session, not every other one.
  const novice = await db.Programs.get(await createProgramFromTemplate(
    PROGRAM_TEMPLATES.find((t) => t.id === "novice-linear-3x5")));
  const dayA = novice.days.find((d) => d.name === "Day A");
  const squatBase = dayA.lifts[0].baseWeightLb;
  const noviceSession = await db.Sessions.get(await session.createSessionFromProgramDay(novice, dayA));
  await completeAll(noviceSession);
  const noviceAfter = await db.Programs.get(novice.id);
  const squatA = noviceAfter.days.find((d) => d.name === "Day A").lifts[0];
  const squatB = noviceAfter.days.find((d) => d.name === "Day B").lifts[0];
  ok(squatA.baseWeightLb === squatBase + 10, `banked novice squat advances +10 (got +${squatA.baseWeightLb - squatBase})`);
  ok(squatB.baseWeightLb === squatA.baseWeightLb, "Day B squat slot stays in sync with Day A");
  await db.Programs.del(novice.id);
}

// ---- anatomy: muscle-map parity, coverage, and figure rendering ----
{
  const A = await import("../app/js/anatomy.js");
  const { normalizedAnatomy } = await import("./anatomy-fixture.mjs");
  const { readFile } = await import("node:fs/promises");
  const fx = JSON.parse(await readFile(new URL("./fixtures/anatomy.json", import.meta.url), "utf8"));
  ok(JSON.stringify(await normalizedAnatomy(), null, 2) === JSON.stringify(fx, null, 2),
    "anatomy matches the shared parity fixture (regenerate via web/tools/generate-anatomy-fixture.mjs)");

  const regionIds = new Set(A.ANATOMY_REGIONS.map((r) => r.id));
  ok([...regionIds].every((id) => A.MUSCLE_NAMES[id]), "every region has a display name");
  for (const [n, p] of Object.entries(A.MUSCLE_MAP)) {
    ok([...p.primary, ...p.secondary].every((id) => regionIds.has(id)) && p.primary.length > 0,
      `${n}: valid muscle profile`);
  }
  for (const e of await db.Exercises.all()) {
    ok(!!A.muscleProfile(e.name, e.movementGroup), `${e.name} resolves a muscle profile (by name or group)`);
  }
  ok(A.muscleBlurb(A.muscleProfile("Overhead Press", "press")) === "Primary: Shoulders, Triceps · Supporting: Traps, Abs",
    "blurb reads as expected");

  const svg = A.figureSVG(A.muscleProfile("Overhead Press", "press"));
  ok(svg.querySelectorAll("polygon").length > 30, "figure renders silhouette + regions for both views");
  ok(svg.querySelectorAll('polygon[fill="#e0453a"]').length >= 2, "primary movers highlighted red");
  ok(svg.querySelectorAll('polygon[fill="#3a7bd5"]').length >= 1, "supporting muscles highlighted blue");
}

// ---- program: a cycle-scoped swap reverts at rollover (issue 20) ----
// The swap gesture is native-only; the reverting state can arrive on web via
// backup, so the rollover must honor it here identically.
{
  let prog = await db.Programs.active();
  const lift = prog.days.find((d) => d.order === 0).lifts.find((l) => l.role === "main");
  const originalLift = lift.exerciseName;
  lift.revertToExerciseName = originalLift;
  lift.exerciseName = "Safety Bar Squat (swap)";
  const accDay = prog.days.find((d) => (d.accessories || []).length);
  const originalAcc = accDay ? accDay.accessories[0].exerciseName : null;
  if (accDay) {
    accDay.accessories[0].revertToExerciseName = originalAcc;
    accDay.accessories[0].exerciseName = "Ring Rows (swap)";
  }
  await db.Programs.save(prog);

  // The marker must survive a web export taken mid-cycle — dropping it would
  // turn the temporary swap into a permanent rename on restore.
  const exported = await db.exportBundle();
  const exLift = exported.programs.find((p) => p.id === prog.uuid).days.find((d) => d.order === 0).lifts.find((l) => l.role === "main");
  ok(exLift.revertToExerciseName === originalLift, "cycle-swap marker survives web export");

  const startCycle = prog.cycleNumber;
  for (let i = 0; i < 16 && (await db.Programs.active()).cycleNumber === startCycle; i++) {
    const p = await db.Programs.active();
    const day = p.days.find((d) => d.order === p.nextDayIndex);
    await completeAll(await db.Sessions.get(await session.createSessionFromProgramDay(p, day)));
  }
  prog = await db.Programs.active();
  ok(prog.cycleNumber === startCycle + 1, "wave rolled over with a swap pending revert");
  const liftAfter = prog.days.find((d) => d.order === 0).lifts.find((l) => l.role === "main");
  ok(liftAfter.exerciseName === originalLift, "cycle-swapped lift reverted at rollover");
  ok(liftAfter.revertToExerciseName == null, "lift revert marker cleared");
  if (accDay) {
    const accAfter = prog.days.find((d) => d.order === accDay.order).accessories[0];
    ok(accAfter.exerciseName === originalAcc, "cycle-swapped accessory reverted at rollover");
    ok(accAfter.revertToExerciseName == null, "accessory revert marker cleared");
  }
  const revertNotes = (await db.Milestones.all()).filter((m) => m.kind === "programNote" && /cycle swap over/.test(m.label));
  ok(revertNotes.length >= (accDay ? 2 : 1), "revert notes written at rollover");
}

// ---- structural editing: add a day with a lift + accessory, generate, then remove ----
{
  let prog = await db.Programs.active();
  const before = prog.days.length;
  prog.days.push({
    name: "Extra Day", order: prog.days.length,
    lifts: [{ exerciseName: "Push Press", role: "main", baseWeightLb: 95, estimatedMaxLb: 115, stallCount: 0, lastIncrementLb: 0 }],
    accessories: [{ exerciseName: "Dips", sets: 3, minReps: 8, maxReps: 12, currentReps: 8, weightLb: 0, incrementLb: 0, stallCount: 0 }],
  });
  await db.Programs.save(prog);
  prog = await db.Programs.active();
  ok(prog.days.length === before + 1, "added a program day");
  const newDay = prog.days.find((d) => d.name === "Extra Day");
  const id = await session.createSessionFromProgramDay(prog, newDay);
  const built = await db.Sessions.get(id);
  ok(built.exercises.some((e) => e.exerciseName === "Push Press" && e.programRole === "main"), "new day's lift appears in the session");
  ok(built.exercises.some((e) => e.exerciseName === "Dips" && e.programRole === "accessory"), "new day's accessory appears in the session");
  newDay.lifts = newDay.lifts.filter((l) => l.exerciseName !== "Push Press");
  await db.Programs.save(prog);
  ok((await db.Programs.active()).days.find((d) => d.name === "Extra Day").lifts.length === 0, "removed a lift from the day");
}

// ---- multiple programs: create, exclusively activate, delete ----
{
  await db.Programs.save({ name: "Cut Block", focus: "maintain", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0, roundingLb: 5, isActive: false, days: [] });
  let all = await db.Programs.all();
  ok(all.length === 2, "second program created");
  const second = all.find((p) => p.name === "Cut Block");
  for (const x of all) { x.isActive = x.id === second.id; await db.Programs.save(x); } // exclusive activate
  ok((await db.Programs.active()).name === "Cut Block", "activating switches the active program");
  ok((await db.Programs.all()).filter((p) => p.isActive).length === 1, "exactly one program active");
  await db.Programs.del(second.id);
  ok((await db.Programs.all()).length === 1, "program deleted");
}


// ---- backup v2: open sessions, lifecycle, and stable tags survive restore ----
{
  const prog = await db.Programs.active();
  const day = prog.days.find((d) => d.order === prog.nextDayIndex);
  const id = await session.createSessionFromProgramDay(prog, day);
  const open = await db.Sessions.get(id);
  open.notes = "backup-v2-open-session";
  await db.Sessions.save(open);

  const bundle = await db.exportBundle();
  const exported = bundle.sessions.find((s) => s.notes === "backup-v2-open-session");
  ok(exported && exported.isCompleted === false, "export preserves an open session");
  ok(exported.programTag?.programName === prog.name && exported.programTag.programId === prog.uuid,
    "export uses a stable cross-platform program id and historical label");
  ok(exported.exercises.flatMap((e) => e.sets).every((set) => set.status === "planned"),
    "prefilled open-session sets export as planned work");
  ok((exported.programTag?.planNames || []).length > 0, "export preserves the built-from plan snapshot");

  await db.importBundle(bundle);
  const restored = (await db.Sessions.all()).find((s) => s.notes === "backup-v2-open-session");
  ok(restored && restored.isCompleted === false, "restore keeps the session open");
  ok(restored.programTag?.programId === prog.uuid && restored.programTag?.programName === prog.name,
    "restore retains the canonical stable program id");
  ok((restored.programTag?.planNames || []).length === exported.programTag.planNames.length,
    "restore keeps resume-vs-rebuild plan context");
}


// ---- synthetic fixture: the broad-coverage dataset must import cleanly ----
// (Runs LAST — importing the fixture replaces the explicit fictional stores.
// The fixture is generated by tools/generate-synthetic-backup.mjs and doubles as the
// cross-platform backup-schema regression lock: the same file restores into
// the iOS app via ImportService.)
{
  const fs = await import("node:fs");
  const fixture = JSON.parse(fs.readFileSync(new URL("./fixtures/synthetic-backup.json", import.meta.url), "utf8"));
  await db.importBundle(fixture);
  const sessions = await db.Sessions.completed();
  ok(sessions.length >= 65, `fixture carries a deep fictional log (${sessions.length} sessions)`);

  const usedNames = new Set(); const flagKinds = new Set();
  let kgSets = 0, perSide = 0, timed = 0, bwSets = 0, drops = 0, signals = 0;
  for (const s of sessions) for (const e of s.exercises) {
    usedNames.add(e.exerciseName);
    for (const x of e.sets) {
      (x.flags || []).forEach((f) => flagKinds.add(f));
      if (x.enteredUnit === "kg") kgSets++;
      if (x.isPerSide) perSide++;
      if (x.durationSeconds) timed++;
      if (x.weightLb === 0) bwSets++;
      if (x.autoregReason) drops++;
      if (x.bodyFlagSite) signals++;
    }
  }
  const unused = (await db.Exercises.all()).map((e) => e.name).filter((n) => !usedNames.has(n));
  ok(unused.length === 0, `every library exercise appears in the log (unused: ${unused.join(", ")})`);
  ok(["clean", "grindy", "wobble", "stopped early"].every((f) => flagKinds.has(f)), "all set-quality flags exercised");
  ok(kgSets > 0 && perSide > 0 && timed > 0 && bwSets > 0 && drops > 0 && signals > 0,
    `kg entry (${kgSets}), per-side (${perSide}), timed (${timed}), bodyweight (${bwSets}), drop-load (${drops}), body signals (${signals}) all present`);

  const progs = await db.Programs.all();
  ok(progs.length >= 3 && new Set(progs.map((p) => p.focus)).size === 3, "programs cover all three training focuses");
  ok(fixture.appVersion === "synthetic" && progs.every((program) => program.name.startsWith("Fixture ")),
    "regression backup is explicitly fictional, never an app export");
  ok((await db.Exercises.all()).every((exercise) => !exercise.isShelved && !exercise.shelvedNote && !exercise.watchSite),
    "fixture exercise library contains no user health defaults");
  ok((await db.Gyms.all()).every((gym) => !gym.barcodeImage), "fixture contains no membership barcode images");
  ok(progs.filter((p) => p.isActive).length === 1, "exactly one program active");
  ok(progs.some((p) => p.days.some((d) => (d.lifts || []).some((l) => l.pending))), "a mid-wave pending peak grade survives the round trip");
  ok(progs.some((p) => p.days.some((d) => (d.lifts || []).some((l) => (l.stallCount || 0) > 0))), "a stalled lift survives the round trip");

  const ms = await db.Milestones.all();
  ok(ms.some((m) => m.kind === "programNote" && /deload/i.test(m.label)), "the auto-deload program note is present");
  ok(ms.some((m) => m.kind === "heaviestSet"), "PR milestones are present");

  const tracks = await db.Tracks.all();
  ok(new Set(tracks.map((t) => t.mode)).size === 2, "both track modes present");
  ok(new Set(tracks.filter((t) => t.mode === "cycle").map((t) => t.nextPhase)).size >= 3, "cycle tracks sit at varied phases");
  ok((await db.Gyms.all()).length === 2, "two gyms (lb + kg plate inventories)");

  // The fixture must itself round-trip: import → re-export reproduces the
  // bundle EXACTLY (deep compare with sorted keys), minus the wall-clock
  // stamps the exporter refreshes. Catches dropped fields/stores, not just
  // counts.
  const stable = (v) => (v && typeof v === "object" && !Array.isArray(v))
    ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, stable(v[k])]))
    : Array.isArray(v) ? v.map(stable) : v;
  // The generated fixture is the current V3 portable contract. Importing and
  // re-exporting it must preserve every field, including coaching decisions
  // and immutable target/planned/performed snapshots.
  const canon = (bundle) => {
    bundle = structuredClone(bundle);
    if (bundle.settings) bundle.settings.gymTagFirstLaunchOfDay ??= false;
    for (const program of bundle.programs || []) for (const day of program.days || []) {
      (day.lifts || []).forEach((lift, index) => {
        lift.order ??= index;
        lift.prescription ??= "automatic";
        lift.warmupPolicy ??= "automatic";
      });
      (day.accessories || []).forEach((accessory, index) => {
        accessory.order ??= index;
        accessory.targetSeconds ??= 30;
        accessory.durationStepSeconds ??= 5;
      });
    }
    const b = stable(bundle);
    delete b.exportedAt; delete b.appVersion;
    if (b.settings) delete b.settings.seededAt;
    for (const t of b.tracks || []) delete t.lastCompletedAt;
    return JSON.stringify(b);
  };
  const again = await db.exportBundle();
  ok(canon(again) === canon(fixture), "fixture re-exports byte-for-byte (sans wall-clock stamps)");
}

// A session started by mistake must be removable from inside itself, not only
// from Today — the original trap was that neither Later, nor stopping the
// clock, nor banking got rid of it.
{
  const openId = await session.createBlankSession();
  await session.openSession(openId);
  await tick();
  const discardBtn = [...document.querySelectorAll("button")]
    .find((b) => (b.getAttribute("aria-label") || "").startsWith("Discard this session"));
  ok(discardBtn, "[INV-SESSION-ALWAYS-ESCAPABLE] a discard control is offered inside the session");
  ok(await db.Sessions.get(openId), "the session exists before discarding");
  await db.Sessions.del(openId);
  ok(!(await db.Sessions.get(openId)),
    "[INV-SESSION-ALWAYS-ESCAPABLE] discarding removes the session and nothing else");
  ok((await db.Sessions.completed()).length > 0,
    "[INV-SESSION-ALWAYS-ESCAPABLE] banked history survives a discard");
}

// The figure is only honest if every shipped exercise says what it trains.
// The movement-group fallback exists for user-created exercises; for seeded
// ones it was merely vague at best and wrong at worst — a leg curl inherited
// "hinge" and so claimed glutes, hip adduction inherited "squat".
{
  const anatomy = await import("../app/js/anatomy.js");
  const seeded = seededExercises.map((e) => e.name);
  const missing = seeded.filter((n) => !anatomy.MUSCLE_MAP[n]);
  ok(missing.length === 0,
    `[INV-ANATOMY-EXPLICIT] every seeded exercise has an explicit muscle profile (missing: ${missing.join(", ") || "none"})`);
  const named = new Set(Object.keys(anatomy.MUSCLE_NAMES));
  const unknown = Object.entries(anatomy.MUSCLE_MAP)
    .flatMap(([n, p]) => [...p.primary, ...p.secondary].filter((m) => !named.has(m)).map((m) => `${n}:${m}`));
  ok(unknown.length === 0, `[INV-ANATOMY-EXPLICIT] every cited muscle is a named muscle (${unknown.join(", ") || "none"})`);
  const drawn = new Set(anatomy.ANATOMY_REGIONS.map((r) => r.id));
  const undrawable = [...named].filter((m) => !drawn.has(m));
  ok(undrawable.length === 0,
    `[INV-ANATOMY-EXPLICIT] every named muscle has a region to highlight (${undrawable.join(", ") || "none"})`);
}

// Unprogrammed work inside a PROGRAM session is extra volume, not the main
// lift. A few light squats added to an upper day were being charted as main
// and dragged the squat progression down to a weight never worked as a main.
{
  const hist = await import("../app/js/views/history.js");
  const roleOf = hist.chartRoleOfForTest;
  const tagged = { programTag: { cycleNumber: 2, week: 3, dayIndex: 1 } };
  const untagged = {};
  ok(roleOf({ programRole: "main" }, tagged) === "main", "[INV-CHART-ROLE-EXCLUDES-EXTRA] a main slot is main");
  ok(roleOf({ programRole: "complementary" }, tagged) === "complementary",
    "[INV-CHART-ROLE-EXCLUDES-EXTRA] a complementary slot is complementary");
  ok(roleOf({ programRole: null }, tagged) === "extra",
    "[INV-CHART-ROLE-EXCLUDES-EXTRA] unprogrammed work in a program session is not main");
  ok(roleOf({ programRole: "accessory" }, tagged) === "extra",
    "[INV-CHART-ROLE-EXCLUDES-EXTRA] accessory work is not main");
  ok(roleOf({ programRole: null }, untagged) === "main",
    "[INV-CHART-ROLE-EXCLUDES-EXTRA] standalone work with no program IS the record for that lift");
}

// ---- progression chart: role split + combined metric ----
// A lift can be MAIN on one day and COMPLEMENTARY on another at a much lighter
// base. Drawing both as one line produced a sawtooth between two unrelated
// progressions; main must stay legible on its own.
{
  const { progressionChart, ROLE_DASH } = await import("../app/js/charts.js");
  const at = (day) => new Date(2026, 0, day).getTime();
  const main = [{ t: at(1), y: 225 }, { t: at(8), y: 235 }, { t: at(15), y: 245 }];
  const e1rm = [{ t: at(1), y: 253 }, { t: at(8), y: 264 }, { t: at(15), y: 260 }];
  const comp = [{ t: at(1), y: 185 }, { t: at(8), y: 190 }, { t: at(15), y: 195 }];
  const vol = [{ t: at(1), y: 5625 }, { t: at(8), y: 4700 }, { t: at(15), y: 2205 }];
  const chart = progressionChart({
    lines: [
      { key: "w", label: "Working weight", color: "#ef4444", points: main },
      { key: "e", label: "Est. 1RM", color: "#5BA06A", points: e1rm },
      { key: "c", label: "Working weight (comp.)", color: "#ef4444", dash: ROLE_DASH.complementary, points: comp },
    ],
    bars: { label: "Volume", color: "#8B9196", points: vol },
  });
  const svg = chart.querySelector("svg");
  const paths = [...svg.querySelectorAll("path.line")];
  ok(paths.length === 3, "every requested load line is drawn");
  ok(paths.filter((p) => (p.getAttribute("style") || "").includes("dasharray")).length === 1,
    "[INV-CHART-SPLITS-BY-ROLE] the complementary line is dashed so main stays visually dominant");
  const bars = [...svg.querySelectorAll("rect.vol-bar")].map((r) => +r.getAttribute("height"));
  ok(bars.length === 3 && bars[0] > bars[1] && bars[1] > bars[2],
    "volume bars track tonnage on their own scale");
  // The point of the combined view: tonnage is orders of magnitude larger, so
  // it must never stretch the load axis the two comparable lines share. The
  // load axis is the LEFT gutter; volume labels its own right-hand scale.
  const labelsAt = (keep) => [...svg.querySelectorAll("text.lbl")]
    .filter((t) => keep(+t.getAttribute("x"))).map((t) => Number(t.textContent))
    .filter(Number.isFinite);
  const loadAxis = labelsAt((x) => x < 20);
  ok(loadAxis.length > 0 && loadAxis.every((v) => v > 150 && v < 300),
    `[INV-VOLUME-KEEPS-ITS-OWN-SCALE] the load axis is scaled to the load lines, not to tonnage (${loadAxis.join()})`);
  ok(labelsAt((x) => x > 300).includes(5625), "[INV-VOLUME-KEEPS-ITS-OWN-SCALE] volume keeps its own right-hand scale");
  ok([...chart.querySelectorAll(".chart-legend span")].length === 4, "every series is named in the legend");
  const empty = progressionChart({ lines: [{ key: "x", points: [] }], bars: null });
  ok(empty.querySelectorAll("path.line").length === 0, "an empty series renders nothing rather than throwing");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
