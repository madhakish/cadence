import assert from 'node:assert/strict';
import 'fake-indexeddb/auto';
import { JSDOM } from 'jsdom';
import * as C from '../app/js/core.js';

const hold = C.holdClockStart(30, 1000);
assert.equal(C.holdClockRemaining(hold, 1000), 30);
assert.equal(C.holdClockRemaining(hold, 1000.2), 30);
assert.equal(C.holdClockLoggedSeconds(hold, 1012.9), 12);
const stopped = C.holdClockStop(hold, 1012.9);
assert.equal(C.holdClockLoggedSeconds(stopped, 2000), 12);
assert.deepEqual(C.holdClockStop(stopped, 2000), stopped);
assert.equal(C.holdClockRemaining(stopped, 2000), 18);
assert.equal(C.holdClockRemaining(hold, 1029.9), 1);
assert.equal(C.holdClockLoggedSeconds(hold, 1029.9), 29);
assert.equal(C.holdClockRemaining(hold, 4000), 0);
assert.equal(C.holdClockLoggedSeconds(hold, 4000), 30);
assert.equal(C.holdClockLoggedSeconds(hold, 900), 0);
for (const value of [-1, 0, 1801, 1.5, NaN]) assert.equal(C.holdClockStart(value, 1000), null);
assert.equal(C.holdClockStart(30, NaN), null);
const rest = C.restClockStart(90, 1000);
C.holdClockStop(hold, 1012);
assert.equal(C.restClockRemaining(rest, 1012), 78);

const dom = new JSDOM('<body><div id="overlays"></div><div id="toast"></div></body>', { url: 'https://cadence.invalid/app/' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document, Node: dom.window.Node, localStorage: dom.window.localStorage });
const { openHoldTimer } = await import('../app/js/hold-timer.js');
const db = await import('../app/js/db.js');
const { openSession } = await import('../app/js/views/session.js');
await db.ensureSeeded();
const settings = await db.Settings.get();
settings.autoStartRest = false; settings.haptics = false; await db.Settings.save(settings);
const original = { now: Date.now, setInterval, clearInterval };
let now = original.now(), nextHandle = 1, chimes = 0, saves = [];
const timers = new Map();
Date.now = () => now;
globalThis.setInterval = (fn) => { const id = nextHandle++; timers.set(id, fn); return id; };
globalThis.clearInterval = (id) => timers.delete(id);
const advance = (seconds) => { now += seconds * 1000; for (const tick of [...timers.values()]) tick(); };
const settle = () => new Promise((resolve) => setTimeout(resolve, 20));
const button = (root, label) => [...root.querySelectorAll('button')].find((b) => b.textContent === label);
try {
  let modal = openHoldTimer({ exerciseName: 'Plank', seconds: 30, onSave: (s) => saves.push(s), onDone: () => chimes++ });
  advance(12.9); button(modal.el, 'Stop hold').click(); advance(1000);
  assert.match(modal.el.querySelector('[role="timer"]').getAttribute('aria-label'), /12 seconds/);
  assert.equal(chimes, 0);
  button(modal.el, 'Log 0:12').click(); await settle();
  assert.deepEqual(saves, [12]); assert.equal(modal.el.isConnected, false);

  // A suspended browser catches up from the deadline and alerts just once.
  modal = openHoldTimer({ exerciseName: 'Plank', seconds: 30, onSave: (s) => saves.push(s), onDone: () => chimes++ });
  now += 300_000; document.dispatchEvent(new dom.window.Event('visibilitychange'));
  advance(1000); assert.equal(chimes, 1); assert.deepEqual(saves, [12]);
  button(modal.el, 'Discard attempt').click();
  advance(1000); assert.equal(chimes, 1); assert.equal(timers.size, 0);

  // Failed persistence leaves the result retryable; duplicate taps and Escape
  // during a pending save cannot lose the attempt or write it twice.
  let release, attempts = 0;
  modal = openHoldTimer({ exerciseName: 'Plank', seconds: 30, onSave: async () => {
    attempts++; if (attempts === 1) throw new Error('injected storage failure');
    await new Promise((resolve) => { release = resolve; });
  } });
  advance(30); button(modal.el, 'Log 0:30').click(); await settle();
  assert.match(modal.el.querySelector('[role="alert"]').textContent, /Could not save/);
  button(modal.el, 'Log 0:30').click(); button(modal.el, 'Log 0:30').click();
  modal.el.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  assert.equal(attempts, 2); assert.equal(modal.el.isConnected, true);
  release(); await settle(); assert.equal(modal.el.isConnected, false);

  const id = await db.Sessions.save({ date: new Date(now).toISOString(), isCompleted: false,
    exercises: [{ order: 0, exerciseName: 'Plank', exerciseId: (await db.Exercises.byName('Plank')).id,
      sets: [{ order: 0, weightLb: 0, reps: 1, status: 'planned', isWarmup: false, flags: [],
        durationSeconds: 30, plannedDurationSeconds: 30, enteredUnit: 'lb' }] }] });
  await openSession(id);
  const logger = [...document.querySelectorAll('.overlay')].at(-1);
  const restButton = [...logger.querySelectorAll('button')].find((b) => /^Rest /.test(b.textContent));
  restButton.click();
  logger.querySelector('[aria-label="Start Plank timer"]').click();
  const timerSheet = [...document.querySelectorAll('.sheet')].at(-1);
  advance(12.9); button(timerSheet, 'Stop hold').click();
  let saved = await db.Sessions.get(id);
  assert.equal(saved.exercises[0].sets[0].status, 'planned', 'timing alone does not log');
  assert.equal(saved.exercises[0].sets[0].durationSeconds, 30);
  assert.notEqual(logger.querySelector('.rest-time').style.display, 'none', 'hold does not cancel rest');
  assert.notEqual(logger.querySelector('.rest-time').textContent, '0:00');
  button(timerSheet, 'Log 0:12').click(); await settle();
  saved = await db.Sessions.get(id);
  assert.equal(saved.exercises[0].sets[0].durationSeconds, 12);
  assert.equal(saved.exercises[0].sets[0].plannedDurationSeconds, 30, 'original prescription survives');
  assert.equal(saved.exercises[0].sets[0].status, 'completed');
  logger.querySelector('.overlay-head button').click(); advance(1);
  console.log('PASS hold timer: shared math, early stop, background catch-up, once-only alert, discard, failed save/retry, real set logging, and independent rest');
} finally {
  Date.now = original.now; globalThis.setInterval = original.setInterval; globalThis.clearInterval = original.clearInterval;
  dom.window.close();
}
