// History — session log (grouped by month), progression charts, milestones.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { lineChart, multiLineChart, progressionChart, ROTATION_COLORS, ROLE_DASH,
  smallMultiples, barSeries, stackedBars, chartTable } from "../charts.js";
import { Sessions, Milestones, Exercises, Programs, Checkins, topSet, workingVolume } from "../db.js";
import { coachingReport } from "../coaching-adapter.js";

import { COPY } from "../constants.js";

let mode = "overview";

export async function render(host) {
  const [sessions, milestones, exercises, program, checkins] = await Promise.all([
    Sessions.completed(), Milestones.all(), Exercises.all(), Programs.active(), Checkins.all(),
  ]);
  const root = ui.h("div");
  root.append(ui.seg([{ value: "overview", label: "Overview" },
    { value: "rotations", label: "Rotations" }, { value: "log", label: "Log" },
    { value: "charts", label: "Charts" }, { value: "milestones", label: "Milestones" }], mode, (m) => { mode = m; render(host); }));
  const panel = ui.h("div");
  root.append(panel);

  if (mode === "overview") renderOverview(panel, sessions, exercises);
  else if (mode === "rotations") renderRotations(panel, sessions, exercises, program, checkins);
  else if (mode === "log") renderLog(panel, sessions);
  else if (mode === "charts") renderCharts(panel, sessions, exercises, program);
  else renderMilestones(panel, milestones);

  host.replaceChildren(root);
}

// The view History opens on. Three questions a lifter actually arrives with,
// each answered by the form that fits it rather than by one crowded plot:
// which lifts are moving (facets), am I turning up (counts over time), and how
// is the work feeling (a status mix). Every one ships a table twin, so no value
// here is reachable only by hovering.
function renderOverview(panel, sessions, exercises) {
  const done = [...sessions].sort((a, b) => new Date(a.date) - new Date(b.date));
  if (!done.length) { panel.append(ui.empty("\u{1F4C8}", COPY.emptyHistory)); return; }
  const displayValue = (lb) => C.primaryUnit(ui.prefs.unitDisplay) === "kg" ? C.kgFromLb(lb) : lb;
  const unit = C.primaryUnit(ui.prefs.unitDisplay) === "kg" ? " kg" : " lb";
  const mainNames = new Set(exercises.filter((e) => e.category === "Main").map((e) => e.name));

  // ---- 1. Every main lift's estimated 1RM, faceted -----------------------
  // One panel per lift, each with its own y-domain: a press and a deadlift
  // share a unit but not a range, so a shared axis would flatten the press
  // into a line at the bottom and invite a comparison that means nothing.
  const byLift = new Map();
  for (const session of done) {
    const t = new Date(session.date).getTime();
    for (const entry of session.exercises || []) {
      if (!mainNames.has(entry.exerciseName)) continue;
      const performed = (entry.sets || []).filter((set) => !set.isWarmup && set.status === "completed");
      const estimates = performed.map((set) => C.epleyE1RM(set.weightLb, set.reps)).filter((v) => v > 0);
      if (!estimates.length) continue;
      const best = Math.max(...estimates);
      const points = byLift.get(entry.exerciseName) || [];
      // One point per session per lift: the best estimate that session.
      const existing = points.find((pt) => pt.t === t);
      if (existing) existing.y = Math.max(existing.y, displayValue(best));
      else points.push({ t, y: displayValue(best) });
      byLift.set(entry.exerciseName, points);
    }
  }
  const facets = [...byLift.entries()]
    .filter(([, points]) => points.length >= 2)
    .map(([label, points]) => ({ label, points }))
    .sort((a, b) => b.points[b.points.length - 1].t - a.points[a.points.length - 1].t);

  if (facets.length) {
    panel.append(ui.h("div", { class: "section-title", text: "Estimated 1RM by lift" }));
    panel.append(smallMultiples(facets, { unit, fmtY: (v) => String(Math.round(v)) }));
    panel.append(chartTable(["Lift", "Latest", "First", "Change", "Sessions"],
      facets.map((f) => {
        const first = f.points[0].y, last = f.points[f.points.length - 1].y;
        const delta = Math.round(last - first);
        return [f.label, `${Math.round(last)}${unit}`, `${Math.round(first)}${unit}`,
          `${delta > 0 ? "+" : ""}${delta}${unit}`, String(f.points.length)];
      }), { label: `Table view \u00B7 ${facets.length} lifts` }));
  }

  // ---- 2. Sessions per week ---------------------------------------------
  // A count, so the baseline is zero and every bar is one colour.
  const weekStart = (ms) => {
    const d = new Date(ms);
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); // Monday
    return d.getTime();
  };
  const weeks = new Map();
  for (const session of done) weeks.set(weekStart(new Date(session.date).getTime()),
    (weeks.get(weekStart(new Date(session.date).getTime())) || 0) + 1);
  const weekKeys = [...weeks.keys()].sort((a, b) => a - b);
  // Fill the gaps: a week with no training is the signal, so it must be a zero
  // bar rather than a missing one that silently compresses the timeline.
  const filled = [];
  const WEEK = 7 * 24 * 60 * 60 * 1000;
  for (let k = weekKeys[0]; k <= weekKeys[weekKeys.length - 1]; k += WEEK) {
    filled.push({ t: k, y: weeks.get(k) || 0, label: ui.fmtDate(new Date(k).toISOString()) });
  }
  if (filled.length) {
    panel.append(ui.h("div", { class: "section-title", text: "Sessions per week" }));
    panel.append(barSeries(filled, { label: "Sessions per week", unit: " sessions", fmtX: (p) => p.label }));
    const trained = filled.filter((w) => w.y > 0).length;
    panel.append(ui.h("div", { class: "sub", style: { margin: "2px 4px 0" },
      text: `${done.length} sessions over ${filled.length} weeks \u00B7 trained in ${trained}` }));
    panel.append(chartTable(["Week of", "Sessions"],
      [...filled].reverse().map((w) => [w.label, String(w.y)]),
      { label: `Table view \u00B7 ${filled.length} weeks` }));
  }

  // ---- 3. How the work felt, per rotation -------------------------------
  // Status, not identity: clean / grindy / wobble is the input the
  // autoregulation runs on, so it takes the reserved status scale and always
  // carries its written label.
  const rotations = new Map();
  for (const session of done) {
    for (const entry of session.exercises || []) {
      const phase = entry.phase;
      const tag = session.programTag;
      const key = phase && tag ? `C${tag.cycleNumber} R${phase}` : "Untracked";
      const bucket = rotations.get(key) || { clean: 0, grindy: 0, wobble: 0, order: phase && tag ? tag.cycleNumber * 10 + phase : -1 };
      for (const set of entry.sets || []) {
        if (set.isWarmup || set.status !== "completed") continue;
        const quality = C.setQuality(set.flags);
        if (quality) bucket[quality] += 1;
      }
      rotations.set(key, bucket);
    }
  }
  const groups = [...rotations.entries()]
    .filter(([, b]) => b.clean + b.grindy + b.wobble > 0)
    .sort((a, b) => a[1].order - b[1].order)
    .map(([label, b]) => ({ label, parts: [
      { key: "clean", label: "clean", value: b.clean, tone: "good" },
      { key: "grindy", label: "grindy", value: b.grindy, tone: "warn" },
      { key: "wobble", label: "wobble", value: b.wobble, tone: "hard" },
    ] }));
  if (groups.length) {
    panel.append(ui.h("div", { class: "section-title", text: "Set quality by rotation" }));
    panel.append(stackedBars(groups));
    panel.append(ui.h("div", { class: "sub", style: { margin: "2px 4px 0" },
      text: "More than one grindy or wobbly working set holds the weight instead of adding it." }));
    panel.append(chartTable(["Rotation", "Clean", "Grindy", "Wobble"],
      groups.map((g) => [g.label, ...g.parts.map((p) => String(p.value))]),
      { label: `Table view \u00B7 ${groups.length} rotations` }));
  }
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

let chartEx = null, chartMetric = "weight", chartSplit = false, chartComplementary = false;
function renderCharts(panel, sessions, exercises, program) {
  const mains = exercises.filter((e) => e.category === "Main").map((e) => e.name).sort();
  if (!mains.length) { panel.append(ui.empty("📈", COPY.emptyHistory)); return; }
  if (!chartEx || !mains.includes(chartEx)) chartEx = mains[0];

  panel.append(ui.field("Exercise", (() => { const sel = ui.h("select", {}, ...mains.map((n) => ui.h("option", { value: n, text: n, selected: n === chartEx }))); sel.addEventListener("change", () => { chartEx = sel.value; renderInner(); }); return sel; })()));
  panel.append(ui.seg([{ value: "weight", label: "Working weight" }, { value: "e1rm", label: "Est. 1RM" },
    { value: "volume", label: "Volume" }, { value: "all", label: "All three" }],
  chartMetric, (m) => { chartMetric = m; renderInner(); }));
  // Main only by default — that alone removes the main/complementary sawtooth.
  panel.append(ui.h("div", { class: "row", style: { padding: "8px 4px" } },
    ui.h("span", { class: "sub", text: "Show complementary" }),
    ui.toggle(chartComplementary, (v) => { chartComplementary = v; renderInner(); })));
  // One line per rotation: compare this cycle's R1 against last cycle's R1
  // instead of reading a sawtooth.
  panel.append(ui.h("div", { class: "row", style: { padding: "8px 4px" } },
    ui.h("span", { class: "sub", text: "Split by rotation" }),
    ui.toggle(chartSplit, (v) => { chartSplit = v; renderInner(); })));
  const slot = ui.h("div", { class: "card" });
  panel.append(slot);
  renderInner();

  function renderInner() {
    const displayValue = (lb) => C.primaryUnit(ui.prefs.unitDisplay) === "kg" ? C.kgFromLb(lb) : lb;
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
        // The point's rotation (R1–R4) for the split view; sessions logged
        // outside a cycle bucket read as "Untracked".
        const phase = entries.find((entry) => entry.phase)?.phase;
        const rot = phase ? `R${phase} ${(C.PHASES[phase] || {}).name || ""}`.trim() : "Untracked";
        const performed = entries.flatMap((entry) => (entry.sets || [])
          .filter((set) => !set.isWarmup && set.status === "completed"));
        const top = entries.map(topSet).filter(Boolean).sort((a, b) => b.weightLb - a.weightLb)[0];
        const estimates = performed.map((set) => C.epleyE1RM(set.weightLb, set.reps));
        rows.push({
          t: new Date(s.date).getTime(), role, rot,
          weight: top ? displayValue(top.weightLb) : null,
          e1rm: estimates.length ? displayValue(Math.max(...estimates)) : null,
          volume: entries.reduce((sum, entry) => sum + workingVolume(entry), 0) || null,
        });
      }
    }
    let roles = chartComplementary ? ["main", "complementary"] : ["main"];
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
      .map((r) => ({ t: r.t, y: r[metric], rot: r.rot }));
    // "Volume" alone keeps a plain line; in the combined view it becomes the
    // background bars so the two comparable load metrics own the axis.
    const series = chartMetric === "all" ? pick("weight", "main") : pick(chartMetric === "volume" ? "volume" : chartMetric, "main");

    ui.clear(slot);
    if (!visible.length) { slot.append(ui.empty("📈", COPY.emptyHistory)); return; }
    const lift = (program?.days || []).flatMap((day) => day.lifts || []).find((item) => item.exerciseName === chartEx);
    const rawTarget = lift?.peakSingleEnabled && lift.lastPeakSingleLb > 0
      ? lift.lastPeakSingleLb + (lift.peakSingleIncrementLb || 5) : null;
    const targetY = Number.isFinite(rawTarget) ? displayValue(rawTarget) : null;
    const chartOptions = { fmtY: (v) => C.trim(v), targetY, targetLabel: "Peak target" };
    const unit = C.primaryUnit(ui.prefs.unitDisplay);
    const metricLabel = chartMetric === "weight" ? "Top working weight"
      : chartMetric === "e1rm" ? "Estimated 1RM"
        : chartMetric === "volume" ? "Working volume" : "Working weight, est. 1RM, and volume";
    const roleNote = chartComplementary ? " · solid = main, dashed = complementary" : " · main slots only";
    if (chartSplit) {
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
      slot.append(progressionChart({ ...chartOptions, lines,
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
      }
      // Combined view: tonnage recedes to bars on its own right-hand scale so
      // the two same-unit load lines keep the weight axis to themselves.
      const bars = chartMetric === "all"
        ? { label: "Volume", color: "#8B9196", points: pick("volume", "main") } : null;
      slot.append(progressionChart({ ...chartOptions, lines, bars,
        caption: `${metricLabel} per session (${unit})${roleNote}` }));
    }
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
