// History — session log (grouped by month), progression charts, milestones.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { lineChart, multiLineChart } from "../charts.js";
import { Sessions, Milestones, Exercises, Programs, Checkins, topSet, workingVolume } from "../db.js";
import { coachingReport } from "../coaching-adapter.js";

import { COPY } from "../constants.js";

let mode = "rotations";

export async function render(host) {
  const [sessions, milestones, exercises, program, checkins] = await Promise.all([
    Sessions.completed(), Milestones.all(), Exercises.all(), Programs.active(), Checkins.all(),
  ]);
  const root = ui.h("div");
  root.append(ui.seg([{ value: "rotations", label: "Rotations" }, { value: "log", label: "Log" },
    { value: "charts", label: "Charts" }, { value: "milestones", label: "Milestones" }], mode, (m) => { mode = m; render(host); }));
  const panel = ui.h("div");
  root.append(panel);

  if (mode === "rotations") renderRotations(panel, sessions, exercises, program, checkins);
  else if (mode === "log") renderLog(panel, sessions);
  else if (mode === "charts") renderCharts(panel, sessions, exercises, program);
  else renderMilestones(panel, milestones);

  host.replaceChildren(root);
}

function renderRotations(panel, sessions, exercises, program, checkins) {
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
  const report = coachingReport(program, sessions, exMap, checkins);
  if (!report.rotations.length) { panel.append(ui.empty("◌", "Complete program days to establish the first rotation baseline.")); return; }
  for (const rotation of [...report.rotations].reverse()) {
    const patternRows = Object.entries(rotation.patternSets || {}).filter(([pattern]) => !C.isConditioningPattern(pattern))
      .sort(([a], [b]) => C.movementPatternName(a).localeCompare(C.movementPatternName(b)))
      .map(([pattern, count]) => ui.h("div", { class: "row" },
        ui.h("span", { class: "sub", text: C.movementPatternName(pattern) }),
        ui.h("span", { class: "mono", text: String(count) })));
    panel.append(ui.h("div", { class: "section-title", text: `Cycle ${rotation.key.cycleNumber} · R${rotation.key.rotation}` }),
      ui.h("div", { class: "card" },
        ui.h("div", { class: "row" },
          ui.h("span", { class: `title readiness-${rotation.readiness}`, text: rotation.readiness[0].toUpperCase() + rotation.readiness.slice(1) }),
          ui.h("span", { class: "mono", text: `${rotation.completedWorkingSets}/${rotation.plannedWorkingSets} sets` })),
        ...patternRows,
        ui.h("div", { class: "row" }, ui.h("span", { class: "sub", text: "Conditioning" }),
          ui.h("span", { class: "mono", text: `${Math.round(rotation.conditioningMinutes)} min` })),
        rotation.reasons?.[0] ? ui.h("div", { class: "sub", text: rotation.reasons[0] }) : null));
  }
}

function setLabel(s) { return s.weightLb === 0 ? "BW" : ui.fmtWeight(s.weightLb); }
// A set that logged distance/time is cardio — render the shared conditioning
// label and skip ×reps (keyed on the DATA so restored history renders right
// even if the library entry is gone).
const isCardioSet = (s) => s.distanceMiles > 0 || s.durationSeconds > 0;

function renderLog(panel, sessions) {
  if (!sessions.length) { panel.append(ui.empty("📋", COPY.emptyHistory)); return; }
  // Session volume relative to the biggest session on record — the thin bar
  // under each card makes trends scannable while scrolling.
  const volumeOf = (s) => (s.exercises || []).reduce((a, e) => a + workingVolume(e), 0);
  const maxVolume = Math.max(1, ...sessions.map(volumeOf));
  let currentMonth = "";
  for (const s of sessions) {
    const my = ui.monthYear(s.date);
    if (my !== currentMonth) { currentMonth = my; panel.append(ui.h("div", { class: "section-title", text: my })); }
    // Lead with the heaviest lift of the day; the rest ride in the sub line.
    const tops = (s.exercises || []).map((e) => ({ e, t: topSet(e) })).filter((x) => x.t);
    const lead = [...tops].sort((a, b) => b.t.weightLb - a.t.weightLb)[0];
    const rest = tops.filter((x) => x !== lead)
      .map((x) => `${x.e.exerciseName} ${ui.fmtWeight(x.t.weightLb)}×${x.t.reps}`).join(" · ");
    const vol = volumeOf(s);
    const bar = ui.h("div", { class: "volbar" }, ui.h("i", { style: { width: `${Math.max(2, (vol / maxVolume) * 100)}%` } }));
    panel.append(ui.h("div", { class: "card list", style: { margin: "6px 0" } },
      ui.h("div", { class: "row", style: { borderBottom: "0" }, onClick: () => openDetail(s) },
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

function openDetail(s) {
  ui.pushScreen({
    title: ui.fmtDate(s.date),
    build: (body) => {
      if (s.notes) body.append(ui.h("div", { class: "card" }, ui.h("span", { class: "sub", text: s.notes })));
      for (const e of s.exercises || []) {
        const card = ui.h("div", { class: "card" },
          ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } },
            ui.h("span", { class: "title", text: e.exerciseName }),
            e.phase ? ui.h("span", { class: "pill accent", text: C.phaseLabel(e.phase) }) : null));
        for (const x of e.sets || []) {
          card.append(ui.h("div", { class: "setrow" },
            ui.h("span", { class: "wt mono" + (x.isWarmup ? " muted" : ""),
              text: isCardioSet(x) ? C.cardioSetLabel(x.distanceMiles, x.durationSeconds, x.inclinePercent) : setLabel(x) }),
            isCardioSet(x) ? null : ui.h("span", { class: "sub mono", text: `× ${x.reps}${x.isPerSide ? "/side" : ""}` }),
            x.isWarmup ? ui.h("span", { class: "pill", text: "warmup" }) : null,
            (x.flags || []).length ? ui.h("span", { class: "pill warn", text: x.flags.join(", ") }) : null,
            x.bodyFlagSite ? ui.h("span", { class: "pill hard", text: x.bodyFlagSite + (x.bodyFlagNote ? ` — ${x.bodyFlagNote}` : "") }) : null));
        }
        if (e.notes) card.append(ui.h("div", { class: "sub", style: { marginTop: "6px" }, text: e.notes }));
        body.append(card);
      }
    },
  });
}

let chartEx = null, chartMetric = "weight", chartSplit = false;
function renderCharts(panel, sessions, exercises, program) {
  const mains = exercises.filter((e) => e.category === "Main").map((e) => e.name).sort();
  if (!mains.length) { panel.append(ui.empty("📈", COPY.emptyHistory)); return; }
  if (!chartEx || !mains.includes(chartEx)) chartEx = mains[0];

  panel.append(ui.field("Exercise", (() => { const sel = ui.h("select", {}, ...mains.map((n) => ui.h("option", { value: n, text: n, selected: n === chartEx }))); sel.addEventListener("change", () => { chartEx = sel.value; renderInner(); }); return sel; })()));
  panel.append(ui.seg([{ value: "weight", label: "Working weight" }, { value: "e1rm", label: "Est. 1RM" }, { value: "volume", label: "Volume" }], chartMetric, (m) => { chartMetric = m; renderInner(); }));
  // One line per rotation: compare this cycle's R1 against last cycle's R1
  // instead of reading a sawtooth.
  panel.append(ui.h("div", { class: "row", style: { padding: "8px 4px" } },
    ui.h("span", { class: "sub", text: "Split by rotation" }),
    ui.toggle(chartSplit, (v) => { chartSplit = v; renderInner(); })));
  const slot = ui.h("div", { class: "card" });
  panel.append(slot);
  renderInner();

  function renderInner() {
    const series = [];
    const displayValue = (lb) => C.primaryUnit(ui.prefs.unitDisplay) === "kg" ? C.kgFromLb(lb) : lb;
    for (const s of [...sessions].sort((a, b) => new Date(a.date) - new Date(b.date))) {
      const entries = (s.exercises || []).filter((x) => x.exerciseName === chartEx);
      if (!entries.length) continue;
      // The session point's rotation (R1–R4), for the split view. Sessions
      // logged outside a cycle bucket as "Untracked".
      const phase = entries.find((entry) => entry.phase)?.phase;
      const rot = phase ? `R${phase} ${(C.PHASES[phase] || {}).name || ""}`.trim() : "Untracked";
      if (chartMetric === "weight") {
        const tops = entries.map(topSet).filter(Boolean);
        const t = tops.sort((a, b) => b.weightLb - a.weightLb)[0];
        if (t) series.push({ t: new Date(s.date).getTime(), y: displayValue(t.weightLb), rot });
      } else if (chartMetric === "e1rm") {
        const estimates = entries.flatMap((entry) => (entry.sets || [])
          .filter((set) => !set.isWarmup && set.status === "completed")
          .map((set) => C.epleyE1RM(set.weightLb, set.reps)));
        if (estimates.length) series.push({ t: new Date(s.date).getTime(), y: displayValue(Math.max(...estimates)), rot });
      } else {
        const v = entries.reduce((sum, entry) => sum + workingVolume(entry), 0);
        if (v > 0) series.push({ t: new Date(s.date).getTime(), y: displayValue(v), rot });
      }
    }
    ui.clear(slot);
    if (!series.length) { slot.append(ui.empty("📈", COPY.emptyHistory)); return; }
    const lift = (program?.days || []).flatMap((day) => day.lifts || []).find((item) => item.exerciseName === chartEx);
    const rawTarget = lift?.peakSingleEnabled && lift.lastPeakSingleLb > 0
      ? lift.lastPeakSingleLb + (lift.peakSingleIncrementLb || 5) : null;
    const targetY = Number.isFinite(rawTarget) ? displayValue(rawTarget) : null;
    const chartOptions = { fmtY: (v) => C.trim(v), targetY, targetLabel: "Peak target" };
    if (chartSplit) {
      const byRot = {};
      for (const p of series) (byRot[p.rot] = byRot[p.rot] || []).push(p);
      slot.append(multiLineChart(byRot, chartOptions));
    } else {
      slot.append(lineChart(series, chartOptions));
    }
    const metricLabel = chartMetric === "weight" ? "Top working weight"
      : chartMetric === "e1rm" ? "Estimated 1RM" : "Working volume";
    slot.append(ui.h("div", { class: "muted", style: { textAlign: "center", fontSize: "12px" }, text: `${metricLabel} per session (${C.primaryUnit(ui.prefs.unitDisplay)})` }));
    const records = new Map();
    for (const session of sessions) for (const entry of session.exercises || []) if (entry.exerciseName === chartEx) {
      for (const set of entry.sets || []) if (!set.isWarmup && set.status === "completed" && set.reps > 0 && set.reps <= 12) {
        records.set(set.reps, Math.max(records.get(set.reps) || 0, set.weightLb));
      }
    }
    if (records.size) slot.append(ui.h("div", { class: "section-title", text: "Rep PRs" }),
      ui.h("div", { class: "row", style: { overflowX: "auto", gap: "12px", borderBottom: "0" } },
        ...[...records].sort((a, b) => a[0] - b[0]).map(([reps, weight]) => ui.h("div", { class: "lead", style: { minWidth: "64px" } },
          ui.h("span", { class: "sub", text: `${reps} rep${reps === 1 ? "" : "s"}` }),
          ui.h("span", { class: "mono title", text: ui.fmtWeight(weight) })))));
  }
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
