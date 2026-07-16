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

// ---- seed ----
await db.ensureSeeded();
ok((await db.Exercises.all()).length === 47, "seeded 47 exercises");
ok((await db.Exercises.all()).every((e) => e.movementGroup), "every seeded exercise has a movement group");
ok((await db.Sessions.completed()).length === 10, "seeded 10 sessions");
ok((await db.Tracks.all()).length === 3, "seeded 3 tracks");
await db.ensureSeeded(); // idempotent
ok((await db.Sessions.completed()).length === 10, "re-seed is a no-op");

// ---- library sync tops up an already-seeded (older) install ----
{
  // Simulate an old install: blank a movement group and edit an exercise's
  // rest, then prove sync backfills the group WITHOUT clobbering the edit.
  const dl = await db.Exercises.byName("Deadlift");
  dl.movementGroup = ""; dl.defaultRestSeconds = 222; await db.Exercises.save(dl);
  await db.syncLibrary();
  ok((await db.Exercises.byName("Deadlift")).movementGroup === "hinge", "sync backfills a missing movement group");
  ok((await db.Exercises.byName("Deadlift")).defaultRestSeconds === 222, "sync does NOT clobber user edits");
  ok((await db.Exercises.all()).length === 47, "sync leaves the count whole (no dupes)");
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

// ---- full session flow: start Deadlift (peak 245×3×3), complete, expect PR + advance ----
const dl = (await db.Tracks.all()).find((t) => t.exerciseName === "Deadlift");
const id = await session.createSessionFromTrack(dl);
const created = await db.Sessions.get(id);
const work = created.exercises[0].sets.filter((s) => !s.isWarmup);
const warm = created.exercises[0].sets.filter((s) => s.isWarmup);
ok(warm.length === 5 && warm[0].weightLb === 45, "deadlift got a warmup ramp");
ok(work.length === 3 && work.every((s) => s.weightLb === 245 && s.reps === 3), "3 working sets at 245×3");

await session.openSession(id); await tick();
const overlayButtons = () => [...document.querySelectorAll("#overlays .overlay button")];
ok(overlayButtons().some((b) => b.textContent === "Rest"), "per-exercise Rest button present in logger");
ok(overlayButtons().some((b) => b.textContent.startsWith("⏱")), "per-exercise rest chip shows duration");
ok(document.querySelector("#overlays .overlay svg.barbell"), "barbell plate visualization renders for a barbell lift");
ok([...document.querySelectorAll("#overlays .overlay select.bar-select option")].some((o) => o.textContent.includes("45 lb")), "bar selector offers 45 lb");
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
ok(ms.some((m) => m.exerciseName === "Deadlift" && m.kind === "heaviestSet" && m.label.includes("245")), "245 heaviest-set milestone logged");

// ---- export / import round trip ----
const json = await db.exportJSON();
const parsed = JSON.parse(json);
ok(parsed.sessions.length === 11 && Array.isArray(parsed.milestones), "export bundle shape");
ok(Array.isArray(parsed.tracks) && parsed.tracks.length === 3, "export carries lift tracks");
ok(Array.isArray(parsed.gyms) && parsed.gyms.length > 0, "export carries gyms");
ok(Array.isArray(parsed.exercises) && parsed.exercises.length === 47, "export carries the exercise library");
ok(parsed.settings && parsed.settings.unitDisplay === "lbPrimary" && parsed.settings.id === undefined, "export carries settings (sans row id)");
ok(parsed.settings.theme === "carbon", "theme defaults to carbon and round-trips");
ok(parsed.settings.rest && parsed.settings.rest.mainCompoundSeconds === 300, "export carries the nested rest buckets");
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
}

// ---- cardio sets: distance/time/incline, not weight×reps ----
{
  // A Walk (type conditioning) logs the 12-3-30: 3 mi, 45 min, 12% incline.
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
  const again = await session.completeSession(done);
  ok(again.lines.length === 0 && again.milestones.length === 0, "re-completing a banked session is a no-op");
  ok((await db.Milestones.all()).length === msBefore, "no duplicate milestones from re-completion");
}

// ---- the same tracked exercise in two sections advances the track twice ----
// (native parity: SwiftData mutates one context-cached object per section)
{
  const before = (await db.Tracks.byName("Incline DB Press")).baseWeightLb; // linear, +5/session
  const sec = (order) => ({
    order, exerciseName: "Incline DB Press", notes: "", phase: null, programRole: null,
    plannedWeightLb: null, plannedSets: null, plannedReps: null,
    sets: [{ order: 0, weightLb: before, reps: 5, isWarmup: false, isPerSide: false, enteredUnit: "lb",
             flags: ["clean"], bodyFlagSite: null, bodyFlagNote: null, durationSeconds: null, distanceMiles: null, autoregReason: null }],
  });
  const sid = await db.Sessions.save({ date: db.iso(new Date()), notes: "", isCompleted: false, gymName: null, exercises: [sec(0), sec(1)] });
  await session.completeSession(await db.Sessions.get(sid));
  const after = (await db.Tracks.byName("Incline DB Press")).baseWeightLb;
  ok(after === before + 10, `duplicate sections advance the track twice (${before}→${after})`);
}

// ---- protein add reflects in today's total ----
await db.Protein.add({ date: new Date().toISOString(), grams: 45, label: "Shake" });
ok((await db.Protein.todayTotal()) >= 45, "protein logged for today");

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
  await session.completeSession(built); // i=0 banked (Lower A, week 1)

  for (let i = 1; i < 16; i++) {        // remaining of 4 weeks × 4 days
    prog = await db.Programs.active();
    const day = prog.days.find((d) => d.order === prog.nextDayIndex);
    const id = await session.createSessionFromProgramDay(prog, day);
    const sess = await db.Sessions.get(id);
    await session.completeSession(sess); // pre-filled working sets at target = a clean cycle
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
    await session.completeSession(sess);
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
  await session.completeSession(sess);
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
  await session.completeSession(sess1);
  prog = await db.Programs.active();
  const graded1 = prog.days.find((d) => d.order === day1.order).lifts.find((l) => l.role === "main");
  ok(graded1.pending && graded1.pending.grade === "success", "at-plan peak with a lighter back-off set still grades clean");

  // Bank the rest of the wave cleanly (2 more peak days + the 4 deload days);
  // rollover applies the stashed grades.
  for (let i = 0; i < 6; i++) {
    const p = await db.Programs.active();
    const day = p.days.find((d) => d.order === p.nextDayIndex);
    const s = await db.Sessions.get(await session.createSessionFromProgramDay(p, day));
    await session.completeSession(s);
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
    await session.completeSession(await db.Sessions.get(await session.createSessionFromProgramDay(p, day)));
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
  await session.completeSession(await db.Sessions.get(idA));
  prog = await db.Programs.active();
  ok(prog.currentWeek === week0 + 1 && prog.nextDayIndex === 0, "first bank advances exactly one week");
  const accReps = prog.days[3].accessories.length ? prog.days[3].accessories[0].currentReps : null;
  await session.completeSession(await db.Sessions.get(idB));
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
    await session.completeSession(sess);
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
  const exLift = exported.programs.find((p) => p.id === prog.id).days.find((d) => d.order === 0).lifts.find((l) => l.role === "main");
  ok(exLift.revertToExerciseName === originalLift, "cycle-swap marker survives web export");

  const startCycle = prog.cycleNumber;
  for (let i = 0; i < 16 && (await db.Programs.active()).cycleNumber === startCycle; i++) {
    const p = await db.Programs.active();
    const day = p.days.find((d) => d.order === p.nextDayIndex);
    await session.completeSession(await db.Sessions.get(await session.createSessionFromProgramDay(p, day)));
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


// ---- synthetic fixture: the broad-coverage dataset must import cleanly ----
// (Runs LAST — importing the fixture replaces the seeded stores. The fixture
// is generated by tools/generate-synthetic-backup.mjs and doubles as the
// cross-platform backup-schema regression lock: the same file restores into
// the iOS app via ImportService.)
{
  const fs = await import("node:fs");
  const fixture = JSON.parse(fs.readFileSync(new URL("./fixtures/synthetic-backup.json", import.meta.url), "utf8"));
  await db.importBundle(fixture);
  const sessions = await db.Sessions.completed();
  ok(sessions.length >= 75, `fixture carries a deep log (${sessions.length} sessions)`);

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
  const canon = (bundle) => {
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
