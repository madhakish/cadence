import assert from "node:assert/strict";
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";
import { nextPendingExerciseIndex } from "../app/js/core.js";

assert.equal(nextPendingExerciseIndex([["completed", "planned"], ["planned"]], 0), 0);
assert.equal(nextPendingExerciseIndex([["completed"], ["skipped"], ["planned"]], 0), 2);
assert.equal(nextPendingExerciseIndex([["planned"], ["completed"]], 1), 0);
assert.equal(nextPendingExerciseIndex([["completed"], ["skipped"]], 0), null);
assert.equal(nextPendingExerciseIndex([], 0), null);
assert.equal(nextPendingExerciseIndex([["planned"]], -1), null);

const dom = new JSDOM('<body><div id="overlays"></div><div id="toast"></div></body>', { url: "https://cadence.invalid/app/" });
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
  Node: dom.window.Node, localStorage: dom.window.localStorage });
const db = await import("../app/js/db.js");
const session = await import("../app/js/views/session.js");
await db.ensureSeeded();
const settings = await db.Settings.get();
settings.haptics = false;
const original = { now: Date.now, setInterval, clearInterval };
let now = original.now(), nextHandle = 1;
const timers = new Map();
Date.now = () => now;
globalThis.setInterval = (callback) => { const id = nextHandle++; timers.set(id, callback); return id; };
globalThis.clearInterval = (id) => timers.delete(id);
const settle = () => new Promise((resolve) => setTimeout(resolve, 30));
const expire = () => { now += 600_000; for (const callback of [...timers.values()]) callback(); };
const entry = (name, order, statuses) => ({ order, exerciseName: name, programRole: order === 0 ? "main" : "complementary",
  sets: statuses.map((status, index) => ({ order: index, weightLb: 40, reps: 5, isWarmup: false,
    status, flags: [], enteredUnit: "lb", loadBasis: "perImplement", implementCount: 2 })) });

try {
  for (const mode of ["auto", "already-running", "manual-after-last-set"]) {
    settings.autoStartRest = mode === "auto";
    await db.Settings.save(settings);
    const id = await db.Sessions.save({ date: new Date(now).toISOString(), isCompleted: false,
      exercises: [entry("Incline DB Press", 0, ["completed", "completed", "planned"]),
        entry("Single-arm DB Row", 1, ["planned", "planned"])] });
    await session.openSession(id);
    const logger = [...document.querySelectorAll(".overlay")].at(-1);
    const press = logger.querySelector(".exercise-card.emphasized");
    const pressRest = [...press.querySelectorAll("button")].find((button) => button.textContent === "Rest");
    if (mode === "already-running") pressRest.click();
    press.querySelector('[aria-label="Set status: planned"]').click();
    await settle();
    if (mode === "manual-after-last-set") pressRest.click();
    expire();
    assert.equal(document.getElementById("toast").textContent, "Rest over · Single-arm DB Row.", mode);
    const saved = await db.Sessions.get(id);
    assert.equal(saved.exercises[0].sets[2].status, "completed");
    assert.equal(saved.exercises[1].sets[0].status, "planned", "notification never completes the next set");
    logger.querySelector(".overlay-head button").click();
    await db.Sessions.del(id);
  }
  settings.autoStartRest = true;
  await db.Settings.save(settings);
  const id = await db.Sessions.save({ date: new Date(now).toISOString(), isCompleted: false,
    exercises: [entry("Incline DB Press", 0, ["planned"])] });
  await session.openSession(id);
  const logger = [...document.querySelectorAll(".overlay")].at(-1);
  logger.querySelector('[aria-label="Set status: planned"]').click();
  await settle(); expire();
  assert.equal(document.getElementById("toast").textContent, "Rest over.", "finished workout does not advertise another set");
  logger.querySelector(".overlay-head button").click();
  await db.Sessions.del(id);
  console.log("Rest targets passed: auto, existing timer, manual, and final workout set.");
} finally {
  Date.now = original.now;
  globalThis.setInterval = original.setInterval;
  globalThis.clearInterval = original.clearInterval;
  dom.window.close();
}
