// IndexedDB storage + repositories + export/import.
// Sessions embed their exercises and sets as one document (the active-session
// screen is one unit of work), which keeps reads/writes join-free.
import * as C from "./core.js";
import { SEED } from "./seed.js";

const DB_NAME = "cadence";
const DB_VERSION = 3;
export const BACKUP_SCHEMA_VERSION = 1;
const STORES = {
  settings: { keyPath: "id" },           // single row id:"app"
  exercises: { keyPath: "name" },
  gyms: { keyPath: "name" },
  tracks: { keyPath: "exerciseName" },
  sessions: { keyPath: "id", autoIncrement: true },
  bodyweight: { keyPath: "id", autoIncrement: true },
  protein: { keyPath: "id", autoIncrement: true },
  checkins: { keyPath: "id", autoIncrement: true },
  milestones: { keyPath: "id", autoIncrement: true },
  programs: { keyPath: "id", autoIncrement: true },
  checkpoints: { keyPath: "id", autoIncrement: true },
};

let _db = null;
let _opening = null;
function open() {
  if (_db) return Promise.resolve(_db);
  if (_opening) return _opening;
  _opening = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    let settled = false;
    const fail = (error) => {
      if (settled) return;
      settled = true;
      _opening = null;
      reject(error);
    };
    req.onupgradeneeded = () => {
      const db = req.result;
      for (const [name, opts] of Object.entries(STORES)) {
        if (!db.objectStoreNames.contains(name)) db.createObjectStore(name, opts);
      }
    };
    req.onsuccess = () => {
      if (settled) { req.result.close(); return; }
      settled = true;
      const db = req.result;
      db.onversionchange = () => {
        db.close();
        if (_db === db) _db = null;
      };
      db.onclose = () => { if (_db === db) _db = null; };
      _db = db;
      _opening = null;
      resolve(db);
    };
    req.onblocked = () => fail(new Error("Cadence storage is open in another tab. Close it and retry."));
    req.onerror = () => fail(req.error || new Error("Couldn't open Cadence storage."));
  });
  return _opening;
}

// One transaction over one or more stores. fn receives a store getter and is
// queued synchronously; a synchronous throw (e.g. put() on a bad record) or a
// rejection aborts the WHOLE transaction — queued writes must never
// auto-commit around a failure.
export function runAll(stores, mode, fn) {
  return open().then((db) => {
    let tx;
    try {
      tx = db.transaction(stores, mode);
    } catch (error) {
      // Safari can retain a cached connection after suspending the PWA. A
      // failure to CREATE the transaction is safe to retry; a transaction
      // that already started is never replayed.
      if (error?.name === "InvalidStateError" && _db === db) {
        db.close(); _db = null;
        return open().then((fresh) => runTransaction(fresh, stores, mode, fn));
      }
      throw error;
    }
    return runTransaction(db, stores, mode, fn, tx);
  });
}
function runTransaction(db, stores, mode, fn, existingTransaction = null) {
  return new Promise((resolve, reject) => {
    const tx = existingTransaction || db.transaction(stores, mode);
    let out;
    tx.oncomplete = () => resolve(out);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error || new Error("transaction aborted"));
    const abort = (e) => { try { tx.abort(); } catch { /* already aborting */ } reject(e); };
    try {
      Promise.resolve(fn((name) => tx.objectStore(name))).then((v) => { out = v; }, abort);
    } catch (e) { abort(e); }
  });
}
function run(store, mode, fn) { return runAll([store], mode, (os) => fn(os(store))); }
const reqP = (r) => new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });

const getAll = (store) => run(store, "readonly", (os) => reqP(os.getAll()));
const get = (store, key) => run(store, "readonly", (os) => reqP(os.get(key)));
const put = (store, value) => run(store, "readwrite", (os) => reqP(os.put(value)));
const del = (store, key) => run(store, "readwrite", (os) => reqP(os.delete(key)));
const clear = (store) => run(store, "readwrite", (os) => reqP(os.clear()));

// ---- Date helpers ----
export const iso = (d) => (d instanceof Date ? d : new Date(d)).toISOString();
export const localDayKey = (d) => {
  const x = d instanceof Date ? d : new Date(d);
  return `${x.getFullYear()}-${x.getMonth()}-${x.getDate()}`;
};
export const isToday = (d) => localDayKey(d) === localDayKey(new Date());

// ---- Settings ----
// get/save both run normalizeSettings, so every consumer sees a COMPLETE
// nested `rest` object (no view-side re-merging) and the legacy flat
// accessoryRestSeconds mirror stays in sync for old exports.
export const Settings = {
  async get() {
    let s = await get("settings", "app");
    if (!s) { s = { id: "app", ...defaultSettings() }; await put("settings", s); }
    return normalizeSettings(s);
  },
  save: (s) => put("settings", { ...normalizeSettings(s), id: "app" }),
};
function defaultSettings() {
  return {
    unitDisplay: "lbPrimary",
    theme: "carbon",
    proteinTargetGrams: 175,
    accessoryRestSeconds: 90, // legacy — superseded by rest.accessorySeconds, kept for old exports
    // Five configurable rest buckets (seconds); secondary rests less than a top main.
    rest: { mainCompoundSeconds: 300, olympicSeconds: 240, mainUpperSeconds: 180, secondarySeconds: 180, accessorySeconds: 90 },
    autoStartRest: false, // manual start by default — auto lies if you rested first
    haptics: true,
    // Fresh installs seed a stamp-free library — nothing to migrate (see
    // RETIRED_REST_STAMPS). Absent on pre-bucket stores, so they get the
    // one-shot clear in syncLibrary.
    restSeedStampsCleared: true,
    seededAt: null,
  };
}

// ---- Repositories ----
export const Exercises = {
  all: () => getAll("exercises"),
  byName: (name) => get("exercises", name),
  save: (e) => put("exercises", e),
};
export const Gyms = {
  all: () => getAll("gyms"),
  save: (g) => put("gyms", g),
  del: (name) => del("gyms", name),
  async default() { const all = await getAll("gyms"); return all.find((g) => g.isDefault) || all[0] || null; },
};
export const Tracks = {
  all: () => getAll("tracks"),
  byName: (n) => get("tracks", n),
  save: (t) => put("tracks", t),
};
export const Sessions = {
  all: () => getAll("sessions"),
  get: (id) => get("sessions", id),
  save: (s) => put("sessions", s),
  del: (id) => del("sessions", id),
  async open() { const all = await getAll("sessions"); return all.filter((s) => !s.isCompleted).sort((a, b) => new Date(b.date) - new Date(a.date))[0] || null; },
  async completed() { const all = await getAll("sessions"); return all.filter((s) => s.isCompleted).sort((a, b) => new Date(b.date) - new Date(a.date)); },
};
export const Bodyweight = {
  all: () => getAll("bodyweight"),
  add: (e) => put("bodyweight", e),
  del: (id) => del("bodyweight", id),
};
export const Protein = {
  all: () => getAll("protein"),
  add: (e) => put("protein", e),
  del: (id) => del("protein", id),
  async today() { const all = await getAll("protein"); return all.filter((p) => isToday(p.date)); },
  async todayTotal() { return (await Protein.today()).reduce((s, p) => s + p.grams, 0); },
};
export const Checkins = {
  all: () => getAll("checkins"),
  add: (c) => put("checkins", c),
};
export const Milestones = {
  all: () => getAll("milestones"),
  add: (m) => put("milestones", m),
};
export const Programs = {
  all: () => getAll("programs"),
  get: (id) => get("programs", id),
  save: (p) => put("programs", p),
  del: (id) => del("programs", id),
  async active() { const all = await getAll("programs"); return all.find((p) => p.isActive) || all[0] || null; },
};

// ---- Session helpers (working with embedded docs) ----
export function topSet(sessionExercise) {
  const working = sessionExercise.sets.filter((s) => !s.isWarmup);
  return working.reduce((best, s) => (!best || s.weightLb > best.weightLb ? s : best), null);
}
export function workingVolume(sessionExercise) {
  return sessionExercise.sets.filter((s) => !s.isWarmup).reduce((sum, s) => sum + s.weightLb * s.reps, 0);
}
// ---- Seeding ----
export async function ensureSeeded() {
  const s = await Settings.get();
  if (s.seededAt) return;
  const records = {
    exercises: SEED.exercises, gyms: SEED.gyms, tracks: SEED.tracks,
    bodyweight: SEED.bodyweight, milestones: SEED.milestones,
    programs: SEED.programs || [], sessions: SEED.sessions,
  };
  const stores = [...Object.keys(records), "settings"];
  await runAll(stores, "readwrite", (os) => {
    // Older builds could die between the per-store writes and leave seededAt
    // unset. Clearing only seed-owned stores makes that state recoverable
    // without touching user-only protein/check-in records.
    for (const [name, values] of Object.entries(records)) {
      const store = os(name);
      store.clear();
      for (const value of values) store.put(value);
    }
    os("settings").put({ ...normalizeSettings(s), seededAt: iso(new Date()), id: "app" });
  });
}

// name → the defaultRestSeconds the pre-bucket seeds stamped on every record
// (values that merely duplicated the rest buckets and are now 0 in seed.js).
// Deliberate deviations (180/120/60 accessories) are NOT here — they stay
// per-exercise. Mirror of Seeder.retiredRestStamps.
const RETIRED_REST_STAMPS = {
  Deadlift: 300, "Back Squat": 300, "Front Squat": 300, "Overhead Squat": 300,
  "Barbell Bench": 300, "Overhead Press": 300, "Push Press": 300, "Push Jerk": 300,
  "Split Jerk": 300, "Incline DB Press": 300, "Flat DB Press": 300,
  "Seated Upright DB Press": 300, "Overhead DB Press": 300,
  Snatch: 240, "Clean & Jerk": 240, Clean: 240, "Power Clean": 240, "Power Snatch": 240,
  "Turkish Get-up": 90, "Single-arm DB Row": 90, "Lat Pulldown": 90, "Chest-supported Row": 90,
  "Ring Row": 90, "Face Pulls": 90, "DB Curls": 90, "DB Overhead Triceps Extension": 90,
  "Walking Lunges": 90, "GHD Sit-up": 90, "KB Swing": 90, "KB Clean": 90, Dips: 90,
  // Template-declared exercises that carried the old blanket 90 default.
  "Back Extension": 90, "Hanging Knee Raise": 90,
};

// Idempotent library top-up, run every launch: adds any SEED exercises an
// already-seeded install is missing (new movements ship over time) and
// backfills movementGroup on older records — WITHOUT clobbering user edits to
// exercises that already exist (rest, shelved, watch site, etc.).
export async function syncLibrary() {
  const have = new Map((await Exercises.all()).map((e) => [e.name, e]));
  for (const seed of SEED.exercises) {
    const cur = have.get(seed.name);
    if (!cur) { await put("exercises", seed); continue; }
    if (!cur.movementGroup && seed.movementGroup) { cur.movementGroup = seed.movementGroup; await put("exercises", cur); }
  }
  // One-shot repair: old seeds stamped EVERY exercise with a rest, and the
  // per-exercise value wins over the buckets — so the rest settings (and the
  // complementary/accessory role timers) never applied to any seeded movement.
  // Clear values that still exactly equal the retired stamps; a value the user
  // changed no longer matches and is left alone.
  const settings = await Settings.get();
  if (!settings.restSeedStampsCleared) {
    for (const [name, stamp] of Object.entries(RETIRED_REST_STAMPS)) {
      const cur = have.get(name);
      if (cur && cur.defaultRestSeconds === stamp) { cur.defaultRestSeconds = 0; await put("exercises", cur); }
    }
    settings.restSeedStampsCleared = true;
    await Settings.save(settings);
  }
}

// ---- Export / Import ----
// The bundle is the Safari-eviction recovery path: it must round-trip ALL
// mutable state, not just the log — tracks (live per-lift progression), gyms
// (barcode image, plate inventory, default bar), the exercise library (rest,
// shelved, watch sites), and settings ride along with sessions.
export async function exportBundle() {
  const [sessions, bodyweight, protein, checkins, milestones, programs, tracks, gyms, exercises, settings] = await Promise.all([
    Sessions.all().then((all) => all.sort((a, b) => new Date(b.date) - new Date(a.date))),
    Bodyweight.all(), Protein.all(), Checkins.all(), Milestones.all(), Programs.all(),
    Tracks.all(), Gyms.all(), Exercises.all(), Settings.get(),
  ]);
  const programsById = new Map(programs.map((p) => [p.id, p]));
  const exportProgramTag = (tag) => {
    if (!tag) return null;
    const programName = tag.programName || programsById.get(tag.programId)?.name || null;
    if (!programName) return null; // orphaned local IDs are not portable linkage
    return {
      programName,
      cycleNumber: tag.cycleNumber ?? null,
      week: tag.week ?? null,
      dayIndex: tag.dayIndex ?? null,
      planNames: tag.planNames || null,
    };
  };
  const { id: _settingsRowId, ...settingsOut } = settings; // strip the fixed row key
  return {
    schemaVersion: BACKUP_SCHEMA_VERSION,
    exportedAt: iso(new Date()),
    appVersion: "web",
    sessions: sessions.map((s) => ({
      date: iso(s.date), notes: s.notes || "", gym: s.gymName || null, isCompleted: !!s.isCompleted,
      programTag: exportProgramTag(s.programTag),
      exercises: (s.exercises || []).map((e) => ({
        name: e.exerciseName, notes: e.notes || "",
        phase: e.phase ? C.phaseLabel(e.phase) : null,
        role: e.programRole || null,
        plannedWeightLb: e.plannedWeightLb ?? null, plannedSets: e.plannedSets ?? null, plannedReps: e.plannedReps ?? null,
        sets: (e.sets || []).map((x) => ({
          weightLb: x.weightLb, reps: x.reps, isWarmup: !!x.isWarmup, isPerSide: !!x.isPerSide,
          enteredUnit: x.enteredUnit || "lb",
          flags: x.flags || [], bodyFlagSite: x.bodyFlagSite || null, bodyFlagNote: x.bodyFlagNote || null,
          durationSeconds: x.durationSeconds ?? null, distanceMiles: x.distanceMiles ?? null,
          // Key emitted only when set (like revertToExerciseName): stamping
          // null onto every record would break byte-stable re-export of
          // pre-incline backups.
          ...(x.inclinePercent != null ? { inclinePercent: x.inclinePercent } : {}),
          autoregReason: x.autoregReason || null,
        })),
      })),
    })),
    bodyweight: bodyweight.map((b) => ({ date: iso(b.date), weightLb: b.weightLb, bodyFatPercent: b.bodyFatPercent ?? null, milestoneLabel: b.milestoneLabel || null })),
    protein: protein.map((p) => ({ date: iso(p.date), grams: p.grams, label: p.label })),
    checkIns: checkins.map((c) => ({ date: iso(c.date), site: c.site, response: c.response, note: c.note || "" })),
    milestones: milestones.map((m) => ({ date: iso(m.date), exercise: m.exerciseName || null, kind: m.kind, label: m.label })),
    programs: programs.map((p) => ({
      id: p.id, name: p.name, focus: p.focus, cycleNumber: p.cycleNumber, currentWeek: p.currentWeek,
      nextDayIndex: p.nextDayIndex, roundingLb: p.roundingLb, isActive: !!p.isActive,
      days: (p.days || []).map((d) => ({
        name: d.name, order: d.order,
        lifts: (d.lifts || []).map((l) => ({
          exerciseName: l.exerciseName, role: l.role, baseWeightLb: l.baseWeightLb, estimatedMaxLb: l.estimatedMaxLb,
          stallCount: l.stallCount || 0, lastIncrementLb: l.lastIncrementLb || 0,
          // Mid-cycle backup: the week-3 Peak stashes a pending result that is
          // applied at rollover — losing it turns the next rollover into a stall.
          pending: l.pending || null,
          // Cycle-scoped swap marker: losing it turns a temporary swap into a
          // permanent rename on restore. Key emitted only when set, so
          // marker-free exports (and the synthetic fixture) stay byte-stable.
          ...(l.revertToExerciseName ? { revertToExerciseName: l.revertToExerciseName } : {}),
        })),
        accessories: (d.accessories || []).map((a) => ({ exerciseName: a.exerciseName, sets: a.sets, minReps: a.minReps, maxReps: a.maxReps, currentReps: a.currentReps, weightLb: a.weightLb, incrementLb: a.incrementLb, stallCount: a.stallCount || 0, ...(a.revertToExerciseName ? { revertToExerciseName: a.revertToExerciseName } : {}) })),
      })),
    })),
    tracks, gyms, exercises,
    settings: settingsOut,
  };
}
export const exportJSON = async () => JSON.stringify(await exportBundle(), null, 2);

export async function exportCSV() {
  const sessions = await Sessions.completed();
  const head = ["date", "exercise", "set_index", "weight_lb", "weight_kg", "reps", "is_warmup", "per_side", "flags", "body_flag_site", "body_flag_note", "autoreg_reason", "session_notes"];
  const esc = (v) => { const s = String(v ?? ""); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const rows = [head.join(",")];
  for (const s of sessions) {
    for (const e of s.exercises || []) {
      (e.sets || []).forEach((x, i) => {
        rows.push([
          iso(s.date), e.exerciseName, i, C.trim(x.weightLb), C.trim(C.kgFromLb(x.weightLb)), x.reps,
          x.isWarmup, x.isPerSide, (x.flags || []).join(";"), x.bodyFlagSite || "", x.bodyFlagNote || "",
          x.autoregReason || "", s.notes || "",
        ].map(esc).join(","));
      });
    }
  }
  return rows.join("\n");
}

// Three local recovery points protect against an accidental valid import or
// reset. They live beside the primary data, so they are NOT a substitute for a
// downloaded JSON backup when Safari evicts the entire origin.
const CHECKPOINT_LIMIT = 3;
export const Checkpoints = {
  async all() {
    return (await getAll("checkpoints")).sort((a, b) => (new Date(b.createdAt) - new Date(a.createdAt)) || (b.id - a.id));
  },
  async latest() { return (await Checkpoints.all())[0] || null; },
  async create(reason = "automatic") {
    const record = { createdAt: iso(new Date()), reason, bundle: await exportBundle() };
    await run("checkpoints", "readwrite", async (store) => {
      const existing = await reqP(store.getAll());
      const id = await reqP(store.add(record));
      const all = [...existing, { ...record, id }].sort((a, b) => (new Date(b.createdAt) - new Date(a.createdAt)) || (b.id - a.id));
      for (const old of all.slice(CHECKPOINT_LIMIT)) store.delete(old.id);
    });
    return record;
  },
  async restoreLatest() {
    const latest = await Checkpoints.latest();
    if (!latest) throw new Error("No local recovery checkpoint exists.");
    // Preserve the current state too; undoing a recovery should be possible.
    await Checkpoints.create("before-checkpoint-restore");
    await importBundle(latest.bundle, { createCheckpoint: false });
    return latest;
  },
};

// Accepts both the current "R{n}" prefix and legacy "Wk{n}" from older backups.
const recoverPhase = (label) => { const m = /(?:R|Wk)(\d)/.exec(label || ""); return m ? Number(m[1]) : null; };

// Rest buckets arrive nested under `rest` (web's canonical shape) or flat as
// `*RestSeconds` keys (native backups) — normalize to a complete nested object
// so a restore never leaves missing buckets (which would render as NaN).
// Precedence: defaults ← legacy accessory ← native flat keys ← nested rest.
function normalizeSettings(s) {
  const num = (v) => (Number.isFinite(v) ? v : undefined);
  const flat = {
    mainCompoundSeconds: num(s.mainCompoundRestSeconds),
    olympicSeconds: num(s.olympicRestSeconds),
    mainUpperSeconds: num(s.mainUpperRestSeconds),
    secondarySeconds: num(s.secondaryRestSeconds),
    accessorySeconds: num(s.accessoryRestSeconds),
  };
  Object.keys(flat).forEach((k) => flat[k] === undefined && delete flat[k]);
  const rest = { ...C.REST_DEFAULTS, ...flat, ...(s.rest || {}) };
  return { ...s, rest, accessoryRestSeconds: rest.accessorySeconds };
}

const BACKUP_ENUMS = {
  units: ["lb", "kg"], unitDisplay: ["lbPrimary", "kgPrimary", "both"],
  themes: ["memento", "carbon", "slate", "system"],
  roles: ["main", "complementary", "accessory"], liftRoles: ["main", "complementary"],
  flags: ["clean", "grindy", "wobble", "stopped early"],
  reasons: ["bar speed", "wobble", "joint signal", "heat", "fatigue"],
  sites: ["Left shoulder", "Left hip", "Right knee"],
  categories: ["Main", "Accessory", "Conditioning"],
  exerciseTypes: ["barbell", "dumbbell", "kettlebell", "bodyweight", "band", "machine", "timed", "conditioning"],
  focuses: ["strength", "hypertrophy", "maintain"], modes: ["cycle", "linear"],
  milestoneKinds: ["heaviestSet", "volumePR", "firstScheme", "programNote"],
};

// Validate the entire payload before the first read or write. IndexedDB will
// reject missing key-paths, but that is too late: it does not catch corrupt
// dates, unknown enum values, or plausible-looking records that would silently
// default to something else on iOS.
export function validateBackup(bundle) {
  const schemaVersion = bundle.schemaVersion ?? 0;
  const invalid = (path, message) => { throw new Error(`Backup validation failed at ${path}: ${message}. Nothing was changed.`); };
  const array = (owner, key, path = key) => {
    if (!(key in owner)) return null;
    if (!Array.isArray(owner[key])) invalid(path, "expected a list");
    return owner[key];
  };
  const object = (value, path) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) invalid(path, "expected an object");
    return value;
  };
  const textValue = (value, path, required = false) => {
    if (value == null && !required) return;
    if (typeof value !== "string" || (required && !value.trim())) invalid(path, "expected non-empty text");
  };
  const numberValue = (value, path, { required = false, integer = false, min = -Infinity, max = Infinity } = {}) => {
    if (value == null && !required) return;
    if (!Number.isFinite(value) || (integer && !Number.isInteger(value)) || value < min || value > max) {
      const kind = integer ? "integer" : "number";
      invalid(path, `expected a finite ${kind} from ${min} to ${max}`);
    }
  };
  const dateValue = (value, path, required = false) => {
    if (value == null && !required) return;
    if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) invalid(path, "expected an ISO-8601 date");
  };
  const enumValue = (value, allowed, path) => {
    if (value != null && !allowed.includes(value)) invalid(path, `unknown value ${JSON.stringify(value)}`);
  };
  const unique = (records, value, path) => {
    const seen = new Set();
    records.forEach((record, index) => {
      const key = value(record);
      if (seen.has(key)) invalid(`${path}[${index}]`, `duplicate identifier ${JSON.stringify(key)}`);
      seen.add(key);
    });
  };
  const each = (records, path, fn) => records?.forEach((record, index) => fn(object(record, `${path}[${index}]`), `${path}[${index}]`));

  const sessions = array(bundle, "sessions");
  each(sessions, "sessions", (session, path) => {
    dateValue(session.date, `${path}.date`, true);
    const tag = session.programTag;
    if (tag != null) {
      object(tag, `${path}.programTag`);
      textValue(tag.programName, `${path}.programTag.programName`, schemaVersion >= 1);
      numberValue(tag.cycleNumber, `${path}.programTag.cycleNumber`, { integer: true, min: 1 });
      numberValue(tag.week, `${path}.programTag.week`, { integer: true, min: 1 });
      numberValue(tag.dayIndex, `${path}.programTag.dayIndex`, { integer: true, min: 0 });
      const names = array(tag, "planNames", `${path}.programTag.planNames`);
      names?.forEach((name, i) => textValue(name, `${path}.programTag.planNames[${i}]`, true));
    }
    each(array(session, "exercises", `${path}.exercises`), `${path}.exercises`, (exercise, exercisePath) => {
      textValue(exercise.name, `${exercisePath}.name`, true);
      enumValue(exercise.role, BACKUP_ENUMS.roles, `${exercisePath}.role`);
      numberValue(exercise.plannedWeightLb, `${exercisePath}.plannedWeightLb`, { min: 0 });
      numberValue(exercise.plannedSets, `${exercisePath}.plannedSets`, { integer: true, min: 0 });
      numberValue(exercise.plannedReps, `${exercisePath}.plannedReps`, { integer: true, min: 0 });
      each(array(exercise, "sets", `${exercisePath}.sets`), `${exercisePath}.sets`, (set, setPath) => {
        numberValue(set.weightLb, `${setPath}.weightLb`, { required: true, min: 0 });
        numberValue(set.reps, `${setPath}.reps`, { required: true, integer: true, min: 0 });
        enumValue(set.enteredUnit, BACKUP_ENUMS.units, `${setPath}.enteredUnit`);
        const flags = array(set, "flags", `${setPath}.flags`);
        flags?.forEach((flag, i) => enumValue(flag, BACKUP_ENUMS.flags, `${setPath}.flags[${i}]`));
        enumValue(set.bodyFlagSite, BACKUP_ENUMS.sites, `${setPath}.bodyFlagSite`);
        enumValue(set.autoregReason, BACKUP_ENUMS.reasons, `${setPath}.autoregReason`);
        numberValue(set.durationSeconds, `${setPath}.durationSeconds`, { integer: true, min: 0 });
        numberValue(set.distanceMiles, `${setPath}.distanceMiles`, { min: 0 });
        numberValue(set.inclinePercent, `${setPath}.inclinePercent`, { min: -100, max: 100 });
      });
    });
  });

  const bodyweight = array(bundle, "bodyweight");
  each(bodyweight, "bodyweight", (entry, path) => {
    dateValue(entry.date, `${path}.date`, true); numberValue(entry.weightLb, `${path}.weightLb`, { required: true, min: 0 });
    numberValue(entry.bodyFatPercent, `${path}.bodyFatPercent`, { min: 0, max: 100 });
  });
  const protein = array(bundle, "protein");
  each(protein, "protein", (entry, path) => {
    dateValue(entry.date, `${path}.date`, true); numberValue(entry.grams, `${path}.grams`, { required: true, min: 0 });
  });
  const checkIns = array(bundle, "checkIns");
  each(checkIns, "checkIns", (entry, path) => {
    dateValue(entry.date, `${path}.date`, true); enumValue(entry.site, BACKUP_ENUMS.sites, `${path}.site`);
    textValue(entry.response, `${path}.response`, true);
  });
  const milestones = array(bundle, "milestones");
  each(milestones, "milestones", (entry, path) => {
    dateValue(entry.date, `${path}.date`, true); enumValue(entry.kind, BACKUP_ENUMS.milestoneKinds, `${path}.kind`);
    textValue(entry.label, `${path}.label`, true);
  });

  const programs = array(bundle, "programs");
  each(programs, "programs", (program, path) => {
    textValue(program.name, `${path}.name`, true); enumValue(program.focus, BACKUP_ENUMS.focuses, `${path}.focus`);
    numberValue(program.cycleNumber, `${path}.cycleNumber`, { integer: true, min: 1 });
    numberValue(program.currentWeek, `${path}.currentWeek`, { integer: true, min: 1 });
    numberValue(program.nextDayIndex, `${path}.nextDayIndex`, { integer: true, min: 0 });
    numberValue(program.roundingLb, `${path}.roundingLb`, { min: Number.MIN_VALUE });
    const days = array(program, "days", `${path}.days`);
    each(days, `${path}.days`, (day, dayPath) => {
      textValue(day.name, `${dayPath}.name`, true); numberValue(day.order, `${dayPath}.order`, { required: true, integer: true, min: 0 });
      each(array(day, "lifts", `${dayPath}.lifts`), `${dayPath}.lifts`, (lift, liftPath) => {
        textValue(lift.exerciseName, `${liftPath}.exerciseName`, true); enumValue(lift.role, BACKUP_ENUMS.liftRoles, `${liftPath}.role`);
        for (const key of ["baseWeightLb", "estimatedMaxLb", "lastIncrementLb"]) numberValue(lift[key], `${liftPath}.${key}`, { min: 0 });
        numberValue(lift.stallCount, `${liftPath}.stallCount`, { integer: true, min: 0 });
        if (lift.pending != null) object(lift.pending, `${liftPath}.pending`);
      });
      each(array(day, "accessories", `${dayPath}.accessories`), `${dayPath}.accessories`, (accessory, accessoryPath) => {
        textValue(accessory.exerciseName, `${accessoryPath}.exerciseName`, true);
        for (const key of ["sets", "minReps", "maxReps", "currentReps", "stallCount"]) numberValue(accessory[key], `${accessoryPath}.${key}`, { integer: true, min: 0 });
        for (const key of ["weightLb", "incrementLb"]) numberValue(accessory[key], `${accessoryPath}.${key}`, { min: 0 });
      });
    });
    if (days?.length && program.nextDayIndex != null && program.nextDayIndex >= days.length) invalid(`${path}.nextDayIndex`, "outside the program's day list");
    if (days) unique(days, (day) => day.order, `${path}.days`);
  });
  if (programs) unique(programs, (program) => program.name.trim(), "programs");

  const tracks = array(bundle, "tracks");
  each(tracks, "tracks", (track, path) => {
    textValue(track.exerciseName, `${path}.exerciseName`, true); enumValue(track.mode, BACKUP_ENUMS.modes, `${path}.mode`);
    numberValue(track.cycleNumber, `${path}.cycleNumber`, { integer: true, min: 1 });
    numberValue(track.nextPhase, `${path}.nextPhase`, { integer: true, min: 1, max: 4 });
    numberValue(track.baseWeightLb, `${path}.baseWeightLb`, { min: 0 });
    numberValue(track.incrementLb, `${path}.incrementLb`, { min: Number.MIN_VALUE });
    numberValue(track.roundingLb, `${path}.roundingLb`, { min: Number.MIN_VALUE });
    dateValue(track.lastCompletedAt, `${path}.lastCompletedAt`);
  });
  if (tracks) unique(tracks, (track) => track.exerciseName.trim(), "tracks");

  const gyms = array(bundle, "gyms");
  each(gyms, "gyms", (gym, path) => {
    textValue(gym.name, `${path}.name`, true);
    each(array(gym, "plateToggles", `${path}.plateToggles`), `${path}.plateToggles`, (plate, platePath) => {
      numberValue(plate.value, `${platePath}.value`, { required: true, min: Number.MIN_VALUE });
      enumValue(plate.unit, BACKUP_ENUMS.units, `${platePath}.unit`);
    });
  });
  if (gyms) unique(gyms, (gym) => gym.name.trim(), "gyms");

  const exercises = array(bundle, "exercises");
  each(exercises, "exercises", (exercise, path) => {
    textValue(exercise.name, `${path}.name`, true); enumValue(exercise.category, BACKUP_ENUMS.categories, `${path}.category`);
    enumValue(exercise.type, BACKUP_ENUMS.exerciseTypes, `${path}.type`); enumValue(exercise.watchSite, BACKUP_ENUMS.sites, `${path}.watchSite`);
    numberValue(exercise.defaultRestSeconds, `${path}.defaultRestSeconds`, { integer: true, min: 0, max: 3600 });
    dateValue(exercise.createdAt, `${path}.createdAt`);
  });
  if (exercises) unique(exercises, (exercise) => exercise.name.trim(), "exercises");

  if ("settings" in bundle) {
    const settings = object(bundle.settings, "settings");
    enumValue(settings.unitDisplay, BACKUP_ENUMS.unitDisplay, "settings.unitDisplay");
    enumValue(settings.theme, BACKUP_ENUMS.themes, "settings.theme");
    numberValue(settings.proteinTargetGrams, "settings.proteinTargetGrams", { min: 0 });
    dateValue(settings.seededAt, "settings.seededAt");
    for (const key of ["accessoryRestSeconds", "mainCompoundRestSeconds", "olympicRestSeconds", "mainUpperRestSeconds", "secondaryRestSeconds"]) {
      numberValue(settings[key], `settings.${key}`, { integer: true, min: 0, max: 3600 });
    }
    if (settings.rest != null) {
      object(settings.rest, "settings.rest");
      for (const key of ["mainCompoundSeconds", "olympicSeconds", "mainUpperSeconds", "secondarySeconds", "accessorySeconds"]) {
        numberValue(settings.rest[key], `settings.rest.${key}`, { integer: true, min: 0, max: 3600 });
      }
    }
  }

  if (![sessions, bodyweight, protein, checkIns, milestones, programs, tracks, gyms, exercises].some((v) => v !== null) && !("settings" in bundle)) {
    throw new Error("Not a Cadence backup");
  }
}

// Restore a backup in ONE transaction: only stores present in the bundle are
// touched (an old backup without e.g. `gyms` leaves current gyms alone), and a
// malformed bundle aborts wholesale instead of leaving stores cleared.
export async function importBundle(bundle, { createCheckpoint = true } = {}) {
  if (!bundle || typeof bundle !== "object" || Array.isArray(bundle)) throw new Error("Not a Cadence backup");
  const schemaVersion = bundle.schemaVersion ?? 0;
  if (!Number.isInteger(schemaVersion) || schemaVersion < 0 || schemaVersion > BACKUP_SCHEMA_VERSION) {
    throw new Error(`Unsupported Cadence backup schema version: ${schemaVersion}`);
  }
  validateBackup(bundle);
  if (createCheckpoint) await Checkpoints.create("before-import");

  const writes = new Map(); // store name -> records to clear+put
  const knownPrograms = bundle.programs || await Programs.all();
  const programsById = new Map(knownPrograms.map((p) => [p.id, p]));
  const programsByName = new Map(knownPrograms.map((p) => [p.name, p]));
  const importProgramTag = (tag) => {
    if (!tag) return null;
    const program = programsById.get(tag.programId) || programsByName.get(tag.programName);
    return {
      programId: program?.id ?? tag.programId ?? null,
      programName: tag.programName || program?.name || null,
      cycleNumber: tag.cycleNumber ?? null,
      week: tag.week ?? null,
      dayIndex: tag.dayIndex ?? null,
      planNames: tag.planNames || [],
    };
  };

  if (bundle.sessions) {
    writes.set("sessions", bundle.sessions.map((s) => ({
      // Version-0 bundles only exported completed sessions, so absence means
      // completed. Version 1 preserves open sessions explicitly.
      date: s.date, notes: s.notes || "", isCompleted: s.isCompleted !== false, gymName: s.gym || null,
      programTag: importProgramTag(s.programTag),
      exercises: (s.exercises || []).map((e, oi) => ({
        order: oi, exerciseName: e.name, notes: e.notes || "", phase: recoverPhase(e.phase),
        programRole: e.role || null,
        plannedWeightLb: e.plannedWeightLb ?? null, plannedSets: e.plannedSets ?? null, plannedReps: e.plannedReps ?? null,
        sets: (e.sets || []).map((x, si) => ({
          order: si, weightLb: x.weightLb, reps: x.reps, isWarmup: !!x.isWarmup, isPerSide: !!x.isPerSide,
          enteredUnit: x.enteredUnit || "lb", flags: x.flags || [], bodyFlagSite: x.bodyFlagSite || null, bodyFlagNote: x.bodyFlagNote || null,
          durationSeconds: x.durationSeconds ?? null, distanceMiles: x.distanceMiles ?? null,
          ...(x.inclinePercent != null ? { inclinePercent: x.inclinePercent } : {}),
          autoregReason: x.autoregReason || null,
        })),
      })),
    })));
  }
  if (bundle.bodyweight) writes.set("bodyweight", bundle.bodyweight.map((b) => ({ date: b.date, weightLb: b.weightLb, bodyFatPercent: b.bodyFatPercent ?? null, milestoneLabel: b.milestoneLabel || null })));
  if (bundle.protein) writes.set("protein", bundle.protein.map((p) => ({ date: p.date, grams: p.grams, label: p.label })));
  if (bundle.checkIns) writes.set("checkins", bundle.checkIns.map((c) => ({ date: c.date, site: c.site, response: c.response, note: c.note || "" })));
  if (bundle.milestones) writes.set("milestones", bundle.milestones.map((m) => ({ date: m.date, exerciseName: m.exercise || null, kind: m.kind, label: m.label })));
  if (bundle.programs) writes.set("programs", bundle.programs);
  if (bundle.tracks) writes.set("tracks", bundle.tracks);
  // Gyms are kept as-is except barcodeImage, which must be an inline base64
  // data:image/* URL — exactly what the gym editor's FileReader produces. A
  // remote URL smuggled into a backup would otherwise beacon the user's IP to
  // an attacker-chosen host every time the gym card renders. (SVG-as-img can't
  // load external resources, so no per-MIME allowlist is needed.)
  const isInlineImage = (v) => typeof v === "string" && /^data:image\/[\w.+-]+;base64,/i.test(v);
  if (bundle.gyms) writes.set("gyms", bundle.gyms.map((g) => ({
    ...g,
    barcodeImage: isInlineImage(g.barcodeImage) ? g.barcodeImage : null,
  })));
  if (bundle.exercises) writes.set("exercises", bundle.exercises);
  // restSeedStampsCleared describes the EXERCISE LIBRARY's migration state, so
  // it follows the bundle only when the library itself was restored from it:
  // a settings-only restore keeps the store's current marker (else the next
  // syncLibrary would re-clear over an untouched library — and could eat a
  // user-set rest that happens to equal a retired stamp), and a library
  // restored with no settings riding along is of unknown vintage, so the
  // marker resets and the next launch re-checks the stamps.
  if (bundle.settings) {
    const s = { ...normalizeSettings(bundle.settings), id: "app" };
    if (!bundle.exercises) {
      const cur = await get("settings", "app");
      if (cur && cur.restSeedStampsCleared !== undefined) s.restSeedStampsCleared = cur.restSeedStampsCleared;
      else delete s.restSeedStampsCleared;
    }
    writes.set("settings", [s]);
  } else if (bundle.exercises) {
    const cur = await get("settings", "app");
    if (cur) writes.set("settings", [{ ...cur, restSeedStampsCleared: false }]);
  }

  const stores = [...writes.keys()];
  if (!stores.length) throw new Error("Not a Cadence backup");
  // runAll aborts wholesale on a synchronous put() throw (bad record), so the
  // queued clears can't auto-commit around a failed import.
  await runAll(stores, "readwrite", (os) => {
    for (const [store, records] of writes) {
      const s = os(store);
      s.clear();
      for (const r of records) s.put(r);
    }
  });
}

export async function wipeAll({ preserveCheckpoints = false } = {}) {
  const stores = Object.keys(STORES).filter((name) => !preserveCheckpoints || name !== "checkpoints");
  await runAll(stores, "readwrite", (os) => { for (const name of stores) os(name).clear(); });
  const db = _db;
  _db = null;
  _opening = null;
  db?.close();
}
