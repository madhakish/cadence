import assert from 'node:assert/strict';
import 'fake-indexeddb/auto';

const id = 'a0000000-0000-4000-8000-000000000063';
const legacy = { id, name: 'Synthetic Favorite', category: 'Main', type: 'barbell',
  movementPattern: 'squat', gateStatus: 'shelved', isShelved: true, notes: 'Keep this note',
  defaultRestSeconds: 123, aliases: ['Fixture squat'] };
const old = await new Promise((resolve, reject) => {
  const req = indexedDB.open('cadence', 10);
  req.onupgradeneeded = () => {
    const exercises = req.result.createObjectStore('exercises', { keyPath: 'name' });
    exercises.createIndex('byId', 'id', { unique: true });
  };
  req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error);
});
await new Promise((resolve, reject) => {
  const tx = old.transaction(['exercises'], 'readwrite');
  tx.objectStore('exercises').put(legacy);
  tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
}); old.close();
const db = await import('../app/js/db.js');
const stored = await db.runAll(['exercises'], 'readonly', (os) => new Promise((resolve, reject) => {
  const req = os('exercises').get(legacy.name); req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error);
}));
assert.deepEqual(stored, { ...legacy, isFavorite: false }, 'actual V10 document upgrades without changing any authored field');
let lift = await db.Exercises.byName(legacy.name);
await db.Exercises.save({ ...lift, isFavorite: true });
await db.syncLibrary();
lift = await db.Exercises.byName(legacy.name);
assert.equal(lift.isFavorite, true, 'seed top-up preserves favorites');
assert.equal(lift.id, id); assert.equal(lift.gateStatus, 'shelved');
const bundle = JSON.parse(await db.exportJSON());
assert.equal(bundle.schemaVersion, 16);
const definition = bundle.exercises.find((e) => e.id === id);
assert.equal(definition.isFavorite, true);
db.validateBackup(bundle);
await db.wipeAll(); await db.importBundle(bundle);
assert.equal((await db.Exercises.byName(legacy.name)).isFavorite, true);
const changed = structuredClone(bundle);
changed.exercises.find((e) => e.id === id).isFavorite = false;
const preview = await db.namedRestorePreview(changed);
assert.equal(preview.exercises.find((e) => e.name === legacy.name).status, 'changed');
assert.equal(await db.backupMatchesCurrent(changed), false);
const incomplete = structuredClone(bundle);
delete incomplete.exercises[0].isFavorite;
assert.throws(() => db.validateBackup(incomplete), /isFavorite/);
const malformed = structuredClone(bundle);
malformed.exercises[0].isFavorite = 'true';
assert.throws(() => db.validateBackup(malformed), /isFavorite/);
assert.equal((await db.Exercises.byName(legacy.name)).isFavorite, true);
const preFavorites = structuredClone(bundle); preFavorites.schemaVersion = 15;
for (const e of preFavorites.exercises) delete e.isFavorite;
await db.importBundle(preFavorites);
assert.equal((await db.Exercises.byName(legacy.name)).isFavorite, false);
const renamed = { ...(await db.Exercises.byName(legacy.name)), name: 'Renamed Favorite', isFavorite: true };
await db.Exercises.save(renamed);
assert.equal((await db.Exercises.byName(renamed.name)).id, id);
assert.equal((await db.Exercises.byName(renamed.name)).isFavorite, true);
assert.equal(await db.Exercises.byName(legacy.name), null, 'rename removes the old name key');
assert.equal((await db.Exercises.all()).filter((e) => e.id === id).length, 1);

const occupied = { ...renamed, id: 'b0000000-0000-4000-8000-000000000063', name: 'Occupied Favorite', isFavorite: false };
await db.Exercises.save(occupied);
await assert.rejects(db.Exercises.save({ ...renamed, name: occupied.name }), /already exists/);
assert.deepEqual(await db.Exercises.byName(renamed.name), renamed, 'name collision retains the original exercise');
assert.deepEqual(await db.Exercises.byName(occupied.name), occupied, 'name collision cannot overwrite another identity');

await assert.rejects(db.Exercises.save({ ...renamed, name: 'Failed Rename', uncloneable: () => {} }), { name: 'DataCloneError' });
assert.deepEqual(await db.Exercises.byName(renamed.name), renamed, 'failed put rolls back the old-key deletion and favorite');
assert.equal(await db.Exercises.byName('Failed Rename'), null);
console.log('V10 → V11 favorites migration, seed preservation, v16 round trip, preview, and legacy restore passed');
