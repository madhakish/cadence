import assert from "node:assert/strict";
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";
const dom = new JSDOM('<!doctype html><body><div id="overlays"></div><div id="toast"></div></body>', { url: "http://localhost/" });
for (const key of ["window", "document", "localStorage", "Node"]) globalThis[key] = dom.window[key] ?? dom.window;
globalThis.window = dom.window;
const C = await import("../app/js/core.js");
const DB = await import("../app/js/db.js");
const { completeSession, rebuildMilestones } = await import("../app/js/views/session.js");
const { historySetPresentationForTest } = await import("../app/js/views/history.js");
const { plateBadgeSVG, barbellSVG, loadoutSummary } = await import("../app/js/barbell.js");
const T = await import("../app/js/plate-theme.js");

await DB.Exercises.save({ name: "Farmer Carry", type: "dumbbell", category: "Accessory", loadBasis: "perImplement", implementCount: 2 });
const set = (weightLb, reps, yards = null) => ({ weightLb, reps, distanceMiles: yards == null ? null : C.milesFromYards(yards),
  loadBasis: "perImplement", implementCount: 2, isPerSide: false, isWarmup: false, status: "completed", flags: [] });
const workout = (id, date, sets, isCompleted) => ({ id, date, notes: "Synthetic regression", isCompleted,
  exercises: [{ exerciseName: "Farmer Carry", notes: "", sets }] });
const past = workout("carry-past", "2026-09-20T12:00:00Z", [set(600, 100), set(50, 1, 40)], true);
await DB.Sessions.save(past);
const current = workout("carry-current", "2026-09-21T12:00:00Z", [set(50, 1, 60)], false);
await DB.Sessions.save(current);
const summary = await completeSession(current);
assert.deepEqual(summary.milestones.map((m) => m.kind), ["volumePR"], "bank compares the 6000 lb·yd carry against 4000 lb·yd, never 120000 lb rep tonnage");
const banked = (await DB.Milestones.all()).filter((m) => m.date === current.date).map(({ kind, label }) => ({ kind, label }));
await rebuildMilestones(["Farmer Carry"]);
const rebuilt = (await DB.Milestones.all()).filter((m) => m.date === current.date).map(({ kind, label }) => ({ kind, label }));
assert.deepEqual(rebuilt, banked, "rebuild uses the same distance baseline as bank");
assert.match(historySetPresentationForTest({ ...set(50, 1, 40), isPerSide: true }, "dumbbell", "Farmer Carry").actual,
  /each × 40 yd \/ side/, "history states per-hand load and per-side distance");

const inventory = [{ value: 45, unit: "lb", enabled: true }, { value: 20, unit: "kg", enabled: false }];
const old = structuredClone(inventory);
const profile = T.plateThemeInventory(inventory, "iwfCompetition");
assert.deepEqual(inventory, old, "profile preparation never mutates the current rack");
assert.deepEqual(profile.filter((p) => p.enabled).map(C.plateId).sort(), T.plateThemeSet("kg", "iwfCompetition").map(C.plateId).sort());
assert.equal(profile.find((p) => C.plateId(p) === "45-lb").enabled, false, "an old plate remains available to re-enable");
assert.deepEqual(T.plateThemeInventory(inventory, "custom"), inventory);
const p = { value: 20, unit: "kg" };
const colour = T.plateThemeColour(p, "lbBlackIron", "steel");
assert.equal(plateBadgeSVG(p, "steel", { plateTheme: "lbBlackIron" }).querySelector("circle").getAttribute("fill"), colour.fill);
const solution = C.enteredPlateSolution(C.BARS.bar45lb, [{ plate: p, count: 1 }]);
const view = loadoutSummary(null, solution, { plateTheme: "lbBlackIron" });
assert.equal(view.querySelector(".loadout-cell-text .sub").textContent, "Iron");
assert.equal(view.querySelector(".plate-badge circle").getAttribute("fill"), colour.fill);
assert.equal(barbellSVG(solution, "full", "steel", { plateTheme: "lbBlackIron" }).plateTheme, "lbBlackIron");
console.log("PR integration: carry lane bank/rebuild, preserved implement counts, themed badges and explicit profile inventory passed");
