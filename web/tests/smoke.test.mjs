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

const db = await import("../js/db.js");
const home = await import("../js/views/home.js");
const history = await import("../js/views/history.js");
const body = await import("../js/views/body.js");
const signals = await import("../js/views/signals.js");
const settings = await import("../js/views/settings.js");
const session = await import("../js/views/session.js");
const plates = await import("../js/views/plates.js");
const barbell = await import("../js/barbell.js");
const C = await import("../js/core.js");
const coach = await import("../js/coaching-adapter.js");
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
  ok(achieved.every((set) => C.solve(set.weightLb, C.BARS.bar45lb,
    rack.plateToggles.filter((toggle) => toggle.enabled), 10, 5, "closest").totalLb === set.weightLb),
    "every generated warmup is achievable on the configured rack");
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

const serviceWorkerSource = await (await import("node:fs/promises")).readFile(
  new URL("../sw.js", import.meta.url), "utf8");
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
ok(warm.length === 5 && warm[0].weightLb === 45, "deadlift got a warmup ramp");
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
ok(withBarOverride.exercises[0].sets.filter((s) => s.isWarmup)[0].weightLb === 35,
  "bar override keeps the warmup ramp in the same equipment context");
ok(document.querySelector("#session-bar .clock").textContent.includes("session"), "session clock shows in the sticky bottom bar");
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

// ---- exact prior slot repairs a stale next target; extras stay extra ----
{
  const name = "Fixture Exact Prior Slot";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 7, currentWeek: 3, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower B", order: 0,
      lifts: [cyc("Back Squat", "main", 150, 240), cyc("Deadlift", "complementary", 180, 250)],
      accessories: [] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const day = program.days[0];
  const squat = day.lifts.find((lift) => lift.role === "main");
  const workSet = (order, weightLb) => ({
    order, weightLb, reps: 3, plannedWeightLb: weightLb, plannedReps: 3,
    isWarmup: false, status: "completed", flags: [], bodyFlagSite: null,
    autoregReason: null, prescriptionBlock: "work",
  });
  const exactSets = Array.from({ length: 5 }, (_, index) => workSet(index, 215));
  // Appended volume and a separate slotless Squat entry are both explicitly
  // extra. Neither can become the program's prior exposure.
  exactSets.push(workSet(5, 315));
  const priorId = await db.Sessions.save({
    date: "2026-07-12T12:00:00.000Z", completedAt: "2026-07-12T13:00:00.000Z",
    notes: "Fictional exact-slot regression fixture", isCompleted: true,
    programTag: { programId: program.uuid, programName: name, cycleNumber: 7,
      week: 2, dayIndex: 0, planNames: ["Back Squat", "Deadlift"] },
    exercises: [
      { order: 0, exerciseName: "Back Squat", programRole: "main", programSlotId: "retired-lower-b-main",
        plannedSets: 5, plannedReps: 3, plannedWeightLb: 215, sets: exactSets },
      { order: 2, exerciseName: "Back Squat", programRole: null, programSlotId: null,
        plannedSets: 1, plannedReps: 1, plannedWeightLb: 405, sets: [workSet(0, 405)] },
    ],
  });
  const distractionId = await db.Sessions.save({
    date: "2026-07-13T12:00:00.000Z", completedAt: "2026-07-13T13:00:00.000Z",
    notes: "Fictional later accessory-only exposure", isCompleted: true,
    programTag: { programId: program.uuid, programName: name, cycleNumber: 7,
      week: 2, dayIndex: 0, planNames: ["Back Squat"] },
    exercises: [
      { order: 0, exerciseName: "Back Squat", programRole: "accessory",
        programSlotId: "conditioning-squat", plannedSets: 3, plannedReps: 10,
        plannedWeightLb: 135, sets: Array.from({ length: 3 }, (_, index) => ({
          ...workSet(index, 135), reps: 10, plannedReps: 10,
        })) },
    ],
  });
  const staleOpenId = await db.Sessions.save({
    date: "2026-07-19T12:00:00.000Z", notes: "Fictional stale preview fixture", isCompleted: false,
    programTag: { programId: program.uuid, programName: name, cycleNumber: 7,
      week: 3, dayIndex: 0, planNames: ["Back Squat", "Deadlift"] },
    exercises: [{ order: 0, exerciseName: "Back Squat", programRole: "main", programSlotId: squat.id,
      targetWeightLb: 175, plannedWeightLb: 175, plannedSets: 3, plannedReps: 3,
      sets: Array.from({ length: 3 }, (_, index) => ({ ...workSet(index, 175), status: "planned" })) }],
  });

  const repairedId = await session.createSessionFromProgramDay(program, day);
  const repaired = await db.Sessions.get(repairedId);
  const repairedSquat = repaired.exercises.find((entry) => entry.programSlotId === squat.id);
  ok(repairedId !== staleOpenId, "a stale open target is rebuilt after exact-slot history repairs the plan");
  ok(repairedSquat.targetWeightLb === 230,
    `clean 5x3 at 215 drives the next programmed Squat exposure (got ${repairedSquat.targetWeightLb})`);
  await session.openSession(repairedId); await tick();
  const activeOverlay = [...document.querySelectorAll("#overlays .overlay")].at(-1);
  const recallText = activeOverlay?.textContent || "";
  ok(recallText.includes("Last main Lower B:") && recallText.includes("215 lb×3"),
    `logger recall names the exact role/day and shows its prescribed work (${recallText})`);
  ok(!recallText.includes("315 lb×3") && !recallText.includes("405 lb×3"),
    "logger recall ignores appended and slotless extra Squat work");
  activeOverlay?.querySelector(".overlay-head button")?.click(); await tick();
  for (const entry of repaired.exercises) {
    for (const set of entry.sets || []) if (!set.isWarmup) set.status = "skipped";
  }
  repaired.exercises.push({
    order: repaired.exercises.length, exerciseName: "Back Squat", programRole: null,
    programSlotId: null, plannedSets: 1, plannedReps: 1, plannedWeightLb: 405,
    sets: [{ ...workSet(0, 405), status: "completed" }],
  });
  await session.completeSession(repaired);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.currentWeek === 3 && program.nextDayIndex === 0,
    "banking only extra work does not advance the program day or phase");
  ok(program.days[0].lifts.find((lift) => lift.id === squat.id).baseWeightLb === 195,
    "the repaired exact-slot base is persisted for preview/session parity");

  await db.Sessions.del(priorId); await db.Sessions.del(distractionId);
  await db.Sessions.del(staleOpenId); await db.Sessions.del(repairedId);
  await db.Programs.del(program.id);
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
  const { PROGRAM_TEMPLATES, createProgramFromTemplate } = await import("../js/templates.js");
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
  const A = await import("../js/anatomy.js");
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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
