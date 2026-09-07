import assert from 'node:assert/strict';
import 'fake-indexeddb/auto';
import { JSDOM } from 'jsdom';

// Launched by build-polish.test.mjs in a fresh America/Chicago process.
assert.equal(process.env.TZ, 'America/Chicago');
const RealDate = Date;
let now;
globalThis.Date = class extends RealDate {
  constructor(...args) { super(...(args.length ? args : [now])); }
  static now() { return now; }
};
const dom = new JSDOM('<body><div id="overlays"></div><div id="toast"></div></body>', {
  url: 'https://cadence.invalid/app/',
});
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
  Node: dom.window.Node, localStorage: dom.window.localStorage });
const db = await import('../app/js/db.js');
const session = await import('../app/js/views/session.js');
const C = await import('../app/js/core.js');
now = RealDate.parse('2026-03-09T00:05:00-05:00');
await db.ensureSeeded();

for (const [days, expected] of [[-1, 'today'], [0, 'today'], [1, 'yesterday'], [2, '2d ago'],
  [13, '13d ago'], [14, '2w ago'], [69, '9w ago'], [70, '2mo ago']]) {
  const before = new RealDate(now);
  before.setDate(before.getDate() - days);
  assert.equal(C.historyAgeLabel(before, now), expected);
  assert.equal(C.historyProvenanceLabel(before, now), `from your last exposure, ${expected}`);
}

for (const [before, after, expected] of [
  ['2026-03-08T23:55:00-05:00', '2026-03-09T00:05:00-05:00', 'yesterday'],
  ['2026-03-07T12:00:00-06:00', '2026-03-08T11:30:00-05:00', 'yesterday'],
  ['2026-10-31T12:00:00-05:00', '2026-11-01T11:30:00-06:00', 'yesterday'],
  ['2026-03-08T00:05:00-06:00', '2026-03-08T23:55:00-05:00', 'today'],
]) {
  now = RealDate.parse(after);
  const pastId = await session.createBlankSession();
  const past = await db.Sessions.get(pastId);
  past.date = before;
  past.isCompleted = true;
  past.exercises = [{ order: 0, exerciseName: 'Deadlift', notes: '', barId: '45-lb', sets: [{
    order: 0, isWarmup: false, weightLb: 135, reps: 5, enteredUnit: 'lb',
    loadBasis: 'totalBar', status: 'completed', flags: [], rpe: null, rir: null, quality: null,
  }] }];
  await db.Sessions.save(past);
  const savedPast = await db.Sessions.get(pastId);
  const currentId = await session.createBlankSession();
  const current = await db.Sessions.get(currentId);
  current.exercises = [{ ...past.exercises[0], sets: [{ ...past.exercises[0].sets[0], status: 'planned' }] }];
  await db.Sessions.save(current);
  await session.openSession(currentId);
  const screen = [...document.querySelectorAll('.overlay')].at(-1);
  const recall = [...screen.querySelectorAll('.sub')].find((el) => el.textContent.startsWith('Last:'));
  assert.ok(recall, 'the actual logger shows previous performed work');
  assert.ok(recall.textContent.endsWith(`(${expected})`), `${before} → ${after}: ${recall.textContent}`);
  assert.deepEqual(await db.Sessions.get(pastId), savedPast, 'display does not rewrite history');
  screen.querySelector('.overlay-head button').click();
  await db.Sessions.del(currentId);
  await db.Sessions.del(pastId);
}
dom.window.close();
console.log('PASS session recall: local midnight, both DST changes, same-day history preserved');
