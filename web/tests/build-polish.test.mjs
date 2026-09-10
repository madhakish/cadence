import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import 'fake-indexeddb/auto';
import { JSDOM } from 'jsdom';
import * as C from '../app/js/core.js';

const dom = new JSDOM('<body><div id="overlays"></div><div id="toast"></div></body>', { url: 'https://cadence.invalid/app/' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document, Node: dom.window.Node, localStorage: dom.window.localStorage });
const db = await import('../app/js/db.js');
const session = await import('../app/js/views/session.js');
const plates = await import('../app/js/views/plates.js');
const settingsView = await import('../app/js/views/settings.js');
await db.ensureSeeded();
const classified = { name: 'Fixture Secondary Classification', category: 'Main',
  type: 'barbell', movementPattern: 'hipHinge', secondaryMovementPattern: 'squat' };
for (const [pattern, expected] of [[null, true], ['hipHinge', true], ['squat', true], ['horizontalPress', false]])
  assert.equal(C.exerciseMatchesMovement(classified, pattern), expected);
assert.equal(C.exerciseMatchesMovement({ ...classified, secondaryMovementPattern: null }, 'squat'), false);
settingsView.exerciseLibrary([classified]);
const library = [...document.querySelectorAll('.overlay')].at(-1);
const filter = library.querySelector('select[aria-label="Movement"]');
filter.value = 'squat'; filter.dispatchEvent(new window.Event('change'));
assert.equal(library.querySelector('.library-group .row .title')?.textContent, classified.name);
library.querySelector('.overlay-head button').click();
// A v13-only enum must reject before any store writes if the bundle claims
// an older version. The four previously shipped themes remain accepted.
const themeBefore = (await db.Settings.get()).theme;
const backup = JSON.parse(await db.exportJSON());
for (const schemaVersion of [0, 1, 12]) {
  await assert.rejects(() => db.importBundle({ ...backup, schemaVersion,
    settings: { ...backup.settings, theme: 'titanium' } }), /settings.theme/);
  assert.equal((await db.Settings.get()).theme, themeBefore);
}
for (const theme of ['carbon', 'memento', 'slate', 'system']) {
  await db.importBundle({ ...backup, schemaVersion: 12, settings: { ...backup.settings, theme } });
  assert.equal((await db.Settings.get()).theme, theme);
}
await db.importBundle({ ...backup, schemaVersion: 13, settings: { ...backup.settings, theme: 'titanium' } });
assert.equal((await db.Settings.get()).theme, 'titanium');
await db.importBundle(backup);
for (const [value, colour] of [[2,'blue'],[1.5,'yellow'],[1,'green'],[0.5,'white']]) {
  assert.equal(C.plateColorToken({ value, unit: 'kg' }, 'bumper'), colour);
  assert.equal(C.plateColorToken({ value, unit: 'kg' }, 'steel'), 'black');
  assert.ok(!C.ALL_STANDARD.some((plate) => plate.unit === 'kg' && plate.value === value));
}
const tick = () => new Promise((resolve) => setTimeout(resolve, 60));

await plates.openPlateCalculator();
let overlay = [...document.querySelectorAll('.overlay')].at(-1);
const target = overlay.querySelector('.target-entry input');
target.focus();
const value = target.value;
const kg = [...overlay.querySelectorAll('.target-entry button')].find((b) => b.textContent === 'kg');
kg.click();
assert.equal(target.getAttribute('aria-label'), 'Requested target in kg');
assert.equal(target.value, value);
assert.equal(document.activeElement, target, 'updating units does not replace or blur the input');
const lb = [...overlay.querySelectorAll('.target-entry button')].find((b) => b.textContent === 'lb');
lb.click();
assert.equal(target.getAttribute('aria-label'), 'Requested target in lb');
overlay.querySelector('.overlay-head button').click();

const set = { weightLb: 50.5, enteredUnit: 'lb' };
for (const unit of ['lb','kg']) {
  const solution = session.plateSolutionForSet({ ...set, enteredUnit: unit }, C.BARS.bar45lb);
  assert.ok(solution.perSide.every(({ plate }) => plate.unit === unit));
}
const station = session.plateSolutionForSet(set, C.BARS.bar45lb, null, { stationDenomination: 'kg' });
assert.ok(station.perSide.some(({ plate }) => plate.unit === 'kg'));
const gym = { collarWeightLb: 0, loadingPolicy: 'closest', plateToggles: C.ALL_STANDARD.map((p) => ({ ...p, enabled: true })) };
const mixed = session.plateSolutionForSet(set, C.BARS.bar45lb, gym);
assert.deepEqual(mixed, C.solve(set.weightLb, C.BARS.bar45lb, C.ALL_STANDARD, 10, 0, 'closest'));

const entries = [['planned','completed'], ['planned'], ['planned']];
assert.equal(C.focusAfterResolving(entries, 0), 0);
assert.deepEqual(entries[0], ['planned','completed']);
entries[0][0] = 'skipped'; assert.equal(C.focusAfterResolving(entries, 0), 1);
entries[0][0] = 'planned'; assert.equal(C.focusAfterResolving(entries, 0), 0);
assert.equal(C.focusAfterResolving(entries, -1), null);
assert.equal(C.focusAfterResolving([['completed'],['skipped']], 1), 1);

// Drive the actual logger: completing the last working set must leave its
// unresolved warmup on the current exercise, without mutating that warmup.
const sid = await session.createBlankSession();
const workout = await db.Sessions.get(sid);
const mkSet = (order, isWarmup, weightLb) => ({ order, isWarmup, weightLb, reps: 5,
  enteredUnit: 'lb', loadBasis: 'totalBar', status: 'planned', flags: [], rpe: null, rir: null,
  quality: null, targetWeightLb: weightLb, plannedWeightLb: weightLb, plannedReps: 5 });
workout.exercises = [
  { order: 0, exerciseName: 'Deadlift', notes: '', barId: '45-lb', sets: [mkSet(0,true,45),mkSet(1,false,135)] },
  { order: 1, exerciseName: 'Overhead Press', notes: '', barId: '45-lb', sets: [mkSet(0,false,65)] },
];
await db.Sessions.save(workout); await session.openSession(sid); await tick();
overlay = [...document.querySelectorAll('.overlay')].at(-1);
overlay.querySelector('.exercise-card.emphasized .setrow.current button[aria-label="Set status: planned"]').click();
await tick();
assert.match(overlay.querySelector('.exercise-card.emphasized').getAttribute('aria-label'), /^Deadlift/);
assert.equal((await db.Sessions.get(sid)).exercises[0].sets[0].status, 'planned');
assert.equal(overlay.querySelector('.prior-exercises'), null);
overlay.querySelector('.overlay-head button').click(); await db.Sessions.del(sid);

// The new glance display must preserve the stored load meaning and must not
// turn a skipped set into a completion checkmark. Use a barbell library entry
// deliberately: the set snapshot, not current equipment metadata, owns this.
for (const [basis, label] of [['perImplement', 'Per implement'], ['assisted', 'Assistance'], ['totalBar', 'bar included']]) {
  const id = await session.createBlankSession();
  const stored = await db.Sessions.get(id);
  stored.exercises = [{ order: 0, exerciseName: 'Deadlift', notes: '', barId: '45-lb', sets:
    ['completed', 'skipped', 'planned'].map((status, index) => ({ ...mkSet(index, false, 50), status, loadBasis: basis })) }];
  await db.Sessions.save(stored); await session.openSession(id); await tick();
  const screen = [...document.querySelectorAll('.overlay')].at(-1);
  const segments = [...screen.querySelectorAll('.set-track-segment')];
  assert.equal(segments[0].textContent, '✓ Set 1');
  assert.equal(segments[1].textContent, '− Set 2', 'skipped sets use the same minus as the status control');
  assert.match(segments[1].getAttribute('aria-label'), /skipped$/);
  assert.match(segments[2].getAttribute('aria-label'), /current$/);
  assert.ok(screen.querySelector('.current-set-hero .sub').textContent.includes(label),
    `the hero explains the stored ${basis} load`);
  assert.ok(screen.querySelector('.current-set-load').getAttribute('aria-label').endsWith(C.loadBasisSuffix(basis)));
  screen.querySelector('.overlay-head button').click(); await db.Sessions.del(id);
}

// Date fixtures execute in a separate real timezone, never mutate process TZ
// after Date initialization, and compare the same cases as Swift.
const dates = [
  ['2026-03-07T12:00:00-06:00','2026-03-08T11:30:00-05:00'],
  ['2026-10-31T12:00:00-05:00','2026-11-01T11:30:00-06:00'],
  ['2026-03-08T23:55:00-05:00','2026-03-09T00:05:00-05:00'],
];
const moduleURL = new URL('../app/js/core.js', import.meta.url).href;
const code = `import {historyProvenanceLabel} from ${JSON.stringify(moduleURL)}; process.stdout.write(JSON.stringify(${JSON.stringify(dates)}.map(([a,b])=>historyProvenanceLabel(a,b))));`;
assert.deepEqual(JSON.parse(execFileSync(process.execPath, ['--input-type=module','-e',code],
  { env: { ...process.env, TZ: 'America/Chicago' }, encoding: 'utf8' })), Array(3).fill('from your last exposure, yesterday'));
execFileSync(process.execPath, [fileURLToPath(new URL('./session-recall.test.mjs', import.meta.url))],
  { env: { ...process.env, TZ: 'America/Chicago' }, stdio: 'inherit', timeout: 60_000 });
console.log('PASS build polish: target accessible unit, no-gym denomination, unresolved warmup focus, DST/calendar labels');
