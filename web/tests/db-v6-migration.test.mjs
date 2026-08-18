// Focused V5 -> V6 IndexedDB migration for explicit programming semantics.
// This starts at the last shipped web DB version so passing through the older
// V4 normalizer cannot accidentally make the new migration look tested.
import "fake-indexeddb/auto";

const old = await new Promise((resolve, reject) => {
  const request = indexedDB.open("cadence", 5);
  request.onupgradeneeded = () => {
    request.result.createObjectStore("programs", { keyPath: "id", autoIncrement: true });
  };
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});

await new Promise((resolve, reject) => {
  const transaction = old.transaction("programs", "readwrite");
  transaction.objectStore("programs").put({
    id: 1,
    uuid: "00000000-0000-4000-8000-000000000001",
    name: "V5 Policy Fixture",
    focus: "strength",
    cycleNumber: 7,
    currentWeek: 3,
    nextDayIndex: 4,
    roundingLb: 5,
    isActive: true,
    days: [{ name: "Speed Lower", order: 4, lifts: [], accessories: [] }],
  });
  transaction.oncomplete = resolve;
  transaction.onerror = () => reject(transaction.error);
});
old.close();

const db = await import("../app/js/db.js");
const migrated = await db.Programs.get(1); // raw read proves the upgrader persisted it
const failures = [];
const check = (condition, message) => { if (!condition) failures.push(message); };

check(migrated?.equipmentPolicy === "any", "V6 did not persist the literal legacy equipment policy");
check(migrated?.days?.[0]?.trainingIntent === "general", "V6 did not persist the literal legacy day intent");
check(migrated?.cycleNumber === 7 && migrated?.currentWeek === 3 && migrated?.nextDayIndex === 4,
  "V6 changed existing cycle position");
check(migrated?.days?.[0]?.name === "Speed Lower" && migrated?.days?.[0]?.order === 4,
  "V6 changed authored day identity while adding intent");

migrated.equipmentPolicy = "freeWeightsOnly";
migrated.days[0].trainingIntent = "explosive";
await db.Programs.save(migrated);
const persisted = await db.Programs.get(1);
check(persisted?.equipmentPolicy === "freeWeightsOnly", "an explicit equipment policy did not persist");
check(persisted?.days?.[0]?.trainingIntent === "explosive", "an explicit day intent did not persist");

if (failures.length) {
  failures.forEach((failure) => console.error("FAIL:", failure));
  process.exit(1);
}
console.log("\n6 focused IndexedDB V6 migration assertions passed, 0 failed");
