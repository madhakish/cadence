import assert from "node:assert/strict";
import "fake-indexeddb/auto";
import { inferredPlateTheme } from "../app/js/plate-theme.js";

// A real V9 database: two gyms saved before plate themes existed.
const old = await new Promise((resolve, reject) => {
  const r = indexedDB.open("cadence", 9);
  r.onupgradeneeded = () => { r.result.createObjectStore("gyms", { keyPath: "name" }); };
  r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
});
const lbGym = {
  id: "a0000000-0000-4000-8000-0000000000a1", name: "Garage", isDefault: true,
  defaultBarId: "35-lb", collarWeightLb: 2.5, loadingPolicy: "under",
  plateToggles: [
    { value: 45, unit: "lb", enabled: true }, { value: 25, unit: "lb", enabled: true },
    { value: 2.5, unit: "lb", enabled: false },
    // Disabled kg plates don't count toward the inferred unit.
    { value: 20, unit: "kg", enabled: false },
  ],
  barcodeImage: null, barcodeLabel: "Membership tag",
};
const mixedGym = {
  id: "a0000000-0000-4000-8000-0000000000a2", name: "Club", isDefault: false,
  defaultBarId: "20-kg", collarWeightLb: 0, loadingPolicy: "closest",
  plateToggles: [{ value: 20, unit: "kg", enabled: true }, { value: 45, unit: "lb", enabled: true }],
  barcodeImage: null, barcodeLabel: "Membership tag",
};
await new Promise((resolve, reject) => {
  const tx = old.transaction(["gyms"], "readwrite");
  tx.objectStore("gyms").put(lbGym); tx.objectStore("gyms").put(mixedGym);
  tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
}); old.close();

const db = await import("../app/js/db.js");
const raw = await db.runAll(["gyms"], "readonly", (os) => new Promise((resolve, reject) => {
  const r = os("gyms").getAll(); r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
}));
const byName = new Map(raw.map((g) => [g.name, g]));
assert.equal(byName.get("Garage").plateTheme, "lbBlackIron", "the actual V9 row was upgraded, not only normalized on read");
assert.equal(byName.get("Club").plateTheme, "custom", "mixed inventory stays custom");
// Same inference native Seeder runs (PlateThemeID.inferred on enabled units).
assert.equal(inferredPlateTheme(["kg", "kg"]), "iwfCompetition");
assert.equal(inferredPlateTheme([]), "custom");
for (const [before, name] of [[lbGym, "Garage"], [mixedGym, "Club"]]) {
  const after = byName.get(name);
  for (const [k, v] of Object.entries(before)) assert.deepEqual(after[k], v, `${name}.${k} survives`);
}
const gyms = await db.Gyms.all();
assert.equal(gyms.find((g) => g.name === "Garage").plateTheme, "lbBlackIron");

// A deliberate custom choice persists and an unknown value reads as custom.
await db.Gyms.save({ ...gyms.find((g) => g.name === "Garage"), plateTheme: "custom" });
assert.equal((await db.Gyms.all()).find((g) => g.name === "Garage").plateTheme, "custom");
await db.Gyms.save({ ...gyms.find((g) => g.name === "Club"), plateTheme: "nonsense" });
assert.equal((await db.Gyms.all()).find((g) => g.name === "Club").plateTheme, "custom");

// Backup contract: v15 requires a known theme; v14 bundles may omit it.
const gymFor = (extra) => ({ id: lbGym.id, name: "Garage", plateToggles: [], ...extra });
assert.doesNotThrow(() => db.validateBackup({ schemaVersion: 14, gyms: [gymFor({})] }));
assert.throws(() => db.validateBackup({ schemaVersion: 15, gyms: [gymFor({})] }), /plateTheme/);
assert.throws(() => db.validateBackup({ schemaVersion: 15, gyms: [gymFor({ plateTheme: "chrome" })] }), /plateTheme/);
assert.doesNotThrow(() => db.validateBackup({ schemaVersion: 15, gyms: [gymFor({ plateTheme: "ipfCalibrated" })] }));
console.log("V9 → V10 migration infers plate themes from inventory without touching any gym field");
