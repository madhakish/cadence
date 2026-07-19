// Opens a real prior-version fake IndexedDB database through the production
// V4 upgrader. Fresh-database smoke coverage cannot prove user records survive
// an onupgradeneeded transaction.
import "fake-indexeddb/auto";

const old = await new Promise((resolve, reject) => {
  const request = indexedDB.open("cadence", 3);
  request.onupgradeneeded = () => {
    const database = request.result;
    database.createObjectStore("exercises", { keyPath: "name" });
    database.createObjectStore("programs", { keyPath: "id", autoIncrement: true });
    database.createObjectStore("sessions", { keyPath: "id", autoIncrement: true });
  };
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});

await new Promise((resolve, reject) => {
  const transaction = old.transaction(["exercises", "programs", "sessions"], "readwrite");
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
        status: "completed", flags: [] }] }],
  });
  transaction.oncomplete = resolve;
  transaction.onerror = () => reject(transaction.error);
  transaction.onabort = () => reject(transaction.error || new Error("prior database transaction aborted"));
});
old.close();

const db = await import("../js/db.js");
const [exercise, program, session] = await Promise.all([
  db.Exercises.byName("Back Squat"), db.Programs.get(1), db.Sessions.get(1),
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

if (failures.length) {
  for (const failure of failures) console.error("FAIL:", failure);
  process.exit(1);
}
console.log("\n9 IndexedDB migration assertions passed, 0 failed");
