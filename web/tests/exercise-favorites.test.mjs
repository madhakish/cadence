import assert from 'node:assert/strict';
import 'fake-indexeddb/auto';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<body><main></main><div id="overlays"></div><div id="toast"></div></body>', { url: 'https://cadence.invalid/app/' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
  Node: dom.window.Node, localStorage: dom.window.localStorage });
const db = await import('../app/js/db.js');
const { exerciseBrowser } = await import('../app/js/views/settings.js');
await db.ensureSeeded();
const names = ['Back Squat', 'Incline DB Press', 'Face Pulls'];
const library = (await db.Exercises.all()).filter((e) => names.includes(e.name));
library.find((e) => e.name === 'Face Pulls').gateStatus = 'shelved';
let selected = [];
const show = (options = {}) => {
  const browser = exerciseBrowser(library, { onSelect: (e) => selected.push(e.id), ...options });
  document.querySelector('main').replaceChildren(browser); return browser;
};
let browser = show();
const stars = (name) => [...browser.querySelectorAll('.exercise-favorite')].filter((b) => b.getAttribute('aria-label').includes(name));
const favorites = () => browser.querySelector('.library-favorites');
const change = (control, value) => { control.value = value; control.dispatchEvent(new window.Event(control.type === 'search' ? 'input' : 'change')); };
const until = async (predicate) => {
  for (let i = 0; i < 50; i++) { if (predicate()) return; await new Promise((r) => setTimeout(r, 0)); }
  assert.ok(predicate(), 'favorite action did not complete');
};
assert.match(favorites().textContent, /Star a lift/);
browser.querySelectorAll('details').forEach((d) => { d.open = true; });
const star = stars('Back Squat')[0]; star.focus(); star.click();
await until(() => library.find((e) => e.name === 'Back Squat').isFavorite);
assert.deepEqual(selected, [], 'starring cannot select a lift');
assert.match(favorites().textContent, /Back Squat/);
assert.equal((await db.Exercises.byName('Back Squat')).isFavorite, true);
assert.equal(document.activeElement.getAttribute('aria-label'), 'Remove Back Squat from Favorites', 'keyboard focus survives repaint');
change(browser.querySelector('input'), 'squat');
change(browser.querySelector('[aria-label="Movement"]'), 'squat');
change(browser.querySelector('[aria-label="Equipment"]'), 'barbell');
assert.match(favorites().textContent, /Back Squat/);
change(browser.querySelector('[aria-label="Equipment"]'), 'dumbbell');
assert.match(browser.textContent, /No exercises match/);
assert.equal(library.find((e) => e.name === 'Back Squat').isFavorite, true, 'filters never mutate favorites');

browser = show();
const removal = favorites().querySelector('.exercise-favorite'); removal.focus(); removal.click();
await until(() => !library.find((e) => e.name === 'Back Squat').isFavorite);
assert.equal(document.activeElement.textContent, 'Favorites', 'removing the last shortcut leaves focus on its entry point');
assert.equal((await db.Exercises.byName('Back Squat')).isFavorite, false);

// Inject a real boundary failure, not an optimistic model mutation. The row
// must keep its previous state and offer another attempt.
const save = db.Exercises.save;
db.Exercises.save = async () => { throw new Error('Synthetic storage failure'); };
const failed = stars('Incline DB Press')[0]; failed.click();
await until(() => !failed.disabled);
// [INV-FAVORITE-FAILED-SAVE] A failed boundary write cannot publish an optimistic preference.
assert.equal(library.find((e) => e.name === 'Incline DB Press').isFavorite, false);
assert.equal(failed.getAttribute('aria-pressed'), 'false');
assert.match(document.querySelector('#toast').textContent, /Couldn't save this favorite/);
db.Exercises.save = save;

for (const e of library) { e.isFavorite = true; await db.Exercises.save(e); }
browser = show();
assert.match(favorites().textContent, /Face Pulls/, 'library preserves a shelved favorite for deliberate review');
browser = show({ availableOnly: true });
assert.doesNotMatch(favorites().textContent, /Face Pulls/, 'program picker excludes a shelved favorite');
browser = show({ equipmentPolicy: 'freeWeightsOnly' });
assert.doesNotMatch(favorites().textContent, /Face Pulls/, 'favorites cannot bypass equipment policy');
assert.match(favorites().textContent, /Incline DB Press/);
const pick = [...favorites().querySelectorAll('button')].find((b) => b.textContent === 'Incline DB Press');
pick.click(); assert.deepEqual(selected, [library.find((e) => e.name === 'Incline DB Press').id]);
console.log('Favorites UI: persistence, filters, policy, shelving, selection, focus, and failed save passed');
dom.window.close();
