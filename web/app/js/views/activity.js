// Ad-hoc physical work — one completed, off-program session on the existing
// timeline. Wood splitting is the first registered activity kind (#166).
import * as ui from "../ui.js";
import * as C from "../core.js";
import { Exercises, Sessions, Settings, iso } from "../db.js";

// Whole minutes, floored — the same reading native gives, so a 59m 31s log
// never reports as an hour on one client and 59 minutes on the other.
const durationLabel = (seconds) => {
  if ((seconds || 0) < 60) return `${Math.max(0, seconds || 0)} sec`;
  const minutes = Math.max(0, Math.floor((seconds || 0) / 60));
  if (minutes < 60) return `${minutes} min`;
  return minutes % 60 ? `${Math.floor(minutes / 60)} hr ${minutes % 60} min` : `${minutes / 60} hr`;
};

// The form's hour and minute fields are whole units, the same contract as
// native's steppers: a decimal entry is floored, never turned into fractional
// seconds that the builder would reject with the wrong message.
export const wholeMinuteSeconds = (hours, minutes) =>
  Math.max(0, Math.floor(Number(hours) || 0)) * 3600 + Math.max(0, Math.floor(Number(minutes) || 0)) * 60;

// The fields show the stored duration as whole minutes. An untouched duration
// saves back exactly as stored, seconds included, so an imported 5430 s record
// is not silently truncated to 5400 by an unrelated edit. Mirrors native.
export const editedDurationSeconds = (original, hours, minutes) => {
  const typed = wholeMinuteSeconds(hours, minutes);
  const stored = Number.isInteger(original) && original > 0 ? original : 0;
  return stored > 0 && typed === stored - (stored % 60) ? stored : typed;
};

// The RPE picker offers the half-step grid every consumer of the contract
// expects, plus the record's own value when it sits off the grid (a valid
// 7.25 from a bundle), so an unrelated edit can never clear it.
export const sessionRPEOptions = (existing = null) => {
  const grid = [];
  for (let value = C.ACTIVITY_SESSION_RPE.min; value <= C.ACTIVITY_SESSION_RPE.max; value += 0.5) grid.push(value);
  if (Number.isFinite(existing) && !grid.includes(existing)) grid.push(existing);
  return grid.sort((a, b) => a - b);
};

export function activitySet(session, kind = session?.activity?.kind) {
  const name = C.activityExerciseName(kind);
  if (!name) return null;
  return (session?.exercises || []).find((entry) =>
    entry.exerciseId === C.exerciseLegacyID(name) || entry.exerciseName === name)?.sets?.[0] || null;
}

export function activityDurationSeconds(session) {
  return (session?.exercises || []).flatMap((entry) => entry.sets || [])
    .filter((set) => !set.isWarmup && set.status === "completed")
    .reduce((sum, set) => sum + (Number.isFinite(set.durationSeconds) ? set.durationSeconds : 0), 0);
}

const nonNegative = (value, label, { integer = false } = {}) => {
  if (value == null || value === "") return null;
  const parsed = Number(String(value).replace(",", "."));
  if (!Number.isFinite(parsed) || parsed < 0 || (integer && !Number.isInteger(parsed))) {
    throw new Error(`${label} must be a real number, zero or more.`);
  }
  return parsed;
};

/// Pure session builder used by the UI and focused regression tests. It keeps
/// an edited session's identity while preserving the canonical #166 shape.
export function buildActivitySession(input, exercise, existing = null) {
  if (!C.ACTIVITY_KINDS.includes(input.kind)) throw new Error("Choose a registered activity.");
  if (!Number.isInteger(input.durationSeconds) || input.durationSeconds <= 0) {
    throw new Error("Duration must be greater than zero.");
  }
  if (input.sessionRPE != null && (!Number.isFinite(input.sessionRPE)
    || input.sessionRPE < C.ACTIVITY_SESSION_RPE.min || input.sessionRPE > C.ACTIVITY_SESSION_RPE.max)) {
    throw new Error("Session RPE must be between 1 and 10.");
  }
  if (!exercise || exercise.name !== C.activityExerciseName(input.kind)) {
    throw new Error(`The exercise library is missing ${C.activityExerciseName(input.kind)}.`);
  }
  const loadLb = nonNegative(input.loadLb, "Implement weight") ?? 0;
  const wood = input.kind === "woodSplitting" ? (input.woodSplitting || {}) : {};
  const activity = {
    kind: input.kind,
    sessionRPE: input.sessionRPE ?? null,
    rounds: nonNegative(wood.rounds, "Rounds", { integer: true }),
    splitPieces: nonNegative(wood.splitPieces, "Split pieces", { integer: true }),
    estimatedStrikes: nonNegative(wood.estimatedStrikes, "Estimated strikes", { integer: true }),
    cordVolume: nonNegative(wood.cordVolume, "Cords split"),
  };
  const start = new Date(input.startDate);
  if (Number.isNaN(start.getTime())) throw new Error("Choose a valid start date.");
  // Editing rewrites the record wholesale, so it must only ever rewrite the
  // canonical shape: one activity, one entry, one set, no program. Anything
  // else is refused rather than silently truncated. Mirrors native
  // ActivitySession.update's invalidSessionShape guard.
  if (existing) {
    const entries = Array.isArray(existing.exercises) ? existing.exercises : [];
    const sets = Array.isArray(entries[0]?.sets) ? entries[0].sets : [];
    if (!existing.activity || entries.length !== 1 || sets.length !== 1 || sets[0].isWarmup
        || existing.programTemplateId != null || existing.programTag != null
        || entries[0].programRole != null || entries[0].programSlotId != null) {
      throw new Error("This activity record is incomplete and can't be edited safely.");
    }
  }
  const oldEntry = (existing?.exercises || [])[0] || {};
  const oldSet = oldEntry.sets?.[0] || {};
  const set = {
    ...oldSet,
    order: 0,
    weightLb: loadLb,
    reps: 0,
    isWarmup: false,
    isPerSide: false,
    enteredUnit: input.enteredUnit === "kg" ? "kg" : "lb",
    targetWeightLb: null,
    plannedWeightLb: null,
    plannedReps: null,
    plannedDurationSeconds: null,
    prescriptionBlock: "conditioning",
    loadBasis: C.resolvedLoadBasis(exercise),
    implementCount: C.resolvedImplementCount(exercise),
    status: "completed",
    flags: [],
    bodyFlagSite: null,
    bodyFlagNote: null,
    durationSeconds: input.durationSeconds,
    distanceMiles: null,
    flights: null,
    inclinePercent: null,
    autoregReason: null,
  };
  const entry = {
    ...oldEntry,
    order: 0,
    exerciseName: exercise.name,
    exerciseId: exercise.id || C.exerciseLegacyID(exercise.name),
    notes: "",
    phase: null,
    programRole: null,
    programSlotId: null,
    barId: null,
    barIdManual: false,
    plannedWeightLb: null,
    targetWeightLb: null,
    plannedSets: null,
    plannedReps: null,
    plannedDurationSeconds: null,
    fallbackWeightLb: null,
    prescriptionStyle: null,
    sets: [set],
  };
  return {
    ...(existing || {}),
    id: existing?.id || crypto.randomUUID(),
    date: iso(start),
    completedAt: iso(new Date(start.getTime() + input.durationSeconds * 1000)),
    notes: input.notes || "",
    gymId: null,
    gymName: null,
    isCompleted: true,
    programTemplateId: null,
    programTag: null,
    activity,
    exercises: [entry],
  };
}

const localDateTimeValue = (date) => {
  const value = new Date(date);
  return new Date(value.getTime() - value.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
};

const numberInput = (value = "", { step = "1", inputMode = "numeric", placeholder = "Optional" } = {}) =>
  ui.h("input", { type: "number", min: "0", step, inputMode, value, placeholder });

export async function openActivityLog(existing = null, { onDone = () => ui.nav.refresh() } = {}) {
  const [settings, completed] = await Promise.all([Settings.get(), Sessions.completed()]);
  const kind = existing?.activity?.kind && C.ACTIVITY_KINDS.includes(existing.activity.kind)
    ? existing.activity.kind : "woodSplitting";
  const set = existing ? activitySet(existing, kind) : null;
  const recent = existing ? null : completed.find((session) =>
    session.activity?.kind === kind && (activitySet(session, kind)?.weightLb || 0) > 0);
  const recentSet = recent ? activitySet(recent, kind) : null;
  const duration = set?.durationSeconds || 0;
  const initialUnit = set?.enteredUnit || recentSet?.enteredUnit || C.primaryUnit(settings.unitDisplay);
  const initialLoadLb = set?.weightLb || recentSet?.weightLb || 0;
  const initialLoad = initialLoadLb > 0
    ? C.trim(initialUnit === "kg" ? C.kgFromLb(initialLoadLb) : initialLoadLb, 2) : "";

  let activityKind = kind;
  const kindSelect = ui.h("select", {}, ...C.ACTIVITY_KINDS.map((value) =>
    ui.h("option", { value, text: C.activityExerciseName(value), selected: value === kind })));
  kindSelect.addEventListener("change", () => { activityKind = kindSelect.value; });
  const started = ui.h("input", { type: "datetime-local", value: localDateTimeValue(existing?.date || new Date()) });
  const hours = numberInput(String(Math.floor(duration / 3600)), { inputMode: "numeric" });
  hours.max = "48";
  const minutes = numberInput(String(Math.floor((duration % 3600) / 60)), { inputMode: "numeric" });
  minutes.max = "59";
  const existingRPE = existing?.activity?.sessionRPE ?? null;
  const rpe = ui.h("select", {},
    ui.h("option", { value: "", text: "Not recorded", selected: existingRPE == null }),
    ...sessionRPEOptions(existingRPE).map((value) =>
      ui.h("option", { value: String(value), text: `RPE ${C.trim(value, 2)}`,
        selected: existingRPE === value })));
  const load = numberInput(initialLoad, { step: "0.25", inputMode: "decimal" });
  const enteredUnit = ui.h("select", {},
    ui.h("option", { value: "lb", text: "lb", selected: initialUnit === "lb" }),
    ui.h("option", { value: "kg", text: "kg", selected: initialUnit === "kg" }));
  const rounds = numberInput(existing?.activity?.rounds ?? "");
  const pieces = numberInput(existing?.activity?.splitPieces ?? "");
  const strikes = numberInput(existing?.activity?.estimatedStrikes ?? "");
  const cords = numberInput(existing?.activity?.cordVolume ?? "", { step: "0.001", inputMode: "decimal" });
  const notes = ui.h("textarea", { rows: 4, placeholder: "Oak, weather, tool, anything useful", value: existing?.notes || "" });

  const screen = ui.pushScreen({ title: existing ? "Edit ad-hoc work" : "Log ad-hoc work", build: (body, api) => {
    body.append(
      ui.h("section", { class: "activity-intro" },
        ui.h("span", { class: "eyebrow accent", text: "AD-HOC WORK" }),
        ui.h("h2", { text: "Physical work, not a training session" }),
        ui.h("p", { class: "sub", text: "Banks immediately on the same history timeline. It never advances a cycle, changes a PR, or counts as lifting tonnage." })),
      ui.h("div", { class: "section-title", text: "Work performed" }),
      ui.h("div", { class: "card form-grid" },
        ui.field("Activity", kindSelect),
        ui.field("Started", started),
        ui.h("div", { class: "duration-grid" }, ui.field("Hours", hours), ui.field("Minutes", minutes))),
      ui.h("div", { class: "section-title", text: "Effort & implement" }),
      ui.h("div", { class: "card form-grid" },
        ui.field("Session effort", rpe),
        ui.h("div", { class: "load-grid" }, ui.field("Maul weight", load), ui.field("Unit", enteredUnit)),
        ui.h("p", { class: "sub", text: "Both are optional. RPE creates duration × effort workload; maul weight remains an implement fact, never volume." })),
      ui.h("div", { class: "section-title", text: "Wood splitting · optional detail" }),
      ui.h("div", { class: "card form-grid two-col" },
        ui.field("Rounds", rounds), ui.field("Split pieces", pieces),
        ui.field("Estimated strikes", strikes), ui.field("Cords split", cords),
        ui.h("p", { class: "sub full", text: "Leave anything you did not count blank. Cadence never infers these facts from one another." })),
      ui.h("div", { class: "section-title", text: "Notes" }),
      ui.h("div", { class: "card" }, notes),
    );

    // One in-flight save at a time: a double tap on a slow device must bank
    // one session, not two with different ids. Mirrors native isSaving.
    let saving = false;
    const bank = ui.h("button", { class: "btn primary wide", text: existing ? "Save" : "Bank work", onClick: async () => {
        if (saving) return;
        saving = true; bank.disabled = true;
        try {
          const durationSeconds = editedDurationSeconds(duration, hours.value, minutes.value);
          const exercise = await Exercises.byName(C.activityExerciseName(activityKind));
          const displayLoad = nonNegative(load.value, "Maul weight");
          const session = buildActivitySession({
            kind: activityKind,
            startDate: new Date(started.value),
            durationSeconds,
            sessionRPE: rpe.value === "" ? null : Number(rpe.value),
            loadLb: displayLoad == null ? null : C.toLb(displayLoad, enteredUnit.value),
            enteredUnit: enteredUnit.value,
            notes: notes.value,
            woodSplitting: {
              rounds: rounds.value, splitPieces: pieces.value,
              estimatedStrikes: strikes.value, cordVolume: cords.value,
            },
          }, exercise, existing);
          await Sessions.save(session);
          api.close();
          ui.toast(existing ? "Ad-hoc work updated." : "Work banked off-program.");
          onDone();
        } catch (error) {
          ui.toast(error?.message || "Couldn't bank this work.");
        } finally {
          saving = false; bank.disabled = false;
        }
      } });
    const actions = ui.h("div", { class: "sticky-actions" },
      bank,
      existing ? ui.h("button", { class: "btn ghost danger wide", text: "Delete activity", onClick: () => {
        ui.actionSheet("Delete this activity? Training cycles and workouts are unchanged.", [
          { label: "Delete activity", role: "danger", onClick: async () => {
            await Sessions.del(existing.id); api.close(); ui.toast("Activity deleted."); onDone();
          } },
        ]);
      } }) : null);
    body.append(actions);
  } });
  return screen;
}

export { durationLabel as activityDurationLabel };
