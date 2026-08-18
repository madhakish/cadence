// Focused V6 -> V7 IndexedDB migration for training-context intervals.
// Starts at the last shipped web DB version so passing through the older
// upgraders cannot accidentally make the new migration look tested. V7 only
// adds the `intervals` store — existing data must survive untouched and the
// new store must be usable immediately.
import "fake-indexeddb/auto";

const old = await new Promise((resolve, reject) => {
  const request = indexedDB.open("cadence", 6);
  request.onupgradeneeded = () => {
    request.result.createObjectStore("programs", { keyPath: "id", autoIncrement: true });
    request.result.createObjectStore("sessions", { keyPath: "id", autoIncrement: true });
  };
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});

await new Promise((resolve, reject) => {
  const transaction = old.transaction(["programs", "sessions"], "readwrite");
  transaction.objectStore("programs").put({
    id: 1,
    uuid: "00000000-0000-4000-8000-000000000002",
    name: "V6 Interval Fixture",
    focus: "strength",
    equipmentPolicy: "freeWeightsOnly",
    cycleNumber: 2,
    currentWeek: 1,
    nextDayIndex: 0,
    roundingLb: 5,
    isActive: true,
    days: [{ name: "Lower", order: 0, trainingIntent: "heavy", lifts: [], accessories: [] }],
  });
  transaction.objectStore("sessions").put({
    id: 1, date: "2026-07-01T10:00:00.000Z", isCompleted: true,
    exercises: [{ order: 0, exerciseName: "Back Squat", barId: "45-lb", sets: [] }],
  });
  transaction.oncomplete = resolve;
  transaction.onerror = () => reject(transaction.error);
});
old.close();

const db = await import("../app/js/db.js");
const failures = [];
const check = (condition, message) => { if (!condition) failures.push(message); };

// The new store exists and round-trips a record through the CRUD surface.
const saved = await db.Intervals.save({
  kind: "away", startDate: "2026-07-10", endDate: "2026-07-20", note: "trip",
});
const intervals = await db.Intervals.all();
check(intervals.length === 1, "V7 did not create a usable intervals store");
check(intervals[0]?.kind === "away" && intervals[0]?.startDate === "2026-07-10"
  && intervals[0]?.endDate === "2026-07-20", "an interval did not round-trip its span");
check(/^[0-9a-f-]{36}$/.test(intervals[0]?.id || ""), "intervals must carry portable UUID ids");

// Existing V6 data is untouched by the additive upgrade.
const program = await db.Programs.get(1);
check(program?.equipmentPolicy === "freeWeightsOnly" && program?.days?.[0]?.trainingIntent === "heavy",
  "V7 changed existing program policy/intent");
const session = await db.Sessions.get(1);
check(session?.exercises?.[0]?.barId === "45-lb", "V7 changed existing session data");
check(session?.exercises?.[0]?.barIdManual !== true,
  "a pre-V10 entry must not read as a manual bar pick");

// An unknown kind normalizes to the safe default rather than persisting junk.
await db.Intervals.save({ kind: "vacation", startDate: "2026-08-01", endDate: "2026-08-02" });
const all = await db.Intervals.all();
check(all.every((interval) => db.BACKUP_ENUMS.trainingIntervalKinds.includes(interval.kind)),
  "an unknown interval kind must normalize into the closed vocabulary");

if (failures.length) {
  failures.forEach((failure) => console.error("FAIL:", failure));
  process.exit(1);
}
console.log("\n7 focused IndexedDB V7 migration assertions passed, 0 failed");
