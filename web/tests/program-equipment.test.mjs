import assert from "node:assert/strict";
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";
const dom = new JSDOM('<body><div id="overlays"></div><div id="toast"></div></body>', { url: "https://cadence.invalid/app/" });
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
  Node: dom.window.Node, localStorage: dom.window.localStorage });
const db = await import("../app/js/db.js");
const { programEditor } = await import("../app/js/views/settings.js");
const { applyProgramEquipmentPolicy, restrictProgramEquipment, assertProgramEquipmentAllowed } = await import("../app/js/program-equipment.js");
const { PROGRAM_TEMPLATES, createProgramFromTemplate } = await import("../app/js/templates.js");
await db.ensureSeeded();
const id = await db.Programs.save({ name: "Synthetic equipment boundary", equipmentPolicy: "any", isActive: true,
  cycleNumber: 4, currentWeek: 2, nextDayIndex: 0, focus: "strength", roundingLb: 5,
  days: [{ name: "Upper", order: 0,
    lifts: [{ exerciseName: "Single-arm DB Row", role: "main", baseWeightLb: 35, estimatedMaxLb: 45,
      revertToExerciseName: "Chest-supported Row", stallCount: 1 }],
    accessories: [{ exerciseName: "Face Pulls", sets: 3, minReps: 8, maxReps: 12, weightLb: 25, incrementLb: 5 },
      { exerciseName: "Push-ups", sets: 3, minReps: 8, maxReps: 12, weightLb: 0, incrementLb: 0 }] }] });
const program = await db.Programs.get(id);
const rowID = program.days[0].lifts[0].id;
const historyID = await db.Sessions.save({ isCompleted: true, date: "2026-01-02T12:00:00Z", programId: program.uuid,
  programName: program.name, exercises: [{ exerciseName: "Face Pulls", sets: [{ order: 0, weightLb: 25, reps: 8, status: "completed", flags: [] }] }] });
const history = await db.Sessions.get(historyID);
await programEditor(program);
const picker = [...document.querySelectorAll("select")].find((select) => [...select.options].some((option) => option.value === "freeWeightsOnly"));
assert.ok(picker, "equipment choice is available in the real program editor");
picker.value = "freeWeightsOnly";
picker.dispatchEvent(new window.Event("change"));
await new Promise((resolve) => setTimeout(resolve, 60));
const revised = await db.Programs.get(id);
assert.deepEqual(revised.days[0].accessories.map((slot) => slot.exerciseName), ["Push-ups"], "selecting the restriction removes the existing machine slot");
assert.equal(revised.days[0].lifts[0].revertToExerciseName, undefined, "rollover cannot reintroduce a machine");
assert.equal(revised.days[0].lifts[0].id, rowID);
assert.equal(revised.days[0].lifts[0].baseWeightLb, 35, "no replacement load is invented");
assert.deepEqual([revised.cycleNumber, revised.currentWeek, revised.nextDayIndex], [4, 2, 0]);
assert.deepEqual(await db.Sessions.get(historyID), history, "performed history is immutable under a preference edit");
const library = await db.Exercises.all();
assert.doesNotThrow(() => assertProgramEquipmentAllowed(revised, library));
assert.throws(() => assertProgramEquipmentAllowed({ ...program, equipmentPolicy: "freeWeightsOnly",
  days: [{ lifts: [], accessories: [{ exerciseName: "Face Pulls" }] }] }, library), /Face Pulls/);
assert.throws(() => restrictProgramEquipment({ ...program, days: [{ lifts: [{ exerciseName: "Missing definition" }] }] },
  "freeWeightsOnly", library), /library is missing/, "an unresolved identity must not be deleted as though it were a machine");

// New template blocks inherit the active restriction, including templates
// whose authored accessories contain cable work.
const template = PROGRAM_TEMPLATES.find((item) => item.days.some((day) => day.accessories.some((slot) => slot.exerciseName === "Face Pulls")));
assert.ok(template);
const newID = await createProgramFromTemplate(template);
const newProgram = await db.Programs.get(newID);
assert.equal(newProgram.equipmentPolicy, "freeWeightsOnly");
assert.doesNotThrow(() => assertProgramEquipmentAllowed(newProgram, library));

// An open workout must not lose its program composition or saved work.
const blocked = structuredClone(revised);
blocked.equipmentPolicy = "any";
blocked.days[0].accessories.push({ ...program.days[0].accessories[0], exerciseName: "Face Pulls" });
await db.Programs.save(blocked);
const openID = await db.Sessions.save({ date: "2026-01-03T12:00:00Z", isCompleted: false,
  programTag: { programId: blocked.uuid, programName: blocked.name, cycleNumber: 4, week: 2, dayIndex: 0 }, exercises: [] });
const before = await db.Programs.get(id);
await assert.rejects(() => applyProgramEquipmentPolicy(blocked, "freeWeightsOnly"), /Finish the current workout/);
assert.deepEqual(await db.Programs.get(id), before);
await db.Sessions.del(openID);
console.log("Equipment boundary applies to existing slots, cycle reverts, and preserves recorded work.");
dom.window.close();
