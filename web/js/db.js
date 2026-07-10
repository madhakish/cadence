// IndexedDB storage + repositories + export/import.
// Sessions embed their exercises and sets as one document (the active-session
// screen is one unit of work), which keeps reads/writes join-free.
import * as C from "./core.js";
import { SEED } from "./seed.js";

const DB_NAME = "cadence";
const DB_VERSION = 2;
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
};

let _db = null;
function open() {
  if (_db) return Promise.resolve(_db);
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      for (const [name, opts] of Object.entries(STORES)) {
        if (!db.objectStoreNames.contains(name)) db.createObjectStore(name, opts);
      }
    };
    req.onsuccess = () => { _db = req.result; resolve(_db); };
    req.onerror = () => reject(req.error);
  });
}

// One transaction over one or more stores. fn receives a store getter and is
// queued synchronously; a synchronous throw (e.g. put() on a bad record) or a
// rejection aborts the WHOLE transaction — queued writes must never
// auto-commit around a failure.
export function runAll(stores, mode, fn) {
  return open().then((db) => new Promise((resolve, reject) => {
    const tx = db.transaction(stores, mode);
    let out;
    tx.oncomplete = () => resolve(out);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error || new Error("transaction aborted"));
    const abort = (e) => { try { tx.abort(); } catch { /* already aborting */ } reject(e); };
    try {
      Promise.resolve(fn((name) => tx.objectStore(name))).then((v) => { out = v; }, abort);
    } catch (e) { abort(e); }
  }));
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
export const Settings = {
  async get() {
    let s = await get("settings", "app");
    if (!s) { s = { id: "app", ...defaultSettings() }; await put("settings", s); }
    return s;
  },
  save: (s) => put("settings", { ...s, id: "app" }),
};
function defaultSettings() {
  return {
    unitDisplay: "lbPrimary",
    theme: "carbon",
    proteinTargetGrams: 175,
    accessoryRestSeconds: 90,
    autoStartRest: false, // manual start by default — auto lies if you rested first
    haptics: true,
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
export const sessionIncludesRunning = (session) =>
  session.exercises.some((e) => (e.exerciseName || "").toLowerCase().includes("run"));

// ---- Seeding ----
export async function ensureSeeded() {
  const s = await Settings.get();
  if (s.seededAt) return;
  for (const e of SEED.exercises) await put("exercises", e);
  for (const g of SEED.gyms) await put("gyms", g);
  for (const t of SEED.tracks) await put("tracks", t);
  for (const b of SEED.bodyweight) await put("bodyweight", b);
  for (const m of SEED.milestones) await put("milestones", m);
  for (const p of SEED.programs || []) await put("programs", p);
  for (const sess of SEED.sessions) await put("sessions", sess);
  s.seededAt = iso(new Date());
  await Settings.save(s);
}

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
}

// ---- Export / Import ----
// The bundle is the Safari-eviction recovery path: it must round-trip ALL
// mutable state, not just the log — tracks (live per-lift progression), gyms
// (barcode image, plate inventory, default bar), the exercise library (rest,
// shelved, watch sites), and settings ride along with sessions.
export async function exportBundle() {
  const [sessions, bodyweight, protein, checkins, milestones, programs, tracks, gyms, exercises, settings] = await Promise.all([
    Sessions.completed(), Bodyweight.all(), Protein.all(), Checkins.all(), Milestones.all(), Programs.all(),
    Tracks.all(), Gyms.all(), Exercises.all(), Settings.get(),
  ]);
  const { id: _settingsRowId, ...settingsOut } = settings; // strip the fixed row key
  return {
    exportedAt: iso(new Date()),
    appVersion: "web",
    sessions: sessions.map((s) => ({
      date: iso(s.date), notes: s.notes || "", gym: s.gymName || null,
      programTag: s.programTag || null,
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
        })),
        accessories: (d.accessories || []).map((a) => ({ exerciseName: a.exerciseName, sets: a.sets, minReps: a.minReps, maxReps: a.maxReps, currentReps: a.currentReps, weightLb: a.weightLb, incrementLb: a.incrementLb, stallCount: a.stallCount || 0 })),
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

// Accepts both the current "R{n}" prefix and legacy "Wk{n}" from older backups.
const recoverPhase = (label) => { const m = /(?:R|Wk)(\d)/.exec(label || ""); return m ? Number(m[1]) : null; };

// Restore a backup in ONE transaction: only stores present in the bundle are
// touched (an old backup without e.g. `gyms` leaves current gyms alone), and a
// malformed bundle aborts wholesale instead of leaving stores cleared.
export async function importBundle(bundle) {
  const writes = new Map(); // store name -> records to clear+put

  if (bundle.sessions) {
    writes.set("sessions", bundle.sessions.map((s) => ({
      date: s.date, notes: s.notes || "", isCompleted: true, gymName: s.gym || null,
      programTag: s.programTag || null,
      exercises: (s.exercises || []).map((e, oi) => ({
        order: oi, exerciseName: e.name, notes: e.notes || "", phase: recoverPhase(e.phase),
        programRole: e.role || null,
        plannedWeightLb: e.plannedWeightLb ?? null, plannedSets: e.plannedSets ?? null, plannedReps: e.plannedReps ?? null,
        sets: (e.sets || []).map((x, si) => ({
          order: si, weightLb: x.weightLb, reps: x.reps, isWarmup: !!x.isWarmup, isPerSide: !!x.isPerSide,
          enteredUnit: x.enteredUnit || "lb", flags: x.flags || [], bodyFlagSite: x.bodyFlagSite || null, bodyFlagNote: x.bodyFlagNote || null,
          durationSeconds: x.durationSeconds ?? null, distanceMiles: x.distanceMiles ?? null, autoregReason: x.autoregReason || null,
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
  if (bundle.gyms) writes.set("gyms", bundle.gyms);
  if (bundle.exercises) writes.set("exercises", bundle.exercises);
  if (bundle.settings) writes.set("settings", [{ ...bundle.settings, id: "app" }]);

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

export async function wipeAll() { for (const st of Object.keys(STORES)) await clear(st); _db = null; }
