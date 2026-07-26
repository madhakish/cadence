// Program-file export/import contract, under fake-indexeddb.
// Run: node tests/program-file.test.mjs
//
// The failure modes come first on purpose. A program import must never be able
// to damage another data domain, and a file that cannot be fully resolved must
// leave the store exactly as it found it — those are the properties worth
// proving before any happy path.
import "fake-indexeddb/auto";

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.error("FAIL:", m); } };
const threw = async (fn) => { try { await fn(); return null; } catch (error) { return error; } };

const db = await import("../app/js/db.js");
const pf = await import("../app/js/program-file.js");

await db.ensureSeeded();

// Seeding creates the library, not a program. An in-progress active program is
// what an import must never disturb, so stand one up explicitly.
await db.Programs.save({
  name: "Fixture Active", focus: "strength", cycleNumber: 2, currentWeek: 3,
  nextDayIndex: 0, roundingLb: 5, isActive: true,
  days: [{
    name: "Existing day", order: 0,
    lifts: [{ exerciseName: "Back Squat", role: "main", baseWeightLb: 185, estimatedMaxLb: 215 }],
    accessories: [],
  }],
});

// A minimal, valid program file built from the seeded library.
const validFile = () => ({
  kind: "cadence.program",
  programSchemaVersion: 1,
  program: {
    name: "Fixture Push/Pull",
    focus: "strength",
    roundingLb: 5,
    coachEnabled: true,
    preferredSessionSpacingDays: 3,
    maximumAddedSetsPerRotation: 6,
    days: [{
      name: "Day A",
      order: 0,
      lifts: [{
        exerciseName: "Back Squat", role: "main", order: 0,
        prescription: "automatic", warmupPolicy: "automatic",
        loadOffsetLb: 0, peakOffsetLb: 0, deloadMultiplier: 0.775,
        doubleProgressionSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 5,
        peakSingleEnabled: false, peakSingleIncrementLb: 5, phasePrimerEnabled: true,
        dropIncrementLb: 0, capacityManaged: true, maximumSets: 6,
        baseWeightLb: 135, estimatedMaxLb: 185,
      }],
      accessories: [{
        exerciseName: "Plank", order: 0, sets: 3, minReps: 8, maxReps: 12, currentReps: 8,
        targetSeconds: 30, durationStepSeconds: 5, capacityManaged: true, maximumSets: 6,
        conditioningEffort: "easy", targetRPE: 0, weightLb: 0, incrementLb: 0,
      }],
    }],
  },
});

// Snapshot of every domain a program import must never touch.
const otherDomains = async () => ({
  sessions: (await db.Sessions.all()).length,
  bodyweight: (await db.Bodyweight.all()).length,
  protein: (await db.Protein.all()).length,
  milestones: (await db.Milestones.all()).length,
  checkIns: (await db.Checkins.all()).length,
  gyms: (await db.Gyms.all()).length,
  exercises: (await db.Exercises.all()).length,
});

// ---------------------------------------------------------------------------
// Test 2 — an unresolved exercise name changes nothing and names the exercise
// ---------------------------------------------------------------------------
{
  const before = await otherDomains();
  const programsBefore = (await db.Programs.all()).length;

  const file = validFile();
  file.program.days[0].lifts[0].exerciseName = "Zercher Good Morning";
  const error = await threw(() => pf.importProgramFile(file));

  ok(error != null, "an unknown exercise name rejects the import");
  ok(/Zercher Good Morning/.test(error?.message || ""),
    `the error names the unresolved exercise (got: ${error?.message})`);
  ok(/Nothing was changed/.test(error?.message || ""),
    "the error states that nothing was changed");
  ok((await db.Programs.all()).length === programsBefore,
    "no program was created by the rejected import");
  const after = await otherDomains();
  ok(JSON.stringify(after) === JSON.stringify(before),
    `no other domain changed (${JSON.stringify(before)} -> ${JSON.stringify(after)})`);
}

// An alias resolves where the canonical name is absent.
{
  await db.Exercises.save({
    name: "Chest-supported Row", category: "Accessory", type: "machine", group: "pull",
    aliases: ["Seal Row", "Chest Supported Machine Row"], createdAt: new Date().toISOString(),
  });
  const file = validFile();
  file.program.name = "Fixture Alias Resolve";
  file.program.days[0].lifts[0].exerciseName = "Seal Row";
  const report = await pf.importProgramFile(file);
  ok(report.action === "created", "a slot naming a known alias imports");
  const created = (await db.Programs.all()).find((p) => p.uuid === report.programId);
  ok(created?.days[0].lifts[0].exerciseName === "Chest-supported Row",
    "the alias is rewritten to the canonical library name");
  await db.Programs.del(report.programId);
}

// ---------------------------------------------------------------------------
// Test 3 — a truncated or corrupt file changes nothing
// ---------------------------------------------------------------------------
{
  const before = await otherDomains();
  const programsBefore = (await db.Programs.all()).length;

  const corrupt = [
    ["truncated JSON text", '{"kind":"cadence.program","programSchemaVersion":1,"program":{"name":"Half'],
    ["not an object", "[]"],
    ["wrong kind", JSON.stringify({ kind: "cadence.backup", programSchemaVersion: 1, program: {} })],
    ["missing kind", JSON.stringify({ programSchemaVersion: 1, program: validFile().program })],
    ["future version", JSON.stringify({ ...validFile(), programSchemaVersion: 99 })],
    ["missing program", JSON.stringify({ kind: "cadence.program", programSchemaVersion: 1 })],
    ["blank program name", JSON.stringify((() => { const f = validFile(); f.program.name = "   "; return f; })())],
    ["no days", JSON.stringify((() => { const f = validFile(); f.program.days = []; return f; })())],
    ["unknown focus", JSON.stringify((() => { const f = validFile(); f.program.focus = "powerbuilding"; return f; })())],
    ["unknown role", JSON.stringify((() => { const f = validFile(); f.program.days[0].lifts[0].role = "tertiary"; return f; })())],
    ["duplicate day order", JSON.stringify((() => {
      const f = validFile(); f.program.days.push({ ...f.program.days[0], name: "Day B" }); return f;
    })())],
    ["non-finite weight", JSON.stringify((() => {
      const f = validFile(); f.program.days[0].lifts[0].baseWeightLb = "heavy"; return f;
    })())],
    ["reps out of range", JSON.stringify((() => {
      const f = validFile(); f.program.days[0].accessories[0].maxReps = 9999; return f;
    })())],
    // nextDayIndex is a day ORDER. A pointer naming no day silently falls back
    // to the first day, losing the wave position the file was carrying.
    ["nextDayIndex naming no day", JSON.stringify((() => {
      const f = validFile();
      f.program.cycleNumber = 1; f.program.currentWeek = 1; f.program.nextDayIndex = 7;
      return f;
    })())],
    // Lift progression state is a group on both clients; a partial set would
    // import natively and be rejected on the web.
    ["partial lift progression state", JSON.stringify((() => {
      const f = validFile(); f.program.days[0].lifts[0].stallCount = 1; return f;
    })())],
    // A stashed peak grade is applied verbatim at rollover, so an unchecked
    // value here crashes or poisons the training max weeks later, mid-session.
    ...[
      ["garbage pending", "totally bogus"],
      ["pending missing its state", { note: "x" }],
      ["pending with an incomplete state", { state: { baseWeightLb: 140 } }],
      ["pending with a negative base", {
        state: { baseWeightLb: -500, estimatedMaxLb: 200, stallCount: 0, lastIncrementLb: 5 },
      }],
      ["pending with an absurd max", {
        state: { baseWeightLb: 140, estimatedMaxLb: 99999, stallCount: 0, lastIncrementLb: 5 },
      }],
      ["pending with a negative stall count", {
        state: { baseWeightLb: 140, estimatedMaxLb: 200, stallCount: -3, lastIncrementLb: 5 },
      }],
    ].map(([label, pending]) => [label, JSON.stringify((() => {
      const f = validFile();
      f.program.cycleNumber = 1; f.program.currentWeek = 1; f.program.nextDayIndex = 0;
      Object.assign(f.program.days[0].lifts[0], {
        stallCount: 0, lastIncrementLb: 0, lastPeakSingleLb: 0, pending,
      });
      return f;
    })())]),
    // Runtime state is one decision for the whole file. Slot counters without
    // a program wave position were being accepted and then silently zeroed.
    ["slot state without program wave position", JSON.stringify((() => {
      const f = validFile();
      Object.assign(f.program.days[0].lifts[0], { stallCount: 3, lastIncrementLb: 5, lastPeakSingleLb: 225 });
      return f;
    })())],
  ];

  for (const [label, text] of corrupt) {
    const error = await threw(() => pf.importProgramText(text));
    ok(error != null, `rejected before any write: ${label}`);
  }

  ok((await db.Programs.all()).length === programsBefore,
    "no program was created by any corrupt file");
  const after = await otherDomains();
  ok(JSON.stringify(after) === JSON.stringify(before),
    `no other domain changed across every corrupt file (${JSON.stringify(before)} -> ${JSON.stringify(after)})`);
}

// ---------------------------------------------------------------------------
// Test 4 — importing while real history exists leaves that history alone
// ---------------------------------------------------------------------------
{
  await db.Bodyweight.add({ date: "2026-07-01T12:00:00.000Z", weightLb: 201 });
  await db.Bodyweight.add({ date: "2026-07-08T12:00:00.000Z", weightLb: 199 });
  await db.Protein.add({ date: "2026-07-01T12:00:00.000Z", grams: 180 });
  await db.Milestones.add({
    date: "2026-07-01T12:00:00.000Z", exerciseName: "Back Squat", kind: "weight", label: "Fixture PR",
  });
  await db.Sessions.save({
    date: "2026-07-01T12:00:00.000Z", isCompleted: true, name: "Fixture session",
    exercises: [{ exerciseName: "Back Squat", sets: [{ weightLb: 185, reps: 5, status: "completed" }] }],
  });

  const before = await otherDomains();
  ok(before.sessions > 0 && before.bodyweight > 0 && before.milestones > 0,
    "the fixture history is actually present before the import");

  const file = validFile();
  file.program.name = "Fixture Alongside History";
  const report = await pf.importProgramFile(file);
  ok(report.action === "created", "the program imported while history existed");

  const after = await otherDomains();
  ok(after.sessions === before.sessions, `session count unchanged (${before.sessions} -> ${after.sessions})`);
  ok(after.bodyweight === before.bodyweight, `bodyweight entries unchanged (${before.bodyweight} -> ${after.bodyweight})`);
  ok(after.milestones === before.milestones, `milestone count unchanged (${before.milestones} -> ${after.milestones})`);
  ok(after.protein === before.protein, "protein entries unchanged");
  ok(after.checkIns === before.checkIns, "check-ins unchanged");
  ok(after.gyms === before.gyms, "gyms unchanged");
  ok(after.exercises === before.exercises, "the exercise library was not added to by a fully-resolvable file");

  const session = (await db.Sessions.all())[0];
  ok(session?.exercises?.[0]?.sets?.[0]?.weightLb === 185, "the logged set survived untouched");
}

// ---------------------------------------------------------------------------
// Never silently overwrite: a name collision creates a distinct program,
// and an import never steals the active flag.
// ---------------------------------------------------------------------------
{
  const active = (await db.Programs.all()).find((p) => p.isActive);
  ok(active != null, "an active program exists before the collision import");

  const file = validFile();
  file.program.name = active.name;
  const report = await pf.importProgramFile(file);

  ok(report.action === "created", "a colliding name still creates rather than overwrites");
  ok(report.name !== active.name, `the created program took a distinct name (${report.name})`);
  const reloaded = (await db.Programs.all()).find((p) => p.uuid === active.uuid);
  ok(reloaded?.isActive === true, "the previously active program is still active");
  ok(reloaded?.days.length === active.days.length, "the previously active program was not modified");
  const imported = (await db.Programs.all()).find((p) => p.uuid === report.programId);
  ok(imported?.isActive === false, "the imported program did not activate itself");
}

// ---------------------------------------------------------------------------
// Test 1 — byte-identical round trip
// ---------------------------------------------------------------------------
{
  const source = (await db.Programs.all()).find((p) => p.name === "Fixture Alongside History");
  ok(source != null, "the round-trip source program exists");

  // A true round trip imports into a store that does not already hold the
  // program. Leaving the source in place would trip the collision rename —
  // correct behaviour, but not what this test is measuring.
  const first = pf.exportProgramText(source);
  await db.Programs.del(source.id);
  const report = await pf.importProgramText(first);
  const second = pf.exportProgramText((await db.Programs.all()).find((p) => p.uuid === report.programId));
  ok(first === second, "export -> import -> export is byte-identical");
  ok(!/"id"/.test(first), "the default file carries no slot or program identity");
  ok(!/exportedAt|generatedAt/.test(first), "the default file carries no timestamp");
  ok(pf.programFilename({ name: "日本語" }) === "cadence-program-日本語.json",
    `a non-ASCII name keeps its letters (got: ${pf.programFilename({ name: "日本語" })})`);
  ok(pf.programFilename({ name: "!!!" }) === "cadence-program-program.json",
    `a name that slugs away falls back (got: ${pf.programFilename({ name: "!!!" })})`);
  ok(!/stallCount|lastIncrementLb|pending|cycleNumber|currentWeek|nextDayIndex/.test(first),
    "the default file carries no runtime progression state");
  ok(!/isActive/.test(first), "the default file does not carry the active flag");

  // Stable key ordering: the same program serialized twice is identical, and
  // key order does not depend on the store's insertion order.
  const shuffled = JSON.parse(JSON.stringify(source));
  shuffled.days[0].lifts[0] = Object.fromEntries(Object.entries(shuffled.days[0].lifts[0]).reverse());
  ok(pf.exportProgramText(shuffled) === first, "key ordering is stable regardless of source field order");
}

// ---------------------------------------------------------------------------
// State and identity are opt-in
// ---------------------------------------------------------------------------
{
  const source = (await db.Programs.all()).find((p) => p.name === "Fixture Alongside History");
  source.days[0].lifts[0].stallCount = 2;
  source.days[0].lifts[0].lastIncrementLb = 5;
  source.days[0].lifts[0].lastPeakSingleLb = 0;
  source.days[0].lifts[0].pending = {
    state: { baseWeightLb: 140, estimatedMaxLb: 190, stallCount: 0, lastIncrementLb: 5 },
    note: "Clean peak",
  };
  source.cycleNumber = 4;
  source.currentWeek = 3;
  await db.Programs.save(source);
  const saved = (await db.Programs.all()).find((p) => p.uuid === source.uuid);

  const stripped = pf.exportProgramText(saved);
  ok(!/stallCount/.test(stripped), "stall counters stay out of the default file");

  const withState = pf.exportProgramText(saved, { includeState: true });
  ok(/"stallCount": 2/.test(withState), "the state file carries the stall counter");
  ok(/"cycleNumber": 4/.test(withState), "the state file carries the cycle number");
  ok(/"pending"/.test(withState), "the state file carries the pending peak grade");

  await db.Programs.del(saved.id);
  const stateReport = await pf.importProgramText(withState);
  const restored = (await db.Programs.all()).find((p) => p.uuid === stateReport.programId);
  ok(restored.days[0].lifts[0].stallCount === 2, "runtime state survives a state round trip");
  ok(restored.cycleNumber === 4, "the cycle number survives a state round trip");
  ok(pf.exportProgramText(restored, { includeState: true }) === withState,
    "the state file also round-trips byte-identically");

  const plain = await pf.importProgramText(stripped);
  const fresh = (await db.Programs.all()).find((p) => p.uuid === plain.programId);
  ok(fresh.days[0].lifts[0].stallCount === 0, "a plan-only file imports with cleared state");
  ok(fresh.cycleNumber === 1 && fresh.currentWeek === 1, "a plan-only file starts at cycle 1 week 1");

  const withIdentity = pf.exportProgramText(saved, { includeIdentity: true });
  ok(withIdentity.includes(saved.uuid), "the identity file carries the program id");
  ok(withIdentity.includes(saved.days[0].lifts[0].id), "the identity file carries slot ids");

  const idReport = await pf.importProgramText(withIdentity, { preserveIdentity: true });
  ok(idReport.action === "updated", "an identity import with a known id updates in place");
  ok(idReport.programId === saved.uuid, "update-in-place kept the program id");
  const updated = (await db.Programs.all()).find((p) => p.uuid === saved.uuid);
  ok(updated.days[0].lifts[0].id === saved.days[0].lifts[0].id, "slot ids were preserved");
  ok((await db.Programs.all()).filter((p) => p.uuid === saved.uuid).length === 1, "no duplicate program was created");

  // Without the flag, the same file is additive.
  const copy = await pf.importProgramText(withIdentity);
  ok(copy.action === "created", "identity is ignored unless preserveIdentity is requested");
  ok(copy.programId !== saved.uuid, "the additive import minted a new program id");
  const copied = (await db.Programs.all()).find((p) => p.uuid === copy.programId);
  ok(copied.days[0].lifts[0].id !== saved.days[0].lifts[0].id, "the additive import minted new slot ids");
}

// ---------------------------------------------------------------------------
// Cycle-scoped swap markers are resolved like any other name. Rollover writes
// revertToExerciseName straight onto the slot, so an unresolvable marker would
// leave the slot bound to nothing weeks after the import looked fine.
// ---------------------------------------------------------------------------
{
  const before = await otherDomains();
  const programsBefore = (await db.Programs.all()).length;

  const file = validFile();
  file.program.name = "Fixture Bad Revert";
  file.program.cycleNumber = 1;
  file.program.currentWeek = 1;
  file.program.nextDayIndex = 0;
  file.program.days[0].lifts[0].stallCount = 0;
  file.program.days[0].lifts[0].lastIncrementLb = 0;
  file.program.days[0].lifts[0].lastPeakSingleLb = 0;
  file.program.days[0].lifts[0].revertToExerciseName = "Zercher Good Morning";

  const error = await threw(() => pf.importProgramFile(file));
  ok(error != null, "an unresolvable revert marker rejects the import");
  ok(/Zercher Good Morning/.test(error?.message || ""),
    `the error names the unresolved revert marker (got: ${error?.message})`);
  ok((await db.Programs.all()).length === programsBefore, "nothing was created");
  ok(JSON.stringify(await otherDomains()) === JSON.stringify(before), "no other domain changed");

  // And a revert marker given as an alias is rewritten to the canonical name.
  file.program.name = "Fixture Alias Revert";
  file.program.days[0].lifts[0].revertToExerciseName = "Seal Row";
  const report = await pf.importProgramFile(file);
  const imported = (await db.Programs.all()).find((p) => p.uuid === report.programId);
  ok(imported.days[0].lifts[0].revertToExerciseName === "Chest-supported Row",
    `the revert marker is stored canonically (got: ${imported.days[0].lifts[0].revertToExerciseName})`);
}

// ---------------------------------------------------------------------------
// Gated exercises: the program imports, and says what is shut
// ---------------------------------------------------------------------------
{
  const squat = await db.Exercises.byName("Back Squat");
  await db.Exercises.save({ ...squat, gateStatus: "shelved", isShelved: true });
  const file = validFile();
  file.program.name = "Fixture Gated";
  const report = await pf.importProgramFile(file);
  ok(report.action === "created", "a program referencing a gated exercise still imports");
  ok(report.warnings.some((w) => /Back Squat/.test(w)), `the report warns about the gated exercise (${report.warnings})`);
  ok(!/gateStatus|reEntry/.test(pf.exportProgramText(file.program)),
    "gate state is never written into a program file");
  const stillShelved = await db.Exercises.byName("Back Squat");
  ok(stillShelved.isShelved === true, "importing did not clear the library's gate state");
}

// ---------------------------------------------------------------------------
// Update-in-place must not drop fields the format doesn't carry. A program
// record holds more than a program file does — reliableHistoryStart is the
// lifter's own "first trustworthy date" choice — and the store is written with
// a whole-record put, so rebuilding from a literal would erase them silently.
// ---------------------------------------------------------------------------
{
  const id = await db.Programs.save({
    name: "Fixture Update In Place", focus: "strength", cycleNumber: 1, currentWeek: 1,
    nextDayIndex: 0, roundingLb: 5, isActive: false,
    reliableHistoryStart: "2025-01-01T00:00:00.000Z",
    days: [{
      name: "A", order: 0,
      lifts: [{ exerciseName: "Back Squat", role: "main", baseWeightLb: 135, estimatedMaxLb: 185 }],
      accessories: [],
    }],
  });
  const before = (await db.Programs.all()).find((p) => p.id === id);
  const text = pf.exportProgramText(before, { includeIdentity: true });
  ok(!/reliableHistoryStart/.test(text), "the format does not carry reliableHistoryStart");

  const edited = JSON.parse(text);
  edited.program.name = "Fixture Update In Place RENAMED";
  const report = await pf.importProgramFile(edited, { preserveIdentity: true });
  ok(report.action === "updated", "the program was updated, not copied");

  const after = (await db.Programs.all()).find((p) => p.uuid === before.uuid);
  ok(after.reliableHistoryStart === "2025-01-01T00:00:00.000Z",
    `a field the format does not carry survived the update (got: ${after.reliableHistoryStart})`);
  ok(after.name === "Fixture Update In Place RENAMED",
    `a rename in the file is honoured (got: ${after.name})`);
  ok((await db.Programs.all()).filter((p) => p.uuid === before.uuid).length === 1,
    "update-in-place did not duplicate the program");

  // A rename that collides is still made unique — Program.name is a unique
  // attribute natively, so a fixed name would upsert into another program.
  await db.Programs.save({
    name: "Fixture Occupied", focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0,
    roundingLb: 5, isActive: false,
    days: [{ name: "A", order: 0, lifts: [{ exerciseName: "Back Squat", role: "main", baseWeightLb: 135, estimatedMaxLb: 185 }], accessories: [] }],
  });
  const collide = JSON.parse(text);
  collide.program.name = "Fixture Occupied";
  const collided = await pf.importProgramFile(collide, { preserveIdentity: true });
  ok(collided.name !== "Fixture Occupied",
    `an update renaming onto a taken name is made unique (got: ${collided.name})`);
}

// ---------------------------------------------------------------------------
// Shared fixture — the same file Swift's ProgramFileContractTests decodes and
// re-encodes. Either mirror drifting fails its own CI job.
// ---------------------------------------------------------------------------
{
  const { readFileSync } = await import("node:fs");
  const fixturePath = new URL("./fixtures/program-file.json", import.meta.url);
  const onDisk = readFileSync(fixturePath, "utf8");
  const fixture = JSON.parse(onDisk);

  ok(fixture.kind === pf.PROGRAM_FILE_KIND, "the fixture carries the program-file discriminator");
  ok(fixture.programSchemaVersion === pf.PROGRAM_SCHEMA_VERSION,
    "the fixture is at the current program schema version");
  ok(await threw(() => pf.validateProgramFile(fixture)) === null, "the fixture validates");

  // Re-export the fixture's own program through the production writer: what
  // the generator wrote must be what the exporter still produces.
  const reexported = `${pf.exportProgramText(
    { ...fixture.program, uuid: fixture.program.id },
    { includeState: true, includeIdentity: true },
  )}\n`;
  ok(reexported === onDisk,
    "the exporter still produces the committed fixture byte-for-byte (regenerate with tools/generate-program-file-fixture.mjs)");

  // The fixture is deliberately the widest shape the contract allows.
  const lifts = fixture.program.days.flatMap((d) => d.lifts);
  const accessories = fixture.program.days.flatMap((d) => d.accessories);
  ok(lifts.some((l) => l.pending), "the fixture exercises a stashed peak grade");
  ok(lifts.some((l) => l.revertToExerciseName), "the fixture exercises a cycle-scoped swap marker");
  ok(accessories.some((a) => a.incrementLb === 2.5), "the fixture exercises a fractional increment");
  ok(accessories.some((a) => a.incrementLb === 0 && a.targetSeconds > 0),
    "the fixture exercises a timed accessory, where a zero increment is correct");
  ok(fixture.program.days.map((d) => d.order).join() === "0,2",
    "the fixture keeps a non-contiguous day order, which must survive verbatim");

  ok(lifts.some((l) => l.revertToExerciseName), "the fixture exercises a revert marker needing resolution");
  ok(fixture.program.days.some((d) => d.order === fixture.program.nextDayIndex),
    "the fixture's next-day pointer names a day it actually has");

  // And it must import cleanly into a library that has its exercises —
  // including the ones only named by a revert marker.
  const referenced = [...lifts, ...accessories]
    .flatMap((s) => [s.exerciseName, s.revertToExerciseName])
    .filter(Boolean);
  for (const name of referenced) {
    if (!(await db.Exercises.byName(name))) {
      await db.Exercises.save({
        name, category: "Accessory", type: "dumbbell", group: "misc",
        createdAt: new Date().toISOString(),
      });
    }
  }
  const fixtureReport = await pf.importProgramText(onDisk);
  ok(fixtureReport.action === "created", "the fixture imports");
  ok(fixtureReport.carriedState === true, "the fixture is recognised as carrying state");
  const importedFixture = (await db.Programs.all()).find((p) => p.uuid === fixtureReport.programId);
  ok(importedFixture.days.map((d) => d.order).join() === "0,2",
    "the non-contiguous day order survived the import");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
