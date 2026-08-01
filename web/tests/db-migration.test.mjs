// Opens a real prior-version fake IndexedDB database through the production
// V4 and V5 upgraders. Fresh-database smoke coverage cannot prove user records
// survive an onupgradeneeded transaction.
//
// The prior database carries a `protein` store and a `proteinTargetGrams`
// setting, because every real pre-V5 install did. V5 drops both, and the point
// of this test is that dropping them takes nothing else with it.
import "fake-indexeddb/auto";

const old = await new Promise((resolve, reject) => {
  const request = indexedDB.open("cadence", 3);
  request.onupgradeneeded = () => {
    const database = request.result;
    database.createObjectStore("exercises", { keyPath: "name" });
    database.createObjectStore("programs", { keyPath: "id", autoIncrement: true });
    database.createObjectStore("sessions", { keyPath: "id", autoIncrement: true });
    database.createObjectStore("protein", { keyPath: "id", autoIncrement: true });
    database.createObjectStore("bodyweight", { keyPath: "id", autoIncrement: true });
    database.createObjectStore("settings", { keyPath: "id" });
  };
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});

await new Promise((resolve, reject) => {
  const transaction = old.transaction(
    ["exercises", "programs", "sessions", "protein", "bodyweight", "settings"], "readwrite"
  );
  transaction.objectStore("protein").put({ id: 1, date: "2025-01-01T12:00:00.000Z", grams: 45, label: "Retired" });
  transaction.objectStore("bodyweight").put({ id: 1, date: "2025-01-01T12:00:00.000Z", weightLb: 201 });
  transaction.objectStore("settings").put({
    id: "app", unitDisplay: "lbPrimary", theme: "carbon", proteinTargetGrams: 145,
    accessoryRestSeconds: 75, autoStartRest: true, seededAt: "2025-01-01T12:00:00.000Z",
  });
  transaction.objectStore("exercises").put({
    name: "Back Squat", category: "Main", type: "barbell",
    movementGroup: "squat", isShelved: false,
  });
  transaction.objectStore("programs").put({
    id: 1, uuid: "00000000-0000-4000-8000-000000000001", name: "Migration Program",
    focus: "strength", cycleNumber: 2, currentWeek: 3, nextDayIndex: 0,
    roundingLb: 5, isActive: true,
    days: [{ name: "Lower", order: 0,
      lifts: [{ id: "00000000-0000-4000-8000-000000000002", exerciseName: "Back Squat",
        role: "main", order: 0, baseWeightLb: 175, estimatedMaxLb: 220 }],
      accessories: [{ id: "00000000-0000-4000-8000-000000000003", exerciseName: "Seated Leg Curl",
        order: 0, sets: 3, minReps: 8, maxReps: 12, currentReps: 8,
        weightLb: 50, incrementLb: 5 }] }],
  });
  transaction.objectStore("sessions").put({
    id: 1, date: "2025-01-01T12:00:00.000Z", notes: "prior-version record", isCompleted: true,
    exercises: [{ exerciseName: "Back Squat", plannedWeightLb: 195, plannedSets: 3,
      plannedReps: 5, sets: [{ order: 0, weightLb: 185, reps: 5, isWarmup: false,
        status: "completed", flags: [] }] },
      // A climb logged the only way a pre-flights install could log one. Set
      // documents are embedded in the session, so this is the record shape the
      // new optional field lands on.
      { exerciseName: "Stair Climber", sets: [{ order: 0, weightLb: 0, reps: 1,
        isWarmup: false, status: "completed", flags: [],
        durationSeconds: 1200, distanceMiles: 0.75 }] }],
  });
  transaction.oncomplete = resolve;
  transaction.onerror = () => reject(transaction.error);
  transaction.onabort = () => reject(transaction.error || new Error("prior database transaction aborted"));
});
old.close();

const db = await import("../app/js/db.js");
const C = await import("../app/js/core.js");
const [exercise, program, session, weights, settings] = await Promise.all([
  db.Exercises.byName("Back Squat"), db.Programs.get(1), db.Sessions.get(1),
  db.Bodyweight.all(), db.Settings.get(),
]);

const failures = [];
const check = (condition, message) => { if (!condition) failures.push(message); };
check(exercise?.movementPattern === "squat", "exercise taxonomy default was not migrated");
check(exercise?.gateStatus === "open", "exercise gate default was not migrated");
check(program?.coachEnabled === true, "program coaching default was not migrated");
check(program?.days?.[0]?.lifts?.[0]?.phasePrimerEnabled === true, "lift defaults were not migrated");
check(program?.days?.[0]?.accessories?.[0]?.maximumSets === 6, "accessory defaults were not migrated");
check(session?.exercises?.[0]?.sets?.[0]?.weightLb === 185, "performed weight changed during migration");
check(session?.exercises?.[0]?.plannedWeightLb === 195, "exercise plan did not survive migration");
check(session?.exercises?.[0]?.sets?.[0]?.plannedWeightLb === null,
  "historical set received a fabricated current plan");
check(session?.exercises?.[0]?.sets?.[0]?.prescriptionBlock === "work",
  "historical working set block default was not migrated");

// [INV-STAIRS-COUNT-FLIGHTS] `flights` is a new OPTIONAL field on embedded set
// documents, so there is nothing to transform and no upgrader adds it — the
// same treatment `inclinePercent` already gets. What has to hold is that a
// session document written before the field existed still reads back whole,
// with the count absent rather than zero, and renders the distance it holds.
const climb = session?.exercises?.find((e) => e.exerciseName === "Stair Climber")?.sets?.[0];
check(climb?.distanceMiles === 0.75, "a pre-flights climb lost the distance it was logged with");
check(climb?.durationSeconds === 1200, "a pre-flights climb lost its duration");
check(climb?.flights === undefined, "an upgraded set was given a flight count it never had");
check(C.cardioSetLabel(climb?.distanceMiles, climb?.durationSeconds, climb?.inclinePercent,
  climb?.weightLb, climb?.flights) === "0.75 mi · 20:00 · 2.3 mph",
  "a pre-flights climb no longer renders what it holds");

// V5 retires protein logging. The store goes; nothing else does.
const database = await new Promise((resolve, reject) => {
  const request = indexedDB.open("cadence");
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});
check(!database.objectStoreNames.contains("protein"), "the protein store was not dropped by V5");
check(database.objectStoreNames.contains("bodyweight"), "V5 dropped a store it had no business touching");
database.close();

check(weights.length === 1 && weights[0].weightLb === 201,
  "a weigh-in did not survive the store deletion alongside it");
check(settings.proteinTargetGrams === undefined,
  "the retired protein target is still being read back into settings");
check(settings.birthYear === 0,
  "an upgraded store did not get the birth-year default");
check(settings.accessoryRestSeconds === 75 && settings.autoStartRest === true,
  "unrelated settings changed during the V5 upgrade");

if (failures.length) {
  for (const failure of failures) console.error("FAIL:", failure);
  process.exit(1);
}
console.log(`\n${19 - failures.length} IndexedDB migration assertions passed, ${failures.length} failed`);
