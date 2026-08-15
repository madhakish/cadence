// Durable workout-stopwatch record — the web mirror of the native
// WorkoutClock's UserDefaults fallback (Cadence/Services/WorkoutClock.swift).
// The stopwatch origin is mirrored into localStorage (keyed by session) so
// reloading or relaunching the PWA mid-workout resumes the elapsed clock
// instead of restarting it at 0:00. Whether a record may be adopted is the
// shared core rule (C.stopwatchRecordUsable): a running record goes stale
// after a day, future-dated fields never fabricate a stopwatch. Every helper
// swallows storage failures (private mode) — the in-memory clock still works.
//
// This lives outside the views so the persistence layer (db.js) can clear
// records when sessions are destroyed without importing a view module.
import * as C from "./core.js";

export const CLOCK_KEY = "cadenceWorkoutClock";

// Single reader, and the self-heal point: bytes that can never be adopted —
// unparsable, shapeless, ownerless, or failing the shared usability rule —
// are deleted on read instead of lingering to shadow the slot forever.
// Mirrors WorkoutClock.loadRecord.
function readClockRecord() {
  let record = null;
  try { record = JSON.parse(localStorage.getItem(CLOCK_KEY) || "null"); } catch { record = undefined; }
  if (record === null) return null;
  if (record && typeof record === "object" && record.sessionId != null
      && C.stopwatchRecordUsable(record.start, null, Date.now())) return record;
  try { localStorage.removeItem(CLOCK_KEY); } catch { /* noop */ }
  return null;
}

export function writeClockRecord(sessionId, start) {
  try { localStorage.setItem(CLOCK_KEY, JSON.stringify({ sessionId, start })); } catch { /* noop */ }
}

// Clears only a record the given session owns — deleting one session must
// never erase another workout's running clock. Wired into Sessions.del, so
// every deletion path (Today's discard buttons, the in-logger discard, and
// any future one) is covered without remembering a second call.
export function clearClockRecord(sessionId) {
  try {
    const record = readClockRecord();
    if (record && String(record.sessionId) === String(sessionId)) localStorage.removeItem(CLOCK_KEY);
  } catch { /* noop */ }
}

// The bulk-deletion clear: a backup import or full wipe replaces or destroys
// the sessions store wholesale, and web session ids are small autoincrement
// integers that collide across installs — whatever record exists belongs to
// the pre-import world and must not graft its stopwatch onto an unrelated
// session that happens to reuse the id.
export function clearAnyClockRecord() {
  try { localStorage.removeItem(CLOCK_KEY); } catch { /* noop */ }
}

// The stored origin for this session, or null: wrong session, or nothing
// usable stored (readClockRecord already deleted stale, future-dated, or
// malformed bytes).
export function storedClockStart(sessionId) {
  const record = readClockRecord();
  return record && String(record.sessionId) === String(sessionId) ? record.start : null;
}
