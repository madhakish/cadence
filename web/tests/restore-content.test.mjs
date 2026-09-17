import assert from "node:assert/strict";
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";
import * as C from "../app/js/core.js";

const dom = new JSDOM('<body><main id="view"></main><div id="overlays"></div><div id="toast"></div></body>', { url: "https://cadence.invalid/app/" });
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
  Node: dom.window.Node, FileReader: dom.window.FileReader, localStorage: dom.window.localStorage });
const db = await import("../app/js/db.js");
const settings = await import("../app/js/views/settings.js");
const button = (text) => [...document.querySelectorAll("button")].find(b => b.textContent === text);
const waitFor = async (predicate) => {
  const deadline = Date.now() + 2000;
  while (!predicate() && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 10));
  assert.ok(predicate(), "UI did not finish the restore operation");
};
await db.ensureSeeded();
const id = "a0000000-0000-4000-8000-000000000001";
await db.Sessions.save({ id, date: "2025-01-01T12:00:00.000Z", isCompleted: true,
  completedAt: "2025-01-01T12:30:00.000Z", exercises: [{ exerciseName: "Back Squat",
    sets: [{ weightLb: 100, reps: 5, status: "completed", isWarmup: false }] }] });
const original = await db.exportBundle();
const corrected = structuredClone(original);
corrected.sessions[0].exercises[0].sets[0].weightLb = 95;
assert.equal(C.isNamedRestoreNoOp(await db.namedRestorePreview(corrected)), true,
  "Reproduction: the shallow preview misses a corrected weight with identical IDs and counts");

async function chooseFile(bundle) {
  document.getElementById("overlays").replaceChildren();
  document.getElementById("toast").textContent = "";
  await settings.render(document.getElementById("view"));
  button("Import JSON").click();
  const input = document.querySelector('#overlays input[type="file"]');
  const file = new window.File([JSON.stringify(bundle)], "synthetic-restore.json", { type: "application/json" });
  Object.defineProperty(input, "files", { value: [file] });
  input.dispatchEvent(new window.Event("change"));
  await waitFor(() => button("Restore") || document.getElementById("toast").textContent);
}

// Drive the file picker and confirmation, not just the lower-level importer.
await chooseFile(corrected);
assert.ok(button("Restore"), `Corrected backup was blocked: ${document.getElementById("toast").textContent}`);
assert.match(document.getElementById("overlays").textContent, /Recorded values or settings differ/);
button("Cancel").click();
assert.equal((await db.Sessions.get(id)).exercises[0].sets[0].weightLb, 100, "Cancel does not write");
assert.equal((await db.Checkpoints.all()).length, 0, "Preview does not create checkpoints");
await chooseFile(corrected);
button("Restore").click();
await waitFor(() => button("Keep it"));
assert.equal((await db.Sessions.get(id)).exercises[0].sets[0].weightLb, 95);
assert.equal((await db.Sessions.all()).length, 1, "Restore retains the session identity");
assert.equal((await db.Checkpoints.all()).length, 1, "Confirmed restore retains rollback protection");

const stored = await db.exportBundle();
assert.equal(await db.backupMatchesCurrent(stored), true);
await chooseFile(stored);
assert.match(document.getElementById("toast").textContent, /matches your current data/);
assert.equal(button("Restore"), undefined, "A truly identical backup skips restore");

// Every payload section participates, including sections absent from the
// named preview. These are synthetic comparison facts, not workout fixtures.
const sample = { schemaVersion: 14, appVersion: "test", exportedAt: "first",
  sessions: [{ exercises: [{ sets: [{ weightLb: 100, reps: 5 }] }] }],
  programs: [{ days: [{ lifts: [{ pending: { state: { estimatedMaxLb: 150 } } }] }] }],
  gyms: [{ plates: [10, 20], barcodeImageDataURL: "old" }],
  exercises: [{ notes: "old" }], tracks: [{ baseWeightLb: 100 }],
  bodyweight: [{ weightLb: 150 }], checkIns: [{ energy: 3 }],
  milestones: [{ label: "old" }], coachingDecisions: [{ explanation: "old" }],
  intervals: [{ end: "old" }], settings: { theme: "slate" } };
for (const key of Object.keys(sample).filter(k => !["schemaVersion", "appVersion", "exportedAt"].includes(k))) {
  const changed = structuredClone(sample);
  changed[key] = Array.isArray(changed[key]) ? [] : {};
  assert.equal(C.backupDataMatches(changed, sample), false, `${key} changes must not be suppressed`);
}
const changedWeight = structuredClone(sample);
changedWeight.sessions[0].exercises[0].sets[0].weightLb = 95;
assert.equal(C.backupDataMatches(changedWeight, sample), false);
const changedPending = structuredClone(sample);
changedPending.programs[0].days[0].lifts[0].pending.state.estimatedMaxLb = 140;
assert.equal(C.backupDataMatches(changedPending, sample), false);
assert.equal(C.backupDataMatches({ ...sample, appVersion: "other", exportedAt: "later" }, sample), true);
assert.equal(C.backupDataMatches({ settings: { theme: "slate" } }, sample), true, "Omitted sections are untouched");
assert.equal(C.backupDataMatches({ settings: { b: 2, a: 1 } }, { settings: { a: 1, b: 2 } }), true);
assert.equal(C.backupDataMatches({ sessions: [] }, sample), false, "An empty section is a deletion");
assert.equal(C.backupDataMatches({ schemaVersion: 14 }, sample), false);
assert.equal(C.backupDataMatches({ settings: { value: false } }, { settings: { value: 0 } }), false);
assert.equal(C.backupDataMatches({ futureSection: [] }, sample), false, "Unknown content cannot be proven equal");
await assert.rejects(db.backupMatchesCurrent({ ...stored, schemaVersion: 999 }), /newer|version|schema/i);
await chooseFile({ schemaVersion: 14, exportedAt: "2025-01-01T00:00:00Z" });
assert.equal(button("Restore"), undefined, "Metadata-only files never reach confirmation");
assert.match(document.getElementById("toast").textContent, /Not a Cadence backup/);
const intervalOnly = { schemaVersion: 14, intervals: [{ id: "a0000000-0000-4000-8000-000000000002",
  kind: "rest", startDate: "2025-01-02", endDate: "2025-01-03", enteredAsDays: true, note: "Synthetic break" }] };
assert.equal(await db.backupMatchesCurrent(intervalOnly), false);
await db.importBundle(intervalOnly, { createCheckpoint: false });
assert.equal((await db.Intervals.all()).length, 1, "Intervals-only backups restore");
assert.equal((await db.Sessions.all()).length, 1, "Partial restore preserves omitted sessions");
assert.equal(await db.backupMatchesCurrent({ schemaVersion: 14, coachingDecisions: [] }), true);
dom.window.close();
console.log("Restore content regression: full file-picker flow, exact content gate, and rollback passed.");
