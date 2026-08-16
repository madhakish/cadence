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
import { BACKUP_ENUMS, Exercises, Programs } from "./db.js";
import * as C from "./core.js";

export const PROGRAM_FILE_KIND = "cadence.program";
export const PROGRAM_SCHEMA_VERSION = 2;

// Allowed values come from the backup validator's table, not a second copy —
// adding a prescription style there must not leave program files rejecting it.
const FOCUSES = BACKUP_ENUMS.focuses;
const ROLES = BACKUP_ENUMS.liftRoles;
const CONDITIONING_EFFORTS = BACKUP_ENUMS.conditioningEfforts;
const WARMUP_POLICIES = BACKUP_ENUMS.warmupPolicies;
const PRESCRIPTIONS = BACKUP_ENUMS.prescriptions;
const EQUIPMENT_POLICIES = BACKUP_ENUMS.equipmentPolicies;
const DAY_TRAINING_INTENTS = BACKUP_ENUMS.dayTrainingIntents;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Shape
// ---------------------------------------------------------------------------
// Field lists are declared once and drive BOTH the writer and the reader, so a
// key can never be exported without being validated or vice versa. Their order
// here is not the order on disk: exportProgramText sorts keys recursively to
// match Swift's `.sortedKeys`, so these lists can be reordered freely.

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

// The stashed week-3 grade. Ranges match the live fields it overwrites at
// rollover, and the backup validator's equivalent check.
const PENDING_STATE_FIELDS = [
  ["baseWeightLb", "num:0:2000"],
  ["estimatedMaxLb", "num:0:2000"],
  ["stallCount", "int:0:100"],
  ["lastIncrementLb", "num:0:500"],
];

const PROGRAM_PLAN_FIELDS = [
  ["name", "text"],
  ["focus", "focus"],
  ["equipmentPolicy", "equipmentPolicy"],
  ["roundingLb", "num:0.5:50"],
  ["coachEnabled", "bool"],
  // Matches the backup contract's range. Accepting 0 or 1 here would let a
  // program file import cleanly and then fail its own backup.
  ["preferredSessionSpacingDays", "int:2:14"],
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
  equipmentPolicy: "any", trainingIntent: "general",
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
      // Days have no id of their own — `order` is their identity, and it is
      // what banked sessions refer to through programTag.dayIndex.
      name: day.name ?? "",
      order,
      trainingIntent: day.trainingIntent ?? DEFAULTS.trainingIntent,
      lifts: [...(day.lifts || [])]
        .sort((a, b) => (a.order ?? 0) - (b.order ?? 0) || String(a.exerciseName).localeCompare(String(b.exerciseName)))
        .map((lift) => ({
          ...(includeIdentity && lift.id ? { id: lift.id } : {}),
          ...pick(lift, liftFields),
          // Emitted only when set, so a marker-free program stays byte-stable.
          // Narrowed to the contract's shape: the live web record is a whole
          // ProgressionResult and carries `grade`, which Swift's PendingResult
          // does not declare and would silently drop on re-encode.
          ...(includeState && lift.pending
            ? { pending: {
              state: pick(lift.pending.state ?? {}, PENDING_STATE_FIELDS),
              ...(lift.pending.note ? { note: lift.pending.note } : {}),
            } }
            : {}),
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

// Recursive key sort. Swift's JSONEncoder writes `.sortedKeys` (the idiom
// ExportService already uses), so sorting here is what lets the same program
// produce byte-identical files on both clients — and it makes output
// independent of the order keys happen to sit in an IndexedDB record.
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((k) => [k, stable(value[k])]));
  }
  return value;
};

/// The file as text. Two spaces and no trailing newline, matching exportJSON.
export const exportProgramText = (program, options) =>
  JSON.stringify(stable(exportProgramFile(program, options)), null, 2);

// Keeps Unicode letters and digits, matching the Swift slug rule, and falls
// back when the name slugs away to nothing — "日本語" and "!!!" would otherwise
// both download as `cadence-program-.json`.
export const programFilename = (program) => {
  const slug = String(program?.name ?? "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "");
  return `cadence-program-${slug || "program"}.json`;
};

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
  if (kind === "equipmentPolicy") {
    if (!EQUIPMENT_POLICIES.includes(value)) invalid(path, `unknown equipment policy ${JSON.stringify(value)}`);
    return;
  }
  if (kind === "trainingIntent") {
    if (!DAY_TRAINING_INTENTS.includes(value)) invalid(path, `unknown training intent ${JSON.stringify(value)}`);
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

  const rawProgram = file.program;
  if (!rawProgram || typeof rawProgram !== "object" || Array.isArray(rawProgram)) invalid("program", "expected an object");
  // Normalize only missing fields to literal legacy values; an explicitly
  // unknown value still fails. This also keeps hand-authored V2 files that
  // omit the new optional semantics aligned with Swift's Codable defaults.
  const program = {
    ...rawProgram,
    equipmentPolicy: rawProgram.equipmentPolicy ?? "any",
    days: Array.isArray(rawProgram.days)
      ? rawProgram.days.map((day) => ({
        ...day,
        trainingIntent: day?.trainingIntent ?? "general",
      }))
      : rawProgram.days,
  };
  checkFields(program, PROGRAM_PLAN_FIELDS, "program");
  if (program.id !== undefined && !UUID_RE.test(program.id)) invalid("program.id", "expected a UUID");
  // State keys are optional as a group, but a file that carries one carries all.
  const stateKeys = PROGRAM_STATE_FIELDS.filter(([key]) => program[key] !== undefined);
  if (stateKeys.length) checkFields(program, PROGRAM_STATE_FIELDS, "program");

  if (!Array.isArray(program.days) || program.days.length === 0) {
    invalid("program.days", "expected at least one day");
  }

  const programCarriesState = PROGRAM_STATE_FIELDS.every(([key]) => program[key] !== undefined);
  let anySlotCarriesState = false;

  const dayOrders = new Set();
  const slotIDs = new Set();
  program.days.forEach((day, dayIndex) => {
    const path = `program.days[${dayIndex}]`;
    if (!day || typeof day !== "object" || Array.isArray(day)) invalid(path, "expected an object");
    checkValue(day.name, "text", `${path}.name`);
    checkValue(day.order, "int:0:99", `${path}.order`);
    checkValue(day.trainingIntent, "trainingIntent", `${path}.trainingIntent`);
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
      if (stateFields.some(([key]) => slot[key] !== undefined)
          || slot.pending !== undefined || slot.revertToExerciseName !== undefined) {
        anySlotCarriesState = true;
      }
      if (stateFields.some(([key]) => slot[key] !== undefined)) checkFields(slot, stateFields, slotPath);
      if (slot.id !== undefined) {
        if (!UUID_RE.test(slot.id)) invalid(`${slotPath}.id`, "expected a UUID");
        // Slot ids are history linkage. Two slots sharing one id would make
        // progression advance the wrong lift, so reject rather than repair.
        if (slotIDs.has(slot.id)) invalid(`${slotPath}.id`, `duplicate identifier ${JSON.stringify(slot.id)}`);
        slotIDs.add(slot.id);
      }
      // The stashed peak grade is applied verbatim at cycle rollover, so it
      // has to survive the same scrutiny as the fields it will overwrite. An
      // unchecked value here does not fail at import — it fails weeks later,
      // mid-session, when rollover reads `pending.state.baseWeightLb`.
      if (slot.pending !== undefined) {
        const pending = slot.pending;
        if (!pending || typeof pending !== "object" || Array.isArray(pending)) {
          invalid(`${slotPath}.pending`, "expected an object");
        }
        if (pending.note !== undefined && pending.note !== null && typeof pending.note !== "string") {
          invalid(`${slotPath}.pending.note`, "expected text");
        }
        const state = pending.state;
        if (!state || typeof state !== "object" || Array.isArray(state)) {
          invalid(`${slotPath}.pending.state`, "expected an object");
        }
        for (const [key, kind] of PENDING_STATE_FIELDS) {
          if (state[key] === undefined) invalid(`${slotPath}.pending.state.${key}`, "is required");
          checkValue(state[key], kind, `${slotPath}.pending.state.${key}`);
        }
      }
      if (slot.revertToExerciseName !== undefined) {
        checkValue(slot.revertToExerciseName, "text", `${slotPath}.revertToExerciseName`);
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

  // nextDayIndex is a day ORDER, not a position in the array. A pointer that
  // names no day silently falls back to the first day, quietly losing the wave
  // position the file was carrying. The backup validator enforces the same
  // membership rule (INV-NEXTDAY-IS-AN-ORDER).
  if (program.nextDayIndex !== undefined && !dayOrders.has(program.nextDayIndex)) {
    invalid("program.nextDayIndex",
      `${program.nextDayIndex} is not one of this program's day orders (${[...dayOrders].sort((a, b) => a - b).join(", ")})`);
  }

  // Runtime state is ONE decision for the whole file. Import keys off the
  // program's wave position, so slot counters in a file that omits it were
  // being read, accepted, and then silently zeroed — the file's state
  // discarded with no error. Reject the combination instead of guessing which
  // half the author meant.
  if (anySlotCarriesState && !programCarriesState) {
    invalid("program.cycleNumber",
      "slots carry progression state but the program carries no wave position; runtime state is all-or-nothing for the whole file");
  }

  return program;
}

// ---------------------------------------------------------------------------
// Slot identity
// ---------------------------------------------------------------------------

/// Every slot id the file carries, lifts and accessories, in document order.
/// Slots without an id contribute nothing — a plan-only file has none at all.
/// Mirrored 1:1 in CadenceCore ProgramFileContract.slotIDs(of:).
export function slotIDsOf(program) {
  return (program.days || []).flatMap((day) => [
    ...(day.lifts || []).map((l) => l.id),
    ...(day.accessories || []).map((a) => a.id),
  ].filter((id) => id != null));
}

/// The file's slot ids that are ALREADY live somewhere else in the store.
///
/// validateProgramFile enforces slot-id uniqueness *within* the file, but
/// nothing there can see the store. An identity-preserving import adopts these
/// ids verbatim, so without this check two live slots can end up sharing one —
/// and programSlotId is what banked sessions point at, so the ambiguity is
/// permanent. Nothing repairs it afterwards either.
///
/// The caller decides what counts as "elsewhere": on update-in-place the
/// program being replaced must be excluded, since its own ids are legitimately
/// being reused.
///
/// Sorted and deduplicated so the error text is stable. Empty is success.
/// Mirrored 1:1 in CadenceCore ProgramFileContract.collidingSlotIDs.
export function collidingSlotIDs(program, liveElsewhere) {
  const live = liveElsewhere instanceof Set ? liveElsewhere : new Set(liveElsewhere);
  return [...new Set(slotIDsOf(program).filter((id) => live.has(id)))].sort();
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
      // The revert marker is resolved too. It is the name the slot springs
      // back to at cycle rollover, and rollover writes it straight onto the
      // slot — so an unresolvable marker leaves the slot bound to no exercise
      // definition weeks later, long after the import looked like it worked.
      for (const raw of [slot.exerciseName, slot.revertToExerciseName]) {
        if (!raw || resolved.has(raw)) continue;
        const key = normalizeName(raw);
        const match = byName.get(key) || byAlias.get(key);
        if (!match) {
          if (!missing.includes(raw)) missing.push(raw);
          continue;
        }
        resolved.set(raw, match);
        const status = C.exerciseGateStatus(match);
        if ((status === "shelved" || status === "re-entry") && !gated.includes(match.name)) {
          gated.push(match.name);
        }
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

const buildSlot = (slot, resolved, fields, { keepIdentity, keepState, extraState }) => {
  const record = { exerciseName: resolved.get(slot.exerciseName).name };
  for (const [key] of fields) {
    if (key === "exerciseName") continue;
    record[key] = slot[key];
  }
  if (keepIdentity && slot.id) record.id = slot.id;
  for (const [key] of extraState) record[key] = keepState && slot[key] !== undefined ? slot[key] : 0;
  // Narrowed to the contract's shape on the way in as well: whatever this
  // writes becomes the next export, so an extra key here would leak straight
  // back out and break cross-client parity a second time.
  if (keepState && slot.pending) {
    record.pending = {
      state: pick(slot.pending.state ?? {}, PENDING_STATE_FIELDS),
      ...(slot.pending.note ? { note: slot.pending.note } : {}),
    };
  }
  // Rewritten to the canonical name, like exerciseName — an alias stored here
  // would resolve to nothing at rollover.
  if (keepState && slot.revertToExerciseName) {
    record.revertToExerciseName = resolved.get(slot.revertToExerciseName).name;
  }
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

  // [INV-SLOT-ID-IS-UNIQUE] Adopting the file's slot ids must not give two live
  // slots the same id. Only reachable through preserveIdentity — the additive
  // path re-mints every id — and the program being updated is excluded, since
  // its own slots are the ones being replaced.
  if (keepIdentity) {
    const owners = new Map();
    for (const other of programs) {
      if (other === existing) continue;
      for (const id of slotIDsOf(other)) if (!owners.has(id)) owners.set(id, other.name);
    }
    const collisions = collidingSlotIDs(program, new Set(owners.keys()));
    if (collisions.length) {
      const named = collisions
        .map((id) => `${JSON.stringify(id)} (already used by ${JSON.stringify(owners.get(id))})`)
        .join(", ");
      throw new Error(
        `Program import failed: slot ${collisions.length === 1 ? "id" : "ids"} ${named}. `
        + "Importing with identity preserved would give two slots the same history linkage. "
        + "Nothing was changed."
      );
    }
  }

  // A rename in the file is honoured on update, but still has to stay unique —
  // two programs sharing a name is ambiguous everywhere, and the native mirror
  // has Program.name as a unique attribute. Same rule for both paths, so the
  // clients cannot disagree about what the same file does.
  const taken = new Set(programs.filter((p) => p !== existing).map((p) => p.name));
  const name = uniqueName(program.name, taken);

  const record = {
    // Spread the existing record first: a program carries fields this format
    // deliberately does not (reliableHistoryStart is the lifter's own "first
    // trustworthy date" choice), and Programs.save is a whole-record put, so
    // rebuilding from a literal would silently drop them on every update.
    ...(existing ?? {}),
    ...(existing ? { id: existing.id, uuid: existing.uuid } : {}),
    ...(!existing && keepIdentity && program.id ? { uuid: program.id } : {}),
    name,
    focus: program.focus,
    equipmentPolicy: program.equipmentPolicy,
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
    days: program.days.map((day) => {
      // A file whose slots all say the same order carries no ordering
      // information beyond the sequence they were written in — keep it, or
      // the tie falls to the alphabetical display fallback and the alphabet
      // does the author's programming. Mirrors ProgramImportService.
      const liftOrders = C.authoredSlotOrders(day.lifts.map((l) => l.order ?? 0));
      const accessoryOrders = C.authoredSlotOrders(day.accessories.map((a) => a.order ?? 0));
      return {
        name: day.name,
        order: day.order,
        trainingIntent: day.trainingIntent,
        lifts: day.lifts.map((lift, i) => ({
          ...buildSlot(lift, resolved, LIFT_PLAN_FIELDS,
            { keepIdentity, keepState, extraState: LIFT_STATE_FIELDS }),
          order: liftOrders[i],
        })),
        accessories: day.accessories.map((accessory, i) => ({
          ...buildSlot(accessory, resolved, ACCESSORY_PLAN_FIELDS,
            { keepIdentity, keepState, extraState: ACCESSORY_STATE_FIELDS }),
          order: accessoryOrders[i],
        })),
      };
    }),
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
