// History — session log (grouped by month), progression charts, milestones.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { lineChart, multiLineChart, progressionChart, smoothLinePath, ROTATION_COLORS, ROLE_DASH } from "../charts.js";
import { Sessions, Milestones, Exercises, Programs, Checkins, Intervals, intervalSnapshots, topSet, workingVolume } from "../db.js";
import { coachingReport } from "../coaching-adapter.js";

import { COPY } from "../constants.js";

let mode = "rotations";

export async function render(host) {
  const [sessions, milestones, exercises, program, checkins, intervals] = await Promise.all([
    Sessions.completed(), Milestones.all(), Exercises.all(), Programs.active(), Checkins.all(), Intervals.all(),
  ]);
  const root = ui.h("div");
  root.append(ui.seg([{ value: "rotations", label: "Rotations" }, { value: "log", label: "Log" },
    { value: "charts", label: "Charts" }, { value: "milestones", label: "Milestones" }], mode, (m) => { mode = m; render(host); }));
  const panel = ui.h("div");
  root.append(panel);

  if (mode === "rotations") renderRotations(panel, sessions, exercises, program, checkins, intervals);
  else if (mode === "log") renderLog(panel, sessions, exercises, intervals);
  else if (mode === "charts") renderCharts(panel, sessions, exercises, program, intervals);
  else renderMilestones(panel, milestones);

  host.replaceChildren(root);
}

function renderRotations(panel, sessions, exercises, program, checkins, intervals = []) {
  const exMap = new Map(exercises.map((exercise) => [exercise.name, exercise]));
  const rolling = (days) => {
    const cutoff = Date.now() - days * 86_400_000;
    const recent = sessions.filter((session) => Date.parse(session.completedAt || session.date) >= cutoff);
    let sets = 0, conditioningSeconds = 0;
    for (const session of recent) for (const entry of session.exercises || []) {
      const exercise = exMap.get(entry.exerciseName);
      const pattern = exercise?.movementPattern || C.movementPattern(entry.exerciseName, exercise?.movementGroup);
      const completed = (entry.sets || []).filter((set) => !set.isWarmup && set.status === "completed");
      if (C.isConditioningPattern(pattern)) conditioningSeconds += completed.reduce((sum, set) => sum + (set.durationSeconds || 0), 0);
      else sets += completed.length;
    }
    return `${sets} work sets · ${Math.round(conditioningSeconds / 60)} min conditioning`;
  };
  panel.append(ui.h("div", { class: "section-title", text: "Rolling load" }),
    ui.h("div", { class: "card" },
      ui.h("div", { class: "row" }, ui.h("span", { text: "14 days" }), ui.h("span", { class: "mono", text: rolling(14) })),
      ui.h("div", { class: "row" }, ui.h("span", { text: "28 days" }), ui.h("span", { class: "mono", text: rolling(28) })),
      ui.h("div", { class: "sub", text: "Working sets and conditioning are separate; warm-ups are excluded." })));
  if (!program) { panel.append(ui.empty("📋", "Create a program to group training by rotation.")); return; }
  const report = coachingReport(program, sessions, exMap, checkins, intervalSnapshots(intervals));
  if (!report.rotations.length) { panel.append(ui.empty("◌", "Complete program days to establish the first rotation baseline.")); return; }
  const rotationNumbers = [...new Set(report.rotations.map((rotation) => rotation.key.rotation))].sort((a, b) => a - b);
  const cycleNumbers = [...new Set(report.rotations.map((rotation) => rotation.key.cycleNumber))].sort((a, b) => b - a);
  const matrix = ui.h("div", { class: "rotation-matrix",
    style: { gridTemplateColumns: `64px repeat(${rotationNumbers.length}, minmax(64px, 1fr))` } },
  ui.h("span", { class: "sub", text: "Cycle" }),
  ...rotationNumbers.map((number) => ui.h("span", { class: "title", text: `R${number}` })));
  for (const cycle of cycleNumbers) {
    matrix.append(ui.h("span", { class: "title mono", text: String(cycle) }));
    for (const number of rotationNumbers) {
      const rotation = report.rotations.find((item) => item.key.cycleNumber === cycle && item.key.rotation === number);
      if (!rotation) { matrix.append(ui.h("span")); continue; }
      matrix.append(ui.h("button", { class: `rotation-cell readiness-${rotation.readiness}`,
        ariaLabel: `Cycle ${cycle}, rotation ${number}, ${rotation.readiness}, ${rotation.completedWorkingSets} of ${rotation.plannedWorkingSets} sets`,
        onClick: () => ui.sheet({ title: `Cycle ${cycle} · R${number}`, build: (content) => {
          content.append(ui.h("div", { class: "card" },
            ui.h("div", { class: `title readiness-${rotation.readiness}`, text: rotation.readiness[0].toUpperCase() + rotation.readiness.slice(1) }),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Completed/planned" }), ui.h("span", { class: "mono", text: `${rotation.completedWorkingSets}/${rotation.plannedWorkingSets}` })),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Conditioning" }), ui.h("span", { class: "mono", text: `${Math.round(rotation.conditioningMinutes)} min` })),
            ...(rotation.reasons || []).map((reason) => ui.h("div", { class: "sub", text: reason }))));
        } }) },
      ui.h("span", { text: rotation.readiness === "red" ? "!" : rotation.readiness === "green" ? "●" : "◐" }),
      ui.h("span", { class: "mono", text: `${rotation.completedWorkingSets}/${rotation.plannedWorkingSets}` }),
      ui.h("span", { class: "sub", text: `${Math.round(rotation.conditioningMinutes)}m` })));
    }
  }
  panel.append(ui.h("div", { class: "section-title", text: "Cycle matrix" }),
    ui.h("div", { class: "card rotation-matrix-wrap" }, matrix));
}

function setLabel(s) { return s.weightLb === 0 ? "BW" : ui.fmtWeight(s.weightLb); }
// A set that logged distance/time is cardio — render the shared conditioning
// label and skip ×reps (keyed on the DATA so restored history renders right
// even if the library entry is gone).
const isCardioSet = (s) => s.distanceMiles > 0 || s.flights > 0 || s.durationSeconds > 0;

const isStrengthEntry = (entry, exercise) => {
  if (exercise?.type) return exercise.type !== "conditioning" && exercise.type !== "timed";
  return !(entry.sets || []).some(isCardioSet);
};

export const completedStrengthSetCountForTest = (session, exerciseByName) =>
  (session.exercises || []).reduce((count, entry) => {
    if (!isStrengthEntry(entry, exerciseByName.get(entry.exerciseName))) return count;
    return count + (entry.sets || []).filter((set) => !set.isWarmup && set.status === "completed").length;
  }, 0);

const historySetKind = (set) => {
  if (set.isWarmup || set.prescriptionBlock === "warmup") return "Warm-up";
  return ({ primer: "Primer", topSingle: "Top single", ramp: "Ramp", work: "Work",
    amrap: "AMRAP", backoff: "Back-off", conditioning: "Conditioning" })[set.prescriptionBlock] || "Work";
};

/// The completed row keeps actual work first and shows the original plan only
/// when the lifter changed it. Historical rows without plan snapshots remain
/// exactly as terse as they were before snapshots existed.
export const historySetPresentationForTest = (set, exerciseType = null) => {
  const cardio = exerciseType === "conditioning" || (exerciseType == null && isCardioSet(set));
  const timed = exerciseType === "timed";
  const performed = cardio
    ? C.cardioSetLabel(set.distanceMiles, set.durationSeconds, set.inclinePercent, set.weightLb, set.flights)
    : timed ? C.cardioDurationLabel(set.durationSeconds || 0)
      : `${setLabel(set)} × ${set.reps}${set.isPerSide ? "/side" : ""}`;
  const state = set.status || "completed";
  const actual = state === "completed" ? performed
    : `${state === "skipped" ? "Skipped" : "Not performed"} · ${performed}`;
  let planned = null;
  if (timed && Number.isFinite(set.plannedDurationSeconds)
      && set.plannedDurationSeconds !== set.durationSeconds) {
    planned = `Planned ${C.cardioDurationLabel(set.plannedDurationSeconds)}`;
  } else if (!cardio && !timed) {
    const plannedWeight = Number.isFinite(set.plannedWeightLb) ? set.plannedWeightLb : set.weightLb;
    const plannedReps = Number.isFinite(set.plannedReps) ? set.plannedReps : set.reps;
    if (Math.abs(plannedWeight - set.weightLb) > 0.001 || plannedReps !== set.reps) {
      planned = `Planned ${plannedWeight === 0 ? "BW" : ui.fmtWeight(plannedWeight)} × ${plannedReps}${set.prescriptionBlock === "amrap" ? "+" : ""}${set.isPerSide ? "/side" : ""}`;
    }
  }
  return { actual, planned, kind: historySetKind(set), state };
};

// Noon-anchored so a bare "yyyy-MM-dd" interval bound never renders as the
// previous day in negative-offset time zones (same dodge db.js uses).
const intervalDay = (s) => new Date(`${String(s).slice(0, 10)}T12:00:00`);

function renderLog(panel, sessions, exercises, intervals = []) {
  if (!sessions.length && !intervals.length) { panel.append(ui.empty("📋", COPY.emptyHistory)); return; }
  const exerciseByName = new Map(exercises.map((exercise) => [exercise.name, exercise]));
  // Session volume relative to the biggest session on record — the thin bar
  // under each card makes trends scannable while scrolling.
  const volumeOf = (s) => (s.exercises || []).reduce((a, e) => a + workingVolume(e, exerciseByName.get(e.exerciseName)), 0);
  const maxVolume = Math.max(1, ...sessions.map(volumeOf));
  // The log interleaves banked sessions with declared intervals — a break the
  // lifter chose is part of the training story, not a hole in it
  // (INV-INTERVAL-IS-NOT-A-GAP). Mirrors HistoryView.swift.
  const rows = [
    ...sessions.map((s) => ({ when: new Date(s.date), s })),
    ...intervals.map((iv) => ({ when: intervalDay(iv.startDate), iv })),
  ].sort((a, b) => b.when - a.when);
  let currentMonth = "";
  for (const row of rows) {
    const my = ui.monthYear(row.when);
    if (my !== currentMonth) { currentMonth = my; panel.append(ui.h("div", { class: "section-title", text: my })); }
    if (row.iv) {
      const iv = row.iv;
      const range = iv.startDate === iv.endDate
        ? ui.fmtDate(intervalDay(iv.startDate))
        : `${ui.fmtDate(intervalDay(iv.startDate))} – ${ui.fmtDate(intervalDay(iv.endDate))}`;
      panel.append(ui.h("div", { class: "card list", style: { margin: "6px 0" } },
        ui.h("div", { class: "row", style: { borderBottom: "0" } },
          ui.h("div", { class: "lead" },
            ui.h("span", { class: "title", text: C.TRAINING_INTERVAL_KIND_LABELS[iv.kind] || iv.kind }),
            ui.h("span", { class: "sub", text: range }),
            iv.note ? ui.h("span", { class: "sub", text: iv.note }) : null))));
      continue;
    }
    const s = row.s;
    // Lead with the heaviest lift of the day; the rest ride in the sub line.
    const tops = (s.exercises || []).map((e) => ({ e, t: topSet(e) })).filter((x) => x.t);
    const lead = [...tops].sort((a, b) => b.t.weightLb - a.t.weightLb)[0];
    const rest = tops.filter((x) => x !== lead)
      .map((x) => `${x.e.exerciseName} ${ui.fmtWeight(x.t.weightLb)}×${x.t.reps}`).join(" · ");
    const vol = volumeOf(s);
    const bar = ui.h("div", { class: "volbar" }, ui.h("i", { style: { width: `${Math.max(2, (vol / maxVolume) * 100)}%` } }));
    panel.append(ui.h("div", { class: "card list", style: { margin: "6px 0" } },
      ui.h("div", { class: "row", style: { borderBottom: "0" }, onClick: () => openDetail(s, exerciseByName) },
        ui.h("div", { class: "lead" },
          ui.h("span", { class: "sub", text: ui.fmtDate(s.date) }),
          lead ? ui.h("span", {},
            ui.h("span", { class: "title", text: `${lead.e.exerciseName} ` }),
            ui.h("span", { class: "wt-big mono accent", text: lead.t.weightLb > 0 ? `${ui.fmtWeight(lead.t.weightLb)}×${lead.t.reps}` : `BW×${lead.t.reps}` })) : ui.h("span", { class: "title", text: "—" }),
          rest ? ui.h("span", { class: "sub", text: rest }) : null),
        ui.h("span", { class: "chev" })),
      vol > 0 ? bar : null));
  }
}

// The stored weight's display form in the entry unit — what an untouched
// field reads, and what the no-edit comparison in draftCorrections uses. C.trim on
// both branches, like native Weight.trim: a kg-entered weight stores float
// noise, and the raw float string must never leak into the editor.
const displayWeightText = (set, unit) => (set.weightLb > 0
  ? C.trim(unit === "kg" ? C.kgFromLb(set.weightLb) : set.weightLb) : "");

// One glyph mapping for a set's status, matching the logger (session.js) so
// "skipped" looks like one concept across the app.
const statusGlyph = (status) => (status === "completed" ? "✓" : status === "skipped" ? "−" : "○");

// One banked set in correction mode: cycle the status, retype the weight or
// reps (or the hold for timed work). The row edits a DRAFT — the stored
// record is untouched until draftCorrections routes every draft through the shared
// C.correctedSetValues rule, so a half-typed number is never written, an
// empty or garbage field keeps the stored value, and nothing beyond the four
// performed fields is reachable. The weight edits in the display's primary
// unit and stores canonical pounds, like every other entry surface.
function editableHistorySetRow(set, exerciseType, draft) {
  const unit = C.primaryUnit(ui.prefs.unitDisplay);
  const effectiveStatus = () => draft.status || set.status;
  const statusBtn = ui.h("button", { class: "btn ghost sm mono", text: statusGlyph(effectiveStatus()),
    style: { minWidth: "44px", minHeight: "44px" },
    "aria-label": `Status: ${effectiveStatus()}. Tap to mark ${C.nextSetStatus(effectiveStatus())}`,
    onClick: () => {
      draft.status = C.nextSetStatus(effectiveStatus());
      statusBtn.textContent = statusGlyph(effectiveStatus());
      statusBtn.setAttribute("aria-label", `Status: ${effectiveStatus()}. Tap to mark ${C.nextSetStatus(effectiveStatus())}`);
    } });
  // Field constraints mirror what the shared rule will actually accept —
  // integers for reps and holds, decimals for weight, nothing negative.
  const numberInput = (label, value, integer, oninput) => ui.h("input", {
    type: "number", inputmode: integer ? "numeric" : "decimal",
    min: "0", step: integer ? "1" : "any", placeholder: label, value,
    style: { maxWidth: "90px" }, "aria-label": label, oninput,
  });
  const fields = exerciseType === "timed"
    ? [numberInput("Hold (s)", draft.secondsText ?? (set.durationSeconds > 0 ? String(set.durationSeconds) : ""), true,
      (event) => { draft.secondsText = event.target.value; })]
    : [numberInput(`Weight (${unit})`, draft.weightText ?? displayWeightText(set, unit), false,
      (event) => { draft.weightText = event.target.value; }),
      ui.h("span", { class: "sub", text: "×" }),
      numberInput("Reps", draft.repsText ?? String(set.reps ?? 0), true,
        (event) => { draft.repsText = event.target.value; })];
  return ui.h("div", { class: `history-set${set.isWarmup ? " warm" : ""}` },
    statusBtn,
    ui.h("div", { class: "history-set-main", style: { display: "flex", gap: "8px", alignItems: "center" } }, ...fields),
    ui.h("span", { class: "history-set-kind", text: historySetKind(set) }));
}

function openDetail(s, exerciseByName) {
  // Correction mode for a banked log: a set that never got its ✓ mid-workout
  // or a weight banked at the stale plan can be fixed here. The corrected
  // history is what charts, recalls, exports, and prior-best evidence read.
  // It does NOT re-run the grading that fired at bank time — that result is
  // already stashed in the lift's pending state — so a prescription built
  // from the wrong base is fixed in the program editor, not here.
  let editing = false;
  let screen = null;
  // Field text buffered per set while editing; the stored record is untouched
  // until the drafts are applied (Save, or leaving the screen), so a
  // half-typed number can never persist and an untouched field is not an edit.
  const drafts = new Map();
  const draftFor = (set) => { if (!drafts.has(set)) drafts.set(set, {}); return drafts.get(set); };
  // Apply every draft through the shared correction rule. The no-edit
  // comparison happens HERE, against the untouched stored values — so a field
  // still reading the stored value's display form (including a kg string
  // whose round-trip would drift the canonical pounds) is not an edit, and
  // the comparison basis can never move mid-typing.
  const draftCorrections = () => {
    const unit = C.primaryUnit(ui.prefs.unitDisplay);
    const entries = [];
    for (const [set, draft] of drafts) {
      const correction = {};
      if (draft.weightText != null && draft.weightText !== displayWeightText(set, unit)) {
        correction.weightLb = C.toLb(parseFloat(draft.weightText), unit);
      }
      if (draft.repsText != null && draft.repsText !== String(set.reps ?? 0)) {
        correction.reps = parseFloat(draft.repsText);
      }
      if (draft.secondsText != null
          && draft.secondsText !== (set.durationSeconds > 0 ? String(set.durationSeconds) : "")) {
        correction.durationSeconds = parseFloat(draft.secondsText);
      }
      if (draft.status && draft.status !== set.status) correction.status = draft.status;
      entries.push({ set, correction });
    }
    return entries;
  };
  const saveCorrections = async () => {
    await Sessions.applyCorrections(s, draftCorrections());
    drafts.clear();
    // The log list and rolling load behind this overlay were rendered from
    // the pre-edit record; refresh them so the correction is visible the
    // moment the user backs out.
    ui.nav.refresh();
  };
  const render = () => screen && renderDetail(screen.body);
  const editBtn = s.isCompleted ? ui.h("button", { class: "btn ghost sm", text: "Edit",
    "aria-label": "Edit this workout's sets",
    onClick: async () => {
      if (editing) {
        // A failed write must not masquerade as a save: stay in edit mode
        // with the drafts intact and say what happened (mirrors the native
        // PersistenceErrorCenter contract).
        try {
          await saveCorrections();
        } catch (error) {
          ui.toast(`Saving the corrections failed — ${error?.message || "storage error"}. Your edits are still here; try Save again, then export a backup.`);
          return;
        }
        ui.toast("Corrections saved.");
      }
      editing = !editing;
      editBtn.textContent = editing ? "Save" : "Edit";
      editBtn.setAttribute("aria-label", editing ? "Save the workout corrections" : "Edit this workout's sets");
      render();
    } }) : null;
  screen = ui.pushScreen({
    title: ui.fmtDate(s.date),
    actions: editBtn ? [editBtn] : [],
    build: (body) => renderDetail(body),
    // Leaving the screen commits like native's save-on-leave: what the
    // fields show is what banks. A read-only visit saves nothing.
    onClose: () => {
      if (!editing || !drafts.size) return;
      saveCorrections().catch(() => {
        ui.toast("Saving the corrections failed — reopen the workout and Save again.");
      });
    },
  });

  function renderDetail(body) {
      // A re-render (Edit/Save toggle) must not throw the reader back to the
      // top of a long session.
      const scrollTop = body.scrollTop;
      ui.clear(body);
      const completedStrengthSets = completedStrengthSetCountForTest(s, exerciseByName);
      const volume = (s.exercises || []).reduce((sum, entry) => sum + workingVolume(entry, exerciseByName.get(entry.exerciseName)), 0);
      const elapsedMinutes = s.completedAt
        ? Math.floor((Date.parse(s.completedAt) - Date.parse(s.date)) / 60000) : 0;
      // The same one-day sanity bound the stopwatch record applies — one
      // constant, so the clock and this label cannot disagree about what a
      // plausible single-day session is.
      const duration = elapsedMinutes > 0 && elapsedMinutes < C.STOPWATCH_RECORD_WINDOW_MS / 60000
        ? (elapsedMinutes >= 60 ? `${Math.floor(elapsedMinutes / 60)}h ${elapsedMinutes % 60}m` : `${elapsedMinutes}m`)
        : null;
      const identity = s.programTag?.programName || "Standalone";
      const summary = ui.h("div", { class: "card" },
        ui.h("div", { class: "row", style: { paddingTop: "0" } },
          ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: identity }),
            ui.h("span", { class: "sub", text: [ui.fmtDate(s.date), s.gymName].filter(Boolean).join(" · ") }))),
        ui.h("div", { class: "session-summary" },
          ui.h("div", { class: "session-stat" }, ui.h("strong", { class: "mono", text: String(completedStrengthSets) }), ui.h("span", { text: "work sets" })),
          ui.h("div", { class: "session-stat" }, ui.h("strong", { class: "mono", text: volume > 0 ? ui.fmtWeight(volume) : "—" }), ui.h("span", { text: "volume" })),
          duration ? ui.h("div", { class: "session-stat" }, ui.h("strong", { class: "mono", text: duration }), ui.h("span", { text: "duration" })) : null));
      body.append(summary);
      if (s.notes) body.append(ui.h("div", { class: "card" }, ui.h("span", { class: "sub", text: s.notes })));
      for (const e of s.exercises || []) {
        const exercise = exerciseByName.get(e.exerciseName);
        const phaseLabel = ui.sessionPhaseLabel(e, exerciseByName.get(e.exerciseName));
        const working = (e.sets || []).filter((set) => !set.isWarmup && set.status === "completed");
        const top = topSet(e);
        const volume = workingVolume(e, exercise);
        const setName = isStrengthEntry(e, exercise) ? "work set" : "completed set";
        const summaryBits = [`${working.length} ${setName}${working.length === 1 ? "" : "s"}`];
        if (top && exercise?.type !== "conditioning" && exercise?.type !== "timed") {
          summaryBits.push(`top ${top.weightLb === 0 ? "BW" : ui.fmtWeight(top.weightLb)}×${top.reps}`);
        }
        if (volume > 0) summaryBits.push(`${ui.fmtWeight(volume)} volume`);
        const card = ui.h("div", { class: "card" },
          ui.h("div", { class: "row", style: { paddingTop: "0" } },
            ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: e.exerciseName }),
              ui.h("span", { class: "sub", text: summaryBits.join(" · ") })),
            phaseLabel ? ui.h("span", { class: "pill accent", text: phaseLabel }) : null));
        for (const x of e.sets || []) {
          // Only strength and timed rows are correctable, keyed on the DATA
          // when the library entry is gone (like the read-only rendering): a
          // restored cardio record whose exercise was deleted must not grow a
          // weight×reps editor over its distance. Conditioning corrections
          // belong to the Health comparison flow, which reconciles against a
          // measurement instead of a memory.
          if (editing && (isStrengthEntry(e, exercise) || exercise?.type === "timed")) {
            card.append(editableHistorySetRow(x, exercise?.type, draftFor(x)));
            continue;
          }
          const shown = historySetPresentationForTest(x, exercise?.type);
          const tags = ui.h("div", { class: "history-set-tags" },
            (x.flags || []).length ? ui.h("span", { class: "pill warn", text: x.flags.join(", ") }) : null,
            x.bodyFlagSite ? ui.h("span", { class: "pill hard", text: x.bodyFlagSite + (x.bodyFlagNote ? ` — ${x.bodyFlagNote}` : "") }) : null);
          card.append(ui.h("div", { class: `history-set state-${shown.state}${x.isWarmup ? " warm" : ""}` },
            ui.h("span", { class: "history-set-state", "aria-hidden": "true",
              text: shown.state === "completed" ? "✓" : shown.state === "skipped" ? "—" : "○" }),
            ui.h("div", { class: "history-set-main" },
              ui.h("span", { class: "title mono", text: shown.actual }),
              shown.planned ? ui.h("span", { class: "sub mono", text: shown.planned }) : null,
              tags.childElementCount ? tags : null),
            ui.h("span", { class: "history-set-kind", text: shown.kind })));
        }
        if (e.notes) card.append(ui.h("div", { class: "sub", style: { marginTop: "6px" }, text: e.notes }));
        body.append(card);
      }
      body.scrollTop = scrollTop;
  }
}

// A lift can hold a MAIN slot on one day and a COMPLEMENTARY slot on another
// at a much lighter base. Charting both as one line produced a sawtooth
// between two unrelated progressions, which is what made main-lift progress
// unreadable.
//
// The third case is unprogrammed work. Inside a PROGRAM session, an entry with
// no role is extra work the lifter added — a few light squats on an upper day —
// and charting it as main dragged the progression line down to weights that
// were never a main effort. In a session with no program at all, an entry with
// no role IS the record for that lift, so it stays main.
const chartRoleOf = (entry, session) => {
  if (entry.programRole === "complementary") return "complementary";
  if (entry.programRole === "main") return "main";
  if (entry.programRole) return "extra";           // accessory and anything later
  return session.programTag ? "extra" : "main";    // untagged work is the real record
};

// Exported for the invariant test; the chart itself uses it directly.
export const chartRoleOfForTest = chartRoleOf;
// The refusal copy has to agree with the engine at every boundary it names, so
// it is asserted directly rather than through whatever the seed happens to
// produce on screen.
export const projectionRefusalForTest = (points, nowT) => projectionRefusal(points, nowT);

// Milliseconds per day. The projection engine works in day offsets so it stays
// free of dates and timezones; the chart converts at the boundary.
const DAY_MS = 86400000;
// Projected lines are drawn in the accent's cooler sibling — near enough to the
// history to read as its continuation, distinct enough to never be mistaken
// for a session that happened.
const PROJECTION_COLOR = "#7aa7d9";

let chartEx = null, chartMetric = "weight", chartIntent = "main";
let chartHorizon = 0;
function renderCharts(panel, sessions, exercises, program, chartIntervals = []) {
  const mains = exercises.filter((e) => e.category === "Main").map((e) => e.name).sort();
  if (!mains.length) { panel.append(ui.empty("📈", COPY.emptyHistory)); return; }
  if (!chartEx || !mains.includes(chartEx)) {
    const nextDay = program?.days?.find((day) => day.order === program.nextDayIndex) || program?.days?.[0];
    const nextMain = nextDay?.lifts?.find((lift) => lift.role === "main")?.exerciseName;
    const recentMain = [...sessions].sort((a, b) => new Date(b.date) - new Date(a.date))
      .flatMap((session) => session.exercises || []).find((entry) => mains.includes(entry.exerciseName))?.exerciseName;
    chartEx = mains.includes(nextMain) ? nextMain : (recentMain || mains[0]);
  }

  panel.append(ui.field("Exercise", (() => { const sel = ui.h("select", {}, ...mains.map((n) => ui.h("option", { value: n, text: n, selected: n === chartEx }))); sel.addEventListener("change", () => { chartEx = sel.value; renderInner(); }); return sel; })()));
  // The metric picker lives in its own slot because WHICH metrics are offered
  // depends on the selected lift, so it has to be rebuilt when that changes.
  const metricSlot = ui.h("div");
  panel.append(metricSlot);
  const intentSelect = ui.h("select", {},
    ui.h("option", { value: "main", text: "Main progression", selected: chartIntent === "main" }),
    ui.h("option", { value: "roles", text: "Compare program roles", selected: chartIntent === "roles" }),
    ui.h("option", { value: "rotations", text: "Compare like rotations", selected: chartIntent === "rotations" }));
  intentSelect.addEventListener("change", () => { chartIntent = intentSelect.value; renderInner(); });
  panel.append(ui.field("Chart intent", intentSelect));
  // How far past today to extend the fitted trend. Off by default: the chart's
  // job is what happened, and a forecast is something the lifter asks for.
  panel.append(ui.h("div", { class: "sub", style: { padding: "8px 4px 0" }, text: "Project forward" }));
  panel.append(ui.seg(C.TREND_HORIZONS.map((h) => ({ value: String(h.value), label: h.label })),
    String(chartHorizon), (v) => { chartHorizon = Number(v); renderInner(); }));
  const slot = ui.h("div", { class: "card" });
  panel.append(slot);
  renderInner();

  function renderInner() {
    const showComplementary = chartIntent === "roles";
    const splitByRotation = chartIntent === "rotations";
    // What the picker offers depends on what this lift's load MEANS. An
    // unloaded pull-up has no external resistance, so working weight, est. 1RM
    // and tonnage can only ever draw a flat zero — the honest series is reps.
    // Offering the load metrics anyway is how promoting pull-ups to Main turned
    // a real progression into three straight lines at 0.
    // Resolved, not raw: loadBasis is optional in the backup contract and
    // normalizeExercise does not fill it in, so a custom or imported lift with
    // no explicit basis must infer from its equipment type — exactly what the
    // native Exercise.loadBasis getter does. Reading the raw field locked such
    // lifts to the Reps-only picker.
    const loaded = C.supportsLoadPR(C.resolvedLoadBasis(exercises.find((e) => e.name === chartEx)));
    const metricOptions = loaded
      ? [{ value: "weight", label: "Working weight" }, { value: "e1rm", label: "Est. 1RM" },
        { value: "all", label: "Weight + e1RM" }]
      : [{ value: "reps", label: "Reps" }];
    if (!metricOptions.some((o) => o.value === chartMetric)) chartMetric = metricOptions[0].value;
    ui.clear(metricSlot);
    metricSlot.append(ui.seg(metricOptions, chartMetric, (m) => { chartMetric = m; renderInner(); }));

    const displayValue = (lb) => C.primaryUnit(ui.prefs.unitDisplay) === "kg" ? C.kgFromLb(lb) : lb;
    const chartExercise = exercises.find((e) => e.name === chartEx) || null;
    // Per (session, role): the top working weight, the best e1RM sample, and
    // the tonnage. One pass keeps every metric describing the same set of
    // performed sets, so switching metric can never re-slice the data.
    const rows = [];
    for (const s of [...sessions].sort((a, b) => new Date(a.date) - new Date(b.date))) {
      const matching = (s.exercises || []).filter((x) => x.exerciseName === chartEx);
      if (!matching.length) continue;
      for (const role of ["main", "complementary"]) {
        const entries = matching.filter((entry) => chartRoleOf(entry, s) === role);
        if (!entries.length) continue;
        // The point's rotation (R1–R4) for the split view. The session's
        // program tag is the fallback, so accessory slots and pre-phase-capture
        // entries chart under the rotation they were actually performed in;
        // only sessions logged outside a program read as "Untracked".
        const phase = entries.find((entry) => entry.phase)?.phase;
        const rot = C.chartRotationLabel(phase, s.programTag?.week);
        const performed = entries.flatMap((entry) => (entry.sets || [])
          .filter((set) => !set.isWarmup && set.status === "completed"));
        const top = entries.map(topSet).filter(Boolean).sort((a, b) => b.weightLb - a.weightLb)[0];
        const estimates = performed.map((set) => C.epleyE1RM(set.weightLb, set.reps));
        rows.push({
          t: new Date(s.date).getTime(), role, rot,
          weight: top ? displayValue(top.weightLb) : null,
          e1rm: estimates.length ? displayValue(Math.max(...estimates)) : null,
          // Tonnage converts at the presentation boundary like every other
          // charted value. It did not, so a kg lifter's volume axis, caption
          // and bars were canonical pounds wearing a kg label — and native
          // (which does convert) drew a different number from the same data.
          volume: displayValue(entries.reduce((sum, entry) => sum + workingVolume(entry, chartExercise), 0)) || null,
          // The best completed working set's reps: the direct analogue of
          // "heaviest set" for a lift whose load never changes. Reps are a
          // count — no unit conversion. Mirrors the native metric == .reps
          // points builder.
          reps: performed.length ? Math.max(...performed.map((set) => set.reps || 0)) || null : null,
        });
      }
    }
    let roles = showComplementary ? ["main", "complementary"] : ["main"];
    // A Main-category lift may exist ONLY as added work inside program
    // sessions (a few squats on an upper day) or only as a programmed
    // accessory. Charting nothing at all hides real history behind a role
    // distinction the user never asked about, so fall back to what exists.
    if (!rows.some((r) => roles.includes(r.role)) && rows.length) {
      roles = [...new Set(rows.map((r) => r.role))];
    }
    const visible = rows.filter((r) => roles.includes(r.role));
    const pick = (metric, role) => visible
      .filter((r) => r.role === role && Number.isFinite(r[metric]))
      .map((r) => ({ ...r, y: r[metric] }));
    // "Volume" alone keeps a plain line; in the combined view it becomes the
    // background bars so the two comparable load metrics own the axis.
    const series = chartMetric === "all" ? pick("weight", "main") : pick(chartMetric, "main");

    ui.clear(slot);
    if (!visible.length) { slot.append(ui.empty("📈", COPY.emptyHistory)); return; }
    const lift = (program?.days || []).flatMap((day) => day.lifts || []).find((item) => item.exerciseName === chartEx);
    const rawTarget = lift?.peakSingleEnabled && lift.lastPeakSingleLb > 0
      ? lift.lastPeakSingleLb + (lift.peakSingleIncrementLb || 5) : null;
    const targetY = Number.isFinite(rawTarget) && chartMetric !== "reps" ? displayValue(rawTarget) : null;
    // Reps are a count, not a load: they carry no weight unit and never convert.
    const unit = chartMetric === "reps" ? "reps" : C.primaryUnit(ui.prefs.unitDisplay);

    // The projection follows the LIFT, not a rotation: it is fitted from every
    // main-role point of the shown metric, so splitting the history into four
    // rotation lines does not fit four separate futures through a quarter of
    // the evidence each. Volume projects too — a tonnage trend is a real thing
    // to ask about — so it reads whichever metric is on screen.
    const projectionMetric = chartMetric === "all" ? "weight" : chartMetric;
    // Main-role points, or whatever role the lift actually has. Choosing a
    // ROLE up front picked "main" whenever the complementary toggle was on,
    // so a lift held only in complementary slots drew its full chart beside
    // "0 of 4 sessions so far" — a refusal stating a count that was false on
    // screen. Mirrors native projectionSamplePoints: fall back to every
    // visible point of the metric when no main-role points exist.
    const mainPoints = pick(projectionMetric, "main");
    const projectionSamples = mainPoints.length
      ? mainPoints : roles.flatMap((role) => pick(projectionMetric, role));
    const nowT = Date.now();
    const fitted = chartHorizon > 0 ? C.projectTrend(
      projectionSamples.map((p) => ({ day: p.t / DAY_MS, value: p.y })),
      chartHorizon, nowT / DAY_MS,
    ) : null;
    const horizonLabel = (C.TREND_HORIZONS.find((h) => h.value === chartHorizon) || {}).label || "";
    const projection = fitted ? {
      label: `Projected · ${horizonLabel}`, color: PROJECTION_COLOR, nowT,
      points: fitted.points.map((p) => ({ t: p.day * DAY_MS, y: p.value })),
    } : null;
    const projectionNote = fitted
      ? `${C.trendSummary(fitted.perWeek, horizonLabel, `${chartMetric === "reps" ? Math.round(fitted.horizonValue) : C.trim(fitted.horizonValue)} ${unit}`, unit)}`
        + ` · ${C.fitDescription(fitted.fitQuality)}${C.isPlateaued(fitted.perWeek, fitted.fitQuality) ? " · Plateaued" : ""}`
      : null;

    const chartOptions = {
      fmtY: (v) => (chartMetric === "reps" ? String(Math.round(v)) : C.trim(v)),
      targetY, targetLabel: "Peak target", projection,
      // Native's showsAreaFill also requires the rotation split to be OFF; a
      // single-rotation history in split mode drew the wash on web only.
      // (The split is now the "rotations" chart intent.)
      area: !splitByRotation,
      // Declared breaks as shaded bands behind the lines (issue #97).
      intervals: intervalSnapshots(chartIntervals),
    };
    const metricLabel = chartMetric === "weight" ? "Top working weight"
      : chartMetric === "e1rm" ? "Estimated 1RM"
        : chartMetric === "volume" ? "Working volume"
          : chartMetric === "reps" ? "Best working set"
            : "Working weight and est. 1RM";
    const roleNote = showComplementary ? " · solid = main, dashed = complementary" : " · main slots only";
    const selection = ui.h("div", { class: "sub mono chart-selection", text: "Tap a point for exact session details." });
    const onSelect = (point) => {
      selection.textContent = `${ui.fmtDate(new Date(point.t))} · ${Number.isFinite(point.weight) ? `${C.trim(point.weight)} ${C.primaryUnit(ui.prefs.unitDisplay)}` : "BW"}`
        + `${Number.isFinite(point.reps) ? ` × ${point.reps}` : ""} · e1RM ${Number.isFinite(point.e1rm) ? C.trim(point.e1rm) : "—"}`
        + ` · ${point.role} · ${point.rot}`;
    };
    if (splitByRotation) {
      // Colour carries the rotation; the dash carries the role, so the two
      // splits compose instead of fighting over the same visual channel.
      const lines = [];
      for (const role of roles) {
        const byRot = {};
        for (const p of pick(chartMetric === "all" ? "weight" : chartMetric, role)) (byRot[p.rot] ||= []).push(p);
        for (const [rot, points] of Object.entries(byRot)) {
          lines.push({ key: `${rot}|${role}`, label: roles.length > 1 ? `${rot} · ${role}` : rot,
            color: ROTATION_COLORS[rot] || "#888", dash: ROLE_DASH[role], points });
        }
      }
      slot.append(progressionChart({ ...chartOptions, lines, onSelect,
        caption: `${metricLabel} per session (${unit})${roleNote}` }));
    } else {
      const lines = [];
      for (const role of roles) {
        const dash = ROLE_DASH[role];
        const suffix = roles.length > 1 ? ` (${role === "main" ? "main" : "comp."})` : "";
        if (chartMetric === "all" || chartMetric === "weight") {
          lines.push({ key: `weight-${role}`, label: `Working weight${suffix}`,
            color: "var(--accent)", dash, points: pick("weight", role) });
        }
        if (chartMetric === "all" || chartMetric === "e1rm") {
          lines.push({ key: `e1rm-${role}`, label: `Est. 1RM${suffix}`,
            color: "#5BA06A", dash, points: pick("e1rm", role) });
        }
        if (chartMetric === "volume") {
          lines.push({ key: `volume-${role}`, label: `Volume${suffix}`,
            color: "var(--accent)", dash, points: pick("volume", role) });
        }
        if (chartMetric === "reps") {
          lines.push({ key: `reps-${role}`, label: `Reps${suffix}`,
            color: "var(--accent)", dash, points: pick("reps", role) });
        }
      }
      // Combined view: tonnage recedes to bars on its own right-hand scale so
      // the two same-unit load lines keep the weight axis to themselves.
      slot.append(progressionChart({ ...chartOptions, lines, onSelect,
        caption: `${metricLabel} per session (${unit})${roleNote}` }));
    }
    slot.append(selection);
    if (loaded) {
      const volumeRole = roles.includes("main") ? "main" : roles[0];
      const volumePoints = pick("volume", volumeRole);
      if (volumePoints.length) {
        slot.append(ui.h("div", { class: "section-title", text: "Working volume" }),
          progressionChart({ height: 130, lines: [{ key: "volume", label: "Volume", color: "#8B9196", points: volumePoints }],
            fmtY: C.trim, area: false, onSelect, caption: `Tonnage per session (${unit}) · separate scale` }));
      }
    }
    // Say what the projection is, or say why there isn't one. Asking for a
    // forecast and getting an unchanged chart back reads as a broken control,
    // and the reason is the useful part: the refusal names what the history is
    // missing.
    if (projectionNote) {
      slot.append(ui.h("div", { class: "row", style: { borderBottom: "0" } },
        ui.h("div", { class: "lead" },
          ui.h("span", { class: "title", style: { color: PROJECTION_COLOR }, text: projectionNote }),
          ui.h("span", { class: "sub", text: "Fitted from performed sessions — a continuation of the past, not a plan." }))));
    } else if (chartHorizon > 0) {
      slot.append(ui.h("div", { class: "row", style: { borderBottom: "0" } },
        ui.h("span", { class: "sub", text: projectionRefusal(projectionSamples, nowT) })));
    }
    const records = new Map();
    for (const session of sessions) for (const entry of session.exercises || []) if (entry.exerciseName === chartEx) {
      for (const set of entry.sets || []) if (!set.isWarmup && set.status === "completed" && set.reps > 0 && set.reps <= 12) {
        records.set(set.reps, Math.max(records.get(set.reps) || 0, set.weightLb));
      }
    }
    if (records.size) slot.append(ui.h("div", { class: "section-title", text: "Rep PRs" }),
      repCurve([...records].sort((a, b) => a[0] - b[0])),
      ui.h("div", { class: "row", style: { overflowX: "auto", gap: "12px", borderBottom: "0" } },
        ...[...records].sort((a, b) => a[0] - b[0]).map(([reps, weight]) => ui.h("div", { class: "lead", style: { minWidth: "64px" } },
          ui.h("span", { class: "sub", text: `${reps} rep${reps === 1 ? "" : "s"}` }),
          ui.h("span", { class: "mono title", text: ui.fmtWeight(weight) })))));
  }
}

function repCurve(records) {
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("class", "chart rep-curve");
  svg.setAttribute("viewBox", "0 0 340 150");
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", "Rep PR curve, weight by repetition count");
  if (!records.length) return svg;
  const W = 340, H = 150, left = 42, right = 14, top = 14, bottom = 28;
  const reps = records.map(([count]) => count);
  const weights = records.map(([, weight]) => C.primaryUnit(ui.prefs.unitDisplay) === "kg" ? C.kgFromLb(weight) : weight);
  const minRep = Math.min(...reps), maxRep = Math.max(...reps);
  let minWeight = Math.min(...weights), maxWeight = Math.max(...weights);
  if (minWeight === maxWeight) { minWeight -= 1; maxWeight += 1; }
  const x = (rep) => left + (W - left - right) * (maxRep > minRep ? (rep - minRep) / (maxRep - minRep) : 0.5);
  const y = (weight) => top + (H - top - bottom) * (1 - (weight - minWeight) / (maxWeight - minWeight));
  const element = (name, attrs = {}, text = null) => {
    const node = document.createElementNS(NS, name);
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
    if (text != null) node.textContent = text;
    return node;
  };
  svg.append(element("line", { class: "axis", x1: left, y1: H - bottom, x2: W - right, y2: H - bottom }));
  const path = smoothLinePath(records.map(([rep], index) => [x(rep), y(weights[index])]));
  svg.append(element("path", { class: "line", d: path }));
  records.forEach(([rep], index) => svg.append(element("circle", { class: "dot", cx: x(rep), cy: y(weights[index]), r: 3 })));
  svg.append(element("text", { class: "lbl", x: left, y: H - 7 }, `${minRep} reps`));
  svg.append(element("text", { class: "lbl", x: W - right, y: H - 7, "text-anchor": "end" }, `${maxRep} reps`));
  svg.append(element("text", { class: "lbl", x: 4, y: y(maxWeight) + 3 }, C.trim(maxWeight)));
  svg.append(element("text", { class: "lbl", x: 4, y: y(minWeight) + 3 }, C.trim(minWeight)));
  return svg;
}

// Why a projection was refused, in the lifter's terms. The engine returns a
// bare null; a chart that just ignores the control it was given is worse than
// one that explains itself.
function projectionRefusal(points, nowT) {
  if (points.length < C.TREND_MIN_SAMPLES) {
    return `Not enough history to project — ${points.length} of ${C.TREND_MIN_SAMPLES} sessions so far.`;
  }
  const days = points.map((p) => p.t / DAY_MS);
  const first = Math.min(...days), last = Math.max(...days);
  // Compare RAW and floor only for display. Rounding before the comparison
  // made the message disagree with the engine at the boundary: a 20.6-day span
  // refused, then explained itself as "spans 21 days, and a trend needs 21".
  const span = last - first;
  if (span < C.TREND_MIN_SPAN_DAYS) {
    return `Not enough time to project — this lift spans ${Math.floor(span)} days, and a trend needs ${C.TREND_MIN_SPAN_DAYS}.`;
  }
  // Likewise raw: rounding here let a 35.4-day gap be refused for staleness by
  // the engine and then explained by the generic fallback below.
  const idle = nowT / DAY_MS - last;
  if (idle > C.TREND_STALENESS_LIMIT_DAYS) {
    return `Last trained ${Math.floor(idle)} days ago — too long to extend a trend from. Log a session to project again.`;
  }
  return "Not enough history to project from yet.";
}

function renderMilestones(panel, milestones) {
  const sorted = [...milestones].sort((a, b) => new Date(b.date) - new Date(a.date));
  if (!sorted.length) { panel.append(ui.empty("⚑", "No milestones yet.")); return; }
  const card = ui.h("div", { class: "card" });
  for (const m of sorted) {
    card.append(ui.h("div", { class: "row" }, ui.h("div", { class: "lead" },
      ui.h("span", { class: "title accent", text: `⚑ ${m.label}` }),
      ui.h("span", { class: "sub", text: ui.fmtLong(m.date) }))));
  }
  panel.append(card);
}
