// Program-level export/import: a single program as a standalone JSON document,
// independent of the full backup.
//
// This is a SEPARATE contract from the portable backup. It carries its own
// `kind` discriminator and its own `programSchemaVersion`, so a program file
// and a backup can version independently and neither importer can be fed the
// other's file by accident. Mirrored 1:1 by the native
// ProgramExportService/ProgramImportService.
//
// Two rules shape everything below:
//
//   1. A program import touches the `programs` store and nothing else. Ever.
//      No session, bodyweight, milestone, gym, or settings record is read for
//      writing or written. The exercise library is READ to resolve names and
//      is never modified — an unresolved name fails the import instead of
//      inventing a stub, because loadBasis and movementPattern drive
//      progression and a wrong stub silently corrupts prescriptions.
//   2. Nothing is written until the whole file has been validated and every
//      exercise resolved. A malformed or partially-resolvable file changes
//      nothing.
import { Exercises, Programs } from "./db.js";

export const PROGRAM_FILE_KIND = "cadence.program";
export const PROGRAM_SCHEMA_VERSION = 1;

const FOCUSES = ["strength", "hypertrophy", "maintain"];
const ROLES = ["main", "complementary"];
const CONDITIONING_EFFORTS = ["easy", "interval", "mixed"];
const WARMUP_POLICIES = ["automatic", "full", "short", "none"];

// Prescription styles are owned by core; keep the list here narrow and
// explicit rather than importing the whole module for one array.
const PRESCRIPTIONS = [
  "automatic", "wave", "repRange", "linearFives", "texasDay", "fiveThreeOne",
  "maxEffort", "dynamicEffort",
];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Shape
// ---------------------------------------------------------------------------
// Field lists are declared once and drive BOTH the writer and the reader, so a
// key can never be exported without being validated or vice versa. Order here
// is the order on disk — that is what makes the output deterministic without a
// sort at write time.

const LIFT_PLAN_FIELDS = [
  ["exerciseName", "text"],
  ["role", "role"],
  ["order", "int:0:99"],
  ["prescription", "prescription"],
  ["warmupPolicy", "warmupPolicy"],
  ["loadOffsetLb", "num:0:500"],
  ["peakOffsetLb", "num:0:500"],
  ["deloadMultiplier", "num:0.25:1"],
  ["doubleProgressionSets", "int:1:20"],
  ["minimumReps", "int:1:100"],
  ["maximumReps", "int:1:100"],
  ["currentReps", "int:1:100"],
  ["peakSingleEnabled", "bool"],
  ["peakSingleIncrementLb", "num:0:500"],
  ["phasePrimerEnabled", "bool"],
  ["dropIncrementLb", "num:0:500"],
  ["capacityManaged", "bool"],
  ["maximumSets", "int:1:20"],
  ["baseWeightLb", "num:0:2000"],
  ["estimatedMaxLb", "num:0:2000"],
];

const LIFT_STATE_FIELDS = [
  ["stallCount", "int:0:100"],
  ["lastIncrementLb", "num:0:500"],
  ["lastPeakSingleLb", "num:0:2000"],
];

const ACCESSORY_PLAN_FIELDS = [
  ["exerciseName", "text"],
  ["order", "int:0:99"],
  ["sets", "int:1:20"],
  ["minReps", "int:1:100"],
  ["maxReps", "int:1:100"],
  ["currentReps", "int:1:100"],
  ["targetSeconds", "int:0:3600"],
  ["durationStepSeconds", "int:0:600"],
  ["capacityManaged", "bool"],
  ["maximumSets", "int:1:20"],
  ["conditioningEffort", "effort"],
  ["targetRPE", "int:0:10"],
  ["weightLb", "num:0:2000"],
  ["incrementLb", "num:0:500"],
];

const ACCESSORY_STATE_FIELDS = [["stallCount", "int:0:100"]];

const PROGRAM_PLAN_FIELDS = [
  ["name", "text"],
  ["focus", "focus"],
  ["roundingLb", "num:0.5:50"],
  ["coachEnabled", "bool"],
  ["preferredSessionSpacingDays", "int:0:14"],
  ["maximumAddedSetsPerRotation", "int:0:60"],
];

const PROGRAM_STATE_FIELDS = [
  ["cycleNumber", "int:1:9999"],
  ["currentWeek", "int:1:4"],
  ["nextDayIndex", "int:0:99"],
];

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

// Defaults mirror db.js normalizeProgram, so a program saved by any build
// exports the same bytes regardless of which optional keys its record carries.
const DEFAULTS = {
  order: 0, prescription: "automatic", warmupPolicy: "automatic",
  loadOffsetLb: 0, peakOffsetLb: 0, deloadMultiplier: 0.775,
  doubleProgressionSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 5,
  peakSingleEnabled: false, peakSingleIncrementLb: 5, phasePrimerEnabled: true,
  dropIncrementLb: 0, capacityManaged: true, maximumSets: 6,
  baseWeightLb: 0, estimatedMaxLb: 0, stallCount: 0, lastIncrementLb: 0,
  lastPeakSingleLb: 0, targetSeconds: 30, durationStepSeconds: 5,
  conditioningEffort: "easy", targetRPE: 0, weightLb: 0, incrementLb: 0,
  sets: 3, minReps: 8, maxReps: 12, roundingLb: 5, coachEnabled: true,
  preferredSessionSpacingDays: 3, maximumAddedSetsPerRotation: 6,
  cycleNumber: 1, currentWeek: 1, nextDayIndex: 0, focus: "strength",
};

const pick = (source, fields) => {
  const out = {};
  for (const [key, kind] of fields) {
    const raw = source?.[key];
    if (raw === undefined || raw === null) {
      out[key] = DEFAULTS[key] ?? (kind === "bool" ? false : kind === "text" ? "" : 0);
    } else {
      out[key] = raw;
    }
  }
  return out;
};

/// Serialize one program. Plan-only by default: a program shared with someone
/// else has no business carrying the author's stall counters, mid-cycle peak
/// grades, or wave position. `includeState` opts into the round-trip shape;
/// `includeIdentity` opts into carrying UUIDs so the file can update in place.
export function exportProgramFile(program, { includeState = false, includeIdentity = false } = {}) {
  if (!program) throw new Error("Program export failed: no program was given.");

  const liftFields = includeState ? [...LIFT_PLAN_FIELDS, ...LIFT_STATE_FIELDS] : LIFT_PLAN_FIELDS;
  const accessoryFields = includeState
    ? [...ACCESSORY_PLAN_FIELDS, ...ACCESSORY_STATE_FIELDS]
    : ACCESSORY_PLAN_FIELDS;

  const days = [...(program.days || [])]
    .map((day, index) => ({ day, order: Number.isInteger(day.order) ? day.order : index }))
    .sort((a, b) => a.order - b.order)
    .map(({ day, order }) => ({
      ...(includeIdentity ? {} : {}),
      name: day.name ?? "",
      order,
      lifts: [...(day.lifts || [])]
        .sort((a, b) => (a.order ?? 0) - (b.order ?? 0) || String(a.exerciseName).localeCompare(String(b.exerciseName)))
        .map((lift) => ({
          ...(includeIdentity && lift.id ? { id: lift.id } : {}),
          ...pick(lift, liftFields),
          // Emitted only when set, so a marker-free program stays byte-stable.
          ...(includeState && lift.pending ? { pending: lift.pending } : {}),
          ...(includeState && lift.revertToExerciseName
            ? { revertToExerciseName: lift.revertToExerciseName } : {}),
        })),
      accessories: [...(day.accessories || [])]
        .sort((a, b) => (a.order ?? 0) - (b.order ?? 0) || String(a.exerciseName).localeCompare(String(b.exerciseName)))
        .map((accessory) => ({
          ...(includeIdentity && accessory.id ? { id: accessory.id } : {}),
          ...pick(accessory, accessoryFields),
          ...(includeState && accessory.revertToExerciseName
            ? { revertToExerciseName: accessory.revertToExerciseName } : {}),
        })),
    }));

  return {
    kind: PROGRAM_FILE_KIND,
    programSchemaVersion: PROGRAM_SCHEMA_VERSION,
    program: {
      ...(includeIdentity && (program.uuid || program.id) ? { id: program.uuid || program.id } : {}),
      ...pick(program, PROGRAM_PLAN_FIELDS),
      ...(includeState ? pick(program, PROGRAM_STATE_FIELDS) : {}),
      days,
    },
  };
}

/// The file as text. Two spaces and no trailing newline, matching exportJSON.
/// Key order comes from the field tables above, not from JSON.stringify's view
/// of the source record, so the same program always produces the same bytes.
export const exportProgramText = (program, options) =>
  JSON.stringify(exportProgramFile(program, options), null, 2);

export const programFilename = (program) =>
  `cadence-program-${String(program?.name || "program").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")}.json`;

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------
// Same sentence and dotted-path convention as validateBackup, so the two
// importers stay diffable and an error is equally readable from either.

const invalid = (path, message) => {
  throw new Error(`Program file validation failed at ${path}: ${message}. Nothing was changed.`);
};

const checkValue = (value, kind, path) => {
  if (kind === "text") {
    if (typeof value !== "string" || !value.trim()) invalid(path, "expected non-empty text");
    return;
  }
  if (kind === "bool") {
    if (typeof value !== "boolean") invalid(path, "expected true or false");
    return;
  }
  if (kind === "role") {
    if (!ROLES.includes(value)) invalid(path, `unknown role ${JSON.stringify(value)}`);
    return;
  }
  if (kind === "focus") {
    if (!FOCUSES.includes(value)) invalid(path, `unknown focus ${JSON.stringify(value)}`);
    return;
  }
  if (kind === "effort") {
    if (!CONDITIONING_EFFORTS.includes(value)) invalid(path, `unknown conditioning effort ${JSON.stringify(value)}`);
    return;
  }
  if (kind === "warmupPolicy") {
    if (!WARMUP_POLICIES.includes(value)) invalid(path, `unknown warm-up policy ${JSON.stringify(value)}`);
    return;
  }
  if (kind === "prescription") {
    if (!PRESCRIPTIONS.includes(value)) invalid(path, `unknown prescription style ${JSON.stringify(value)}`);
    return;
  }
  const [type, min, max] = kind.split(":");
  const lo = Number(min);
  const hi = Number(max);
  if (!Number.isFinite(value) || (type === "int" && !Number.isInteger(value)) || value < lo || value > hi) {
    invalid(path, `expected a finite ${type === "int" ? "integer" : "number"} from ${lo} to ${hi}`);
  }
};

const checkFields = (record, fields, path) => {
  for (const [key, kind] of fields) {
    if (record[key] === undefined) invalid(`${path}.${key}`, "is required");
    checkValue(record[key], kind, `${path}.${key}`);
  }
};

/// Full structural validation. Throws on the first problem, having written
/// nothing — this runs before the store is opened for writing at all.
export function validateProgramFile(file) {
  if (!file || typeof file !== "object" || Array.isArray(file)) invalid("file", "expected an object");
  if (file.kind !== PROGRAM_FILE_KIND) {
    invalid("kind", `expected ${JSON.stringify(PROGRAM_FILE_KIND)}, got ${JSON.stringify(file.kind ?? null)}`);
  }
  const version = file.programSchemaVersion;
  if (!Number.isInteger(version) || version < 1) invalid("programSchemaVersion", "expected a positive integer");
  if (version > PROGRAM_SCHEMA_VERSION) {
    invalid("programSchemaVersion", `version ${version} is newer than this app supports (${PROGRAM_SCHEMA_VERSION})`);
  }

  const program = file.program;
  if (!program || typeof program !== "object" || Array.isArray(program)) invalid("program", "expected an object");
  checkFields(program, PROGRAM_PLAN_FIELDS, "program");
  if (program.id !== undefined && !UUID_RE.test(program.id)) invalid("program.id", "expected a UUID");
  // State keys are optional as a group, but a file that carries one carries all.
  const stateKeys = PROGRAM_STATE_FIELDS.filter(([key]) => program[key] !== undefined);
  if (stateKeys.length) checkFields(program, PROGRAM_STATE_FIELDS, "program");

  if (!Array.isArray(program.days) || program.days.length === 0) {
    invalid("program.days", "expected at least one day");
  }

  const dayOrders = new Set();
  const slotIDs = new Set();
  program.days.forEach((day, dayIndex) => {
    const path = `program.days[${dayIndex}]`;
    if (!day || typeof day !== "object" || Array.isArray(day)) invalid(path, "expected an object");
    checkValue(day.name, "text", `${path}.name`);
    checkValue(day.order, "int:0:99", `${path}.order`);
    if (dayOrders.has(day.order)) invalid(`${path}.order`, `duplicate day order ${day.order}`);
    dayOrders.add(day.order);

    if (!Array.isArray(day.lifts)) invalid(`${path}.lifts`, "expected a list");
    if (!Array.isArray(day.accessories)) invalid(`${path}.accessories`, "expected a list");
    if (day.lifts.length === 0 && day.accessories.length === 0) {
      invalid(path, "expected at least one lift or accessory");
    }

    const checkSlot = (slot, kind, index, planFields, stateFields) => {
      const slotPath = `${path}.${kind}[${index}]`;
      if (!slot || typeof slot !== "object" || Array.isArray(slot)) invalid(slotPath, "expected an object");
      checkFields(slot, planFields, slotPath);
      if (stateFields.some(([key]) => slot[key] !== undefined)) checkFields(slot, stateFields, slotPath);
      if (slot.id !== undefined) {
        if (!UUID_RE.test(slot.id)) invalid(`${slotPath}.id`, "expected a UUID");
        // Slot ids are history linkage. Two slots sharing one id would make
        // progression advance the wrong lift, so reject rather than repair.
        if (slotIDs.has(slot.id)) invalid(`${slotPath}.id`, `duplicate identifier ${JSON.stringify(slot.id)}`);
        slotIDs.add(slot.id);
      }
      if (slot.minReps !== undefined && slot.maxReps !== undefined && slot.minReps > slot.maxReps) {
        invalid(`${slotPath}.maxReps`, "maximum reps is below minimum reps");
      }
      if (slot.minimumReps !== undefined && slot.maximumReps !== undefined && slot.minimumReps > slot.maximumReps) {
        invalid(`${slotPath}.maximumReps`, "maximum reps is below minimum reps");
      }
    };

    day.lifts.forEach((lift, i) => checkSlot(lift, "lifts", i, LIFT_PLAN_FIELDS, LIFT_STATE_FIELDS));
    day.accessories.forEach((a, i) => checkSlot(a, "accessories", i, ACCESSORY_PLAN_FIELDS, ACCESSORY_STATE_FIELDS));
  });

  return program;
}

// ---------------------------------------------------------------------------
// Exercise resolution
// ---------------------------------------------------------------------------

const normalizeName = (name) => String(name).trim().toLowerCase().replace(/\s+/g, " ");

/// Resolve every referenced name against the library: canonical name first,
/// then aliases. Returns a name -> canonical map, or throws naming every
/// unresolved exercise.
///
/// Deliberately NOT creating stubs. `loadBasis` and `movementPattern` decide
/// how a slot progresses and how its volume is counted, so a guessed stub
/// produces confidently wrong prescriptions — worse than a refused import.
export async function resolveExercises(program, library) {
  const byName = new Map();
  const byAlias = new Map();
  for (const exercise of library) {
    byName.set(normalizeName(exercise.name), exercise);
    for (const alias of exercise.aliases || []) {
      const key = normalizeName(alias);
      // A canonical name always wins over someone else's alias.
      if (!byAlias.has(key)) byAlias.set(key, exercise);
    }
  }

  const resolved = new Map();
  const missing = [];
  const gated = [];
  for (const day of program.days) {
    for (const slot of [...day.lifts, ...day.accessories]) {
      const raw = slot.exerciseName;
      if (resolved.has(raw)) continue;
      const key = normalizeName(raw);
      const match = byName.get(key) || byAlias.get(key);
      if (!match) {
        if (!missing.includes(raw)) missing.push(raw);
        continue;
      }
      resolved.set(raw, match);
      const status = match.gateStatus || (match.isShelved ? "shelved" : "open");
      if ((status === "shelved" || status === "re-entry") && !gated.includes(match.name)) {
        gated.push(match.name);
      }
    }
  }

  if (missing.length) {
    const names = missing.map((n) => JSON.stringify(n)).join(", ");
    throw new Error(
      `Program import failed: ${missing.length === 1 ? "exercise" : "exercises"} ${names} ` +
      `${missing.length === 1 ? "is" : "are"} not in your library. ` +
      "Add it there first, or rename the slot to a name or alias you already have. Nothing was changed."
    );
  }

  return { resolved, gated };
}

// ---------------------------------------------------------------------------
// Import
// ---------------------------------------------------------------------------

const uniqueName = (base, taken) => {
  if (!taken.has(base)) return base;
  let n = 2;
  while (taken.has(`${base} ${n}`)) n += 1;
  return `${base} ${n}`;
};

const buildSlot = (slot, canonicalName, fields, { keepIdentity, keepState, extraState }) => {
  const record = { exerciseName: canonicalName };
  for (const [key] of fields) {
    if (key === "exerciseName") continue;
    record[key] = slot[key];
  }
  if (keepIdentity && slot.id) record.id = slot.id;
  for (const [key] of extraState) record[key] = keepState && slot[key] !== undefined ? slot[key] : 0;
  if (keepState && slot.pending) record.pending = slot.pending;
  if (keepState && slot.revertToExerciseName) record.revertToExerciseName = slot.revertToExerciseName;
  return record;
};

/// Apply a program file.
///
/// Additive by default: creates a NEW program, never overwriting an existing
/// one and never stealing the active flag. `preserveIdentity` opts into
/// update-in-place when the file carries an id that is already present.
///
/// Writes exactly one record, to the `programs` store. No other domain is
/// touched, and nothing is written until validation and resolution both pass.
export async function importProgramFile(file, { preserveIdentity = false } = {}) {
  const program = validateProgramFile(file);

  // Reads only. The library is never written by a program import.
  const [library, programs] = await Promise.all([Exercises.all(), Programs.all()]);
  const { resolved, gated } = await resolveExercises(program, library);

  const existing = preserveIdentity && program.id
    ? programs.find((p) => p.uuid === program.id || p.id === program.id)
    : null;

  const keepIdentity = preserveIdentity;
  const keepState = PROGRAM_STATE_FIELDS.every(([key]) => program[key] !== undefined);

  const taken = new Set(programs.filter((p) => p !== existing).map((p) => p.name));
  const name = existing ? program.name : uniqueName(program.name, taken);

  const record = {
    ...(existing ? { id: existing.id, uuid: existing.uuid } : {}),
    ...(!existing && keepIdentity && program.id ? { uuid: program.id } : {}),
    name,
    focus: program.focus,
    roundingLb: program.roundingLb,
    coachEnabled: program.coachEnabled,
    preferredSessionSpacingDays: program.preferredSessionSpacingDays,
    maximumAddedSetsPerRotation: program.maximumAddedSetsPerRotation,
    cycleNumber: keepState ? program.cycleNumber : 1,
    currentWeek: keepState ? program.currentWeek : 1,
    nextDayIndex: keepState ? program.nextDayIndex : 0,
    // An import never activates itself over a program the lifter is mid-cycle
    // on. The only exception is an empty store, where there is nothing to steal.
    isActive: existing ? !!existing.isActive : programs.length === 0,
    days: program.days.map((day) => ({
      name: day.name,
      order: day.order,
      lifts: day.lifts.map((lift) => buildSlot(
        lift, resolved.get(lift.exerciseName).name, LIFT_PLAN_FIELDS,
        { keepIdentity, keepState, extraState: LIFT_STATE_FIELDS },
      )),
      accessories: day.accessories.map((accessory) => buildSlot(
        accessory, resolved.get(accessory.exerciseName).name, ACCESSORY_PLAN_FIELDS,
        { keepIdentity, keepState, extraState: ACCESSORY_STATE_FIELDS },
      )),
    })),
  };

  const id = await Programs.save(record);
  const saved = (await Programs.all()).find((p) => p.id === id || p.uuid === (record.uuid ?? id));

  return {
    action: existing ? "updated" : "created",
    programId: saved?.uuid ?? record.uuid ?? id,
    name,
    days: record.days.length,
    lifts: record.days.reduce((n, d) => n + d.lifts.length, 0),
    accessories: record.days.reduce((n, d) => n + d.accessories.length, 0),
    carriedState: keepState,
    warnings: gated.map((exerciseName) =>
      `${exerciseName} is gated in your library — the slot imported, but it will not be programmed until you reopen it.`),
  };
}

/// Parse and apply. Text-level failures read the same as structural ones.
export async function importProgramText(text, options) {
  let file;
  try {
    file = JSON.parse(text);
  } catch {
    throw new Error("Program file validation failed at file: not valid JSON. Nothing was changed.");
  }
  return importProgramFile(file, options);
}
