// Focused V7 -> V8 IndexedDB migration for stable portable identity
// (epic #155 Stage 2). Starts at the last shipped web DB version so passing
// through older upgraders cannot make the new migration look tested. V8 adds
// no store and keeps every key path: it backfills deterministic legacy ids
// (exercises, program slots, session entries, tracks, milestones), adds the
// unique `byId` index on exercises, and must leave user data untouched.
import "fake-indexeddb/auto";
import * as C from "../app/js/core.js";

const old = await new Promise((resolve, reject) => {
  const request = indexedDB.open("cadence", 7);
  request.onupgradeneeded = () => {
    for (const [name, options] of [
      ["exercises", { keyPath: "name" }],
      ["tracks", { keyPath: "exerciseName" }],
      ["milestones", { keyPath: "id", autoIncrement: true }],
      ["programs", { keyPath: "id", autoIncrement: true }],
      ["sessions", { keyPath: "id", autoIncrement: true }],
    ]) request.result.createObjectStore(name, options);
  };
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});

await new Promise((resolve, reject) => {
  const transaction = old.transaction(["exercises", "tracks", "milestones", "programs", "sessions"], "readwrite");
  transaction.objectStore("exercises").put({
    name: "Legacy Row", category: "Main", type: "barbell", movementGroup: "hinge",
    notes: "user notes survive", defaultRestSeconds: 180,
  });
  // A row that already carries a portable id (user-created post-v11 shape)
  // must keep it verbatim.
  transaction.objectStore("exercises").put({
    name: "Custom Kept", category: "Accessory", type: "dumbbell",
    id: "12345678-1234-4123-a123-123456789abc",
  });
  transaction.objectStore("tracks").put({ exerciseName: "Legacy Row", mode: "cycle", cycleNumber: 3, baseWeightLb: 185 });
  transaction.objectStore("milestones").put({ id: 7, date: "2026-07-01T10:00:00.000Z", exerciseName: "Legacy Row", kind: "heaviestSet", label: "185 lb×5" });
  transaction.objectStore("programs").put({
    id: 1, uuid: "00000000-0000-4000-8000-000000000002", name: "V7 Identity Fixture",
    focus: "strength", cycleNumber: 2, currentWeek: 1, nextDayIndex: 0, roundingLb: 5, isActive: true,
    days: [{ name: "Pull", order: 0, lifts: [
      { id: "00000000-0000-4000-8000-00000000000a", exerciseName: "Legacy Row", role: "main", order: 0, baseWeightLb: 185, estimatedMaxLb: 220 },
    ], accessories: [] }],
  });
  transaction.objectStore("sessions").put({
    id: 1, date: "2026-07-01T10:00:00.000Z", isCompleted: true,
    exercises: [{ order: 0, exerciseName: "Legacy Row", sets: [{ order: 0, weightLb: 185, reps: 5, status: "completed" }] }],
  });
  transaction.oncomplete = resolve;
  transaction.onerror = () => reject(transaction.error);
});
old.close();

const db = await import("../app/js/db.js");
const failures = [];
let checks = 0;
const check = (condition, message) => { checks += 1; if (!condition) failures.push(message); };

const legacyID = C.exerciseLegacyID("Legacy Row");
const legacy = await db.Exercises.byName("Legacy Row");
check(legacy?.id === legacyID, "legacy exercise gains the deterministic derived id");
check(legacy?.notes === "user notes survive" && legacy?.defaultRestSeconds === 180,
  "user fields survive the id backfill untouched");
const kept = await db.Exercises.byName("Custom Kept");
check(kept?.id === "12345678-1234-4123-a123-123456789abc", "an existing portable id is kept verbatim");

const program = (await db.Programs.all()).find((p) => p.name === "V7 Identity Fixture");
check(program?.days[0].lifts[0].exerciseId === legacyID, "program lift references gain the derived exercise id");
check(program?.days[0].lifts[0].id === "00000000-0000-4000-8000-00000000000a", "existing slot ids stay untouched");
check(program?.templateId == null, "a legacy program's template origin stays unknown — never guessed");

const session = await db.Sessions.get(1);
check(session?.exercises[0].exerciseId === legacyID, "session entries gain the derived exercise id");
check(session?.exercises[0].sets[0].weightLb === 185, "banked sets survive untouched");

const track = (await db.Tracks.all()).find((t) => t.exerciseName === "Legacy Row");
check(track?.exerciseId === legacyID && track?.baseWeightLb === 185, "tracks gain the id, keep their state");
const milestone = (await db.Milestones.all()).find((m) => m.id === 7);
check(milestone?.exerciseId === legacyID && milestone?.label === "185 lb×5", "milestones gain the id, keep their label");

// The byId index exists, is unique, and resolves an exercise.
const viaIndex = await new Promise((resolve, reject) => {
  const request = indexedDB.open("cadence");
  request.onsuccess = () => {
    const database = request.result;
    const transaction = database.transaction("exercises");
    const index = transaction.objectStore("exercises").index("byId");
    check(index.unique === true, "byId index is unique");
    const get = index.get(legacyID);
    get.onsuccess = () => { database.close(); resolve(get.result); };
    get.onerror = () => { database.close(); reject(get.error); };
  };
  request.onerror = () => reject(request.error);
});
check(viaIndex?.name === "Legacy Row", "byId index resolves the exercise by portable id");

// Idempotence: re-running the normalizers changes nothing.
await db.Exercises.save(legacy);
check((await db.Exercises.byName("Legacy Row"))?.id === legacyID, "re-normalizing keeps the same derived id");

if (failures.length) { for (const f of failures) console.error("FAIL:", f); }
console.log(`${checks - failures.length} focused IndexedDB V8 migration assertions passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
