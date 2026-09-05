// Runtime smoke test under jsdom + fake-indexeddb: seeds, renders every view,
// and drives a real session-completion flow (PR detection + track advance) and
// an export/import round trip. Run: node tests/smoke.test.mjs
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";
import { withCleanup } from "./fixture-cleanup.mjs";

const dom = new JSDOM(`<!doctype html><html><body>
  <header id="topbar"><h1 id="screen-title"></h1><div id="topbar-actions"></div></header>
  <main id="view"></main><button id="fab"></button><nav id="tabbar"></nav>
  <div id="overlays"></div><div id="toast"></div></body></html>`,
// localStorage needs a real origin (opaque about:blank has none) — the app
// itself is served from /cadence/app/, so any http origin is faithful here.
{ url: "http://localhost/cadence/app/" });
global.window = dom.window;
global.document = dom.window.document;
global.FileReader = dom.window.FileReader;
global.Node = dom.window.Node;
global.localStorage = dom.window.localStorage;

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.error("FAIL:", m); } };
const tick = () => new Promise((r) => setTimeout(r, 60));
const host = () => document.getElementById("view");

const db = await import("../app/js/db.js");
const home = await import("../app/js/views/home.js");
const programView = await import("../app/js/views/program.js");
const history = await import("../app/js/views/history.js");
const body = await import("../app/js/views/body.js");
const signals = await import("../app/js/views/signals.js");
const settings = await import("../app/js/views/settings.js");
const session = await import("../app/js/views/session.js");
const plates = await import("../app/js/views/plates.js");
const activity = await import("../app/js/views/activity.js");
const barbell = await import("../app/js/barbell.js");
const ui = await import("../app/js/ui.js");
const C = await import("../app/js/core.js");
const coach = await import("../app/js/coaching-adapter.js");
const completeAll = async (workout) => {
  for (const exercise of workout.exercises || []) for (const set of exercise.sets || []) if (!set.isWarmup) set.status = "completed";
  return session.completeSession(workout);
};

{
  const adjusted = history.historySetPresentationForTest({
    weightLb: 215, reps: 3, plannedWeightLb: 225, plannedReps: 5,
    status: "completed", isWarmup: false, isPerSide: false, prescriptionBlock: "work",
  }, "barbell");
  ok(adjusted.actual.includes("215") && adjusted.planned?.includes("225") && adjusted.planned.includes("5"),
    "completed-history rows keep performed work primary and expose a changed prescription");
  const unchanged = history.historySetPresentationForTest({
    weightLb: 225, reps: 5, plannedWeightLb: 225, plannedReps: 5,
    status: "completed", isWarmup: false, isPerSide: false, prescriptionBlock: "amrap",
  }, "barbell");
  ok(unchanged.planned === null && unchanged.kind === "AMRAP",
    "unchanged history stays terse while preserving the set's prescription kind");

  const completed = (count, fields = {}) => Array.from({ length: count }, () => ({
    status: "completed", isWarmup: false, weightLb: 0, reps: 1, ...fields,
  }));
  const exerciseByName = new Map([
    ["Back Squat", { type: "barbell" }],
    ["Run-Walk Intervals", { type: "conditioning" }],
    ["Plank", { type: "timed" }],
  ]);
  const mixedSession = { exercises: [
    { exerciseName: "Back Squat", sets: [...completed(3), { ...completed(1)[0], isWarmup: true }] },
    { exerciseName: "Run-Walk Intervals", sets: completed(4, { durationSeconds: 60 }) },
    { exerciseName: "Plank", sets: completed(2, { durationSeconds: 30 }) },
    // Missing library metadata still has enough stored data to stay out of the
    // strength count after an exercise is deleted.
    { exerciseName: "Deleted conditioning", sets: completed(1, { distanceMiles: 1 }) },
  ] };
  ok(history.completedStrengthSetCountForTest(mixedSession, exerciseByName) === 3,
    "session history counts lifting work without relabeling conditioning intervals as work sets");
}

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
ok(seededExercises.length === 159, "seeded 159 exercises");
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

// Ad-hoc work uses the ordinary history timeline but owns a deliberately
// off-program shape: one completed duration set, no bar, role, or program tag
// [INV-WOOD-WORK-USES-ONE-TIMELINE]. The builder is the web write-site guard,
// mirroring native ActivitySession.create/update.
{
  const wood = await db.Exercises.byName("Wood Splitting");
  const built = activity.buildActivitySession({
    kind: "woodSplitting", startDate: new Date("2026-01-17T14:00:00Z"),
    durationSeconds: 7_200, sessionRPE: 8.5, loadLb: 8,
    enteredUnit: "lb", notes: "Oak rounds",
    woodSplitting: { rounds: 55, splitPieces: 15, estimatedStrikes: 340, cordVolume: 0.25 },
  }, wood);
  const set = activity.activitySet(built);
  ok(built.isCompleted && built.programTag === null && built.activity.kind === "woodSplitting"
    && built.exercises.length === 1 && set.status === "completed" && set.durationSeconds === 7_200,
  "the quick logger builds one completed off-program duration exposure");
  ok(set.weightLb === 8 && set.enteredUnit === "lb" && set.reps === 0 && set.loadBasis === "externalTotal",
    "maul weight remains an exact implement fact instead of lifting volume");
  ok(C.activityWorkload(activity.activityDurationSeconds(built), built.activity.sessionRPE)?.arbitraryUnits === 1_020,
    "wood workload is duration × session effort, independent of maul weight");
  const edited = activity.buildActivitySession({
    kind: "woodSplitting", startDate: new Date("2026-01-17T14:00:00Z"),
    durationSeconds: 7_500, sessionRPE: 9, loadLb: C.lbFromKg(4), enteredUnit: "kg",
    notes: "More oak", woodSplitting: { rounds: 60 },
  }, wood, built);
  ok(edited.id === built.id && activity.activitySet(edited).enteredUnit === "kg"
    && edited.activity.rounds === 60 && edited.activity.splitPieces === null,
  "editing preserves identity and exact entered unit without inventing uncounted wood facts");
  const rejects = (input) => {
    try { activity.buildActivitySession(input, wood); return false; } catch { return true; }
  };
  ok(rejects({ kind: "woodSplitting", startDate: new Date(), durationSeconds: 0 }),
    "ad-hoc work refuses a zero-duration record");
  ok(rejects({ kind: "woodSplitting", startDate: new Date(), durationSeconds: 60, sessionRPE: 11 }),
    "ad-hoc work refuses an out-of-contract session RPE");
  ok(rejects({ kind: "woodSplitting", startDate: new Date(), durationSeconds: 60, woodSplitting: { rounds: -1 } }),
    "ad-hoc work refuses a negative count, matching the backup validators");
  ok(rejects({ kind: "hiking", startDate: new Date(), durationSeconds: 60 }),
    "ad-hoc work refuses an unregistered kind");
  let driftedRejected = false;
  try {
    activity.buildActivitySession({ kind: "woodSplitting", startDate: new Date(), durationSeconds: 60 }, wood,
      { ...built, exercises: [...built.exercises, { exerciseName: "Back Squat", sets: [] }] });
  } catch { driftedRejected = true; }
  ok(driftedRejected, "editing refuses a record that drifted from the one-entry, one-set shape instead of truncating it");
  ok(activity.activityDurationLabel(59 * 60 + 31) === "59 min",
    "duration labels floor to whole minutes like native, never rounding 59m31s up to an hour");
  ok(activity.wholeMinuteSeconds("1.1", "0") === 3600 && activity.wholeMinuteSeconds("0", "0.5") === 0
    && activity.wholeMinuteSeconds("", "45") === 2700 && activity.wholeMinuteSeconds("-2", "10") === 600,
  "the form floors decimal hours and minutes to whole minutes, matching native's steppers");
  await activity.openActivityLog(); await tick();
  const activityOverlay = document.querySelector("#overlays .overlay");
  ok(activityOverlay?.textContent.includes("Physical work, not a training session")
    && activityOverlay?.textContent.includes("never advances a cycle"),
  "the logger states its off-program boundary before anything is banked");
  activityOverlay?.querySelector(".overlay-head button")?.click();
}

// Recover an install missing its seed stamp without touching user-owned data.
await withCleanup(async (keep) => {
  const sentinelId = keep(db.Sessions, await db.Sessions.save({
    date: "2000-01-01T00:00:00.000Z", notes: "Fictional seed-repair sentinel",
    isCompleted: true, gymName: "Main Gym", exercises: [],
  }));
  const weighInId = keep(db.Bodyweight, await db.Bodyweight.add({ date: "2000-01-01T00:00:00.000Z", weightLb: 199 }));
  const s = await db.Settings.get(); s.seededAt = null; await db.Settings.save(s);
  await db.ensureSeeded();
  ok((await db.Sessions.all()).some((workout) => workout.id === sentinelId), "seed repair preserves workout history");
  ok((await db.Exercises.all()).length === 159, "seed repair does not duplicate exercises");
  ok((await db.Bodyweight.all()).some((entry) => entry.id === weighInId), "seed repair preserves other user stores");
})();

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
  const fullBar = barbell.barbellSVG(135, "lb", C.BARS.bar45lb, legacyRack, null, null, "full").svg;
  ok(fullBar.classList.contains("full") && fullBar.querySelectorAll("rect").length > 6,
    "plate calculator can render the solved load across the complete mirrored bar");
  const fullPlateRects = [...fullBar.querySelectorAll("rect")].filter((rect) => rect.getAttribute("stroke"));
  ok(fullPlateRects.length > 0 && fullPlateRects.length % 2 === 0,
    "every solved plate is drawn once on each side");
  const mixedBar = barbell.barbellSVG(195, "lb", C.BARS.bar45lb,
    { ...legacyRack, collarWeightLb: 0 }, null, null, "full").svg;
  const leftStack = [...mixedBar.querySelectorAll('.barbell-plate[data-side="left"]')];
  const rightStack = [...mixedBar.querySelectorAll('.barbell-plate[data-side="right"]')];
  const plateValues = (stack) => stack.map((plate) => Number(plate.dataset.plateValue));
  const plateXs = (stack) => stack.map((plate) => Number(plate.getAttribute("x")));
  ok(JSON.stringify(plateValues(leftStack)) === JSON.stringify([45, 25, 5])
    && JSON.stringify(plateValues(rightStack)) === JSON.stringify([45, 25, 5]),
  "mixed plate stacks are ordered from each collar outward, not copied left to right across the screen");
  ok(plateXs(leftStack).every((x, index, xs) => index === 0 || x < xs[index - 1])
    && plateXs(rightStack).every((x, index, xs) => index === 0 || x > xs[index - 1]),
  "left and right sleeve coordinates mirror while preserving the same collar-first load order");
  const bumperBar = barbell.barbellSVG(195, "lb", C.BARS.bar45lb,
    { ...legacyRack, collarWeightLb: 0 }, null, null, "full", "bumper").svg;
  const bumperRight = [...bumperBar.querySelectorAll('.barbell-plate[data-side="right"]')];
  ok(Number(bumperRight[0].getAttribute("height")) === Number(bumperRight[1].getAttribute("height"))
    && Number(rightStack[0].getAttribute("height")) > Number(rightStack[1].getAttribute("height")),
  "bumper plates keep competition diameter while calibrated steel steps down by denomination");
  ok(bumperBar.querySelectorAll("ellipse.barbell-plate-face").length === bumperRight.length * 2
    && bumperBar.querySelectorAll("ellipse.barbell-plate-hub").length === bumperRight.length * 2
    && bumperBar.querySelectorAll("text.barbell-plate-label").length >= bumperRight.length * 2,
  "plate bodies have disc faces, steel hubs, rims, and denomination marks rather than flat blocks");
  ok(fullBar.querySelector("linearGradient#cadence-bar-steel") && fullBar.querySelectorAll("line.barbell-knurl").length > 10,
    "the calculator bar uses reflective steel and real knurl detail rather than flat blocks");
  ok(fullBar.getAttribute("viewBox") === "0 0 340 96",
    "the complete bar has enough vertical canvas for plates to be legible on a phone");
  const plateBadge = barbell.plateBadgeSVG({ value: 20, unit: "kg" }, "steel");
  ok(plateBadge.getAttribute("aria-label") === "20 kg plate"
    && plateBadge.textContent.includes("20") && plateBadge.textContent.includes("kg")
    && plateBadge.querySelectorAll("circle").length >= 2,
  "calculator rows use a large face-on plate key with visible denomination and unit");
  ok(barbell.plateBadgeSVG({ value: 1.25, unit: "kg" }, "steel").textContent.includes("1.25"),
    "fractional plate badges preserve the exact denomination instead of rounding to one decimal");
  const collarsOnly = barbell.barbellSVG(50, "lb", C.BARS.bar45lb, legacyRack,
    null, null, "full").svg;
  ok(collarsOnly.querySelectorAll("rect.barbell-lock-collar").length === 2,
    "a collar-only full bar draws one lock collar on each sleeve");
  ok(collarsOnly.textContent.includes("bar + collars") && !collarsOnly.textContent.includes("bar only")
    && collarsOnly.getAttribute("aria-label").includes("with collars, no plates")
    && !collarsOnly.getAttribute("aria-label").includes("bar only"),
  "a collar-only load is labeled as bar plus collars visually and accessibly");
  const compactCollarsOnly = barbell.barbellSVG(50, "lb", C.BARS.bar45lb, legacyRack).svg;
  ok(compactCollarsOnly.querySelectorAll("rect.barbell-lock-collar").length === 1
    && compactCollarsOnly.textContent.includes("bar + collars"),
  "the compact one-sleeve load also shows its collar instead of claiming bar only");
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
await withCleanup(async (keep) => {
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
  keep(db.CoachingDecisions, decision.id);
  await db.Programs.saveWithDecision(proposed, decision);
  ok((await db.Programs.active()).preferredSessionSpacingDays === 2
      && (await db.CoachingDecisions.all()).some((item) => item.id === decision.id),
    "program mutation and accepted-decision audit commit together");
  await db.Programs.save(original);
})();

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

  const manuallyChanged = structuredClone(original);
  const liveSlot = manuallyChanged.days.flatMap((day) => day.lifts || [])
    .find((item) => item.id === slot.id);
  const manualReplacement = seededExercises.find((candidate) =>
    candidate.name !== before.name && C.swapCompatible(from, candidate));
  ok(!!manualReplacement, "the fixture has a compatible manual replacement");
  liveSlot.exerciseName = manualReplacement.name;
  refused = false;
  try {
    await coach.applyCoachingRecommendation(manuallyChanged, {
      id: "rotate-stale", ruleID: "program.slot.rotate.stalled", title: "Stuck",
      explanation: "Fixture recommendation",
      change: { type: "rotateExercise", slotID: slot.id, exerciseName: before.name },
    }, seededExercises);
  } catch { refused = true; }
  ok(refused && liveSlot.exerciseName === manualReplacement.name,
    "a stale recommendation never overwrites a manual slot change");
}

// A program-level equipment boundary applies to automatic coaching changes.
// The alphabetically first compatible candidate is deliberately a machine so
// this proves the adapter filters before its deterministic ranking.
{
  const program = {
    equipmentPolicy: "freeWeightsOnly", roundingLb: 5,
    days: [{ name: "Anchor", lifts: [{
      id: "policy-lift", exerciseName: "Current Squat", role: "main",
      prescription: "automatic", baseWeightLb: 100, estimatedMaxLb: 150,
      stallCount: 1, lastIncrementLb: 0,
    }], accessories: [] }],
  };
  const exercises = [
    { name: "Current Squat", category: "Main", type: "barbell", movementGroup: "squat" },
    { name: "A Machine Squat", category: "Main", type: "machine", movementGroup: "squat" },
    { name: "Z Free Squat", category: "Main", type: "barbell", movementGroup: "squat" },
  ];
  await coach.applyCoachingRecommendation(program, {
    id: "rotate-policy", ruleID: "program.slot.rotate.stalled", title: "Stuck",
    explanation: "Fixture recommendation",
    change: { type: "rotateExercise", slotID: "policy-lift", exerciseName: "Current Squat" },
  }, exercises);
  ok(program.days[0].lifts[0].exerciseName === "Z Free Squat",
    "a free-weight program never accepts a machine coaching substitution");
}

// The vertical-pull promotion crosses the tier: the machine accessory retires
// and the day gains the template's pull-up slot — complementary double
// progression born at bodyweight. Programs predating the vertical-pull
// template change (issue #126) have no other upgrade path, because no
// migration rewrites an authored program.
{
  const original = await db.Programs.active();
  const proposed = structuredClone(original);
  const day = proposed.days[0];
  // Shape the day like a pre-#126 program: no pull-up lift, a machine pull
  // accessory, and deliberately noncontiguous authored lift orders.
  day.lifts = (day.lifts || []).filter((slot) => slot.exerciseName !== "Pull-ups");
  day.lifts.forEach((slot, index) => { slot.order = index === 0 ? 0 : 5; });
  day.accessories = [...(day.accessories || []), { id: "legacy-pulldown", exerciseName: "Lat Pulldown",
    order: (day.accessories || []).length, sets: 4, minReps: 8, maxReps: 12, currentReps: 8,
    weightLb: 120, incrementLb: 5, stallCount: 0, capacityManaged: true, maximumSets: 6 }];
  const message = await coach.applyCoachingRecommendation(proposed, {
    id: "promote-recommendation", ruleID: "program.day.vertical-pull-tier.v1",
    title: "Train the pull as lift work", explanation: "Fixture recommendation",
    change: { type: "promoteVerticalPull", dayIndex: day.order ?? 0,
      accessorySlotIDs: ["legacy-pulldown"], accessoryNames: ["Lat Pulldown"] },
  }, seededExercises);
  ok(!day.accessories.some((slot) => slot.id === "legacy-pulldown"),
    "the machine vertical pull retires from the day");
  ok(day.accessories.every((slot, index) => slot.order === index),
    "surviving accessories are renumbered");
  const added = (day.lifts || []).find((slot) => slot.exerciseName === "Pull-ups" && slot.role === "complementary");
  ok(!!added && added.prescription === "doubleProgression"
    && added.doubleProgressionSets === 3 && added.baseWeightLb === 0,
    "the day gains the template's pull-up slot: complementary double progression at bodyweight");
  ok(added.order === 6,
    `the promoted slot appends after the highest authored order (got ${added.order})`);
  ok(message.includes("Lat Pulldown") && message.includes("Pull-ups"),
    `the result names both sides of the promotion (${message})`);

  // A stale offer stays safe: the day already trains pull-ups at the lift
  // tier, so a second apply retires the accessory without duplicating the
  // slot.
  day.accessories = [...day.accessories, { id: "legacy-pulldown-2", exerciseName: "Lat Pulldown",
    order: day.accessories.length, sets: 4, minReps: 8, maxReps: 12, currentReps: 8,
    weightLb: 120, incrementLb: 5, stallCount: 0, capacityManaged: true, maximumSets: 6 }];
  await coach.applyCoachingRecommendation(proposed, {
    id: "promote-stale", ruleID: "program.day.vertical-pull-tier.v1",
    title: "Train the pull as lift work", explanation: "Fixture recommendation",
    change: { type: "promoteVerticalPull", dayIndex: day.order ?? 0,
      accessorySlotIDs: ["legacy-pulldown-2"], accessoryNames: ["Lat Pulldown"] },
  }, seededExercises);
  ok((day.lifts || []).filter((slot) => slot.exerciseName === "Pull-ups").length === 1
    && !day.accessories.some((slot) => slot.id === "legacy-pulldown-2"),
    "a stale offer retires the accessory without duplicating the pull-up slot");

  // Without pull-ups in the library the promotion refuses rather than
  // guessing — same posture as a rotation with no compatible variation.
  let refused = false;
  try {
    await coach.applyCoachingRecommendation(structuredClone(original), {
      id: "promote-no-pullups", ruleID: "program.day.vertical-pull-tier.v1",
      title: "Train the pull as lift work", explanation: "Fixture recommendation",
      change: { type: "promoteVerticalPull", dayIndex: 0, accessorySlotIDs: ["x"], accessoryNames: ["Lat Pulldown"] },
    }, seededExercises.filter((item) => item.name !== "Pull-ups"));
  } catch { refused = true; }
  ok(refused, "a library without pull-ups refuses the promotion");
}

// Max-effort rotation follows the seeded special-exercise sequence and gives
// the replacement its own target instead of inheriting the outgoing lift.
{
  const proposed = {
    roundingLb: 5,
    days: [{ name: "ME Lower", lifts: [{
      id: "me-lower", exerciseName: "Low Box Squat", role: "main",
      prescription: "maxEffort", baseWeightLb: 365, estimatedMaxLb: 405,
      stallCount: 0, lastIncrementLb: 10,
    }], accessories: [] }],
  };
  const history = [{ isCompleted: true, exercises: [{ exerciseName: "Front Box Squat", sets: [
    { weightLb: 350, reps: 1, isWarmup: false, status: "completed",
      prescriptionBlock: "work", flags: ["grindy"] },
    { weightLb: 315, reps: 1, isWarmup: false, status: "completed",
      prescriptionBlock: "work", flags: ["clean"] },
  ] }] }];
  await coach.applyCoachingRecommendation(proposed, {
    id: "rotate-me-weekly", ruleID: "program.slot.rotate.max-effort-weekly.v2",
    title: "Rotate Low Box Squat", explanation: "Fixture recommendation",
    change: { type: "rotateExercise", slotID: "me-lower", exerciseName: "Low Box Squat" },
  }, seededExercises, history);
  const rotated = proposed.days[0].lifts[0];
  ok(rotated.exerciseName === "Front Box Squat",
    "max-effort rotation follows the authored special-exercise sequence");
  ok(rotated.baseWeightLb === 325,
    "a returning variation uses its clean 315 single, not the outgoing target or a grindy 350");
  ok(rotated.stallCount === 0 && rotated.lastIncrementLb === 0,
    "the new variation starts without inherited stall or earned-increment state");
}

// An accepted linear-stage recommendation mutates only the proposed slot and
// leaves an explicit strategy-stage value in the audit record.
{
  const original = await db.Programs.active();
  const proposed = structuredClone(original);
  const slot = proposed.days.flatMap((day) => day.lifts || [])[0];
  slot.prescription = "linearFives";
  slot.doubleProgressionSets = 3;
  slot.currentReps = 5;
  slot.stallCount = 0;
  const recommendation = {
    id: "linear-triples-recommendation", ruleID: "program.slot.linear-triples.v1",
    title: "Move to triples", explanation: "Synthetic rebuild evidence",
    change: {
      type: "useLinearTriples", slotID: slot.id, exerciseName: slot.exerciseName,
      expectedBaseWeightLb: slot.baseWeightLb,
    },
  };

  const swappedProgram = structuredClone(proposed);
  const swappedSlot = swappedProgram.days.flatMap((day) => day.lifts || [])
    .find((candidate) => candidate.id === slot.id);
  swappedSlot.exerciseName = "Barbell Bench Press";
  let swappedRefused = false;
  try { await coach.applyCoachingRecommendation(swappedProgram, recommendation, seededExercises); }
  catch { swappedRefused = true; }
  ok(swappedRefused && swappedSlot.doubleProgressionSets === 3 && swappedSlot.currentReps === 5,
    "a recommendation cannot mutate a different exercise swapped into the same slot");

  const reloadedProgram = structuredClone(proposed);
  const reloadedSlot = reloadedProgram.days.flatMap((day) => day.lifts || [])
    .find((candidate) => candidate.id === slot.id);
  reloadedSlot.baseWeightLb += 5;
  let reloadedRefused = false;
  try { await coach.applyCoachingRecommendation(reloadedProgram, recommendation, seededExercises); }
  catch { reloadedRefused = true; }
  ok(reloadedRefused && reloadedSlot.doubleProgressionSets === 3 && reloadedSlot.currentReps === 5,
    "a recommendation cannot overwrite a slot whose base changed after evaluation");

  const lockedProgram = structuredClone(proposed);
  const lockedSlot = lockedProgram.days.flatMap((day) => day.lifts || [])
    .find((candidate) => candidate.id === slot.id);
  lockedSlot.capacityManaged = false;
  let lockedRefused = false;
  try { await coach.applyCoachingRecommendation(lockedProgram, recommendation, seededExercises); }
  catch { lockedRefused = true; }
  ok(lockedRefused && lockedSlot.doubleProgressionSets === 3 && lockedSlot.currentReps === 5,
    "a recommendation cannot bypass a slot that now disallows coached set changes");

  const cappedProgram = structuredClone(proposed);
  const cappedSlot = cappedProgram.days.flatMap((day) => day.lifts || [])
    .find((candidate) => candidate.id === slot.id);
  cappedSlot.maximumSets = 4;
  let cappedRefused = false;
  try { await coach.applyCoachingRecommendation(cappedProgram, recommendation, seededExercises); }
  catch { cappedRefused = true; }
  ok(cappedRefused && cappedSlot.doubleProgressionSets === 3 && cappedSlot.currentReps === 5,
    "a recommendation cannot bypass a slot whose set cap fell below five");

  const message = await coach.applyCoachingRecommendation(proposed, recommendation, seededExercises);
  ok(slot.doubleProgressionSets === 5 && slot.currentReps === 3,
    "accepting the stage change converts only that linear slot to 5x3");
  ok(message.includes("3×5") && message.includes("5×3"), "the applied result names both prescription shapes");
  const decision = coach.coachingDecision(proposed, recommendation, "accepted", ["fixture rebuild"]);
  ok(decision.afterValue === `linearTriples:slot:${slot.id}:5x3`,
    "the audit record names the accepted strategy stage");
  let staleRefused = false;
  try { await coach.applyCoachingRecommendation(proposed, recommendation, seededExercises); }
  catch { staleRefused = true; }
  ok(staleRefused, "a stale stage recommendation cannot overwrite a prescription changed since evaluation");
}

const serviceWorkerSource = await (await import("node:fs/promises")).readFile(
  new URL("../app/sw.js", import.meta.url), "utf8");
ok(serviceWorkerSource.includes('"js/coaching-adapter.js"'),
  "offline shell precaches the eagerly imported coaching adapter");

// Historical and current volume must use the same load multiplier. Two
// identical two-dumbbell sessions are not a volume PR.
await withCleanup(async (keep) => {
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
  const priorID = keep(db.Sessions, await db.Sessions.save({ date: "2020-01-01T12:00:00.000Z", notes: "", isCompleted: true,
    gymName: null, exercises: [section()] }));
  const currentID = keep(db.Sessions, await db.Sessions.save({ date: "2020-01-02T12:00:00.000Z", notes: "", isCompleted: false,
    gymName: null, exercises: [section()] }));
  const result = await session.completeSession(await db.Sessions.get(currentID));
  ok(!result.milestones.some((event) => event.kind === "volumePR"),
    "identical two-dumbbell history does not emit a false volume PR");
})();

// withCleanup regression: a block whose body throws partway through must
// still leave every tracked store clean — the guarantee this helper exists
// to provide, verified by store counts rather than internal helper state.
{
  const beforeSessionCount = (await db.Sessions.all()).length;
  let threw = false;
  try {
    await withCleanup(async (keep) => {
      keep(db.Sessions, await db.Sessions.save({ date: "2000-01-01T00:00:00.000Z",
        notes: "", isCompleted: false, gymName: null, exercises: [] }));
      keep(db.Sessions, await db.Sessions.save({ date: "2000-01-02T00:00:00.000Z",
        notes: "", isCompleted: false, gymName: null, exercises: [] }));
      throw new Error("simulated assertion failure mid-block");
    })();
  } catch {
    threw = true;
  }
  ok(threw, "withCleanup re-throws the wrapped block's error rather than swallowing it");
  ok((await db.Sessions.all()).length === beforeSessionCount,
    "withCleanup deletes every tracked record even when the wrapped block throws partway through");
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
  ok((await db.Exercises.all()).length === 159, "sync leaves the count whole (no dupes)");
}

// ---- vertical pulls: migrate old installs once, then respect user edits ----
{
  const pullups = await db.Exercises.byName("Pull-ups");
  const chinups = await db.Exercises.byName("Chin-ups");
  pullups.category = "Accessory";
  chinups.category = "Accessory";
  await db.Exercises.save(pullups);
  await db.Exercises.save(chinups);
  const settings = await db.Settings.get();
  delete settings.verticalPullMainsPromoted; // pre-promotion seeded install
  await db.Settings.save(settings);

  await db.syncLibrary();
  ok((await db.Exercises.byName("Pull-ups")).category === "Main"
    && (await db.Exercises.byName("Chin-ups")).category === "Main",
  "an existing seeded install promotes bodyweight vertical pulls to main lifts");
  ok((await db.Settings.get()).verticalPullMainsPromoted === true,
    "the vertical-pull promotion records its one-shot marker");

  pullups.category = "Accessory";
  await db.Exercises.save(pullups);
  await db.syncLibrary();
  ok((await db.Exercises.byName("Pull-ups")).category === "Accessory",
    "a deliberate post-migration demotion survives later library syncs");
  pullups.category = "Main";
  await db.Exercises.save(pullups);
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
  const builtProgramSession = await db.Sessions.get(sid);
  const defaultGym = await db.Gyms.default();
  ok(builtProgramSession.exercises.filter((entry) =>
    seededExercises.find((exercise) => exercise.name === entry.exerciseName)?.type === "barbell")
    .every((entry) => entry.barId === defaultGym.defaultBarId),
  "program sessions stamp the bar that built every barbell prescription");
  await session.openSession(sid); await tick();
  const logger = [...document.querySelectorAll("#overlays .overlay")].at(-1);
  ok(logger.querySelector(".overlay-head h2")?.textContent === day.name,
    "the logger title is the workout name, with the date kept in its progress card");
  ok(logger.querySelector(".session-progress")?.textContent.includes("Exercise 1 of"),
    "the logger reports exercise and whole-workout set progress");
  ok(logger.querySelector(".current-set-card") && [...logger.querySelectorAll("button")].some((button) => button.textContent === "Show all sets"),
    "the current set owns the cockpit while a full-set control remains available");
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
for (const [name, view] of [["home", home], ["program", programView], ["history", history], ["body", body], ["signals", signals], ["settings", settings]]) {
  try { await view.render(host()); ok(host().childElementCount > 0, `${name} rendered`); }
  catch (e) { ok(false, `${name} threw: ${e.message}`); }
}

// ---- style-aware labels and the exposure preview render (#105, #106) -------
// Today used to print a Volume/Load/Peak name against every slot on the screen,
// including the ones whose prescription never touches a phase. The label is now
// per-slot, so a program mixing styles has to be able to say so on one screen.
{
  const program = await db.Programs.active();
  const day = program.days.find((d) => d.order === program.nextDayIndex) || program.days[0];
  const originals = day.lifts.map((l) => l.prescription);
  day.lifts[0].prescription = "linearFives";
  if (day.lifts[1]) day.lifts[1].prescription = "wave";
  program.currentWeek = 3;
  await db.Programs.save(program);
  try {
    await home.render(host());
    const text = host().textContent;
    const todayHero = host().querySelector(".today-hero");
    ok(todayHero && todayHero.parentElement?.firstElementChild === todayHero,
      "Today leads with the next workout when no session is open");
    ok(host().querySelector(".coach-summary") && host().querySelector(".day-sequence"),
      "Today keeps coach and program sequence compact beneath the hero");
    ok(text.includes("Main · Linear") || text.includes("Complementary · Linear"),
      "a per-exposure slot is badged with what it actually does");
    ok(!host().querySelector(".wave"), "the rising wave glyph is gone from the program header");
    ok(host().querySelector(".rotation"), "a style-neutral rotation indicator took its place");

    // The phase name survives ONLY against the wave slot.
    const badges = [...host().querySelectorAll(".slot-badge")];
    ok(badges.length > 0, "every program slot carries a badge");
    const linearBadge = badges.find((b) => b.textContent.includes("Linear"));
    ok(linearBadge && !linearBadge.textContent.includes("Peak"),
      "[INV-PHASE-NAME-IS-PER-SLOT] no phase name is rendered against a slot whose style does not use phases");
    if (day.lifts[1]) {
      const waveBadge = badges.find((b) => b.textContent.includes("· Wave"));
      ok(waveBadge && waveBadge.textContent.includes("R3 Peak"),
        "a wave slot still says which phase it is in");
    }
  } finally {
    day.lifts.forEach((l, i) => { l.prescription = originals[i]; });
    program.currentWeek = 1;
    await db.Programs.save(program);
  }
}

// The editor is a wall of inputs; the preview is the only output on it.
{
  const program = await db.Programs.active();
  const day = program.days[0];
  const lift = day.lifts[0];
  const exercises = await db.Exercises.all();
  const exercise = exercises.find((e) => e.name === lift.exerciseName);
  const prior = { prescription: lift.prescription, base: lift.baseWeightLb };
  lift.prescription = "wave";
  lift.baseWeightLb = 190;
  program.roundingLb = 5;
  const card = ui.exposurePreview(lift, program, exercise);
  const text = card.textContent;
  ok(text.includes("Next 4 exposures"), "the preview names what it is showing");
  ok(text.includes("R3 Peak"), "a wave slot's exposures carry their phase names");
  ok(text.includes("225"),
    "[INV-PREVIEW-RUNS-THE-REAL-ENGINE] a 190 lb base previews its real 225 lb peak triple");
  ok(text.includes("Base"), "the preview says what the numbers derive from");

  lift.prescription = "fiveThreeOne";
  const wendlerCard = ui.exposurePreview(lift, program, exercise);
  const wendler = wendlerCard.textContent;
  ok(!wendler.includes("Peak") && !wendler.includes("Volume"),
    "5/3/1 previews exposures, never wave phases");
  ok(wendler.includes("Session 1"), "phase-independent styles number their exposures");
  ok(wendler.includes("+ set"), "the graded + set is visible, not hidden behind the top line");
  ok(wendler.includes("ramp"), "and so are the ramp sets that make up most of the session");
  ok(wendler.includes("Training max"), "a 5/3/1 base is named as the training max it is");
  const firstWendlerRow = wendlerCard.querySelector(".row");
  const mainLoad = firstWendlerRow?.querySelector(".mono")?.textContent;
  ok(mainLoad && firstWendlerRow.textContent.split(mainLoad).length - 1 === 1,
    "the 5/3/1 top set is identified without duplicating its load and scheme");

  ok(ui.sessionPhaseLabel({ phase: 3, prescriptionStyle: "linearFives", programRole: "main" }, exercise) === null,
    "active and history surfaces hide false Peak labels on linear slots");
  ok(ui.sessionPhaseLabel({ phase: 3, prescriptionStyle: "wave", programRole: "main" }, exercise) === "R3 Peak",
    "active and history surfaces retain truthful wave phase labels");
  ok(ui.sessionPhaseLabel({ phase: 3 }, exercise) === C.phaseLabel(3),
    "legacy sessions without captured style retain their historical label");

  lift.prescription = prior.prescription;
  lift.baseWeightLb = prior.base;
  await db.Programs.save(program);
}

// The preview is the only output on the slot editor, and every control beside
// it is an input. A stepper that saves without refreshing it leaves the lifter
// reading the previous walk — which is precisely the 188-vs-190 lb comparison
// the feature exists to make visible. Drive the real editor DOM, not the
// component in isolation, because the defect was in the wiring.
{
  const program = await db.Programs.active();
  const day = program.days.find((d) => (d.lifts || []).length) || program.days[0];
  const lift = day.lifts[0];
  const priorStyle = lift.prescription;
  const priorBase = lift.baseWeightLb;
  lift.prescription = "wave";
  lift.baseWeightLb = 190;
  program.roundingLb = 5;
  await db.Programs.save(program);

  await programView.render(host());
  const addProgram = [...host().querySelectorAll("button")].find((button) => button.textContent.includes("Add program"));
  addProgram.click(); await tick();
  let creator = [...document.querySelectorAll("#overlays .sheet")].at(-1);
  ok(["Start from a template", "Blank program", "Import a program file"]
    .every((label) => creator.textContent.includes(label)),
  "Add program exposes three clear creation paths before making a choice");
  [...creator.querySelectorAll("button")].find((button) => button.textContent.includes("Start from a template")).click();
  await tick();
  creator = [...document.querySelectorAll("#overlays .sheet")].at(-1);
  ok(creator.textContent.includes("days ·") && creator.textContent.includes("strength")
    && creator.textContent.includes("Wave"),
  "template choices expose days, focus, and dominant prescriptions before selection");
  [...creator.querySelectorAll("button")].find((button) => button.textContent === "Cancel").click();
  await tick();

  const progRow = [...host().querySelectorAll(".program-day-card")]
    .find((row) => row.textContent.includes(day.name));
  progRow.click(); await tick();
  const editor = [...document.querySelectorAll("#overlays .overlay")].at(-1);
  const dayLead = [...editor.querySelectorAll(".lead")].find((el) => el.textContent.includes(day.name));
  ok(dayLead, "the program editor lists the day");
  dayLead.click(); await tick();

  const dayEditor = [...document.querySelectorAll("#overlays .overlay")].at(-1);
  const baseRow = [...dayEditor.querySelectorAll(".row")].find((r) => r.textContent.includes("Rotation-1 base"));
  ok(baseRow, "the slot editor offers the base stepper");
  const before = dayEditor.textContent;
  ok(before.includes("225"), "a 190 lb base previews its 225 lb peak before any edit");

  // One step down: 190 → 185, whose peak rounds to 215 rather than 225.
  baseRow.querySelector(".stepper button").click(); await tick();
  const after = dayEditor.textContent;
  ok(!after.includes("225") || after.includes("215"),
    "[INV-PREVIEW-RUNS-THE-REAL-ENGINE] stepping the base refreshes the preview instead of leaving a stale walk");
  ok(after.includes("215"), "and it shows the new base's real peak");

  // Drive the real Add lift picker. The lift bootstrap and accessory
  // bootstrap intentionally have different shapes; reading `weightLb` here
  // persisted an undefined main-lift base even though the helper was correct.
  const addedExercise = await db.Exercises.byName("Barbell Row");
  const { bootstrapLiftFromHistory } = await import("../app/js/templates.js");
  const expectedBootstrap = await bootstrapLiftFromHistory(addedExercise,
    { role: "complementary", focus: program.focus, roundingLb: program.roundingLb });
  [...dayEditor.querySelectorAll("button")]
    .find((button) => button.textContent.includes("Add lift")).click();
  await tick();
  const picker = [...document.querySelectorAll("#overlays .sheet")].at(-1);
  const pickerSearch = picker.querySelector('input[type="search"]');
  pickerSearch.value = addedExercise.name;
  pickerSearch.dispatchEvent(new window.Event("input"));
  [...picker.querySelectorAll("button")]
    .find((button) => button.textContent === addedExercise.name).click();
  await tick();
  const withAddedLift = await db.Programs.active();
  const addedDay = withAddedLift.days.find((candidate) => candidate.name === day.name);
  const addedLift = addedDay.lifts.find((candidate) => candidate.exerciseName === addedExercise.name);
  ok(addedLift?.baseWeightLb === expectedBootstrap.baseWeightLb
      && Number.isFinite(addedLift.baseWeightLb),
  "Add lift persists the history/default bootstrap's finite baseWeightLb");
  addedDay.lifts = addedDay.lifts.filter((candidate) => candidate !== addedLift);
  await db.Programs.save(withAddedLift);

  // Close both overlays and restore.
  for (const overlay of [...document.querySelectorAll("#overlays .overlay")].reverse()) {
    overlay.querySelector(".overlay-head button").click(); await tick();
  }
  const restored = await db.Programs.active();
  const restoredLift = (restored.days.find((d) => d.name === day.name) || restored.days[0]).lifts[0];
  restoredLift.prescription = priorStyle;
  restoredLift.baseWeightLb = priorBase;
  await db.Programs.save(restored);
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
const intentLabels = [...host().querySelectorAll("select option")].map((option) => option.textContent);
ok(["Main progression", "Compare program roles", "Compare like rotations"].every((label) => intentLabels.includes(label)),
  "history exposes the three explicit chart intents");

// Asking for a projection must always produce an answer. A control that
// silently changes nothing when the history is too thin reads as broken, so
// the chart either draws the trend or says why it will not.
{
  const horizonBtn = [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "3 months");
  if (horizonBtn) {
    horizonBtn.click(); await tick();
    const drewIt = host().querySelector("path.projection");
    // Match the SENTENCES the refusal actually produces, not a loose keyword.
    // A /project|trained|history/i sweep matched the control's own "Project
    // forward" heading, so this passed whether or not anything was explained —
    // the invariant had no UI coverage at all while appearing to have some.
    const REFUSALS = [/^Not enough history to project/, /^Not enough time to project/, /^Last trained \d+ days ago/];
    const said = [...host().querySelectorAll(".sub, .title")]
      .map((n) => (n.textContent || "").trim())
      .filter((t) => REFUSALS.some((r) => r.test(t)));
    // A lift with no charted points at all is its own answer — there is no
    // chart to project from — so the empty state counts as having responded.
    const emptyChart = !!host().querySelector(".empty");
    ok(drewIt || said.length > 0 || emptyChart,
      "[INV-PROJECTION-REFUSES-THIN-HISTORY] a horizon either projects, refuses, or has no chart at all");
    // Whichever branch ran, the other must NOT be on screen: a chart showing a
    // projected line and a refusal at once is the contradiction worth catching.
    ok(!(drewIt && said.length > 0),
      "[INV-PROJECTION-REFUSES-THIN-HISTORY] it never both projects and refuses");
    ok(!REFUSALS.some((r) => r.test("Project forward")),
      "the refusal patterns cannot match the control's own heading");
    // Back to off, so later renders in this file see the default chart.
    [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "Off")?.click();
    await tick();
    ok(!host().querySelector("path.projection"), "turning the horizon off removes the projected line");
  }
}

// Promoting pull-ups to Main made them selectable in the charts — but an
// unloaded pull-up has no external resistance, so working weight, est. 1RM and
// tonnage can only ever draw a flat zero. The honest series is reps, and the
// picker must offer that instead of three straight lines at 0.
{
  // Real logged history, so the assertions below test the chart's DATA path,
  // not only its labels — a picker that says "Reps" above an empty chart
  // passed the previous version of this block.
  const pullDay = (daysAgo, reps) => db.Sessions.save({
    date: new Date(Date.now() - daysAgo * 86_400_000).toISOString(), notes: "", isCompleted: true,
    gymName: null, exercises: [{ order: 0, exerciseName: "Pull-ups", notes: "", phase: null,
      sets: [{ order: 0, weightLb: 0, reps, isWarmup: false, status: "completed" }] }],
  });
  const pullIds = [];
  for (const [daysAgo, reps] of [[28, 5], [21, 6], [14, 7], [7, 8], [0, 9]]) {
    pullIds.push(await pullDay(daysAgo, reps));
  }
  await history.render(host());
  [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "Charts")?.click();
  await tick();
  const select = host().querySelector("select");
  const hasPullUps = select && [...select.options].some((o) => o.value === "Pull-ups");
  ok(hasPullUps, "a promoted pull-up is selectable in the chart picker");
  if (hasPullUps) {
    select.value = "Pull-ups";
    select.dispatchEvent(new window.Event("change"));
    await tick();
    const labels = [...host().querySelectorAll(".seg button")].map((b) => b.textContent);
    ok(labels.includes("Reps"), `a bodyweight lift is offered Reps (${labels.join(", ")})`);
    ok(!labels.includes("Working weight") && !labels.includes("Est. 1RM"),
      "and is NOT offered the load metrics it could only draw as zero");
    // The metric must have a data source: five logged sessions are five dots.
    ok(host().querySelectorAll("svg.chart path.line").length >= 1,
      "the Reps metric draws a line, not a blank chart");
    ok(host().querySelectorAll("svg.chart circle.dot").length >= 5,
      `every logged pull-up session charts a point (${host().querySelectorAll("svg.chart circle.dot").length})`);
    // And it projects: 5 samples over 28 days clears every refusal threshold.
    [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "3 months")?.click();
    await tick();
    ok(host().querySelector("path.projection"),
      "a rep progression projects like any other metric");
    ok([...host().querySelectorAll(".title")].some((n) => /reps\/week/.test(n.textContent || "")),
      "and the projected rate is a rep count, not a load");
    [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "Off")?.click();
    await tick();
    // A loaded lift keeps every load metric and is never offered reps.
    select.value = "Weighted Pull-up";
    select.dispatchEvent(new window.Event("change"));
    await tick();
    const loadedLabels = [...host().querySelectorAll(".seg button")].map((b) => b.textContent);
    ok(loadedLabels.includes("Working weight") && !loadedLabels.includes("Reps"),
      `belt weight is real resistance, so it charts load (${loadedLabels.join(", ")})`);
  }
  for (const id of pullIds) await db.Sessions.del(id);
}

// Imported/custom exercises may omit loadBasis. The chart gate must use the
// same type-based fallback as every set and PR path, not treat a missing raw
// field as an unloadable lift.
{
  const squat = await db.Exercises.byName("Back Squat");
  const withoutBasis = { ...squat };
  delete withoutBasis.loadBasis;
  await db.Exercises.save(withoutBasis);
  await history.render(host());
  const select = host().querySelector("select");
  select.value = "Back Squat";
  select.dispatchEvent(new window.Event("change"));
  await tick();
  const labels = [...host().querySelectorAll(".seg button")].map((b) => b.textContent);
  ok(labels.includes("Working weight") && labels.includes("Est. 1RM") && !labels.includes("Reps"),
    `a Main barbell lift with no raw loadBasis still resolves to load metrics (${labels.join(", ")})`);
  await db.Exercises.save(squat);
}

// plate calculator overlay
await plates.openPlateCalculator(); await tick();
const plateOverlay = document.querySelector("#overlays .overlay");
ok(plateOverlay, "plate calculator opened");
const targetTotal = plateOverlay.querySelector(".dual-weight");
const targetHero = plateOverlay.querySelector(".barbell-hero");
ok(targetTotal?.textContent.includes("lb") && targetTotal?.textContent.includes("kg"),
  "target mode always shows the achieved bar in both pounds and kilograms");
ok((targetTotal?.compareDocumentPosition(targetHero) || 0) & Node.DOCUMENT_POSITION_FOLLOWING,
  "target mode puts the dual-unit answer before the loadout graphic");
ok(plateOverlay.querySelectorAll("svg.plate-badge").length > 0,
  "target per-side rows expose readable denomination badges");
const reverseButton = [...plateOverlay.querySelectorAll(".seg button")].find((button) => button.textContent === "On the bar");
ok(reverseButton, "plate calculator exposes the reverse-mode control");
reverseButton?.click(); await tick();
const reverseTotal = plateOverlay.querySelector(".dual-weight");
const reversePlateList = [...plateOverlay.querySelectorAll(".section-title")]
  .find((heading) => heading.textContent === "Plates on one side");
ok(reverseTotal?.textContent.includes("lb") && reverseTotal?.textContent.includes("kg"),
  "reverse mode always shows mixed bar-and-plate totals in both units");
ok((reverseTotal?.compareDocumentPosition(reversePlateList) || 0) & Node.DOCUMENT_POSITION_FOLLOWING,
  "reverse mode keeps the dual-unit total above the plate controls");
ok(plateOverlay.querySelectorAll("svg.plate-badge[aria-label$='plate']").length > 0,
  "reverse controls keep plate numbers visible instead of relying on colour");
const kg20Row = plateOverlay.querySelector('svg.plate-badge[aria-label="20 kg plate"]')?.closest(".row");
ok(kg20Row, "reverse mode exposes the 20 kg plate control");
kg20Row?.querySelector(".stepper button:last-child")?.click();
const mixedTotalLb = 45 + (2 * C.lbFromKg(20));
const updatedMixedTotal = plateOverlay.querySelector(".dual-weight");
ok(updatedMixedTotal.textContent.includes(C.trim(mixedTotalLb))
  && updatedMixedTotal.textContent.includes(C.trim(C.kgFromLb(mixedTotalLb))),
"a 45 lb bar plus mirrored kg plates is converted exactly in both displayed totals");
plateOverlay.querySelector(".overlay-head button").click(); // close
await tick();

ok(session.complementaryEffortCueForEntry(
  { programRole: "complementary", prescriptionStyle: "automatic" }, { movementGroup: "hinge" }, { focus: "strength" },
)?.includes("2–3 reps left"), "automatic strength sessions show the secondary-volume effort contract");
ok(session.complementaryEffortCueForEntry(
  { programRole: "complementary", prescriptionStyle: "automatic" }, { movementGroup: "hinge" }, { focus: "hypertrophy" },
) === null, "automatic hypertrophy sessions do not show a strength-only effort contract");
ok(session.complementaryEffortCueForEntry(
  { programRole: "complementary", prescriptionStyle: "automatic" }, { movementGroup: "hinge" }, null,
) === null, "an orphaned automatic session stays silent when its focus cannot be recovered");

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
ok(created.exercises[0].barId === (await db.Gyms.default()).defaultBarId,
  "tracked barbell sessions preserve the bar used to build their history");
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
// Pinned to a literal, and deliberately meant to fail and be updated by hand.
// Every other assertion here compares against the constant, so a JS-only bump
// would drift from BackupContract.currentSchemaVersion in CadenceCore without
// anything noticing. This is the lockstep the backup docs claim exists.
ok(db.BACKUP_SCHEMA_VERSION === 12, `backup schema is pinned at 12 (got ${db.BACKUP_SCHEMA_VERSION})`);

// An app must never write a backup it cannot itself restore. A corrupted or
// out-of-range birthYear is clamped to the not-set sentinel on the way through
// settings, using the SAME rule the importer validates against — otherwise it
// would persist, ride out in an export, and be rejected on the way back in.
{
  const original = await db.Settings.get();
  for (const bad of [1850, 3000, 1901, 1958.5, "1958", null]) {
    await db.Settings.save({ ...original, birthYear: bad });
    const back = await db.Settings.get();
    ok(back.birthYear === 0, `an implausible birthYear (${JSON.stringify(bad)}) is clamped to 0, got ${back.birthYear}`);
    const bundle = JSON.parse(await db.exportJSON());
    ok(bundle.settings.birthYear === 0, `and never reaches an export (${JSON.stringify(bad)})`);
  }
  await db.Settings.save({ ...original, birthYear: 1958 });
  ok((await db.Settings.get()).birthYear === 1958, "a plausible birth year is kept");
  const roundTrip = JSON.parse(await db.exportJSON());
  ok(roundTrip.settings.birthYear === 1958, "and is exported");
  await db.importBundle(roundTrip);
  ok((await db.Settings.get()).birthYear === 1958, "and survives a round trip through the importer");
  await db.Settings.save(original);
}
ok(parsed.sessions.length === 11 && Array.isArray(parsed.milestones), "export bundle shape");
ok(Array.isArray(parsed.tracks) && parsed.tracks.length === 3, "export carries lift tracks");
ok(Array.isArray(parsed.gyms) && parsed.gyms.length > 0, "export carries gyms");
ok(Array.isArray(parsed.exercises) && parsed.exercises.length === 159, "export carries the exercise library");
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

// ---- named restore preview ----
// The store already matches `parsed` (it was just re-imported above), so a
// preview of the SAME bundle across all five collections must be a no-op —
// and, being a preview, must not itself write anything.
{
  const beforeSessions = (await db.Sessions.all()).length;
  const beforePrograms = (await db.Programs.all()).length;
  const beforeTracks = (await db.Tracks.all()).length;
  const beforeGyms = (await db.Gyms.all()).length;
  const beforeExercises = (await db.Exercises.all()).length;

  const samePreview = await db.namedRestorePreview(parsed);
  ok(C.isNamedRestoreNoOp(samePreview), "previewing the bundle already resident is a no-op");
  for (const key of ["exercises", "tracks", "gyms", "sessions", "programs"]) {
    ok(samePreview[key].every((d) => d.status === "unchanged"), `${key} preview against itself is all-unchanged`);
  }

  ok((await db.Sessions.all()).length === beforeSessions
    && (await db.Programs.all()).length === beforePrograms
    && (await db.Tracks.all()).length === beforeTracks
    && (await db.Gyms.all()).length === beforeGyms
    && (await db.Exercises.all()).length === beforeExercises,
    "computing a preview reads only — no store is touched");

  // Drop a session, add a brand-new one, and grow the fixture program's slot
  // count — a preview must name each one under the status the eventual
  // restore would actually apply.
  const modified = structuredClone(parsed);
  const droppedSession = modified.sessions.shift();
  const changedProgram = modified.programs.find((p) => p.name === "Fixture Upper/Lower");
  const originalSlotCount = changedProgram.days.reduce((sum, d) => sum + d.lifts.length + d.accessories.length, 0);
  changedProgram.days[0].accessories.push({ exerciseName: "Face Pulls", order: 99, sets: 3, minReps: 12, maxReps: 15 });
  const newSession = { ...structuredClone(droppedSession), id: "brand-new-session-id", date: "2099-01-01T00:00:00.000Z" };
  modified.sessions.push(newSession);

  const diffPreview = await db.namedRestorePreview(modified);
  ok(!C.isNamedRestoreNoOp(diffPreview), "a modified bundle is not a no-op");
  ok(diffPreview.sessions.some((d) => d.status === "removed" && d.id === droppedSession.id),
    "a session the modified bundle omits previews as removed");
  ok(diffPreview.sessions.some((d) => d.status === "new" && d.name === newSession.date),
    "a brand-new session id previews as new");
  ok(diffPreview.programs.some((d) => d.status === "changed" && d.id === changedProgram.id),
    `a program with a different slot count (was ${originalSlotCount}) previews as changed`);

  // A bundle that keeps the `programs` key but empties it wholesale-replaces
  // the store with nothing — every current program previews as removed.
  const emptied = { ...structuredClone(parsed), programs: [] };
  const removalPreview = await db.namedRestorePreview(emptied);
  const currentProgramIDs = (await db.Programs.all()).map((p) => p.uuid);
  ok(currentProgramIDs.length > 0
    && currentProgramIDs.every((id) => removalPreview.programs.some((d) => d.id === id && d.status === "removed")),
    "emptying the bundle's programs key previews every current program as removed");

  // The write path is untouched by any of the above: importing the
  // UNCHANGED original bundle after computing two different previews still
  // restores exactly the original session/program counts.
  await db.importBundle(parsed);
  ok((await db.Sessions.all()).length === beforeSessions && (await db.Programs.all()).length === beforePrograms,
    "confirmed-restore write behavior is unaffected by having computed a preview first");
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

// [INV-TIED-ORDER-IS-AUTHORED] A backup whose slots all say order 0 was written in the
// sequence the author meant — older exports (and native pre-#69 programs)
// carry exactly that shape. Import stamps array positions so the tie never
// falls to the alphabetical display fallback; explicit distinct orders are
// the author's sequence and survive verbatim.
{
  const tied = structuredClone(parsed);
  const program = tied.programs.find((p) => p.name === "Fixture Upper/Lower");
  const upperA = program.days.find((d) => d.name === "Upper A");
  const lowerA = program.days.find((d) => d.name === "Lower A");
  for (const slot of [...upperA.lifts, ...upperA.accessories]) slot.order = 0;
  lowerA.accessories.forEach((slot, i) => { slot.order = [2, 1, 0][i]; });

  await db.importBundle(tied);
  const restored = (await db.Programs.all()).find((p) => p.name === "Fixture Upper/Lower");
  const restoredUpperA = restored.days.find((d) => d.name === "Upper A");
  const restoredLowerA = restored.days.find((d) => d.name === "Lower A");
  ok(restoredUpperA.lifts.map((l) => `${l.exerciseName}:${l.order}`).join(", ")
    === "Incline DB Press:0, Single-arm DB Row:1",
    `[INV-TIED-ORDER-IS-AUTHORED] tied backup lifts keep authored sequence (got: ${
      restoredUpperA.lifts.map((l) => `${l.exerciseName}:${l.order}`).join(", ")})`);
  ok(restoredUpperA.accessories.map((a) => `${a.exerciseName}:${a.order}`).join(", ")
    === "Face Pulls:0, DB Curls:1, Band Pull-aparts:2",
    `[INV-TIED-ORDER-IS-AUTHORED] tied backup accessories keep authored sequence (got: ${
      restoredUpperA.accessories.map((a) => `${a.exerciseName}:${a.order}`).join(", ")})`);
  ok(restoredLowerA.accessories.map((a) => a.order).join() === "2,1,0",
    `[INV-TIED-ORDER-IS-AUTHORED] explicit distinct orders survive a backup import verbatim (got: ${
      restoredLowerA.accessories.map((a) => a.order).join()})`);
  // Round-trip healing: the next export carries the resolved orders, so a
  // once-tied backup can never re-tie itself on a future restore.
  const healed = JSON.parse(await db.exportJSON())
    .programs.find((p) => p.name === "Fixture Upper/Lower")
    .days.find((d) => d.name === "Upper A");
  ok(healed.lifts.map((l) => l.order).join() === "0,1"
    && healed.accessories.map((a) => a.order).join() === "0,1,2",
    "[INV-TIED-ORDER-IS-AUTHORED] the repaired orders are what the next backup exports");
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

// Library migration markers follow the exercise library, not settings alone.
// A settings-only restore keeps the current markers; restoring an older
// library re-arms every repair that depends on those rows.
{
  ok((await db.Settings.get()).restSeedStampsCleared === true, "marker is set before the partial-restore checks");
  const settingsOnly = { sessions: parsed.sessions, settings: { ...parsed.settings } };
  delete settingsOnly.settings.restSeedStampsCleared; // a pre-migration, exercise-less backup
  delete settingsOnly.settings.verticalPullMainsPromoted;
  await db.importBundle(settingsOnly);
  ok((await db.Settings.get()).restSeedStampsCleared === true, "settings-only restore keeps the stamp-clear marker");
  ok((await db.Settings.get()).verticalPullMainsPromoted === true,
    "settings-only restore keeps the vertical-pull marker");

  const oldLibrary = parsed.exercises.map((exercise) =>
    exercise.name === "Pull-ups" ? { ...exercise, category: "Accessory" }
      // A category the lifter set THEMSELVES — the repair must not argue.
      // Main would be indistinguishable from a promotion, so the fixture uses
      // the one value that tells the guard apart from its absence.
      : exercise.name === "Chin-ups" ? { ...exercise, category: "Conditioning" }
        : exercise);
  await db.importBundle({ exercises: oldLibrary });
  const rearmed = await db.Settings.get();
  ok(rearmed.restSeedStampsCleared === false, "library restore without settings re-arms the stamp check");
  ok(rearmed.verticalPullMainsPromoted === false,
    "library restore without settings re-arms the vertical-pull promotion");
  await db.syncLibrary();
  ok((await db.Exercises.byName("Pull-ups")).category === "Main",
    "library sync promotes vertical pulls restored from an older backup");
  ok((await db.Exercises.byName("Chin-ups")).category === "Conditioning",
    "a category the lifter set themselves is never overwritten — delete the guard and this fails");
  // Re-arm before the full restore: syncLibrary's repair just set both markers
  // back to true, so without this the assertion below proves a true→true
  // non-transition and a restore that dropped the bundle's marker would pass.
  await db.Settings.save({ ...(await db.Settings.get()),
    restSeedStampsCleared: false, verticalPullMainsPromoted: false });
  await db.importBundle(parsed); // full post-migration bundle restores the marker
  ok((await db.Settings.get()).restSeedStampsCleared === true,
    "full post-migration restore flips the re-armed marker back to true");
  ok((await db.Settings.get()).verticalPullMainsPromoted === true,
    "and the vertical-pull marker rides the same restore");
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

// ---- post-import revert affordance: the "before-import" checkpoint the
// settings-view actionSheet offers restores the pre-import state ----
{
  const preImport = await db.Tracks.byName("Deadlift");
  const preImportWeight = preImport.baseWeightLb;
  const bundle = JSON.parse(await db.exportJSON());
  bundle.tracks = bundle.tracks.map((t) => t.exerciseName === "Deadlift" ? { ...t, baseWeightLb: preImportWeight + 500 } : t);
  // Default createCheckpoint: true — the same "before-import" snapshot
  // SettingsView.restore(from:)/importData() take before every restore.
  await db.importBundle(bundle);
  ok((await db.Tracks.byName("Deadlift")).baseWeightLb === preImportWeight + 500,
    "the import lands the new data before any revert");
  // Exercise the exact db.js helper the actionSheet's revert action calls.
  await db.Checkpoints.restoreLatest();
  ok((await db.Tracks.byName("Deadlift")).baseWeightLb === preImportWeight,
    "reverting via Checkpoints.restoreLatest() restores the pre-import state");
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

  // [INV-STAIRS-COUNT-FLIGHTS] A climber's belt goes nowhere. It gets flights
  // and a flights-per-minute pace where a walk gets miles and mph, and it never
  // acquires a distance it could not have measured.
  {
    const cid = await session.createBlankSession();
    const c = await db.Sessions.get(cid);
    c.exercises.push({ order: 0, exerciseName: "Stair Climber", notes: "", phase: null,
      plannedWeightLb: null, plannedSets: null, plannedReps: null,
      sets: [{ order: 0, weightLb: 0, reps: 1, isWarmup: false, isPerSide: false, enteredUnit: "lb",
        flags: [], bodyFlagSite: null, bodyFlagNote: null,
        durationSeconds: 900, distanceMiles: null, flights: 120, autoregReason: null }] });
    await db.Sessions.save(c);
    await session.openSession(cid); await tick();

    const climbRow = [...document.querySelectorAll("#overlays .overlay .setrow")]
      .find((r) => r.textContent.includes("120 flights"));
    ok(climbRow && climbRow.textContent.includes("120 flights · 15:00 · 8 fl/min"),
      "[INV-STAIRS-COUNT-FLIGHTS] a climb renders as flights and a pace, not miles and mph");

    climbRow.querySelector("button.ghost").click(); await tick();
    const sheetEl = [...document.querySelectorAll("#overlays .sheet")].pop();
    const numbers = [...sheetEl.querySelectorAll("input[type=number]")];
    const rowLabel = (input) => input.closest(".row")?.textContent || "";
    const flightField = numbers.find((i) => rowLabel(i).includes("Flights"));
    const paceField = numbers.find((i) => rowLabel(i).includes("Pace"));
    ok(flightField && paceField, "the climber sheet offers both flights and pace");
    ok(!numbers.some((i) => rowLabel(i).includes("Distance")),
      "[INV-STAIRS-COUNT-FLIGHTS] a climber is offered no distance field at all");
    ok(paceField.value === "8", "pace opens as the readout derived from 120 flights in 15:00");

    // Setting a pace fills in the count it reaches, and leaves the time alone.
    paceField.value = "10";
    paceField.dispatchEvent(new window.Event("input", { bubbles: true }));
    ok(flightField.value === "150",
      `[INV-STAIRS-COUNT-FLIGHTS] 10 fl/min for 15:00 fills in 150 flights (got ${flightField.value})`);

    // Typing a count flips the derived side back to pace.
    flightField.value = "120";
    flightField.dispatchEvent(new window.Event("input", { bubbles: true }));
    ok(paceField.value === "8",
      `[INV-STAIRS-COUNT-FLIGHTS] 120 flights in 15:00 reads back as 8 fl/min (got ${paceField.value})`);

    [...sheetEl.querySelectorAll("button")].find((b) => b.textContent === "Done").click(); await tick();
    const saved = (await db.Sessions.get(cid)).exercises[0].sets[0];
    ok(saved.flights === 120 && saved.durationSeconds === 900,
      "the climb stores flights and duration only");
    ok(!("pacePerMinute" in saved), "pace is never persisted as a third field");
    ok(saved.distanceMiles == null,
      "[INV-STAIRS-COUNT-FLIGHTS] a hidden distance block never writes a distance");

    // The count survives the portable contract, and the key stays off records
    // that have no flights (the conditional-spread convention).
    const climbState = await db.Sessions.get(cid);
    climbState.isCompleted = true;
    await db.Sessions.save(climbState);
    const climbBundle = JSON.parse(await db.exportJSON());
    ok(climbBundle.schemaVersion === 12, "climbed flights ship inside the current backup schema");
    const climbExport = climbBundle.sessions.flatMap((x) => x.exercises)
      .find((e) => e.name === "Stair Climber");
    ok(climbExport && climbExport.sets[0].flights === 120, "export carries the flight count");
    const noFlights = climbBundle.sessions.flatMap((x) => x.exercises)
      .find((e) => e.name === "Deadlift").sets[0];
    ok(!("flights" in noFlights), "sets without flights don't grow the key (byte-stable exports)");
    await db.Sessions.del(cid);
  }

  // The station preference (v8) survives the portable contract: declared
  // once on the exercise, exported, and restored — and a pre-v8 bundle has
  // no key at all, which restores as "gym inventory", exactly what every
  // lift did before stations existed. [INV-STATION-OWNS-ITS-PLATES]
  {
    const deadlift = await db.Exercises.byName("Deadlift");
    deadlift.stationDenomination = "kg";
    await db.Exercises.save(deadlift);
    const stationBundle = JSON.parse(await db.exportJSON());
    ok(stationBundle.exercises.find((e) => e.name === "Deadlift").stationDenomination === "kg",
      "export carries the kg deadlift station");
    deadlift.stationDenomination = null;
    await db.Exercises.save(deadlift);
    await db.importBundle(stationBundle);
    ok((await db.Exercises.byName("Deadlift")).stationDenomination === "kg",
      "restore returns the kg deadlift station");
    const preStation = JSON.parse(await db.exportJSON());
    preStation.schemaVersion = 7;
    preStation.exercises.forEach((e) => { delete e.stationDenomination; });
    await db.importBundle(preStation);
    ok((await db.Exercises.byName("Deadlift")).stationDenomination === null,
      "a pre-v8 bundle restores every lift onto the gym inventory");
  }

  // A climb logged in miles before flights existed keeps its distance and stays
  // editable — the fields follow the DATA as well as the movement, so history
  // never disappears behind a measure it was not recorded with.
  {
    const lid = await session.createBlankSession();
    const l = await db.Sessions.get(lid);
    l.exercises.push({ order: 0, exerciseName: "Stair Climber", notes: "", phase: null,
      plannedWeightLb: null, plannedSets: null, plannedReps: null,
      sets: [{ order: 0, weightLb: 0, reps: 1, isWarmup: false, isPerSide: false, enteredUnit: "lb",
        flags: [], bodyFlagSite: null, bodyFlagNote: null,
        durationSeconds: 1200, distanceMiles: 0.75, autoregReason: null }] });
    await db.Sessions.save(l);
    await session.openSession(lid); await tick();

    const legacyRow = [...document.querySelectorAll("#overlays .overlay .setrow")]
      .find((r) => r.textContent.includes("0.75 mi"));
    ok(legacyRow && legacyRow.textContent.includes("0.75 mi · 20:00 · 2.3 mph"),
      "[INV-STAIRS-COUNT-FLIGHTS] a pre-flights climb still renders the distance it holds");
    legacyRow.querySelector("button.ghost").click(); await tick();
    const legacySheet = [...document.querySelectorAll("#overlays .sheet")].pop();
    const legacyRows = [...legacySheet.querySelectorAll("input[type=number]")]
      .map((i) => i.closest(".row")?.textContent || "");
    ok(legacyRows.some((t) => t.includes("Distance")),
      "[INV-STAIRS-COUNT-FLIGHTS] the distance it was logged with stays editable");
    ok(legacyRows.some((t) => t.includes("Flights")),
      "and the new measure is offered alongside it");

    // The row's affordance line and the sheet's rows come from one rule, so the
    // line can neither promise a field the sheet withholds nor — as a
    // hand-written string did for exactly this legacy case — understate it.
    const hinted = (legacyRow.textContent.match(/flights|distance|speed|pace|incline|load/g) || []);
    for (const field of ["flights", "distance", "speed", "pace"]) {
      ok(hinted.includes(field),
        `[INV-STAIRS-COUNT-FLIGHTS] the row names "${field}", which its sheet actually shows`);
    }
    ok(legacyRows.some((t) => t.includes("Speed")) && legacyRows.some((t) => t.includes("Pace")),
      "and the sheet does show both readouts the row named");
    // This climb carries no incline, so neither names one: a legacy DISTANCE
    // brings its block back, a legacy incline is a separate question.
    ok(!hinted.includes("incline") && !legacyRows.some((t) => t.includes("Incline")),
      "[INV-STAIRS-COUNT-FLIGHTS] a climber with no logged incline is offered none");

    [...legacySheet.querySelectorAll("button")].find((b) => b.textContent === "Done").click(); await tick();
    const legacySaved = (await db.Sessions.get(lid)).exercises[0].sets[0];
    ok(legacySaved.distanceMiles === 0.75 && legacySaved.flights == null,
      "opening and closing the sheet converts nothing");
    await db.Sessions.del(lid);
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

// The motivating log for the honest base ([INV-ADVANCE-BUYS-PLATES]): a kg
// rack solved last cycle's 215 AND the advanced 225 to the identical 2×20 kg
// stack (221.4), so "my 5×5 deadlift today still has me at 225" — for a third
// straight cycle. The builder must plan the new volume rotation from the
// honest base: label(221.4) + the earned 10 = 235, whose kg twin stack
// (232.4) finally puts more plates on the bar.
{
  const name = "Fixture Advance Buys Plates";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 2, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Pull", order: 0, accessories: [],
      lifts: [{ exerciseName: "Deadlift", role: "main", prescription: "wave",
        baseWeightLb: 225, estimatedMaxLb: 280, stallCount: 0, lastIncrementLb: 10 }] }],
  });
  const program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const slot = program.days[0].lifts[0];
  // Last cycle's banked volume rotation: five completed pulls at the kg stack.
  const priorId = await db.Sessions.save({
    date: db.iso(new Date(Date.now() - 14 * 86400000)), notes: "", isCompleted: true,
    completedAt: db.iso(new Date(Date.now() - 14 * 86400000)), gymName: null,
    programTag: { programId: program.uuid || program.id, programName: name,
      cycleNumber: 1, week: 1, dayIndex: 0, planNames: ["Deadlift"] },
    exercises: [{ order: 0, exerciseName: "Deadlift", notes: "", phase: 1,
      programRole: "main", programSlotId: slot.id,
      plannedWeightLb: 215, plannedSets: 5, plannedReps: 5,
      sets: Array.from({ length: 5 }, (_, index) => ({
        order: index, weightLb: 221.37, reps: 5, isWarmup: false, isPerSide: false,
        enteredUnit: "lb", status: "completed", loadBasis: "totalBar", flags: [],
        bodyFlagSite: null, autoregReason: null, prescriptionBlock: "work",
      })) }],
  });
  const builtId = await session.createSessionFromProgramDay(program, program.days[0]);
  const built = await db.Sessions.get(builtId);
  const deadlift = built.exercises.find((entry) => entry.exerciseName === "Deadlift");
  ok(deadlift.plannedWeightLb === 235,
    `[INV-ADVANCE-BUYS-PLATES] the stale 225 plans as the honest 235 (got ${deadlift.plannedWeightLb})`);
  ok(deadlift.targetWeightLb === 235,
    "and the resume comparison sees the same honest target, not the stale label");
  // A hand-set base is its own truth: clearing the earned increment (what the
  // editor does on a manual edit) switches the repair off.
  await db.Sessions.del(builtId);
  slot.lastIncrementLb = 0;
  await db.Programs.save(program);
  const editedProgram = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const editedId = await session.createSessionFromProgramDay(editedProgram, editedProgram.days[0]);
  const edited = await db.Sessions.get(editedId);
  ok(edited.exercises.find((entry) => entry.exerciseName === "Deadlift").plannedWeightLb === 225,
    "[INV-ADVANCE-BUYS-PLATES] a hand-set base is never repaired");
  await db.Sessions.del(editedId);
  await db.Sessions.del(priorId);
  await db.importBundle(parsed);
}

// The rebuild-pace pair, shaped like the real log that motivated it: base 226
// (lastIncrement 5, estimated max 278 → 81% headroom → rebuild step 10), last
// cycle's volume banked as 220×5 at plan plus a deliberate 245×3 the lifter
// added past the prescription. The bonus rows never touch grading, but they
// arm one rebuild step of catch-up: the card plans from 236 and shows 235.
{
  const name = "Fixture Rebuild Pace";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 3, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower", order: 0, accessories: [],
      lifts: [{ exerciseName: "Deadlift", role: "main", prescription: "wave",
        baseWeightLb: 226, estimatedMaxLb: 278.3, stallCount: 0, lastIncrementLb: 5 }] }],
  });
  const program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const slot = program.days[0].lifts[0];
  const atPlan = (index) => ({
    order: index, weightLb: 220, reps: 5, isWarmup: false, isPerSide: false,
    enteredUnit: "lb", status: "completed", loadBasis: "totalBar", flags: [],
    bodyFlagSite: null, autoregReason: null, prescriptionBlock: "work",
  });
  const bonus = (index) => ({ ...atPlan(index), weightLb: 245, reps: 3 });
  const priorId = await db.Sessions.save({
    date: db.iso(new Date(Date.now() - 20 * 86400000)), notes: "", isCompleted: true,
    completedAt: db.iso(new Date(Date.now() - 20 * 86400000)), gymName: null,
    programTag: { programId: program.uuid || program.id, programName: name,
      cycleNumber: 2, week: 1, dayIndex: 0, planNames: ["Deadlift"] },
    exercises: [{ order: 0, exerciseName: "Deadlift", notes: "", phase: 1,
      programRole: "main", programSlotId: slot.id,
      plannedWeightLb: 220, plannedSets: 5, plannedReps: 5,
      sets: [...Array.from({ length: 5 }, (_, index) => atPlan(index)),
        ...Array.from({ length: 3 }, (_, index) => bonus(5 + index))] }],
  });
  const builtId = await session.createSessionFromProgramDay(program, program.days[0]);
  const built = await db.Sessions.get(builtId);
  const deadlift = built.exercises.find((entry) => entry.exerciseName === "Deadlift");
  ok(deadlift.plannedWeightLb === 235,
    `[INV-ADVANCE-BUYS-PLATES] bonus 245×3 lifts the 226-base card to 235 (got ${deadlift.plannedWeightLb})`);
  await db.Sessions.del(builtId);

  // A failed heavy attempt (zero reps, marked completed) is not capability
  // evidence — without real reps the bonus row must not raise the plan.
  const failedTag = { ...((await db.Sessions.get(priorId)).programTag) };
  await db.Sessions.del(priorId);
  const failedId = await db.Sessions.save({
    date: db.iso(new Date(Date.now() - 20 * 86400000)), notes: "", isCompleted: true,
    completedAt: db.iso(new Date(Date.now() - 20 * 86400000)), gymName: null,
    programTag: failedTag,
    exercises: [{ order: 0, exerciseName: "Deadlift", notes: "", phase: 1,
      programRole: "main", programSlotId: slot.id,
      plannedWeightLb: 220, plannedSets: 5, plannedReps: 5,
      sets: [...Array.from({ length: 5 }, (_, index) => atPlan(index)),
        { ...bonus(5), reps: 0 }] }],
  });
  const failedBuiltId = await session.createSessionFromProgramDay(program, program.days[0]);
  const failedBuilt = await db.Sessions.get(failedBuiltId);
  ok(failedBuilt.exercises.find((entry) => entry.exerciseName === "Deadlift").plannedWeightLb === 225,
    "[INV-ADVANCE-BUYS-PLATES] a zero-rep bonus attempt never arms catch-up");
  await db.Sessions.del(failedBuiltId);
  await db.Sessions.del(failedId);

  // Catch-up is a cycle-slot mechanism: a per-exposure methodology's own
  // rule is its contract, and the plan must stay on the persisted base the
  // style's advance actually writes.
  slot.prescription = "linearFives";
  await db.Programs.save(program);
  const linearProgram = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const linearSlot = linearProgram.days[0].lifts[0];
  const linearPriorId = await db.Sessions.save({
    date: db.iso(new Date(Date.now() - 4 * 86400000)), notes: "", isCompleted: true,
    completedAt: db.iso(new Date(Date.now() - 4 * 86400000)), gymName: null,
    programTag: { programId: linearProgram.uuid || linearProgram.id, programName: name,
      cycleNumber: 3, week: 1, dayIndex: 0, planNames: ["Deadlift"] },
    exercises: [{ order: 0, exerciseName: "Deadlift", notes: "", phase: 1,
      programRole: "main", programSlotId: linearSlot.id,
      plannedWeightLb: 220, plannedSets: 5, plannedReps: 5,
      sets: [...Array.from({ length: 5 }, (_, index) => atPlan(index)),
        ...Array.from({ length: 3 }, (_, index) => bonus(5 + index))] }],
  });
  const linearBuiltId = await session.createSessionFromProgramDay(linearProgram, linearProgram.days[0]);
  const linearBuilt = await db.Sessions.get(linearBuiltId);
  ok(linearBuilt.exercises.find((entry) => entry.exerciseName === "Deadlift").plannedWeightLb === 225,
    "[INV-ADVANCE-BUYS-PLATES] a per-exposure methodology keeps its own contract — bonus catch-up never overrides it");
  await db.Sessions.del(linearBuiltId);
  await db.Sessions.del(linearPriorId);
  await db.importBundle(parsed);
}

// The repair must read evidence from BEFORE the cycle being planned. A clean
// lb lifter's own week-1 session (performed exactly at the honestly-advanced
// base) is NOT proof the advance was stale — feeding it back would inflate
// the load and peak rotations by a full unearned increment, every cycle.
{
  const name = "Fixture Cycle-Scoped Evidence";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 2, currentWeek: 2, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Pull", order: 0, accessories: [],
      lifts: [{ exerciseName: "Deadlift", role: "main", prescription: "wave",
        baseWeightLb: 225, estimatedMaxLb: 280, stallCount: 0, lastIncrementLb: 10 }] }],
  });
  const program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const slot = program.days[0].lifts[0];
  const banked = (cycleNumber, week, weightLb, daysAgo) => ({
    date: db.iso(new Date(Date.now() - daysAgo * 86400000)), notes: "", isCompleted: true,
    completedAt: db.iso(new Date(Date.now() - daysAgo * 86400000)), gymName: null,
    programTag: { programId: program.uuid || program.id, programName: name,
      cycleNumber, week, dayIndex: 0, planNames: ["Deadlift"] },
    exercises: [{ order: 0, exerciseName: "Deadlift", notes: "", phase: week,
      programRole: "main", programSlotId: slot.id,
      plannedWeightLb: weightLb, plannedSets: 5, plannedReps: 5,
      sets: Array.from({ length: 5 }, (_, index) => ({
        order: index, weightLb, reps: 5, isWarmup: false, isPerSide: false,
        enteredUnit: "lb", status: "completed", loadBasis: "totalBar", flags: [],
        bodyFlagSite: null, autoregReason: null, prescriptionBlock: "work",
      })) }],
  });
  // Last cycle's R1 at 215 (the advance to 225 was honestly earned), and THIS
  // cycle's R1 performed exactly at the advanced 225.
  const lastCycleId = await db.Sessions.save(banked(1, 1, 215, 21));
  const thisCycleId = await db.Sessions.save(banked(2, 1, 225, 3));
  const builtId = await session.createSessionFromProgramDay(program, program.days[0]);
  const built = await db.Sessions.get(builtId);
  const deadlift = built.exercises.find((entry) => entry.exerciseName === "Deadlift");
  const honest = C.programPlanFor(
    { cycleNumber: 2, baseWeightLb: 225, nextPhase: 2, incrementLb: 0 },
    5, "barbell", "hinge", "main", "strength", "wave",
    { ...slot, workingSets: slot.doubleProgressionSets ?? 3 },
  ).weightLb;
  ok(deadlift.targetWeightLb === honest,
    `[INV-ADVANCE-BUYS-PLATES] a clean lifter's own week-1 bank never inflates the load rotation (got ${deadlift.targetWeightLb}, want ${honest})`);
  await db.Sessions.del(builtId);
  await db.Sessions.del(thisCycleId);
  await db.Sessions.del(lastCycleId);
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

// A recovery exposure is observation-free and progression-free.
{
  const name = "Fixture Deload Observation";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 4, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower", order: 0, accessories: [acc("Walking Lunges", 0, 0)],
      lifts: [
        { exerciseName: "Back Squat", role: "main", prescription: "wave",
          baseWeightLb: 190, estimatedMaxLb: 221.45, stallCount: 0, lastIncrementLb: 5 },
        { ...cyc("Deadlift", "complementary", 205, 275), prescription: "linearFives", doubleProgressionSets: 3 },
        { ...cyc("Incline DB Press", "complementary", 45, 55), prescription: "doubleProgression",
          doubleProgressionSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 5 },
      ] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const before = JSON.parse(JSON.stringify(program.days[0]));
  const deloadId = await session.createSessionFromProgramDay(program, program.days[0]);
  const deload = await db.Sessions.get(deloadId);
  ok(deload.exercises.find((entry) => entry.programRole === "accessory").plannedSets === 1,
    "a recovery accessory is reduced to one set");
  for (const set of deload.exercises[0].sets) set.status = "completed";
  for (const entry of deload.exercises.slice(1)) for (const set of entry.sets) set.status = "completed";
  await session.completeSession(deload);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.days[0].lifts[0].estimatedMaxLb === 221.45,
    `light deload work is not evidence the max fell (got ${program.days[0].lifts[0].estimatedMaxLb})`);
  ok(program.days[0].lifts[1].baseWeightLb === before.lifts[1].baseWeightLb,
    "recovery cannot advance a per-exposure linear lift");
  ok(program.days[0].lifts[2].baseWeightLb === before.lifts[2].baseWeightLb
    && program.days[0].lifts[2].currentReps === before.lifts[2].currentReps,
  "recovery cannot advance a lift-level rep window");
  ok(program.days[0].accessories[0].currentReps === before.accessories[0].currentReps,
    "recovery cannot advance accessory double progression");

  await db.importBundle(parsed);
}

// A bodyweight rep-window LIFT slot progresses by reps alone — its identity
// carries no external load, so a numeric increment would store weight that
// history, tonnage, and PR detection all ignore (adding a belt is switching
// to the Weighted Pull-up identity). A loaded slot still earns the step.
{
  const name = "Fixture Bodyweight Rep Window";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Upper", order: 0, accessories: [],
      lifts: [
        { exerciseName: "Overhead Press", role: "main", prescription: "wave",
          baseWeightLb: 95, estimatedMaxLb: 130, stallCount: 0, lastIncrementLb: 0 },
        { exerciseName: "Pull-ups", role: "complementary", prescription: "doubleProgression",
          doubleProgressionSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 8,
          baseWeightLb: 0, estimatedMaxLb: 0, stallCount: 0, lastIncrementLb: 0 },
        { exerciseName: "Incline DB Press", role: "complementary", prescription: "doubleProgression",
          doubleProgressionSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 8,
          baseWeightLb: 45, estimatedMaxLb: 60, stallCount: 0, lastIncrementLb: 0 },
      ] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const id = await session.createSessionFromProgramDay(program, program.days[0]);
  const topped = await db.Sessions.get(id);
  for (const entry of topped.exercises) for (const set of entry.sets) set.status = "completed";
  await session.completeSession(topped);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const pullups = program.days[0].lifts.find((l) => l.exerciseName === "Pull-ups");
  const inclineDb = program.days[0].lifts.find((l) => l.exerciseName === "Incline DB Press");
  ok(pullups.baseWeightLb === 0 && pullups.currentReps === 9,
    `a bodyweight rep-window lift tops its window by adding reps, never phantom load (got ${pullups.baseWeightLb} @ ${pullups.currentReps})`);
  ok(inclineDb.baseWeightLb === 50 && inclineDb.currentReps === 5,
    `a loaded rep-window lift still earns the step and resets the window (got ${inclineDb.baseWeightLb} @ ${inclineDb.currentReps})`);

  await db.importBundle(parsed);
}

// A non-loadable slot's stored load step is IGNORED at advance time, never
// destroyed. Banking gates the increment to zero for the advance, but writing
// that zero back would silently delete a step the lifter configured (staged
// for the weighted variant, or a basis fix away from mattering) — and the
// editor warning that explains it would vanish with the data.
{
  const name = "Fixture Stored Step Survives";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Upper", order: 0,
      lifts: [{ exerciseName: "Overhead Press", role: "main", prescription: "wave",
        baseWeightLb: 95, estimatedMaxLb: 130, stallCount: 0, lastIncrementLb: 0 }],
      accessories: [{ exerciseName: "Pull-ups", sets: 3, minReps: 8, maxReps: 12,
        currentReps: 8, weightLb: 0, incrementLb: 5, stallCount: 0 }] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const id = await session.createSessionFromProgramDay(program, program.days[0]);
  const workout = await db.Sessions.get(id);
  for (const entry of workout.exercises) for (const set of entry.sets) set.status = "completed";
  await session.completeSession(workout);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const pullups = program.days[0].accessories[0];
  ok(pullups.incrementLb === 5,
    `banking ignores a bodyweight slot's stored step without destroying it (got ${pullups.incrementLb})`);
  ok(pullups.weightLb === 0 && pullups.currentReps === 9,
    `and the slot still progresses by reps alone (got ${pullups.weightLb} @ ${pullups.currentReps})`);

  await db.importBundle(parsed);
}

// The banking bridge reads a lift's rep window exactly the way the
// prescription did — raw stored values through repWindow, no view-layer
// defaults. A legacy record with zeroed endpoints prescribed its floored
// window; grading it against `|| 5` defaults failed a performed prescription.
{
  const name = "Fixture Legacy Zero Window";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Upper", order: 0, accessories: [],
      lifts: [
        { exerciseName: "Overhead Press", role: "main", prescription: "wave",
          baseWeightLb: 95, estimatedMaxLb: 130, stallCount: 0, lastIncrementLb: 0 },
        { exerciseName: "Incline DB Press", role: "complementary", prescription: "doubleProgression",
          doubleProgressionSets: 3, minimumReps: 0, maximumReps: 0, currentReps: 2,
          baseWeightLb: 45, estimatedMaxLb: 60, stallCount: 0, lastIncrementLb: 0 },
      ] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const id = await session.createSessionFromProgramDay(program, program.days[0]);
  const workout = await db.Sessions.get(id);
  const dbEntry = workout.exercises.find((entry) => entry.exerciseName === "Incline DB Press");
  const workReps = dbEntry.sets.filter((set) => !set.isWarmup).map((set) => set.reps);
  ok(workReps.every((reps) => reps === 1),
    `a zeroed window prescribes its floor, not a default (got ${workReps})`);
  for (const entry of workout.exercises) for (const set of entry.sets) set.status = "completed";
  await session.completeSession(workout);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const lift = program.days[0].lifts.find((l) => l.exerciseName === "Incline DB Press");
  ok(lift.stallCount === 0,
    `a performed prescription can never fail its own grade (stallCount ${lift.stallCount})`);

  await db.importBundle(parsed);
}

// The program overview runs the same engine reading as every other surface:
// the slot's loadability and set count reach the plan, so the overview and
// the Today card can never quote different numbers for the same slot.
{
  const name = "Fixture Overview Parity";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Upper", order: 0, accessories: [],
      lifts: [
        { exerciseName: "Overhead Press", role: "main", prescription: "wave",
          baseWeightLb: 95, estimatedMaxLb: 130, stallCount: 0, lastIncrementLb: 0 },
        { exerciseName: "Pull-ups", role: "complementary", prescription: "doubleProgression",
          doubleProgressionSets: 5, minimumReps: 5, maximumReps: 8, currentReps: 9,
          baseWeightLb: 0, estimatedMaxLb: 0, stallCount: 0, lastIncrementLb: 0 },
      ] }],
  });
  await programView.render(host());
  const card = [...host().querySelectorAll(".program-day-card")]
    .find((row) => row.textContent.includes("Pull-ups"));
  ok(card && card.textContent.includes("5×9"),
    `the overview quotes the uncapped bodyweight target the lifter is graded against (got ${card && card.textContent.match(/\d+×\d+/g)})`);

  await db.importBundle(parsed);
}

// A slot whose exercise is missing from the library must not fail OPEN: the
// "Needs progression" pill and the editor's no-increment warning both fall
// back to the inferred (external) basis instead of going silent — the quietly
// stuck slot is exactly what they exist to flag. A crossed rep window is also
// warned about on EVERY lift, not just double-progression ones, because the
// program-file contract rejects the stored pair regardless of style.
{
  const name = "Fixture Ghost And Crossed";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Upper", order: 0,
      lifts: [
        { exerciseName: "Overhead Press", role: "main", prescription: "wave",
          baseWeightLb: 95, estimatedMaxLb: 130, stallCount: 0, lastIncrementLb: 0,
          minimumReps: 9, maximumReps: 5, currentReps: 5 },
      ],
      accessories: [{ exerciseName: "Ghost Cable Row", sets: 3, minReps: 8, maxReps: 12,
        currentReps: 12, weightLb: 40, incrementLb: 0, stallCount: 0 }] }],
  });
  const program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  await programView.render(host());
  const card = [...host().querySelectorAll(".program-day-card")]
    .find((row) => row.textContent.includes("1 accessories"));
  ok(card && card.textContent.includes("Needs progression"),
    "a loaded no-increment slot is flagged even when its exercise is missing from the library");

  settings.programEditor(program); await tick();
  const editor = [...document.querySelectorAll("#overlays .overlay")].at(-1);
  ok(editor && editor.textContent.includes("Ghost Cable Row carries load but has no increment"),
    "the editor's no-increment warning survives a missing exercise");
  ok(editor && editor.textContent.includes("Overhead Press's minimum reps exceed its maximum; program export will reject it."),
    "a crossed window warns on every lift the export contract rejects, whatever its style");
  document.getElementById("overlays").replaceChildren();

  await db.importBundle(parsed);
}

// The rep-window steppers never touch the slot's banked target: exploring the
// endpoints up and back down must not inject reps the lifter never earned.
// And a carry updates only the SIBLING stepper node — never a full editor
// redraw that replaces the control under the finger pressing it.
{
  const name = "Fixture Stepper Honesty";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Upper", order: 0,
      lifts: [
        { exerciseName: "Overhead Press", role: "main", prescription: "wave",
          baseWeightLb: 95, estimatedMaxLb: 130, stallCount: 0, lastIncrementLb: 0 },
        { exerciseName: "Incline DB Press", role: "complementary", prescription: "doubleProgression",
          doubleProgressionSets: 3, minimumReps: 8, maximumReps: 10, currentReps: 8,
          baseWeightLb: 45, estimatedMaxLb: 60, stallCount: 0, lastIncrementLb: 0 },
      ],
      accessories: [{ exerciseName: "Face Pulls", sets: 3, minReps: 8, maxReps: 12,
        currentReps: 8, weightLb: 40, incrementLb: 5, stallCount: 0 }] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  settings.programEditor(program); await tick();
  const editorOverlay = [...document.querySelectorAll("#overlays .overlay")].at(-1);
  const dayLead = [...editorOverlay.querySelectorAll(".lead")].find((el) => el.textContent.includes("Upper"));
  dayLead.click(); await tick();
  let dayEditor = [...document.querySelectorAll("#overlays .overlay")].at(-1);
  const windowRow = () => [...dayEditor.querySelectorAll(".row")]
    .find((r) => r.textContent.includes("Sets / rep window"));
  let steppers = windowRow().querySelectorAll(".stepper");
  const minStepper = steppers[1];
  const minUp = () => [...minStepper.querySelectorAll("button")].at(-1);
  const minDown = () => minStepper.querySelectorAll("button")[0];

  // 8 → 9 → 10: inside the window, nothing carried, nothing else moves.
  minUp().click(); await tick();
  minUp().click(); await tick();
  // 10 → 11: crosses the maximum. The maximum carries; the tapped stepper
  // itself must survive (no full redraw).
  minUp().click(); await tick();
  ok(document.contains(minStepper),
    "a carry redraws only the sibling stepper, not the editor under the lifter's finger");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  let lift = program.days[0].lifts.find((l) => l.exerciseName === "Incline DB Press");
  ok(lift.minimumReps === 11 && lift.maximumReps === 11,
    `the maximum carries with the minimum (got ${lift.minimumReps}-${lift.maximumReps})`);
  ok(windowRow().textContent.includes("11"),
    "the carried maximum is visible without a manual refresh");
  // Back down to 8: the window returns, and the banked target was NEVER
  // touched — the old setters ratcheted it to 11 here.
  minDown().click(); await tick();
  minDown().click(); await tick();
  minDown().click(); await tick();
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  lift = program.days[0].lifts.find((l) => l.exerciseName === "Incline DB Press");
  ok(lift.currentReps === 8,
    `exploring the endpoints injects no unearned reps into a lift (got currentReps ${lift.currentReps})`);
  ok(lift.minimumReps === 8 && lift.maximumReps === 11,
    `endpoints land where they were tapped (got ${lift.minimumReps}-${lift.maximumReps})`);

  // The accessory pair follows the same rules.
  dayEditor = [...document.querySelectorAll("#overlays .overlay")].at(-1);
  const repRange = [...dayEditor.querySelectorAll(".row")].find((r) => r.textContent.includes("Rep range"));
  const accSteppers = repRange.querySelectorAll(".stepper");
  const accMinUp = [...accSteppers[0].querySelectorAll("button")].at(-1);
  const accMinDown = accSteppers[0].querySelectorAll("button")[0];
  accMinUp.click(); await tick();
  accMinDown.click(); await tick();
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const accessory = program.days[0].accessories[0];
  ok(accessory.currentReps === 8,
    `exploring the endpoints injects no unearned reps into an accessory (got currentReps ${accessory.currentReps})`);
  document.getElementById("overlays").replaceChildren();

  await db.importBundle(parsed);
}


// A 5/3/1 day is ALL amrap and ramp blocks — it has no ordinary `work` set at
// all. Every gate that asked "is this `work`" therefore answered no, so the
// session banked as history and the schedule never advanced. The template was
// completely inert.
{
  const name = "Fixture 531 Advance";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower", order: 0, accessories: [],
      lifts: [{ exerciseName: "Back Squat", role: "main", prescription: "fiveThreeOne",
        baseWeightLb: 300, estimatedMaxLb: 340, stallCount: 0, lastIncrementLb: 0 }] }],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const id = await session.createSessionFromProgramDay(program, program.days[0]);
  const s531 = await db.Sessions.get(id);
  const blocks = s531.exercises[0].sets.filter((set) => !set.isWarmup).map((set) => set.prescriptionBlock);
  ok(blocks.includes("amrap") && !blocks.includes("work"),
    `a 531 day carries an amrap top set and no ordinary work set (${blocks})`);
  for (const set of s531.exercises[0].sets) set.status = "completed";
  await session.completeSession(s531);
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.currentWeek === 2, `banking a 531 day advances the rotation (got ${program.currentWeek})`);

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

// ---- main-first ordering makes a stale first complementary slot bridge ----
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
  ok(built.exercises[0].programRole === "main",
    "a main lift executes before a complementary lift despite crossed authored orders");
  const cold = built.exercises.find((entry) => entry.programRole === "complementary");
  ok(cold.sets.filter((set) => set.isWarmup).length === 2,
    "[INV-COMP-WARMUP-BRIDGE] role-first ordering lets the complementary lift use its two-step bridge");
  await db.Sessions.del(sId);
  await db.Programs.del(prog.id);

  const onlyName = "Fixture Cold Complementary Only";
  await db.Programs.save({
    name: onlyName, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Lower", order: 0,
      lifts: [{ ...cyc("Deadlift", "complementary", 185, 255), order: 0 }],
      accessories: [] }],
  });
  const onlyProgram = (await db.Programs.all()).find((candidate) => candidate.name === onlyName);
  const onlySessionID = await session.createSessionFromProgramDay(onlyProgram, onlyProgram.days[0]);
  const onlyBuilt = await db.Sessions.get(onlySessionID);
  ok(onlyBuilt.exercises[0].sets.filter((set) => set.isWarmup).length > 2,
    "[INV-COMP-WARMUP-BRIDGE] a complementary-only day keeps the full cold ramp");
  await db.Sessions.del(onlySessionID);
  await db.Programs.del(onlyProgram.id);
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

// ---- program: bank three full progressions + a two-exposure recovery bridge ----
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

  const recoveryDays = [];
  for (let i = 1; i < 14; i++) { // 3 × 4 progression exposures + 2 recovery exposures
    prog = await db.Programs.active();
    const day = prog.days.find((d) => d.order === prog.nextDayIndex);
    const id = await session.createSessionFromProgramDay(prog, day);
    const sess = await db.Sessions.get(id);
    if (sess.programTag.week === C.DELOAD_WEEK) {
      recoveryDays.push(day.name);
      ok(sess.exercises.filter((entry) => entry.programRole === "accessory")
        .every((entry) => entry.plannedSets === 1),
      "[INV-RECOVERY-IS-A-BRIDGE] every recovery accessory is reduced to one easy set");
    }
    await completeAll(sess); // pre-filled working sets at target = a clean cycle
  }

  prog = await db.Programs.active();
  ok(prog.cycleNumber === 2, `cycle rolled over (cyc=${prog.cycleNumber})`);
  ok(prog.currentWeek === 1, `wave reset to week 1 (wk=${prog.currentWeek})`);
  ok(recoveryDays.join(",") === "Lower A,Upper A",
    `[INV-RECOVERY-IS-A-BRIDGE] phase 4 banks one lower and one upper exposure (${recoveryDays})`);
  const squatMain = prog.days[0].lifts.find((l) => l.role === "main");
  // A freshly seeded base sits well under the template's estimated max, so
  // the headroom axis reads rebuild and the clean cycle earns the +10 class
  // — new programs climb out of their conservative start at novice-LP pace
  // instead of change-plate crumbs, and the axis stands down at 85%.
  ok(squatMain.baseWeightLb === squatBase0 + 10,
    `[INV-NEEDLE-ALWAYS-MOVES] clean rebuild cycle bumped squat ${squatBase0}→${squatMain.baseWeightLb} (+10 class)`);
  ok(squatMain.estimatedMaxLb > 204, "e1RM updated from the peak");
  ok(prog.days[1].accessories[0].currentReps > accReps0, "accessory reps progressed (double progression)");
  ok((await db.Tracks.byName("Back Squat")).baseWeightLb === sqTrackBase, "standalone Back Squat track NOT double-advanced");
}

// ---- in-flight legacy phase 4 accounts for bridge work already banked ----
{
  const name = "Fixture In-flight Recovery Bridge";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: C.DELOAD_WEEK,
    nextDayIndex: 2, roundingLb: 5, isActive: false,
    days: [
      { name: "Lower A", order: 0, lifts: [cyc("Back Squat", "main", 175, 225)], accessories: [] },
      { name: "Upper A", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
      { name: "Lower B", order: 2, lifts: [cyc("Deadlift", "main", 205, 275)], accessories: [] },
      { name: "Upper B", order: 3, lifts: [cyc("Overhead Press", "main", 95, 125)], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const priorIds = [];
  for (const [index, dayIndex] of [0, 1].entries()) {
    priorIds.push(await db.Sessions.save({
      date: `2042-01-0${index + 1}T12:00:00.000Z`,
      completedAt: `2042-01-0${index + 1}T13:00:00.000Z`,
      notes: "Synthetic pre-upgrade recovery exposure", isCompleted: true,
      programTag: { programId: program.uuid, programName: name,
        cycleNumber: 1, week: C.DELOAD_WEEK, dayIndex, planNames: [] },
      exercises: [],
    }));
  }

  // The previous release expected all four phase-4 days, so its persisted
  // pointer can legitimately sit on Lower B even though the new bridge's
  // Lower A and Upper A representatives are already complete. Today must
  // reconcile that state before it creates a third recovery workout.
  const reconciliation = await session.reconcileRecoveryBridge(
    program, await db.Sessions.completed(), new Date("2042-01-03T12:00:00.000Z"),
  );
  ok(reconciliation?.reason === "selectedExposures",
    "already-banked bridge representatives are recognized before Start");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.cycleNumber === 2 && program.currentWeek === 1 && program.nextDayIndex === 0,
    "[INV-RECOVERY-IS-A-BRIDGE] an in-flight old phase-4 pointer rolls over from already-banked bridge exposures");

  for (const id of priorIds) await db.Sessions.del(id);
  await db.Programs.del(program.id);
}

// ---- recovery is capped at two sessions and expires after seven days ----
{
  const name = "Fixture Bounded Recovery";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 7, currentWeek: C.DELOAD_WEEK,
    nextDayIndex: 2, roundingLb: 5, isActive: false,
    days: [
      { name: "Lower A", order: 0, lifts: [cyc("Back Squat", "main", 175, 225)], accessories: [] },
      { name: "Upper A", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
      { name: "Lower B", order: 2, lifts: [cyc("Deadlift", "main", 205, 275)], accessories: [] },
      { name: "Upper B", order: 3, lifts: [cyc("Overhead Press", "main", 95, 125)], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const ids = [];
  ids.push(await db.Sessions.save({
    date: "2042-02-01T12:00:00.000Z", completedAt: "2042-02-01T13:00:00.000Z",
    notes: "Synthetic Peak anchor", isCompleted: true,
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 7, week: C.GRADED_WEEK, dayIndex: 3, planNames: [] }, exercises: [],
  }));
  for (const [index, dayIndex] of [2, 3].entries()) {
    ids.push(await db.Sessions.save({
      date: `2042-02-0${index + 2}T12:00:00.000Z`,
      completedAt: `2042-02-0${index + 2}T13:00:00.000Z`,
      notes: "Synthetic non-selected Recovery", isCompleted: true,
      programTag: { programId: program.uuid, programName: name,
        cycleNumber: 7, week: C.DELOAD_WEEK, dayIndex, planNames: [] }, exercises: [],
    }));
  }
  const capped = await session.reconcileRecoveryBridge(
    program, await db.Sessions.completed(), new Date("2042-02-04T12:00:00.000Z"),
  );
  ok(capped?.reason === "sessionLimit",
    "[INV-RECOVERY-IS-A-BRIDGE] two recovery sessions close the bridge even on non-selected days");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.cycleNumber === 8 && program.currentWeek === 1 && program.nextDayIndex === 0,
    "the two-session cap starts the next cycle at Volume day 1");
  for (const id of ids) await db.Sessions.del(id);
  await db.Programs.del(program.id);
}

{
  const name = "Fixture Expired Recovery";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 4, currentWeek: C.DELOAD_WEEK,
    nextDayIndex: 0, roundingLb: 5, isActive: false,
    days: [
      { name: "Lower A", order: 0, lifts: [cyc("Back Squat", "main", 175, 225)], accessories: [] },
      { name: "Upper A", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const peakID = await db.Sessions.save({
    date: "2042-03-01T12:00:00.000Z", completedAt: "2042-03-01T13:00:00.000Z",
    notes: "Synthetic Peak anchor", isCompleted: true,
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 4, week: C.GRADED_WEEK, dayIndex: 1, planNames: [] }, exercises: [],
  });
  // The window is fixed to Peak even before reduced work is banked.
  const beforeBoundary = await session.reconcileRecoveryBridge(
    program, await db.Sessions.completed(), new Date("2042-03-08T12:59:59.999Z"),
  );
  ok(beforeBoundary === null,
    "[INV-RECOVERY-IS-A-BRIDGE] Recovery remains available inside seven days of Peak");

  // Banking reduced work does not start a fresh seven-day window.
  const recoveryID = await db.Sessions.save({
    date: "2042-03-02T12:00:00.000Z", completedAt: "2042-03-02T13:00:00.000Z",
    notes: "Synthetic recovery exposure", isCompleted: true,
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 4, week: C.DELOAD_WEEK, dayIndex: 0, planNames: [] }, exercises: [],
  });
  const inside = await session.reconcileRecoveryBridge(
    program, await db.Sessions.completed(), new Date("2042-03-08T12:59:59.999Z"),
  );
  ok(inside === null, "Recovery remains available one millisecond before the seven-day boundary");
  const expired = await session.reconcileRecoveryBridge(
    program, await db.Sessions.completed(), new Date("2042-03-08T13:00:00.000Z"),
  );
  ok(expired?.reason === "windowElapsed",
    "[INV-RECOVERY-IS-A-BRIDGE] the bridge expires seven days after Peak, not seven days after reduced work");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.cycleNumber === 5 && program.currentWeek === 1,
    "expired Recovery starts the next cycle rather than prescribing stale reduced work");
  await db.Sessions.del(recoveryID);
  await db.Sessions.del(peakID);
  await db.Programs.del(program.id);
}

{
  const name = "Fixture Recovery Start Guard";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 2, currentWeek: C.DELOAD_WEEK,
    nextDayIndex: 0, roundingLb: 5, isActive: false,
    days: [
      { name: "Lower A", order: 0, lifts: [cyc("Back Squat", "main", 175, 225)], accessories: [] },
      { name: "Upper A", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const oldPeak = new Date(Date.now() - C.RECOVERY_WINDOW_MS - 60_000);
  const peakID = await db.Sessions.save({
    date: oldPeak.toISOString(), completedAt: oldPeak.toISOString(),
    notes: "Synthetic expired Peak", isCompleted: true,
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 2, week: C.GRADED_WEEK, dayIndex: 1, planNames: [] }, exercises: [],
  });
  // Half-finished: one recovery exposure banked, then eight days of silence.
  const staleRecovery = new Date(Date.now() - C.RECOVERY_WINDOW_MS - 30_000);
  const recoveryID = await db.Sessions.save({
    date: staleRecovery.toISOString(), completedAt: staleRecovery.toISOString(),
    notes: "Synthetic stale recovery exposure", isCompleted: true,
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 2, week: C.DELOAD_WEEK, dayIndex: 0, planNames: [] }, exercises: [],
  });
  const createdID = await session.createSessionFromProgramDay(program, program.days[0]);
  const created = await db.Sessions.get(createdID);
  ok(created.programTag.cycleNumber === 3 && created.programTag.week === 1,
    "Start reconciles expired Recovery and creates Volume work in the next cycle");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.cycleNumber === 3 && program.currentWeek === 1,
    "Start never creates a stale third recovery prescription");
  await db.Sessions.del(createdID);
  await db.Sessions.del(recoveryID);
  await db.Sessions.del(peakID);
  await db.Programs.del(program.id);
}

// Reconciliation must never advance the program out from under a workout in
// progress: the open session was built against this rotation, so rolling the
// cycle makes banking it fail the stale-tag guard and land as orphaned history.
// On this client it also let Start open a SECOND session while the first
// stayed open.
{
  const name = "Fixture Recovery Open Session";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 2, currentWeek: C.DELOAD_WEEK,
    nextDayIndex: 0, roundingLb: 5, isActive: false,
    days: [
      { name: "Lower A", order: 0, lifts: [cyc("Back Squat", "main", 175, 225)], accessories: [] },
      { name: "Upper A", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const stale = new Date(Date.now() - C.RECOVERY_WINDOW_MS - 60_000);
  const peakID = await db.Sessions.save({
    date: stale.toISOString(), completedAt: stale.toISOString(),
    notes: "Synthetic expired Peak", isCompleted: true,
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 2, week: C.GRADED_WEEK, dayIndex: 1, planNames: [] }, exercises: [],
  });
  const recoveryID = await db.Sessions.save({
    date: stale.toISOString(), completedAt: stale.toISOString(),
    notes: "Synthetic stale recovery exposure", isCompleted: true,
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 2, week: C.DELOAD_WEEK, dayIndex: 0, planNames: [] }, exercises: [],
  });
  // Everything is in place for the bridge to expire — except that a workout is
  // open right now.
  const openID = await db.Sessions.save({
    date: new Date().toISOString(), isCompleted: false, notes: "In progress",
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 2, week: C.DELOAD_WEEK, dayIndex: 0, planNames: [] }, exercises: [],
  });
  const blocked = await session.reconcileRecoveryBridge(program, await db.Sessions.completed());
  ok(blocked === null,
    "[INV-RECOVERY-IS-A-BRIDGE] reconciliation holds off while a session is open");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.cycleNumber === 2 && program.currentWeek === C.DELOAD_WEEK,
    "the program the open session was built against is left exactly as it was");

  // Scoped to THIS program. A lingering blank session — which Today explicitly
  // supports keeping around — must not suppress the cap and the expiry window
  // indefinitely; that is the indefinite-light-work path this mechanism closes.
  await db.Sessions.del(openID);
  const blankID = await db.Sessions.save({
    date: new Date().toISOString(), isCompleted: false, notes: "Unrelated blank session",
    exercises: [],
  });
  const unrelated = await session.reconcileRecoveryBridge(program, await db.Sessions.completed());
  ok(unrelated?.reason === "windowElapsed",
    "an open session belonging to no program never blocks reconciliation");
  await db.Sessions.del(blankID);
  // Put the program back into recovery for the final leg of this scenario.
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  program.cycleNumber = 2; program.currentWeek = C.DELOAD_WEEK;
  await db.Programs.save(program);
  const openID2 = await db.Sessions.save({
    date: new Date().toISOString(), isCompleted: false, notes: "In progress",
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 2, week: C.DELOAD_WEEK, dayIndex: 0, planNames: [] }, exercises: [],
  });
  ok((await session.reconcileRecoveryBridge(program, await db.Sessions.completed())) === null,
    "but one belonging to this program still does");
  await db.Sessions.del(openID2);

  // Bank or discard it and the same reconciliation goes through.
  const allowed = await session.reconcileRecoveryBridge(program, await db.Sessions.completed());
  ok(allowed?.reason === "windowElapsed", "and runs on the next render once nothing is open");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  await db.Sessions.del(recoveryID);
  await db.Sessions.del(peakID);
  await db.Programs.del(program.id);
}

// A program that is not recognizably upper/lower keeps its FULL authored pass.
// Capping that at a constant two dropped day three onward — losing exactly the
// work the fallback exists to preserve.
{
  const name = "Fixture Full Pass Recovery";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: C.DELOAD_WEEK,
    nextDayIndex: 0, roundingLb: 5, isActive: false,
    days: [
      { name: "Full A", order: 0, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
      { name: "Full B", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
      { name: "Full C", order: 2, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const ids = [];
  for (const dayIndex of [0, 1]) {
    ids.push(await db.Sessions.save({
      date: new Date().toISOString(), completedAt: new Date().toISOString(),
      notes: "Synthetic recovery exposure", isCompleted: true,
      programTag: { programId: program.uuid, programName: name,
        cycleNumber: 1, week: C.DELOAD_WEEK, dayIndex, planNames: [] }, exercises: [],
    }));
  }
  const held = await session.reconcileRecoveryBridge(program, await db.Sessions.completed());
  ok(held === null,
    "[INV-RECOVERY-IS-A-BRIDGE] a three-day authored bridge is not closed by two sessions");
  ids.push(await db.Sessions.save({
    date: new Date().toISOString(), completedAt: new Date().toISOString(),
    notes: "Synthetic recovery exposure", isCompleted: true,
    programTag: { programId: program.uuid, programName: name,
      cycleNumber: 1, week: C.DELOAD_WEEK, dayIndex: 2, planNames: [] }, exercises: [],
  }));
  const closed = await session.reconcileRecoveryBridge(program, await db.Sessions.completed());
  ok(closed?.reason === "selectedExposures", "and closes once its own length is banked");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.cycleNumber === 2 && program.currentWeek === 1, "then rolls to the next cycle at Volume");
  for (const id of ids) await db.Sessions.del(id);
  await db.Programs.del(program.id);
}

// Banking is a SECOND call site for the completion rule, and it took the count
// positionally. A three-day authored bridge must not close at bank time after
// two exposures either — that is the same truncation, reached the other way.
{
  const name = "Fixture Full Pass Bank Time";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: C.DELOAD_WEEK,
    nextDayIndex: 0, roundingLb: 5, isActive: false,
    days: [
      { name: "Full A", order: 0, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
      { name: "Full B", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
      { name: "Full C", order: 2, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const banked = [];
  for (const dayIndex of [0, 1]) {
    const day = program.days.find((d) => d.order === dayIndex);
    const id = await session.createSessionFromProgramDay(program, day);
    banked.push(id);
    await completeAll(await db.Sessions.get(id));
    program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  }
  ok(program.cycleNumber === 1 && program.currentWeek === C.DELOAD_WEEK,
    "[INV-RECOVERY-IS-A-BRIDGE] banking two of a three-day bridge does not close it");
  const lastDay = program.days.find((d) => d.order === 2);
  const lastID = await session.createSessionFromProgramDay(program, lastDay);
  banked.push(lastID);
  await completeAll(await db.Sessions.get(lastID));
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.cycleNumber === 2 && program.currentWeek === 1,
    "banking the third closes it and starts the next cycle at Volume");
  for (const id of banked) await db.Sessions.del(id);
  await db.Programs.del(program.id);
}

{
  const name = "Fixture Reused Recovery Name";
  await db.Programs.save({
    name, focus: "strength", cycleNumber: 1, currentWeek: C.DELOAD_WEEK,
    nextDayIndex: 0, roundingLb: 5, isActive: false,
    days: [
      { name: "Lower A", order: 0, lifts: [cyc("Back Squat", "main", 175, 225)], accessories: [] },
      { name: "Upper A", order: 1, lifts: [cyc("Barbell Bench", "main", 135, 175)], accessories: [] },
    ],
  });
  let program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  const ids = [];
  for (const [index, dayIndex] of [0, 1].entries()) {
    ids.push(await db.Sessions.save({
      date: `2042-04-0${index + 1}T12:00:00.000Z`,
      completedAt: `2042-04-0${index + 1}T13:00:00.000Z`,
      notes: "Synthetic session owned by a deleted same-name program", isCompleted: true,
      programTag: { programId: "deleted-program-stable-id", programName: name,
        cycleNumber: 1, week: C.DELOAD_WEEK, dayIndex, planNames: [] }, exercises: [],
    }));
  }
  const collision = await session.reconcileRecoveryBridge(
    program, await db.Sessions.completed(), new Date("2042-04-03T12:00:00.000Z"),
  );
  ok(collision === null,
    "same-name sessions carrying another stable program ID cannot close Recovery");

  // Name fallback remains valid for genuinely legacy sessions with no ID.
  for (const [index, dayIndex] of [0, 1].entries()) {
    ids.push(await db.Sessions.save({
      date: `2042-04-0${index + 3}T12:00:00.000Z`,
      completedAt: `2042-04-0${index + 3}T13:00:00.000Z`,
      notes: "Synthetic legacy same-name Recovery", isCompleted: true,
      programTag: { programId: null, programName: name,
        cycleNumber: 1, week: C.DELOAD_WEEK, dayIndex, planNames: [] }, exercises: [],
    }));
  }
  const legacy = await session.reconcileRecoveryBridge(
    program, await db.Sessions.completed(), new Date("2042-04-05T12:00:00.000Z"),
  );
  ok(legacy?.reason === "selectedExposures",
    "legacy sessions without a stable ID retain the program-name fallback");
  program = (await db.Programs.all()).find((candidate) => candidate.name === name);
  ok(program.cycleNumber === 2 && program.currentWeek === 1,
    "only the legacy fallback sessions close the reused-name program's Recovery");
  for (const id of ids) await db.Sessions.del(id);
  await db.Programs.del(program.id);
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

  // Bank the rest cleanly (2 more peak days + the 2 recovery exposures);
  // rollover applies the stashed grades.
  for (let i = 0; i < 4; i++) {
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
  const { PROGRAM_TEMPLATES, createProgramFromTemplate,
    bootstrapLiftFromHistory, bootstrapAccessoryFromHistory } = await import("../app/js/templates.js");
  ok(PROGRAM_TEMPLATES.length >= 3, "styles on offer: strength, oly, metcon");

  // Cross-language parity anchor: the JS templates must equal the shared
  // fixture byte-for-byte; ProgramTemplateDataTests holds Swift to the same
  // fixture, so either mirror drifting fails its own CI job.
  const { normalizedTemplates } = await import("./template-fixture.mjs");
  const fixture = JSON.parse(await (await import("node:fs/promises")).readFile(new URL("./fixtures/program-templates.json", import.meta.url), "utf8"));
  ok(JSON.stringify(await normalizedTemplates(), null, 2) === JSON.stringify(fixture, null, 2),
    "templates match the shared parity fixture (regenerate via web/tools/generate-template-fixture.mjs)");
  const { normalizedProgrammingDefaults } = await import("./programming-defaults-fixture.mjs");
  const defaultsFixture = JSON.parse(await (await import("node:fs/promises")).readFile(
    new URL("./fixtures/programming-defaults.json", import.meta.url), "utf8"));
  ok(JSON.stringify(await normalizedProgrammingDefaults(), null, 2)
    === JSON.stringify(defaultsFixture, null, 2),
  "programming defaults match the shared Swift/web parity fixture");
  const conjugate = PROGRAM_TEMPLATES.find((template) => template.id === "conjugate");
  ok(conjugate.days.map((day) => day.name).join("|")
    === "Mon — Max Effort Lower|Wed — Max Effort Upper|Fri — Dynamic Effort Lower|Sun — Dynamic Effort Upper",
  "conjugate keeps the source weekly schedule");
  ok(conjugate.days.flatMap((day) => day.lifts)
    .filter((lift) => lift.prescription === "dynamicEffort")
    .map((lift) => lift.startFraction).join(",") === "0.5,0.5,0.4",
  "conjugate starts squat/pull at 50% and speed bench at 40%");
  ok(conjugate.exercises.filter((exercise) => exercise.name.startsWith("Speed"))
    .every((exercise) => exercise.defaultRestSeconds === 60),
  "conjugate speed exercises carry one-minute rest");
  const sled = conjugate.days[2].accessories.find((accessory) => accessory.exerciseName === "Sled Pull");
  ok(sled.sets === 4 && sled.targetSeconds === 60 && sled.conditioningEffort === "easy" && sled.targetRPE === 5,
    "conjugate includes four easy one-minute sled trips");
  // Vertical pulling is main work (issue #126): both Upper/Lower upper days
  // program pull-ups as a LIFT slot on a rep window that earns load, not as
  // an accessory — and every template compat record agrees with the seed.
  const upperLower = PROGRAM_TEMPLATES.find((template) => template.id === "strength-upper-lower");
  const upperDays = upperLower.days.filter((day) => day.name.startsWith("Upper"));
  ok(upperDays.length === 2
    && upperDays.every((day) => day.lifts.some((l) =>
      l.exerciseName === "Pull-ups" && l.prescription === "doubleProgression" && l.sets === 3)),
  "upper/lower trains the vertical pull as programmed lift work on both upper days");
  ok(PROGRAM_TEMPLATES.every((template) => (template.exercises || [])
    .filter((e) => e.name === "Pull-ups").every((e) => e.category === "Main")),
  "every template compat record agrees with the seed: pull-ups are Main");

  const squatBefore = await db.Exercises.byName("Back Squat"); // seeded — must never be overwritten
  for (const t of PROGRAM_TEMPLATES) {
    const id = await createProgramFromTemplate(t);
    const prog = await db.Programs.get(id);
    ok(prog && prog.days.length === t.days.length && prog.focus === t.focus, `${t.id}: program created with all days`);
    ok(!prog.isActive, `${t.id}: not activated over the existing program`);
    ok(prog.days.every((day, dayIndex) =>
      day.lifts.every((l, i) => l.order === i && l.exerciseName === t.days[dayIndex].lifts[i].exerciseName)
      && day.accessories.every((a, i) => a.order === i && a.exerciseName === t.days[dayIndex].accessories[i].exerciseName)),
      `[INV-TIED-ORDER-IS-AUTHORED] ${t.id}: slots carry the template author's written sequence`);
    for (const day of prog.days) {
      for (const lift of day.lifts) {
        const exercise = await db.Exercises.byName(lift.exerciseName);
        if (!["bodyweight", "band", "timed", "conditioning"].includes(exercise.type)) {
          ok(lift.baseWeightLb > 0 && lift.estimatedMaxLb > 0,
            `${t.id}/${lift.exerciseName}: loaded lift receives a nonblank bootstrap`);
        }
      }
      for (const accessory of day.accessories) {
        const exercise = await db.Exercises.byName(accessory.exerciseName);
        if (!["bodyweight", "band", "timed", "conditioning"].includes(exercise.type)) {
          ok(accessory.weightLb > 0 && accessory.incrementLb > 0,
            `${t.id}/${accessory.exerciseName}: loaded accessory receives a nonblank bootstrap`);
        }
      }
    }
    if (t.id === "strength-upper-lower") {
      const defaults = await import("../app/js/programming-defaults.js");
      const ytw = defaults.recommendation("Y-T-W Raises", "Accessory", "dumbbell");
      ok(ytw.weightLb === 5 && ytw.incrementLb === 2.5,
        "Y-T-W raises have a genuinely light 5 lb per-dumbbell fallback");
    }
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

  // A first-session correction becomes the next template's starting point;
  // defaults are not sticky user state.
  const ytwHistoryID = await db.Sessions.save({
    date: new Date("2035-06-01T10:00:00Z").toISOString(), notes: "", isCompleted: true,
    completedAt: new Date("2035-06-01T10:30:00Z").toISOString(),
    exercises: [{ exerciseName: "Y-T-W Raises", sets: [
      { order: 0, weightLb: 2.5, reps: 12, isWarmup: false, status: "completed", flags: [] },
    ] }],
  });
  const upperLowerFromHistory = await db.Programs.get(await createProgramFromTemplate(
    PROGRAM_TEMPLATES.find((t) => t.id === "strength-upper-lower")));
  ok(upperLowerFromHistory.days[0].accessories.find((a) => a.exerciseName === "Y-T-W Raises")?.weightLb === 2.5,
    "a recorded Y-T-W correction replaces the generic bootstrap in the next program");
  await db.Programs.del(upperLowerFromHistory.id);
  await db.Sessions.del(ytwHistoryID);

  // History is global to the lifter, not trapped inside the program that
  // produced it: a later Oly or conditioning block should pick it up.
  const snatchHistoryID = await db.Sessions.save({
    date: new Date("2036-01-01T10:00:00Z").toISOString(), notes: "", isCompleted: true,
    exercises: [{ exerciseName: "Snatch", sets: [
      { order: 0, weightLb: 95, reps: 3, isWarmup: false, status: "completed", flags: [] },
    ] }],
  });
  const swingHistoryID = await db.Sessions.save({
    date: new Date("2036-01-02T10:00:00Z").toISOString(), notes: "", isCompleted: true,
    exercises: [{ exerciseName: "KB Swing", sets: [
      { order: 0, weightLb: 40, reps: 15, isWarmup: false, status: "completed", flags: [] },
    ] }],
  });
  const olyFromHistory = await db.Programs.get(await createProgramFromTemplate(
    PROGRAM_TEMPLATES.find((t) => t.id === "olympic-weightlifting")));
  const metconFromHistory = await db.Programs.get(await createProgramFromTemplate(
    PROGRAM_TEMPLATES.find((t) => t.id === "metabolic-conditioning")));
  const olySnatch = olyFromHistory.days[0].lifts[0];
  const olyOverheadSquat = olyFromHistory.days[1].lifts.find((lift) => lift.exerciseName === "Overhead Squat");
  ok(olySnatch.baseWeightLb === 70 && olyOverheadSquat.baseWeightLb === 70,
    "an Oly block derives its 70% technique start and aliased variation from global Snatch history");
  ok(metconFromHistory.days[0].accessories[0].weightLb === 40,
    "a conditioning block reuses the latest KB Swing load logged in any program");
  const customSnatch = await bootstrapLiftFromHistory(await db.Exercises.byName("Snatch"),
    { role: "complementary", focus: "strength", roundingLb: 5 });
  const customSwing = await bootstrapAccessoryFromHistory(await db.Exercises.byName("KB Swing"));
  ok(customSnatch.baseWeightLb === 70 && customSwing.weightLb === 40,
    "custom-program slots use the same cross-program history bootstrap as templates");
  await db.Programs.del(olyFromHistory.id); await db.Programs.del(metconFromHistory.id);
  await db.Sessions.del(snatchHistoryID); await db.Sessions.del(swingHistoryID);

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
  const conjugateFromHistory = await db.Programs.get(await createProgramFromTemplate(
    PROGRAM_TEMPLATES.find((t) => t.id === "conjugate")));
  const meLower = conjugateFromHistory.days.find((d) => d.name === "Mon — Max Effort Lower");
  const deLower = conjugateFromHistory.days.find((d) => d.name === "Fri — Dynamic Effort Lower");
  ok(meLower.lifts[0].exerciseName === "Low Box Squat" && meLower.lifts[0].baseWeightLb === 330,
    "a special ME squat derives its opening target from Back Squat history");
  ok(deLower.lifts[0].exerciseName === "Speed Box Squat" && deLower.lifts[0].baseWeightLb === 180,
    "a special speed squat derives its 50% base from Back Squat history");
  ok(deLower.accessories.find((a) => a.exerciseName === "Sled Pull")?.targetSeconds === 60,
    "template conditioning configuration survives instantiation");
  await db.Programs.del(conjugateFromHistory.id);
  // No recorded history for a loaded custom slot → the shared type fallback,
  // not an arbitrary template literal or a blank, supplies a safe base.
  const noHistory = await db.Programs.get(await createProgramFromTemplate({
    id: "test-fallback", name: "Fallback Check", tagline: "", focus: "strength", roundingLb: 5,
    exercises: [],
    days: [{ name: "Day", accessories: [], lifts: [{
      exerciseName: "Landmine Press", role: "main", baseWeightLb: 40, estimatedMaxLb: 60,
      stallCount: 0, lastIncrementLb: 0, prescription: "fiveThreeOne", sets: 0, startFraction: 0.90,
    }] }],
  }));
  ok(noHistory.days[0].lifts[0].baseWeightLb === 45,
    "no recorded history → safe main-barbell default replaces template literal");
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
  ok(svg.getAttribute("viewBox") === "0 0 430 230" && svg.querySelectorAll("image.anatomy-reference").length === 2,
    "figure renders matching engraved front and back reference art side by side");
  ok([...svg.querySelectorAll("image.anatomy-reference")].map((image) => image.getAttribute("href")).join("/")
    === "assets/vitruvian-front.jpeg/assets/vitruvian-back.jpeg"
    && [...svg.querySelectorAll("image.anatomy-reference")].every((image) => image.dataset.species === "gorilla"
      && image.dataset.source === "exact-reference" && image === image.parentElement.firstElementChild)
    && svg.querySelectorAll("g.anatomy-figure-panel").length === 2
    && svg.querySelectorAll("g.anatomy-highlight-layer").length === 1,
  "the anatomy view uses the exact supplied gorilla drawings beneath the muscle washes");
  ok(A.muscleProfile("Face Pulls", "pull").primary[0] === "reardelts",
    "face pulls highlight rear delts instead of the generic shoulder cap");
  ok(svg.querySelectorAll('path[fill="#e0453a"]').length >= 2, "primary movers highlighted red");
  ok(svg.querySelectorAll('path[fill="#3a7bd5"]').length >= 1, "supporting muscles highlighted blue");
  ok(svg.querySelectorAll("image.anatomy-region-mask.primary").length >= 2
    && svg.querySelectorAll("image.anatomy-region-mask.supporting").length >= 1,
  "back-view highlights use muscle-shaped masks rather than balloon contours");
  ok([...svg.querySelectorAll("text.anatomy-view-label")].map((node) => node.textContent).join("/") === "Ape front/Ape back",
    "the two anatomical views identify their orientation");
  const legend = A.muscleLegend(A.muscleProfile("Overhead Press", "press"));
  ok(legend.querySelector('[data-role="primary"]')?.textContent.includes("Shoulders, Triceps")
    && legend.querySelector('[data-role="supporting"]')?.textContent.includes("Traps, Abs"),
    "the visual key names the exact primary and supporting muscle groups");

  const frontAsset = await readFile(new URL("../app/assets/vitruvian-front.jpeg", import.meta.url));
  const backAsset = await readFile(new URL("../app/assets/vitruvian-back.jpeg", import.meta.url));
  const { createHash } = await import("node:crypto");
  const sha256 = (buffer) => createHash("sha256").update(buffer).digest("hex");
  ok(sha256(frontAsset) === "ec95ffe80e86263a441f31e01e7e5fcf6b9312d3b2d7a3e6fc3a9ae36bfd1006",
    "front asset is byte-for-byte the supplied Vitruvian gorilla drawing");
  ok(sha256(backAsset) === "940bbc7bf72794778d3304d226cf5ca3d265e68985bc0ffa72cb198c743a51f5",
    "back asset is byte-for-byte the supplied matching rear drawing");
  const anatomyStyles = await readFile(new URL("../app/styles.css", import.meta.url), "utf8");
  ok(anatomyStyles.includes(".anatomy-figure-panel")
    && anatomyStyles.includes("mask-image: radial-gradient(ellipse closest-side")
    && anatomyStyles.includes(".anatomy-highlight-layer { filter: blur(2.1px); }"),
  "anatomy art feathers into its card and colour washes have softened boundaries");
  const frontTraps = A.VITRUVIAN_FRONT_REGIONS.find((region) => region.id === "traps");
  ok(Math.min(...frontTraps.points.map((point) => point[1])) >= 55
    && A.VITRUVIAN_FRONT_REGIONS.filter((region) => region.id === "forearms").length === 4
    && A.VITRUVIAN_FRONT_REGIONS.filter((region) => region.id === "forearms")
      .every((region) => Math.max(...region.points.map((point) => point[1])) <= 85),
  "front washes align to the ape's neck and both Vitruvian arm poses");
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
  const original = await db.Programs.active();
  const originalState = JSON.stringify({ cycleNumber: original.cycleNumber,
    currentWeek: original.currentWeek, nextDayIndex: original.nextDayIndex, days: original.days });
  await db.Programs.save({ name: "Cut Block", focus: "maintain", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0, roundingLb: 5, isActive: false, days: [] });
  let all = await db.Programs.all();
  ok(all.length === 2, "second program created");
  const second = all.find((p) => p.name === "Cut Block");
  for (const x of all) { x.isActive = x.id === second.id; await db.Programs.save(x); } // exclusive activate
  ok((await db.Programs.active()).name === "Cut Block", "activating switches the active program");
  ok((await db.Programs.all()).filter((p) => p.isActive).length === 1, "exactly one program active");
  all = await db.Programs.all();
  for (const x of all) { x.isActive = x.id === original.id; await db.Programs.save(x); }
  const resumed = await db.Programs.active();
  ok(resumed.id === original.id && JSON.stringify({ cycleNumber: resumed.cycleNumber,
    currentWeek: resumed.currentWeek, nextDayIndex: resumed.nextDayIndex, days: resumed.days }) === originalState,
  "switching away and back preserves the program's independent progression state");
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

  // v12 ad-hoc activity (wood splitting, the first kind): the standalone
  // session restores with its typed detail intact, derives the workload,
  // and re-exports verbatim [INV-WOOD-WORK-ROUND-TRIPS]. It is one
  // off-program `WorkoutSession` on the same timeline as the training log
  // [INV-WOOD-WORK-USES-ONE-TIMELINE]. Duration and maul weight live only
  // on the canonical conditioning set.
  {
    const wood = sessions.find((s) => s.activity);
    ok(!!wood, "the wood-splitting session restores with its typed activity detail");
    ok(wood.activity.kind === "woodSplitting", "the activity kind survives import");
    ok(wood.activity.sessionRPE === 8.5 && wood.activity.rounds === 55
      && wood.activity.splitPieces === 15 && wood.activity.estimatedStrikes === 340
      && wood.activity.cordVolume === 0.25, "every recorded wood fact survives import");
    ok(!wood.programTag, "wood splitting is off-program");
    const woodEntry = wood.exercises.find((e) => e.exerciseName === C.activityExerciseName(wood.activity.kind));
    const woodSet = woodEntry?.sets?.[0];
    ok(woodSet?.durationSeconds === 7200 && woodSet?.weightLb === 8,
      "duration and maul weight stay on the canonical conditioning set");
    ok(woodSet?.prescriptionBlock === "conditioning",
      "the canonical set carries the conditioning block native's creator stamps");
    ok(new Date(wood.completedAt) - new Date(wood.date) === 7200 * 1000,
      "completedAt is the end of the work: start + duration");
    ok(C.activityWorkload(woodSet.durationSeconds, wood.activity.sessionRPE)?.arbitraryUnits === 1020,
      "workload derives as duration minutes × session RPE");
    const reexport = JSON.parse(await db.exportJSON());
    const woodOut = reexport.sessions.find((s) => s.activity);
    ok(JSON.stringify(woodOut.activity)
      === JSON.stringify({ kind: "woodSplitting", sessionRPE: 8.5, rounds: 55, splitPieces: 15, estimatedStrikes: 340, cordVolume: 0.25 }),
      "the activity detail re-exports verbatim");
    ok(reexport.sessions.filter((s) => s.activity).length === 1
      && reexport.sessions.every((s) => s.activity || !("activity" in s)),
      "sessions without a detail never gain the key");
  }

  // The importer is a second write path: it refuses the shapes the creator
  // refuses, before any write, and the canonical shape still validates.
  // Mirrors native ImportService.validate.
  {
    const woodID = "b7a2c9d4-5e31-4f8a-9c06-2d7e84f1a3b5";
    const withWood = (mutate) => {
      const copy = structuredClone(fixture);
      mutate(copy.sessions.find((s) => s.id === woodID));
      return copy;
    };
    const rejects = (why, mutate) => {
      let rejected = false;
      try { db.validateBackup(withWood(mutate)); } catch { rejected = true; }
      ok(rejected, why);
    };
    rejects("an activity session with a second entry is rejected before writes",
      (s) => { s.exercises.push(structuredClone(s.exercises[0])); });
    rejects("an activity session with two sets is rejected before writes",
      (s) => { s.exercises[0].sets.push(structuredClone(s.exercises[0].sets[0])); });
    rejects("an activity session that is not completed is rejected before writes",
      (s) => { s.isCompleted = false; });
    rejects("an activity session carrying a program tag is rejected before writes",
      (s) => { s.programTag = { programId: "0f3c2a9e-6b7d-4c1e-9a2b-5d4e3f2a1b0c" }; });
    rejects("an activity session whose entry is not the kind's exercise is rejected before writes",
      (s) => { s.exercises[0].name = "Back Squat"; });
    rejects("an activity session without a timed set is rejected before writes",
      (s) => { s.exercises[0].sets[0].durationSeconds = null; });
    db.validateBackup(withWood(() => {}));
    ok(true, "the canonical activity shape still validates");

    // An edit to the facts alone is visible to the named-restore preview,
    // so it can never be refused as "nothing to restore"
    // [INV-WOOD-WORK-ROUND-TRIPS].
    const edited = withWood((s) => { s.activity.sessionRPE = 9; s.activity.cordVolume = 0.4; });
    const preview = await db.namedRestorePreview(edited);
    ok(preview.sessions.some((d) => d.id === woodID && d.status !== "unchanged"),
      "editing only the activity facts previews the session as changed");
    ok(!preview.sessions.some((d) => d.id !== woodID && d.status !== "unchanged"),
      "the activity signature leaves every other session unchanged");

    // The version label never drops facts the bundle carries.
    const relabelled = withWood(() => {});
    relabelled.schemaVersion = 11;
    await db.importBundle(relabelled, { createCheckpoint: false });
    const restored = (await db.Sessions.completed()).find((s) => s.id === woodID);
    ok(restored?.activity?.sessionRPE === 8.5 && restored?.activity?.cordVolume === 0.25,
      "a bundle labelled below v12 that still carries the facts restores them rather than dropping them");
  }

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
  // The generated fixture is the current portable contract. Importing and
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

// ---- v10 upgrade path: the frozen v10 fixture imports and derives ids ----
// (epic #155 Stage 2 gate: "v10 fixture imports on both clients and exports
// v11".) The pre-identity fixture is kept frozen at v10 forever; importing it
// must synthesize the SAME deterministic ids the native importer derives.
{
  const fs = await import("node:fs");
  const v10 = JSON.parse(fs.readFileSync(new URL("./fixtures/synthetic-backup-v10.json", import.meta.url), "utf8"));
  ok(v10.schemaVersion === 10, "the frozen upgrade fixture stays at schema 10");
  await db.importBundle(v10, { createCheckpoint: false });
  const exercises = await db.Exercises.all();
  ok(exercises.length > 0 && exercises.every((e) => e.id === C.exerciseLegacyID(e.name)),
    "every v10 exercise derives its deterministic legacy id");
  const programs = await db.Programs.all();
  ok(programs.every((p) => p.templateId == null), "v10 programs get no invented template origin");
  ok(programs.every((p) => (p.days || []).every((d) =>
    (d.lifts || []).every((l) => l.exerciseId === C.exerciseLegacyID(l.exerciseName)))),
    "v10 program slots derive their exercise ids");
  const sessions = await db.Sessions.completed();
  ok(sessions.every((s) => (s.exercises || []).every((e) => e.exerciseId === C.exerciseLegacyID(e.exerciseName))),
    "v10 session entries derive their exercise ids");
  const reexport = await db.exportBundle();
  ok(reexport.schemaVersion === 12, "importing v10 re-exports as the current version");
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

// An exercise added mid-session is born at ITS OWN starting load, not the
// empty bar's. The first "+ Set" of an entry with no plan and no predecessor
// defaulted to a literal 45 lb whatever the movement was — a bodyweight GHD
// sit-up came into the world asking for 45 lb of phantom plates.
{
  const gid = await session.createBlankSession();
  const g = await db.Sessions.get(gid);
  g.exercises.push({ order: 0, exerciseName: "GHD Sit-up", notes: "", phase: null,
    plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
  g.exercises.push({ order: 1, exerciseName: "DB Curls", notes: "", phase: null,
    plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
  await db.Sessions.save(g);
  await session.openSession(gid); await tick();
  const addSetButtons = () => [...[...document.querySelectorAll("#overlays .overlay")].pop()
    .querySelectorAll("button")].filter((b) => b.textContent === "+ Set");
  addSetButtons()[0].click(); await tick();
  let stored = await db.Sessions.get(gid);
  ok(stored.exercises[0].sets[0].weightLb === 0,
    `a bodyweight movement added mid-session is born unloaded (got ${stored.exercises[0].sets[0].weightLb})`);
  addSetButtons()[1].click(); await tick();
  stored = await db.Sessions.get(gid);
  ok(stored.exercises[1].sets[0].weightLb === 5,
    `a dumbbell accessory added mid-session starts at the catalog's light default (got ${stored.exercises[1].sets[0].weightLb})`);

  // A total-bar movement is floored at the bar in hand: the catalog says
  // 20 lb for a skull crusher (assuming a lighter bar), but a set on the
  // gym's 45 lb bar cannot weigh less than its own bar. This exercises the
  // no-history branch specifically, so clear any Skull Crusher exposure the
  // synthetic fixture imported earlier in this suite left banked — an
  // ad-hoc suggestion from real history is the whole point of that feature
  // and must not be mistaken for a broken floor here.
  for (const stale of (await db.Sessions.completed())
    .filter((s) => (s.exercises || []).some((e) => e.exerciseName === "Skull Crusher"))) {
    await db.Sessions.del(stale.id);
  }
  const bid = await session.createBlankSession();
  const b = await db.Sessions.get(bid);
  b.exercises.push({ order: 0, exerciseName: "Skull Crusher", notes: "", phase: null,
    plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
  await db.Sessions.save(b);
  await session.openSession(bid); await tick();
  addSetButtons()[0].click(); await tick();
  const barbell = await db.Sessions.get(bid);
  ok(barbell.exercises[0].sets[0].weightLb === 45,
    `a barbell add is floored at the active bar, never below it (got ${barbell.exercises[0].sets[0].weightLb})`);
  await db.Sessions.del(gid); await db.Sessions.del(bid);
}

// The history-based first-set suggestion above is silent about where its
// number came from unless the UI discloses it: secondary text under the
// first working set, present only when a real exposure shaped the
// suggestion — never for the generic catalog-default fallback.
{
  const priorId = await db.Sessions.save({
    date: new Date(Date.now() - 21 * 86_400_000).toISOString(), notes: "", isCompleted: true,
    gymName: null, exercises: [{ order: 0, exerciseName: "Cable Fly", notes: "", phase: null,
      plannedWeightLb: null, plannedSets: null, plannedReps: null,
      sets: [{ order: 0, weightLb: 30, reps: 10, isWarmup: false, status: "completed",
        loadBasis: "externalTotal", flags: ["clean"] }] }],
  });
  const hid = await session.createBlankSession();
  const h = await db.Sessions.get(hid);
  h.exercises.push({ order: 0, exerciseName: "Cable Fly", notes: "", phase: null,
    plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
  await db.Sessions.save(h);
  await session.openSession(hid); await tick();
  const historyOverlay = [...document.querySelectorAll("#overlays .overlay")].pop();
  [...historyOverlay.querySelectorAll("button")].find((b) => b.textContent === "+ Set").click(); await tick();
  const provenance = [...historyOverlay.querySelectorAll(".sub")]
    .map((n) => (n.textContent || "").trim())
    .find((t) => t.startsWith("from your last exposure"));
  ok(provenance === "from your last exposure, 3w ago",
    `the first working set discloses where its history-based suggestion came from (got ${provenance})`);
  await db.Sessions.del(priorId); await db.Sessions.del(hid);

  // A never-before-seen off-program exercise has no history to disclose —
  // the catalog-default fallback stays silent, as before.
  const nid = await session.createBlankSession();
  const n = await db.Sessions.get(nid);
  n.exercises.push({ order: 0, exerciseName: "Reverse Hyperextension", notes: "", phase: null,
    plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
  await db.Sessions.save(n);
  await session.openSession(nid); await tick();
  const freshOverlay = [...document.querySelectorAll("#overlays .overlay")].pop();
  [...freshOverlay.querySelectorAll("button")].find((b) => b.textContent === "+ Set").click(); await tick();
  ok(![...freshOverlay.querySelectorAll(".sub")].some((el) => (el.textContent || "").startsWith("from your last exposure")),
    "no provenance line for the catalog-default fallback");
  await db.Sessions.del(nid);
}

// Tapping the lift's name inside the logger opens the lift info screen —
// muscles figure, history, exercise settings — not only from the library.
// Mid-workout is exactly when "what does this train, what did I do last
// time" gets asked, and the name looked tappable but did nothing.
{
  const sid = await session.createBlankSession();
  const s = await db.Sessions.get(sid);
  s.exercises.push({ order: 0, exerciseName: "Deadlift", notes: "", phase: null,
    plannedWeightLb: 225, plannedSets: 3, plannedReps: 5, sets: [] });
  await db.Sessions.save(s);
  await session.openSession(sid); await tick();
  const logger = [...document.querySelectorAll("#overlays .overlay")].pop();
  const title = [...logger.querySelectorAll(".title")].find((t) => t.textContent === "Deadlift");
  ok(title, "logger shows the lift name");
  title.click(); await tick();
  const detail = [...document.querySelectorAll("#overlays .overlay")].pop();
  ok(detail !== logger && detail.querySelector(".anatomy-card svg"),
    "tapping the lift name in the logger opens lift info with the muscles figure");

  // The detail screen live-edits the exercise (rest, load basis, shelving).
  // Back must repaint the logger, or the card keeps showing the pre-edit
  // state: bump the lift's own rest and check the ⏱ chip caught up.
  const restRow = [...detail.querySelectorAll(".row")].find((r) => r.textContent.startsWith("Rest"));
  const plus = [...restRow.querySelectorAll(".stepper button")].pop();
  plus.click(); await tick(); // Default → 0:15 of the lift's own rest
  detail.querySelector(".overlay-head button").click(); await tick();
  const chip = [...logger.querySelectorAll("button")].find((b) => b.textContent.startsWith("⏱"));
  ok(chip && chip.textContent.includes("0:15"),
    `closing lift info repaints the logger (rest chip reads ${chip?.textContent})`);

  // Restore the seeded default and close the logger so later overlay-based
  // tests don't inherit this screen stack.
  const deadlift = await db.Exercises.byName("Deadlift");
  deadlift.defaultRestSeconds = 0;
  await db.Exercises.save(deadlift);
  logger.querySelector(".overlay-head button").click(); await tick();
  await db.Sessions.del(sid);
}

// The workout stopwatch must survive an app relaunch. The origin previously
// lived only in a closure, so force-quitting the PWA mid-workout restarted
// the timer at 0:00 on resume; now it is mirrored into localStorage the way
// the native WorkoutClock mirrors its clock into UserDefaults.
{
  const { CLOCK_KEY, clearClockRecord } = await import("../app/js/workout-clock.js");
  const lastBar = () => [...document.querySelectorAll("#session-bar")].pop();
  const sid = await session.createBlankSession();
  await session.openSession(sid); await tick();
  lastBar().querySelector("button[aria-label^='Start the workout clock']").click(); await tick();
  const record = JSON.parse(localStorage.getItem(CLOCK_KEY) || "null");
  ok(record && String(record.sessionId) === String(sid) && Number.isFinite(record.start),
    "[INV-CLOCK-SURVIVES-RELAUNCH] starting the workout writes a durable clock record");

  // The relaunch: a fresh open of the same session resumes the running clock
  // from the stored origin instead of offering Start again.
  await session.openSession(sid); await tick();
  ok(lastBar().querySelector(".clock").textContent.includes("session"),
    "[INV-CLOCK-SURVIVES-RELAUNCH] reopening resumes the running clock, not 'not started'");

  // Another session must not inherit the stored clock.
  const otherId = await session.createBlankSession();
  await session.openSession(otherId); await tick();
  ok(lastBar().querySelector(".clock").textContent.includes("not started"),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a different session does not inherit the stored clock");

  // A stale record (older than a day) must not resurrect last week's
  // stopwatch onto a reopened session.
  localStorage.setItem(CLOCK_KEY, JSON.stringify({ sessionId: sid, start: Date.now() - 25 * 60 * 60 * 1000 }));
  await session.openSession(sid); await tick();
  ok(lastBar().querySelector(".clock").textContent.includes("not started"),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a stale record does not restart the clock");

  // A future-dated record (clock skew, corrupt bytes) is just as unusable —
  // it would paint a running stopwatch with negative elapsed time.
  localStorage.setItem(CLOCK_KEY, JSON.stringify({ sessionId: sid, start: Date.now() + 60 * 60 * 1000 }));
  await session.openSession(sid); await tick();
  ok(lastBar().querySelector(".clock").textContent.includes("not started"),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a future-dated record does not restart the clock");

  // Reset from the owning session clears the record for good.
  localStorage.setItem(CLOCK_KEY, JSON.stringify({ sessionId: sid, start: Date.now() }));
  await session.openSession(sid); await tick();
  lastBar().querySelector("button[aria-label^='Reset this session']").click(); await tick();
  ok(localStorage.getItem(CLOCK_KEY) == null,
    "[INV-CLOCK-SURVIVES-RELAUNCH] reset clears the durable record");

  // The cleanup is ownership-checked: it drops the named session's record
  // and ONLY that one, so a discard can never erase another workout's
  // running clock.
  localStorage.setItem(CLOCK_KEY, JSON.stringify({ sessionId: sid, start: Date.now() }));
  clearClockRecord(otherId);
  ok(localStorage.getItem(CLOCK_KEY) != null,
    "[INV-CLOCK-SURVIVES-RELAUNCH] clearing a different session's record leaves the running clock alone");

  // A PAUSED record is frozen evidence — elapsed is fixed at pausedAt −
  // start — so wall-clock age does not stale it (native pauses; the shared
  // core rule decides for both platforms).
  const threeDaysAgo = Date.now() - 3 * 24 * 60 * 60 * 1000;
  ok(C.stopwatchRecordUsable(threeDaysAgo, threeDaysAgo + 30 * 60 * 1000, Date.now()),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a paused record outlives the running window");

  // Session deletion clears the record at the persistence choke point, not
  // just behind the discard buttons — every deletion path is covered.
  localStorage.setItem(CLOCK_KEY, JSON.stringify({ sessionId: sid, start: Date.now() }));
  await db.Sessions.del(sid);
  ok(localStorage.getItem(CLOCK_KEY) == null,
    "[INV-CLOCK-SURVIVES-RELAUNCH] deleting a session clears its durable record");
  await db.Sessions.del(otherId);

  // Bulk destruction is a world reset: a backup import replaces the sessions
  // store (and small autoincrement ids collide across installs), so whatever
  // record exists must not graft its stopwatch onto an imported session.
  localStorage.setItem(CLOCK_KEY, JSON.stringify({ sessionId: 999999, start: Date.now() }));
  await db.importBundle(JSON.parse(await db.exportJSON()), { createCheckpoint: false });
  ok(localStorage.getItem(CLOCK_KEY) == null,
    "[INV-CLOCK-SURVIVES-RELAUNCH] a backup import clears the pre-import clock record");
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

  // The refusal copy must agree with the engine at every boundary it names. It
  // did not: both thresholds were rounded for the message while the engine
  // compared raw, so a refusal could explain itself with numbers that say it
  // should have succeeded.
  const DAY = 86400000;
  const refuse = hist.projectionRefusalForTest;
  const pts = (days, now) => ({ points: days.map((d) => ({ t: d * DAY, y: 200 })), now: now * DAY });

  const thin = pts([0, 7, 14], 14);
  ok(/^Not enough history to project — 3 of 4 sessions so far\.$/.test(refuse(thin.points, thin.now)),
    "[INV-PROJECTION-REFUSES-THIN-HISTORY] too few exposures says how many are missing");

  // 20.6 days refuses; the message must not claim it already spans 21.
  const shortSpan = pts([0, 7, 14, 20.6], 20.6);
  const spanMsg = refuse(shortSpan.points, shortSpan.now);
  ok(/^Not enough time to project — this lift spans 20 days, and a trend needs 21\.$/.test(spanMsg),
    `[INV-PROJECTION-REFUSES-THIN-HISTORY] a sub-threshold span never reads as meeting it (${spanMsg})`);
  ok(!/spans 21 days, and a trend needs 21/.test(spanMsg),
    "[INV-PROJECTION-REFUSES-THIN-HISTORY] the span message cannot contradict itself");

  // 35.4 idle days is refused by the engine, so the message must name staleness
  // rather than falling through to the generic line.
  const stale = pts([0, 7, 14, 21, 28], 28 + 35.4);
  ok(C.projectTrend(stale.points.map((p) => ({ day: p.t / DAY, value: p.y })), 90, stale.now / DAY) === null,
    "the engine refuses a 35.4-day gap");
  ok(/^Last trained 35 days ago —/.test(refuse(stale.points, stale.now)),
    "[INV-PROJECTION-REFUSES-THIN-HISTORY] the staleness message covers the engine's whole refusal band");
}

// ---- progression chart: role split + combined metric ----
// A lift can be MAIN on one day and COMPLEMENTARY on another at a much lighter
// base. Drawing both as one line produced a sawtooth between two unrelated
// progressions; main must stay legible on its own.
{
  const { progressionChart, smoothLinePath, ROLE_DASH } = await import("../app/js/charts.js");
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
  ok(paths.every((path) => path.getAttribute("d").includes("C")),
    "performed histories use smooth point-preserving curves instead of chunky angular joins");
  ok(smoothLinePath([[0, 10], [5, 0], [10, 10]]).endsWith("10.0 10.0"),
    "the smoothed chart path still passes through the final recorded value");
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

  let selected = null;
  const selectable = progressionChart({
    lines: [{ key: "w", label: "Working weight", color: "#ef4444", points: main }],
    onSelect: (point) => { selected = point; },
  });
  const selectableSVG = selectable.querySelector("svg");
  const hit = selectable.querySelector("rect.chart-hit");
  selectableSVG.getBoundingClientRect = () => ({ left: 0, top: 0, width: 340, height: 220,
    right: 340, bottom: 220 });
  const firstDot = selectable.querySelector("circle.dot");
  hit?.dispatchEvent(new window.MouseEvent("click", { bubbles: true,
    clientX: +firstDot.getAttribute("cx"), clientY: +firstDot.getAttribute("cy") }));
  ok(selected === main[0] && hit?.getAttribute("aria-pressed") === "true",
    "selecting a chart point reports the exact record and exposes selected state");
  ok(selectable.querySelector("line.selection-line") && selectable.querySelector("circle.selection-halo"),
    "selection remains visible on the chart instead of changing only the detail text");

  const dense = Array.from({ length: 40 }, (_, index) => ({ t: at(index + 1), y: 225 }));
  let denseSelected = null;
  const denseChart = progressionChart({
    lines: [{ key: "w", label: "Working weight", color: "#ef4444", points: dense }],
    onSelect: (point) => { denseSelected = point; },
  });
  const denseSVG = denseChart.querySelector("svg");
  denseSVG.getBoundingClientRect = selectableSVG.getBoundingClientRect;
  const denseHits = denseChart.querySelectorAll("rect.chart-hit");
  const olderDot = denseChart.querySelectorAll("circle.dot")[5];
  denseHits[0]?.dispatchEvent(new window.MouseEvent("click", { bubbles: true,
    clientX: +olderDot.getAttribute("cx"), clientY: +olderDot.getAttribute("cy") }));
  ok(denseHits.length === 1 && denseSelected === dense[5],
    "dense flat histories use one plot hit surface and keep older points directly selectable");

  // ---- the projected trend, drawn past today ----
  // The forecast shares the load axis with the history it continues, but must
  // be impossible to mistake for performed work at a glance.
  const history = [[1, 200], [8, 205], [15, 210], [22, 215], [29, 220]].map(([d, y]) => ({ t: at(d), y }));
  const nowT = at(29);
  const fit = C.projectTrend(history.map((p) => ({ day: p.t / 86400000, value: p.y })), 30, nowT / 86400000);
  ok(fit && Math.abs(fit.perWeek - 5) < 0.0001, "the chart's samples fit the rate they were built from");
  const projected = progressionChart({
    lines: [{ key: "w", label: "Working weight", color: "#ef4444", points: history }],
    projection: { label: "Projected · 1 month", color: "#7aa7d9", nowT,
      points: fit.points.map((p) => ({ t: p.day * 86400000, y: p.value })) },
  });
  const psvg = projected.querySelector("svg");
  const proj = psvg.querySelector("path.projection");
  ok(proj, "the projected trend is drawn");
  ok((proj.getAttribute("style") || "").includes("#7aa7d9"), "in its own colour, not the history's");
  ok(psvg.querySelectorAll("path.line").length === 1, "and is not counted as another performed line");
  ok(psvg.querySelector("line.now-line"), "a today divider separates performed from projected");
  ok([...psvg.querySelectorAll("text.now-lbl")].some((t) => t.textContent === "today"), "and says so");
  ok(psvg.querySelector("rect.future"), "the future region is shaded before anything is drawn on it");
  ok([...projected.querySelectorAll(".chart-legend span")].some((s) => s.textContent.includes("Projected")),
    "the legend names the projection as projected");
  // The forecast climbs above every performed point, so a load axis fitted to
  // the history alone would clip it off the top of the plot.
  const axis = [...psvg.querySelectorAll("text.lbl")]
    .filter((t) => +t.getAttribute("x") < 20).map((t) => Number(t.textContent)).filter(Number.isFinite);
  ok(axis.length > 0 && Math.max(...axis) >= 235,
    `the load axis grows to hold the projection (${axis.join()})`);
  // Off means off.
  const noProjection = progressionChart({
    lines: [{ key: "w", label: "Working weight", color: "#ef4444", points: history }],
  });
  ok(!noProjection.querySelector("path.projection"), "no horizon, no projected line");
  ok(!noProjection.querySelector("line.now-line"), "and no today divider on a chart of the past");

  // The wash is depth for a LONE line. With several up there is no "the" line
  // to fill, and shading one of them reads as a region that means something —
  // native gates it the same way, so an ungated web fill drew a different
  // chart from the same data.
  ok(noProjection.querySelector("path.area"), "a single line gets the depth wash");
  const twoLines = progressionChart({ lines: [
    { key: "a", label: "R1 Volume", color: "#5ba06a", points: history },
    { key: "b", label: "R3 Peak", color: "#ef4444", points: e1rm },
  ] });
  ok(!twoLines.querySelector("path.area"), "several lines get none — no arbitrary one is shaded");

  // Today outside the plotted span must not shade it. Without the divider's
  // own guard the wash covered the whole plot with nothing to explain it.
  const nowBeforeStart = progressionChart({
    lines: [{ key: "w", label: "Working weight", color: "#ef4444", points: history }],
    projection: { label: "Projected", color: "#7aa7d9", nowT: at(0) - 86400000,
      points: fit.points.map((p) => ({ t: p.day * 86400000, y: p.value })) },
  });
  ok(!nowBeforeStart.querySelector("rect.future"),
    "a today left of the domain shades nothing rather than the whole plot");
  ok(!nowBeforeStart.querySelector("line.now-line"), "and draws no divider either — the two agree");

  // A dashed legend swatch with no colour rendered `3px dashed undefined`,
  // an invalid rule that dropped the swatch.
  const noColor = progressionChart({ lines: [
    { key: "a", label: "One", color: "#ef4444", points: history },
    { key: "b", label: "Two", dash: "5 4", points: e1rm },
  ] });
  const dashSwatch = [...noColor.querySelectorAll(".chart-legend i")]
    .find((i) => (i.style.borderTop || "").includes("dashed"));
  ok(dashSwatch && !/undefined/.test(dashSwatch.style.borderTop),
    `a colourless dashed swatch falls back to the accent (${dashSwatch?.style.borderTop})`);
}

// ---- Cross-client parity: shared abstractions spelled once ----

// The clock reader self-heals: bytes that can never be adopted (unparsable,
// shapeless, ownerless, stale) are deleted on read instead of shadowing the
// slot forever — mirroring native WorkoutClock.loadRecord.
{
  const { CLOCK_KEY, storedClockStart } = await import("../app/js/workout-clock.js");
  localStorage.setItem(CLOCK_KEY, "not json{");
  ok(storedClockStart(1) === null && localStorage.getItem(CLOCK_KEY) == null,
    "[INV-CLOCK-SURVIVES-RELAUNCH] unparsable clock bytes are deleted on read");
  localStorage.setItem(CLOCK_KEY, JSON.stringify({ sessionId: 1, start: Date.now() - 25 * 60 * 60 * 1000 }));
  ok(storedClockStart(1) === null && localStorage.getItem(CLOCK_KEY) == null,
    "[INV-CLOCK-SURVIVES-RELAUNCH] a stale record is deleted on read, not left to linger");
  const live = { sessionId: 7, start: Date.now() - 60 * 1000 };
  localStorage.setItem(CLOCK_KEY, JSON.stringify(live));
  ok(storedClockStart(1) === null && localStorage.getItem(CLOCK_KEY) != null,
    "[INV-CLOCK-SURVIVES-RELAUNCH] another session's LIVE record survives a foreign read");
  ok(storedClockStart(7) === live.start, "the owner still adopts its record");
  localStorage.removeItem(CLOCK_KEY);
}

// The gym-tag day stamp has one owner module (mirroring the clock record), and
// the persistence layer clears it on wipe/import — a restored phone gets its
// prominent tag and first-launch auto-show back.
{
  const { GYM_TAG_DAY_KEY, gymTagShownOn, markGymTagShown } = await import("../app/js/gym-tag.js");
  const today = new Date().toLocaleDateString("en-CA");
  markGymTagShown(today);
  ok(gymTagShownOn(today) && localStorage.getItem(GYM_TAG_DAY_KEY) === today,
    "the gym-tag stamp records today through the owner module");
  ok(!gymTagShownOn("2001-01-01"), "a different day reads as not shown");
  await db.importBundle(JSON.parse(await db.exportJSON()), { createCheckpoint: false });
  ok(localStorage.getItem(GYM_TAG_DAY_KEY) == null,
    "a backup import clears the pre-import gym-tag stamp");
}

// Session→program linkage is spelled once: a tag carrying a programId belongs
// to that program and NO other — a deleted program's sessions must never be
// attributed to a later program that reuses the display name. Mirrors native
// WorkoutSession.belongs(to:).
{
  const program = { uuid: "11111111-1111-4111-8111-111111111111", id: 3, name: "Strength" };
  const s = (tag) => ({ programTag: tag });
  ok(db.sessionBelongsToProgram(s({ programId: program.uuid, programName: "Old Name" }), program),
    "a uuid-tagged session matches its program regardless of name");
  ok(db.sessionBelongsToProgram(s({ programId: 3, programName: null }), program),
    "a legacy numeric-id tag still matches");
  ok(!db.sessionBelongsToProgram(s({ programId: "22222222-2222-4222-8222-222222222222", programName: "Strength" }), program),
    "a FOREIGN id never falls back to the name — deleted programs stay deleted");
  ok(db.sessionBelongsToProgram(s({ programId: null, programName: "Strength" }), program),
    "only an ID-LESS legacy tag may match by display name");
  ok(!db.sessionBelongsToProgram(s(null), program) && !db.sessionBelongsToProgram({}, program),
    "an untagged session belongs to no program");
}

// Working volume: the library TYPE excludes conditioning first; the per-set
// DATA still excludes cardio sets whose library entry is gone. One rule,
// mirroring native SessionExercise.workingVolumeLb.
{
  const liftEntry = { sets: [
    { isWarmup: false, status: "completed", weightLb: 100, reps: 5, loadBasis: "totalBar", implementCount: 1 },
    { isWarmup: true, status: "completed", weightLb: 45, reps: 5, loadBasis: "totalBar", implementCount: 1 },
  ] };
  ok(db.workingVolume(liftEntry, { type: "barbell" }) === 500,
    "a completed working set contributes weight × reps; warmups never do");
  ok(db.workingVolume(liftEntry, { type: "conditioning" }) === 0,
    "a conditioning-TYPED movement contributes nothing even with plain weight×reps sets");
  const carryEntry = { sets: [
    { isWarmup: false, status: "completed", weightLb: 20, reps: 1, distanceMiles: 3, loadBasis: "external", implementCount: 1 },
  ] };
  ok(db.workingVolume(carryEntry) === 0,
    "a loaded carry is excluded by its DATA when the library entry is gone");
}

// Backup validator bounds are RELEASED acceptance, shared with native
// ImportService (which widened its lift set-count caps to this envelope):
// values this validator has already let into real stores must stay
// restorable forever — a bound tightened after the fact would reject a
// user's own next backup.
{
  const bundle = (program) => ({ schemaVersion: db.BACKUP_SCHEMA_VERSION, programs: [program] });
  const base = { id: "33333333-3333-4333-8333-333333333333", name: "P", focus: "strength", equipmentPolicy: "any", cycleNumber: 1 };
  const rejects = (program, why) => {
    try { db.validateBackup(bundle(program)); return ok(false, why); } catch { return ok(true, why); }
  };
  const lifts = (fields) => [{ name: "D", order: 0, trainingIntent: "general", lifts: [{ exerciseName: "X", role: "main", ...fields }] }];
  db.validateBackup(bundle({ ...base, currentWeek: 4 }));
  ok(true, "currentWeek 4 (deload) is a valid rotation pointer");
  db.validateBackup(bundle({ ...base, days: lifts({ doubleProgressionSets: 100, maximumSets: 100 }) }));
  ok(true, "lift set counts up to the released 100 envelope stay restorable");
  rejects({ ...base, days: lifts({ doubleProgressionSets: 101 }) },
    "doubleProgressionSets above the released envelope is rejected");
  rejects({ ...base, days: [{ name: "D", order: 0, accessories: [{ exerciseName: "X", maximumSets: 21 }] }] },
    "accessory maximumSets above the released 20 cap is rejected (both clients released 20)");
}

// Accepted coaching decisions carry the before/after program snapshots the
// native audit trail records; deferred decisions record none. The accessory
// cut clamps to the 1% floor like native.
{
  const before = { uuid: "44444444-4444-4444-8444-444444444444", name: "P", cycleNumber: 2, currentWeek: 3,
    days: [{ name: "Upper", order: 0,
      lifts: [{ exerciseName: "Bench Press", role: "main", order: 0 }],
      accessories: [{ exerciseName: "Face Pulls", sets: 3, order: 0 }] }] };
  ok(coach.programDescription(before) === "Upper[Bench Press:lift,Face Pulls:3]",
    "programDescription reads exactly like native CoachingService.programDescription");
  const after = structuredClone(before);
  after.days[0].accessories[0].sets = 4;
  const rec = { id: "r1", ruleID: "rule", title: "t", explanation: "e", change: { type: "addSet", slotID: "s", count: 1 } };
  const accepted = coach.coachingDecision(after, rec, "accepted", [], before);
  ok(accepted.beforeValue === "Upper[Bench Press:lift,Face Pulls:3]"
    && accepted.afterValue === "Upper[Bench Press:lift,Face Pulls:4]",
    "an accepted decision snapshots the plan before and after the change");
  const deferred = coach.coachingDecision(before, rec, "deferred", []);
  ok(deferred.beforeValue === null && deferred.afterValue === null,
    "a deferred decision records no snapshot, like native record()");
  const cut = coach.coachingDecision(before, { ...rec, change: { type: "reduceAccessoryVolume", percent: 100 } }, "accepted", [], before);
  ok(cut.afterValue === "temporaryAccessoryPercent:1:cycle:2:rotation:3",
    "a total cut clamps to the 1% floor instead of writing an unparseable 0");
}

// A banked log is correctable: the set that never got its ✓ mid-workout and
// the set that banked the stale plan's weight are the record charts, recalls,
// exports, and prior-best evidence read, so History must be able to fix them.
{
  const sid = await db.Sessions.save({
    date: db.iso(new Date()), completedAt: db.iso(new Date()), isCompleted: true, notes: "",
    exercises: [{ exerciseName: "Back Squat", order: 0, sets: [
      { order: 0, weightLb: 195, reps: 5, isWarmup: false, status: "completed", enteredUnit: "lb",
        prescriptionBlock: "work", plannedWeightLb: 195, plannedReps: 5, flags: ["clean"] },
      { order: 1, weightLb: 195, reps: 5, isWarmup: false, status: "planned", enteredUnit: "lb",
        prescriptionBlock: "work", plannedWeightLb: 195, plannedReps: 5 },
    ] }],
  });
  await history.render(host()); await tick();
  [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "Log").click(); await tick();
  const row = [...host().querySelectorAll(".card .row")]
    .find((r) => (r.textContent || "").includes("Back Squat"));
  ok(row, "the banked session appears in the log");
  row.click(); await tick();
  const overlay = [...document.querySelectorAll(".overlay")].pop();
  const editBtn = overlay.querySelector('button[aria-label="Edit this workout\'s sets"]');
  ok(editBtn, "[INV-BANKED-SETS-CORRECTABLE] a banked session offers Edit");
  editBtn.click(); await tick();

  const weightInputs = [...overlay.querySelectorAll('input[aria-label^="Weight"]')];
  ok(weightInputs.length === 2, "both work sets grow weight fields in edit mode");
  weightInputs[0].value = "205";
  weightInputs[0].dispatchEvent(new window.Event("input", { bubbles: true }));
  const plannedStatus = overlay.querySelector('button[aria-label^="Status: planned"]');
  ok(plannedStatus, "the never-ticked set shows its planned status");
  plannedStatus.click(); await tick();
  editBtn.click(); await tick(); // Save

  const corrected = await db.Sessions.get(sid);
  const [reweighed, ticked] = corrected.exercises[0].sets;
  ok(reweighed.weightLb === 205 && reweighed.reps === 5,
    "[INV-BANKED-SETS-CORRECTABLE] the corrected weight is stored; reps survive the edit");
  ok(reweighed.plannedWeightLb === 195,
    "[INV-BANKED-SETS-CORRECTABLE] the correction never rewrites what was prescribed");
  ok((reweighed.flags || []).includes("clean"),
    "[INV-BANKED-SETS-CORRECTABLE] quality flags survive the edit");
  ok(ticked.status === "completed" && ticked.weightLb === 195,
    "[INV-BANKED-SETS-CORRECTABLE] the missed ✓ becomes real history without touching its weight");
  ok(db.workingVolume(corrected.exercises[0]) === 205 * 5 + 195 * 5,
    "session volume reads the corrected record");

  // Re-entering edit mode and firing the field's event WITHOUT changing the
  // value is not an edit: the rounded kg display string must never round-trip
  // into a drifted canonical pound value. The comparison runs at commit time
  // against the untouched stored value, so the basis cannot move mid-typing.
  ui.prefs.unitDisplay = "kgPrimary";
  editBtn.click(); await tick();
  const kgInput = [...overlay.querySelectorAll('input[aria-label^="Weight"]')][0];
  kgInput.dispatchEvent(new window.Event("input", { bubbles: true }));
  editBtn.click(); await tick(); // Save
  ok((await db.Sessions.get(sid)).exercises[0].sets[0].weightLb === 205,
    "[INV-BANKED-SETS-CORRECTABLE] an untouched kg field never drifts the stored pounds");
  ui.prefs.unitDisplay = "lbPrimary";

  // Leaving the screen commits like native's save-on-leave: corrections must
  // not silently vanish on ‹ Back.
  editBtn.click(); await tick();
  const repsInput = [...overlay.querySelectorAll('input[aria-label="Reps"]')][0];
  repsInput.value = "6";
  repsInput.dispatchEvent(new window.Event("input", { bubbles: true }));
  overlay.querySelector("button")?.click(); await tick(); await tick(); // ‹ Back
  ok((await db.Sessions.get(sid)).exercises[0].sets[0].reps === 6,
    "[INV-BANKED-SETS-CORRECTABLE] backing out mid-edit saves the corrections instead of dropping them");
  await db.Sessions.del(sid);
}

// The correctable gate keys on the DATA when the library entry is gone, like
// the read-only rendering: a restored cardio record whose exercise was
// deleted must not grow a weight×reps editor over its distance.
{
  const sid = await db.Sessions.save({
    date: db.iso(new Date()), completedAt: db.iso(new Date()), isCompleted: true, notes: "",
    exercises: [{ exerciseName: "Deleted Custom Ruck", order: 0, sets: [
      { order: 0, weightLb: 20, reps: 1, isWarmup: false, status: "completed", enteredUnit: "lb",
        prescriptionBlock: "conditioning", distanceMiles: 2, durationSeconds: 1800 },
    ] }],
  });
  await history.render(host()); await tick();
  [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "Log").click(); await tick();
  [...host().querySelectorAll(".card .row")]
    .find((r) => (r.textContent || "").includes("Deleted Custom Ruck")).click(); await tick();
  const overlay = [...document.querySelectorAll(".overlay")].pop();
  overlay.querySelector('button[aria-label="Edit this workout\'s sets"]').click(); await tick();
  ok(!overlay.querySelector('input[aria-label^="Weight"]'),
    "[INV-BANKED-SETS-CORRECTABLE] a cardio record with no library entry stays read-only in edit mode");
  overlay.querySelector("button")?.click(); await tick();
  await db.Sessions.del(sid);
}


// ---- Stage 0 characterization (epic #155): correcting a banked session ----
// Pins exactly which projections follow the canonical sets after a session
// correction and which persisted ones go stale. Topology from the epic: a
// programmed 5x5 deadlift day banks with the final work set never completed;
// the editor then corrects it to completed 5x5. Assertions labeled STALE
// document today's behavior deliberately — they are the Stage 6 work list.
await withCleanup(async (keep) => {
  const name = "Fixture 5x5 Correction";
  await db.Programs.save({
    // Week 3 (peak): the one week whose bank writes the lift's pending
    // grade/state, so the correction's staleness surface is fully on record.
    name, focus: "strength", cycleNumber: 1, currentWeek: 3, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "Pull", order: 0, lifts: [cyc("Deadlift", "main", 235, 320)], accessories: [] }],
  });
  let program = (await db.Programs.all()).find((p) => p.name === name);
  keep(db.Programs, program.id);
  const milestoneIdsBefore = new Set((await db.Milestones.all()).map((m) => m.id));

  const sid = keep(db.Sessions, await session.createSessionFromProgramDay(program, program.days[0]));
  const s = await db.Sessions.get(sid);
  const main = s.exercises.find((e) => e.exerciseName === "Deadlift");
  // Normalize the generated prescription to the epic's exact topology: five
  // work sets of five at 235. A lifter can add, remove, and edit sets
  // mid-session, so this is a legitimate pre-bank state — and banking still
  // runs the full production completeSession path.
  const warmups = main.sets.filter((set) => set.isWarmup);
  const template = main.sets.find((set) => !set.isWarmup);
  const work = Array.from({ length: 5 }, (_, i) => ({
    ...template, order: warmups.length + i, weightLb: 235, reps: 5,
    plannedWeightLb: 235, plannedReps: 5,
    // The fifth set never got its checkmark mid-workout.
    status: i < 4 ? "completed" : "planned",
  }));
  main.sets = [...warmups, ...work];
  s.notes = "fixture-5x5-correction";
  await session.completeSession(s);

  program = (await db.Programs.all()).find((p) => p.name === name);
  const banked = await db.Sessions.get(sid);
  const liftAfterBank = JSON.parse(JSON.stringify(program.days[0].lifts[0]));
  const cursorAfterBank = { currentWeek: program.currentWeek, nextDayIndex: program.nextDayIndex, cycleNumber: program.cycleNumber };
  const milestonesAfterBank = (await db.Milestones.all()).filter((m) => !milestoneIdsBefore.has(m.id));
  for (const m of milestonesAfterBank) keep(db.Milestones, m.id);
  const bankedWork = banked.exercises[0].sets.filter((set) => !set.isWarmup);
  ok(bankedWork.filter((set) => set.status === "completed").length === 4,
    "characterization baseline: the bank saw four completed work sets");
  // The un-ticked fifth set graded the peak as a FAIL at bank time: stall
  // count up, pending e1RM cut from 320 to 306.25, hold note attached.
  ok(liftAfterBank.pending?.grade === "fail"
      && liftAfterBank.pending?.state.stallCount === 1
      && liftAfterBank.pending?.state.estimatedMaxLb === 306.25,
    "characterization baseline: the four-set bank graded fail with a stall and an e1RM cut");
  ok(milestonesAfterBank.some((m) => m.kind === "firstScheme" && m.label.includes("4×5"))
      && milestonesAfterBank.some((m) => m.kind === "volumePR" && m.label.includes("4700")),
    "characterization baseline: milestones recorded the four-set session (First 4×5, 4700 lb volume PR)");

  // The correction: mark the fifth set completed, through the extracted
  // shared boundary (the same call views/history.js delegates to).
  const fifth = bankedWork[4];
  await db.Sessions.applyCorrections(banked, [{ set: fifth, correction: { status: "completed" } }]);

  // 1. Canonical session follows the correction.
  const corrected = await db.Sessions.get(sid);
  const correctedWork = corrected.exercises[0].sets.filter((set) => !set.isWarmup);
  ok(correctedWork.length === 5 && correctedWork.every((set) => set.status === "completed" && set.reps === 5 && set.weightLb === 235),
    "canonical record: exactly five completed 235x5 work sets after the correction");

  // 2. Export reads the canonical sets — corrected values, nothing stale.
  // Export keys sessions by portable id and exercises by `name`, so find
  // the fixture by its unique notes marker.
  const bundle = JSON.parse(await db.exportJSON());
  const exported = bundle.sessions.find((es) => es.notes === "fixture-5x5-correction");
  const exportedWork = exported.exercises.find((e) => e.name === "Deadlift").sets.filter((set) => !set.isWarmup);
  ok(exportedWork.length === 5 && exportedWork.every((set) => set.status === "completed" && set.reps === 5 && set.weightLb === 235),
    "export follows the corrected canonical sets (no stale copy)");

  // 3+4. Volume and chart e1RM inputs are computed from canonical sets at
  // read time, so they follow the correction too.
  const tonnage = correctedWork.reduce((sum, set) => sum + set.weightLb * set.reps, 0);
  ok(tonnage === 5 * 5 * 235, "volume computed from canonical sets sees all five corrected sets");
  ok(correctedWork.every((set) => C.epleyE1RM(set.weightLb, set.reps) === C.epleyE1RM(235, 5)),
    "chart e1RM samples (computed at render) see the corrected sets");

  // 5. STALE: milestones were written at bank time and the correction adds,
  // removes, and rewrites none of them.
  const milestonesAfterCorrection = (await db.Milestones.all()).filter((m) => !milestoneIdsBefore.has(m.id));
  ok(JSON.stringify(milestonesAfterCorrection) === JSON.stringify(milestonesAfterBank),
    "STALE (Stage 6): persisted milestones are untouched by the correction");
  ok(milestonesAfterCorrection.some((m) => m.kind === "firstScheme" && m.label.includes("4×5"))
      && !milestonesAfterCorrection.some((m) => m.label.includes("5×5")),
    "STALE (Stage 6): 'First 4×5' stands and no 5×5 milestone is ever earned, though the canonical record now says 5x5");

  // 6. STALE: the lift's banked pending grade and state are untouched — the
  // grade that fired at bank time (four of five sets) stands.
  program = (await db.Programs.all()).find((p) => p.name === name);
  const liftAfterCorrection = program.days[0].lifts[0];
  ok(JSON.stringify(liftAfterCorrection) === JSON.stringify(liftAfterBank),
    "STALE (Stage 6): the lift's pending grade/state are untouched by the correction");
  ok(liftAfterCorrection.pending?.grade === "fail"
      && liftAfterCorrection.pending?.state.stallCount === 1
      && liftAfterCorrection.pending?.state.estimatedMaxLb === 306.25,
    "STALE (Stage 6): the fail grade, stall, and 320→306.25 e1RM cut all stand despite the corrected 5x5 — and will apply at rollover");

  // 7. Program cursor banked exactly once and the correction leaves it alone.
  ok(program.currentWeek === cursorAfterBank.currentWeek
      && program.nextDayIndex === cursorAfterBank.nextDayIndex
      && program.cycleNumber === cursorAfterBank.cycleNumber,
    "program cursor advanced once at bank time; the correction does not move it");

  // 8. The correction boundary is idempotent: reapplying the same correction
  // changes nothing.
  const snapshot = JSON.stringify(corrected);
  await db.Sessions.applyCorrections(corrected, [{ set: corrected.exercises[0].sets.filter((set) => !set.isWarmup)[4], correction: { status: "completed" } }]);
  ok(JSON.stringify(await db.Sessions.get(sid)) === snapshot,
    "reapplying the identical correction is a no-op (idempotent)");

  // 9. Re-running completion after a correction must not double-bank.
  await session.completeSession(await db.Sessions.get(sid));
  const reProgram = (await db.Programs.all()).find((p) => p.name === name);
  const reMilestones = (await db.Milestones.all()).filter((m) => !milestoneIdsBefore.has(m.id));
  ok(JSON.stringify(reProgram.days[0].lifts[0]) === JSON.stringify(liftAfterBank)
      && reProgram.currentWeek === cursorAfterBank.currentWeek
      && JSON.stringify(reMilestones) === JSON.stringify(milestonesAfterBank),
    "completeSession's idempotence latch holds after a correction — no duplicate advancement or milestones");
})();


// ---- Stage 1 pin (epic #155): history-driven slot seeding stays exact ----
// Pins bootstrapLiftFromHistory / bootstrapAccessoryFromHistory against
// synthetic history BEFORE recordedHistory is refactored onto the shared
// C.athleteHistoryIndex fold; the native twin is
// CadenceMigrationTests/AthleteHistorySeedingTests.swift.
await withCleanup(async (keep) => {
  const { bootstrapLiftFromHistory, bootstrapAccessoryFromHistory } = await import("../app/js/templates.js");
  const gm = await db.Exercises.byName("Good Morning");
  ok(gm, "seed sanity: Good Morning exists and no other suite block logs it");
  const gmSession = (date, sets) => ({
    date: db.iso(date), completedAt: db.iso(date), isCompleted: true, notes: "",
    exercises: [{ exerciseName: "Good Morning", order: 0, sets }],
  });
  // Older but heavier: 200x5 (Epley 233.33) is the lifetime best...
  keep(db.Sessions, await db.Sessions.save(gmSession(new Date("2030-01-01T10:00:00Z"), [
    { order: 0, weightLb: 200, reps: 5, isWarmup: false, status: "completed", enteredUnit: "lb" },
  ])));
  // ...the newer exposure is lighter (180x3), with a warmup and an
  // unfinished planned set that must both stay invisible to seeding.
  keep(db.Sessions, await db.Sessions.save(gmSession(new Date("2030-02-01T10:00:00Z"), [
    { order: 0, weightLb: 135, reps: 5, isWarmup: true, status: "completed", enteredUnit: "lb" },
    { order: 1, weightLb: 180, reps: 3, isWarmup: false, status: "completed", enteredUnit: "lb" },
    { order: 2, weightLb: 500, reps: 5, isWarmup: false, status: "planned", enteredUnit: "lb" },
  ])));

  const accessory = await bootstrapAccessoryFromHistory(gm);
  ok(accessory.weightLb === 180, "accessory seeding takes the LATEST completed load (180), not the lifetime best");

  const lift = await bootstrapLiftFromHistory(gm, { role: "complementary", focus: "strength", roundingLb: 5 });
  ok(lift.estimatedMaxLb === 233, `lift seeding estimates max from the lifetime best set (200x5 -> 233, got ${lift.estimatedMaxLb})`);
  const style = C.resolvedPrescriptionStyle("automatic", gm.movementGroup || null, "complementary", "strength");
  const expectedBase = Math.floor((C.templateStartFraction(style) * (200 * (1 + 5 / 30))) / 5 + 1e-9) * 5;
  ok(lift.baseWeightLb >= expectedBase && lift.baseWeightLb % 5 === 0,
    `lift base seeds from fraction x best e1RM floored to the step (>= ${expectedBase}, got ${lift.baseWeightLb})`);
})();


// ---- Stage 4: program switching is suspend + activate (epic #155) ----
// A -> B -> A must preserve every cursor and every session, and a switch that
// would strand an open session from another program must fail loudly.
await withCleanup(async (keep) => {
  const settingsView = await import("../app/js/views/settings.js");
  const mk = async (name, isActive) => {
    const id = await db.Programs.save({
      name, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
      roundingLb: 5, isActive,
      days: [{ name: "Pull", order: 0, lifts: [cyc("Deadlift", "main", 235, 320)], accessories: [] }],
    });
    return keep(db.Programs, id);
  };
  const aId = await mk("Switch Fixture A", true);
  const bId = await mk("Switch Fixture B", false);
  let a = await db.Programs.get(aId);
  a.cycleNumber = 3; a.currentWeek = 3; a.nextDayIndex = 2;
  a.days[0].lifts[0].stallCount = 1;
  a.days[0].lifts[0].pending = { state: { baseWeightLb: 245 }, grade: "fail", note: "held at the peak" };
  await db.Programs.save(a);

  // An open session tagged to A blocks switching away from it.
  const openId = keep(db.Sessions, await db.Sessions.save({
    date: db.iso(new Date()), isCompleted: false, notes: "", exercises: [],
    programTag: { programId: a.uuid, programName: a.name },
  }));
  let blocked = false;
  try { await settingsView.assertNoForeignOpenSession((await db.Programs.get(bId)).uuid); }
  catch { blocked = true; }
  ok(blocked, "an open session from another program blocks the switch instead of orphaning it");
  await db.Sessions.del(openId);

  // A -> B -> A preserves everything.
  const b = await db.Programs.get(bId);
  await settingsView.suspendProgram(await db.Programs.get(aId));
  b.isActive = true; await db.Programs.save(b);
  a = await db.Programs.get(aId);
  ok(!a.isActive && a.cycleNumber === 3 && a.currentWeek === 3 && a.nextDayIndex === 2,
    "[INV-SWITCH-PRESERVES-CURSOR] a suspended program keeps its cycle, rotation and next day");
  ok(a.days[0].lifts[0].stallCount === 1 && a.days[0].lifts[0].pending?.state.baseWeightLb === 245,
    "and its per-slot progression state and pending peak result");

  await settingsView.suspendProgram(await db.Programs.get(bId));
  a = await db.Programs.get(aId);
  a.isActive = true; await db.Programs.save(a);
  a = await db.Programs.get(aId);
  ok(a.isActive && a.cycleNumber === 3 && a.nextDayIndex === 2
    && a.days[0].lifts[0].pending?.note === "held at the peak",
    "resuming re-derives nothing — it is a pause, not a restart");
})();


// ---- Stage 4 UI: the switcher is reachable from Today (epic #155) ----
await withCleanup(async (keep) => {
  const home = await import("../app/js/views/home.js");
  const id = keep(db.Programs, await db.Programs.save({
    name: "Switcher UI Fixture", focus: "strength", cycleNumber: 2, currentWeek: 1,
    nextDayIndex: 0, roundingLb: 5, isActive: true,
    days: [{ name: "Pull", order: 0, lifts: [cyc("Deadlift", "main", 235, 320)], accessories: [] }],
  }));
  // Only one program may be active; park any other the suite left behind.
  for (const other of await db.Programs.all()) {
    if (other.id !== id && other.isActive) { other.isActive = false; await db.Programs.save(other); }
  }
  await home.render(host()); await tick();
  const button = [...host().querySelectorAll("button")]
    .find((b) => b.getAttribute("aria-label") === "Switch training program");
  ok(button, "Today offers a program switcher next to the active block");
  button.click();
  // programSwitcher resolves two dynamic imports before it builds the sheet.
  for (let i = 0; i < 5; i += 1) await tick();
  // Other suite blocks leave sheets parked in the DOM; find OURS by title.
  const sheet = [...document.querySelectorAll("#overlays .sheet")]
    .reverse().find((o) => /Switch program/.test(o.textContent || ""));
  const text = sheet?.textContent || "";
  ok(/Start a new block/.test(text), "the switcher offers starting a new block");
  ok(/already earned/.test(text),
    "[INV-NEW-BLOCK-USES-CURRENT-HISTORY] and promises history and earned weights survive the switch");
  sheet?.querySelector("button")?.click(); await tick();
})();
// ---- Stage 5: program is a filter over one global history (epic #155) ----
// [INV-PROGRAM-IS-A-FILTER] The same lift trained under two blocks is ONE
// all-time series that each scope narrows; changing the active program never
// changes what history draws.
{
  const historyView = await import("../app/js/views/history.js");
  const eq = (a, b, msg) => ok(a === b, `${msg} (got ${a}, want ${b})`);
  const programs = [
    { id: 1, uuid: "aaaaaaaa-0000-4000-a000-000000000001", name: "Block A", templateId: "strength-upper-lower" },
    { id: 2, uuid: "aaaaaaaa-0000-4000-a000-000000000002", name: "Block B", templateId: "conjugate" },
    { id: 3, uuid: "aaaaaaaa-0000-4000-a000-000000000003", name: "Block C", templateId: "strength-upper-lower" },
  ];
  const sess = (programId, programName) => ({ date: "2026-08-01T10:00:00.000Z", isCompleted: true,
    programTag: programId ? { programId, programName } : null, exercises: [] });
  const sessions = [
    sess(programs[0].uuid, "Block A"), sess(programs[1].uuid, "Block B"),
    sess(programs[2].uuid, "Block C"), sess(null, null),
  ];

  const inScope = (scope) => sessions.filter((s) => historyView.sessionInScope(s, scope, programs)).length;
  eq(inScope("all"), 4, "all-time is the default and includes untracked work");
  eq(inScope(`program:${programs[0].uuid}`), 1, "one instance narrows to that block");
  eq(inScope("style:strength-upper-lower"), 2, "a style spans every block of that methodology");
  eq(inScope("style:conjugate"), 1, "and isolates a different style");

  const scopes = historyView.programScopes(sessions, programs);
  eq(scopes[0].value, "all", "all-time leads the picker");
  ok(scopes.some((s) => s.label === "Block A") && scopes.some((s) => s.label === "Block B"),
    "every block that logged this history is offered");
  ok(scopes.some((s) => s.value === "style:strength-upper-lower"),
    "and so is the style that spans two of them");
  // A legacy session carrying only a program NAME still resolves.
  ok(historyView.sessionInScope({ programTag: { programName: "Block A" } },
    `program:${programs[0].uuid}`, programs), "legacy name-only tags still resolve to their block");
  // Scoping is a pure function of the session and the programs — no notion of
  // which program is active appears anywhere in it.
  eq(inScope("all"), 4, "switching the active program cannot change history");
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);


// ---- Stage 6: corrections rebuild what is replayable (epic #155) ----
// PR milestones are regenerated deterministically from the corrected
// canonical sessions — never appended to — and the rebuild is idempotent.
await withCleanup(async (keep) => {
  const sessionView = await import("../app/js/views/session.js");
  const before = new Set((await db.Milestones.all()).map((m) => m.id));
  const mk = async (date, reps) => keep(db.Sessions, await db.Sessions.save({
    date: db.iso(date), completedAt: db.iso(date), isCompleted: true, notes: "",
    exercises: [{ exerciseName: "Good Morning", order: 0, sets: [
      { order: 0, weightLb: 185, reps, isWarmup: false, status: "completed", enteredUnit: "lb" },
    ] }],
  }));
  await mk(new Date("2031-01-01T10:00:00Z"), 5);
  await mk(new Date("2031-02-01T10:00:00Z"), 3);

  await sessionView.rebuildMilestones(["Good Morning"]);
  const first = (await db.Milestones.all()).filter((m) => !before.has(m.id) && m.exerciseName === "Good Morning");
  for (const m of first) keep(db.Milestones, m.id);
  ok(first.length > 0, "replaying corrected history regenerates the lift's PR milestones");
  ok(first.some((m) => m.kind === "heaviestSet" && /185/.test(m.label)),
    "including the heaviest-set record the history actually earns");

  // Idempotent: replaying unchanged history reproduces the same set, not a
  // second copy appended beside it.
  await sessionView.rebuildMilestones(["Good Morning"]);
  const second = (await db.Milestones.all()).filter((m) => m.exerciseName === "Good Morning" && !before.has(m.id));
  for (const m of second) keep(db.Milestones, m.id);
  const signature = (list) => list.map((m) => `${m.date}|${m.kind}|${m.label}`).sort().join("\n");
  ok(signature(second) === signature(first),
    "[INV-CORRECTION-REBUILDS-DERIVED-STATE] a second rebuild reproduces the same "
    + "milestones rather than appending duplicates");

  // Another lift's milestones are untouched by a scoped rebuild.
  const otherBefore = (await db.Milestones.all()).filter((m) => m.exerciseName !== "Good Morning").length;
  await sessionView.rebuildMilestones(["Good Morning"]);
  const otherAfter = (await db.Milestones.all()).filter((m) => m.exerciseName !== "Good Morning").length;
  ok(otherAfter === otherBefore, "a scoped rebuild never touches records it does not own");
})();

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
