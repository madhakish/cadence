// History — session log (grouped by month), progression charts, milestones.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { lineChart } from "../charts.js";
import { Sessions, Milestones, Exercises, topSet, workingVolume } from "../db.js";
import { COPY } from "../constants.js";

let mode = "log";

export async function render(host) {
  const [sessions, milestones, exercises] = await Promise.all([Sessions.completed(), Milestones.all(), Exercises.all()]);
  const root = ui.h("div");
  root.append(ui.seg([{ value: "log", label: "Log" }, { value: "charts", label: "Charts" }, { value: "milestones", label: "Milestones" }], mode, (m) => { mode = m; render(host); }));
  const panel = ui.h("div");
  root.append(panel);

  if (mode === "log") renderLog(panel, sessions);
  else if (mode === "charts") renderCharts(panel, sessions, exercises);
  else renderMilestones(panel, milestones);

  host.replaceChildren(root);
}

function setLabel(s) { return s.weightLb === 0 ? "BW" : ui.fmtWeight(s.weightLb); }

function renderLog(panel, sessions) {
  if (!sessions.length) { panel.append(ui.empty("📋", COPY.emptyHistory)); return; }
  let currentMonth = "";
  for (const s of sessions) {
    const my = ui.monthYear(s.date);
    if (my !== currentMonth) { currentMonth = my; panel.append(ui.h("div", { class: "section-title", text: my })); }
    const summary = (s.exercises || []).map((e) => { const t = topSet(e); return t ? `${e.exerciseName} ${C.trim(t.weightLb)}×${t.reps}` : e.exerciseName; }).join(" · ");
    panel.append(ui.h("div", { class: "card list", style: { margin: "6px 0" } },
      ui.h("div", { class: "row", style: { borderBottom: "0" }, onClick: () => openDetail(s) },
        ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: ui.fmtDate(s.date) }), ui.h("span", { class: "sub", text: summary || "—" })),
        ui.h("span", { class: "chev" }))));
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
            ui.h("span", { class: "wt mono" + (x.isWarmup ? " muted" : ""), text: setLabel(x) }),
            ui.h("span", { class: "sub mono", text: `× ${x.reps}${x.isPerSide ? "/side" : ""}` }),
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

let chartEx = null, chartMetric = "weight";
function renderCharts(panel, sessions, exercises) {
  const mains = exercises.filter((e) => e.category === "Main").map((e) => e.name).sort();
  if (!mains.length) { panel.append(ui.empty("📈", COPY.emptyHistory)); return; }
  if (!chartEx || !mains.includes(chartEx)) chartEx = mains[0];

  panel.append(ui.field("Exercise", (() => { const sel = ui.h("select", {}, ...mains.map((n) => ui.h("option", { value: n, text: n, selected: n === chartEx }))); sel.addEventListener("change", () => { chartEx = sel.value; renderInner(); }); return sel; })()));
  panel.append(ui.seg([{ value: "weight", label: "Working weight" }, { value: "volume", label: "Volume" }], chartMetric, (m) => { chartMetric = m; renderInner(); }));
  const slot = ui.h("div", { class: "card" });
  panel.append(slot);
  renderInner();

  function renderInner() {
    const series = [];
    for (const s of [...sessions].sort((a, b) => new Date(a.date) - new Date(b.date))) {
      const e = (s.exercises || []).find((x) => x.exerciseName === chartEx);
      if (!e) continue;
      if (chartMetric === "weight") { const t = topSet(e); if (t) series.push({ t: new Date(s.date).getTime(), y: t.weightLb }); }
      else { const v = workingVolume(e); if (v > 0) series.push({ t: new Date(s.date).getTime(), y: v }); }
    }
    ui.clear(slot);
    if (!series.length) slot.append(ui.empty("📈", COPY.emptyHistory));
    else { slot.append(lineChart(series, { fmtY: (v) => C.trim(chartMetric === "weight" ? v : v) })); slot.append(ui.h("div", { class: "muted", style: { textAlign: "center", fontSize: "12px" }, text: chartMetric === "weight" ? "Top working weight per session (lb)" : "Working volume per session (lb)" })); }
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
