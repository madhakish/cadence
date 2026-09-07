import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import 'fake-indexeddb/auto';
import { JSDOM } from 'jsdom';
import * as C from '../app/js/core.js';

const dom = new JSDOM('<body><div id="overlays"></div><div id="toast"></div></body>', { url: 'https://cadence.invalid/app/' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document, Node: dom.window.Node, localStorage: dom.window.localStorage });
const ui = await import('../app/js/ui.js');
const db = await import('../app/js/db.js');
const inputEvent = () => new dom.window.Event('input', { bubbles: true });
const submit = (form) => form.dispatchEvent(new dom.window.Event('submit', { bubbles: true, cancelable: true }));
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

for (const [parts, expected] of [
  [['0','0','0'], 0], [['0','0','1'], 1], [['0','1','37'], 97], [['0','0','90'], 90],
  [['0','59','59'], 3599], [['1','0','0'], 3600], [['','60',''], 3600],
]) assert.equal(C.restDurationParse(...parts), expected);
for (const invalid of ['-1','1.5','1e2','NaN','abc','9999999999999999999999'])
  assert.equal(C.restDurationParse('0','0',invalid), null);
assert.equal(C.restDurationParse('1','0','1'), null);
assert.equal(C.restDurationLabel(90), '00:01:30');
assert.equal(C.restDurationLabel(3600), '01:00:00');
assert.equal(C.REST_DURATION_MAX, 3600);

const clock = C.restClockStart(300, 100);
const edited = C.restClockSettingRemaining(clock, 97, 200);
assert.equal(C.restClockRemaining(edited, 200), 97);
assert.equal(edited.total, 197);
const paused = C.restClockPause(clock, 200);
const pausedEdit = C.restClockSettingRemaining(paused, 30, 900);
assert.equal(pausedEdit.paused, true);
assert.equal(C.restClockRemaining(pausedEdit, 1000), 30);
assert.equal(C.restClockSettingRemaining(clock, 30, 400), null);
assert.equal(C.restClockSettingRemaining(paused, 0, 900), null);

let saves = [];
let dialog = ui.durationEditor({ title: 'Rest override', seconds: 97, zeroLabel: 'Use default', onSave: (v) => saves.push(v) });
const fields = () => [...dialog.el.querySelectorAll('input')];
assert.deepEqual(fields().map((f) => f.getAttribute('aria-label')), ['Hours','Minutes','Seconds']);
assert.deepEqual(fields().map((f) => f.value), ['0','1','37']);
fields()[2].value = '90'; fields()[2].dispatchEvent(inputEvent());
assert.match(dialog.el.querySelector('[role="status"]').textContent, /00:02:30/);
assert.deepEqual(saves, [], 'draft typing never writes');
[...dialog.el.querySelectorAll('button')].find((b) => b.textContent === 'Cancel').click();
assert.deepEqual(saves, [], 'Cancel preserves the original');

let releaseSave;
dialog = ui.durationEditor({ title: 'Rest', seconds: 0, onSave: async (v) => { saves.push(v); await new Promise((r) => { releaseSave = r; }); } });
const paste = new dom.window.Event('paste', { bubbles: true, cancelable: true });
Object.defineProperty(paste, 'clipboardData', { value: { getData: () => '00:01:37' } });
fields()[0].dispatchEvent(paste);
assert.deepEqual(fields().map((f) => f.value), ['00','01','37']);
const form = dialog.el.querySelector('form');
submit(form); submit(form);
assert.deepEqual(saves, [97], 'duplicate Save does not write twice');
releaseSave(); await tick(); assert.equal(dialog.el.isConnected, false);

dialog = ui.durationEditor({ title: 'Rest', seconds: 3600, onSave: () => { throw new Error('save failed'); } });
fields()[2].value = '1'; fields()[2].dispatchEvent(inputEvent());
assert.equal(dialog.el.querySelector('[type="submit"]').disabled, true);
assert.equal(fields()[2].getAttribute('aria-invalid'), 'true');
fields()[2].value = '0'; fields()[2].dispatchEvent(inputEvent());
submit(dialog.el.querySelector('form')); await tick();
assert.equal(dialog.el.isConnected, true);
assert.match(dialog.el.textContent, /Could not save/);
assert.equal(dialog.el.querySelector('[type="submit"]').disabled, false);
dialog.close();

// Exercise the real persistence and portable contract at every boundary.
await db.ensureSeeded();
for (const seconds of [0, 1, 97, 3599, 3600]) {
  const settings = await db.Settings.get();
  settings.rest.secondarySeconds = seconds; await db.Settings.save(settings);
  const exercise = (await db.Exercises.all())[0];
  exercise.defaultRestSeconds = seconds; await db.Exercises.save(exercise);
  const bundle = JSON.parse(await db.exportJSON());
  await db.importBundle(bundle);
  assert.equal((await db.Settings.get()).rest.secondarySeconds, seconds);
  assert.equal((await db.Exercises.byName(exercise.name)).defaultRestSeconds, seconds);
}
const invalid = JSON.parse(await db.exportJSON());
invalid.settings.rest.secondarySeconds = 3601;
await assert.rejects(() => db.importBundle(invalid));
const native = readFileSync(new URL('../../Cadence/Services/ImportService.swift', import.meta.url), 'utf8');
assert.match(native, /defaultRestSeconds.*min: 0, max: 3600/);
assert.ok(/settings.rest.mainCompoundSeconds/.test(native) && /try integer\(value, path, min: 0, max: 3600\)/.test(native), 'native rest buckets keep the same one-hour boundary');
console.log('PASS rest duration: exact entry, normalization, active countdown, staged dialog, once-only save, and persistence boundaries');
