// Tiny DOM toolkit + shared UI: hyperscript, formatting, icons, sheets,
// full-screen overlays, segmented controls, steppers, toggles, toasts.
import * as C from "./core.js";

// Live display preference, kept in sync by app.js after settings load.
export const prefs = { unitDisplay: "lbPrimary" };

// Navigation hub — app.js fills these in; views call them without importing
// app.js (avoids an import cycle).
export const nav = {
  go: () => {},          // go(tabId)
  refresh: () => {},     // re-render current tab
  openPlates: () => {},  // plate calculator
  openSession: () => {}, // openSession(id)
};

// ---- hyperscript ----
export function h(tag, props = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === "class" || k === "className") el.className = v;
    else if (k === "text") el.textContent = v;
    else if (k === "html") el.innerHTML = v;
    else if (k === "dataset") Object.assign(el.dataset, v);
    else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
    else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k in el && k !== "list") { try { el[k] = v; } catch { el.setAttribute(k, v); } }
    else el.setAttribute(k, v);
  }
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return el;
}
export const clear = (node) => { while (node.firstChild) node.removeChild(node.firstChild); return node; };
export const mount = (node, ...kids) => { clear(node); for (const k of kids.flat()) if (k != null && k !== false) node.append(k.nodeType ? k : document.createTextNode(String(k))); return node; };

// ---- formatting ----
export const fmtWeight = (lb) => C.unitFormat(prefs.unitDisplay, lb);
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const dd = (d) => (d instanceof Date ? d : new Date(d));
export const fmtDate = (d) => { const x = dd(d); return `${MONTHS[x.getMonth()]} ${x.getDate()}, ${x.getFullYear()}`; };
export const fmtLong = (d) => { const x = dd(d); return `${MONTHS[x.getMonth()]} ${x.getDate()}, ${x.getFullYear()}`; };
export const monthYear = (d) => { const x = dd(d); return `${MONTHS[x.getMonth()]} ${x.getFullYear()}`; };
export const mmss = (sec) => { sec = Math.max(0, Math.round(sec)); return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}`; };

// ---- icons (inline SVG) ----
const ICONS = {
  today: '<rect x="2" y="9" width="3" height="6" rx="1"/><rect x="5" y="7" width="2.5" height="10" rx="1"/><rect x="7.3" y="10.8" width="9.4" height="2.4" rx="1"/><rect x="16.5" y="7" width="2.5" height="10" rx="1"/><rect x="19" y="9" width="3" height="6" rx="1"/>',
  program: '<rect x="4" y="3" width="16" height="18" rx="2" fill="none" stroke="currentColor" stroke-width="2"/><line x1="8" y1="8" x2="17" y2="8" stroke="currentColor" stroke-width="2"/><line x1="8" y1="12" x2="17" y2="12" stroke="currentColor" stroke-width="2"/><line x1="8" y1="16" x2="14" y2="16" stroke="currentColor" stroke-width="2"/>',
  history: '<rect x="3" y="4.5" width="18" height="16" rx="2.5" fill="none" stroke="currentColor" stroke-width="2"/><line x1="3" y1="9" x2="21" y2="9" stroke="currentColor" stroke-width="2"/><line x1="8" y1="2.5" x2="8" y2="6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="16" y1="2.5" x2="16" y2="6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  body: '<rect x="3.5" y="4.5" width="17" height="15" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 7.6 L14 11.4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="12.4" r="1.5"/>',
  signals: '<path d="M13 2 L4 14 h5.5 l-1 8 9.5-12 H12 z"/>',
  settings: '<path d="M19.4 13a7.6 7.6 0 000-2l1.8-1.4-1.9-3.3-2.2.9a7.3 7.3 0 00-1.7-1l-.3-2.3H10.9l-.3 2.3a7.3 7.3 0 00-1.7 1l-2.2-.9L4.8 9.6 6.6 11a7.6 7.6 0 000 2l-1.8 1.4 1.9 3.3 2.2-.9a7.3 7.3 0 001.7 1l.3 2.3h2.2l.3-2.3a7.3 7.3 0 001.7-1l2.2.9 1.9-3.3zM12 15a3 3 0 110-6 3 3 0 010 6z"/>',
  plates: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2.4"/><circle cx="12" cy="12" r="3.2"/><rect x="11" y="1.6" width="2" height="3.6" rx="1"/><rect x="11" y="18.8" width="2" height="3.6" rx="1"/>',
};
export function icon(name) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.innerHTML = ICONS[name] || "";
  return svg;
}

// ---- overlays (full-screen pushed screens) ----
const overlays = () => document.getElementById("overlays");
export function pushScreen({ title, build, actions = [] }) {
  const body = h("div", { class: "overlay-body" });
  const back = h("button", { class: "btn ghost sm", text: "‹ Back", onClick: () => close() });
  const head = h("div", { class: "overlay-head" }, back, h("h2", { text: title || "" }), h("div", { class: "btn-row" }, ...actions));
  const el = h("div", { class: "overlay" }, head, body);
  overlays().append(el);
  const api = { el, body, close, setTitle: (t) => { head.querySelector("h2").textContent = t; } };
  function close() { el.remove(); }
  if (build) build(body, api);
  return api;
}

// ---- bottom sheets ----
export function sheet({ title, build, onClose }) {
  const content = h("div", { class: "sheet" }, h("div", { class: "grip" }), title ? h("h2", { text: title }) : null);
  const scrim = h("div", { class: "scrim", onClick: (e) => { if (e.target === scrim) close(); } }, content);
  overlays().append(scrim);
  const api = { el: content, close };
  function close() { scrim.remove(); onClose?.(); }
  if (build) build(content, api);
  return api;
}

export function actionSheet(title, options) {
  // options: [{ label, role?: 'danger', onClick }]
  return sheet({
    title,
    build: (c, api) => {
      for (const o of options) {
        c.append(h("button", {
          class: "btn wide" + (o.role === "danger" ? " danger" : "") + (o.role === "primary" ? " primary" : ""),
          style: { marginTop: "8px" }, text: o.label,
          onClick: () => { api.close(); o.onClick && o.onClick(); },
        }));
      }
      c.append(h("button", { class: "btn wide ghost", style: { marginTop: "12px" }, text: "Cancel", onClick: () => api.close() }));
    },
  });
}

export function toast(msg) {
  const t = document.getElementById("toast");
  t.textContent = msg; t.classList.add("show");
  clearTimeout(t._timer); t._timer = setTimeout(() => t.classList.remove("show"), 1800);
}

// ---- controls ----
export function seg(options, value, onChange) {
  // options: [{ value, label }] or [value...]
  const opts = options.map((o) => (typeof o === "object" ? o : { value: o, label: o }));
  const wrap = h("div", { class: "seg" });
  const render = (val) => {
    clear(wrap);
    for (const o of opts) {
      wrap.append(h("button", {
        class: o.value === val ? "on" : "", text: o.label,
        onClick: () => { render(o.value); onChange(o.value); },
      }));
    }
  };
  render(value);
  return wrap;
}

export function stepper(value, { min = -Infinity, max = Infinity, step = 1, format = (v) => String(v), onChange = () => {} } = {}) {
  let v = value;
  const label = h("span", { class: "mono", style: { minWidth: "70px", textAlign: "center" }, text: format(v) });
  const set = (nv) => { v = Math.min(max, Math.max(min, nv)); label.textContent = format(v); onChange(v); };
  return h("div", { class: "stepper" },
    h("button", { text: "−", onClick: () => set(Math.round((v - step) * 1000) / 1000) }),
    label,
    h("button", { text: "+", onClick: () => set(Math.round((v + step) * 1000) / 1000) }),
  );
}

export function toggle(value, onChange) {
  const b = h("button", { class: "toggle" + (value ? " on" : "") , type: "button" });
  b.addEventListener("click", () => { const nv = !b.classList.contains("on"); b.classList.toggle("on", nv); onChange(nv); });
  return b;
}

export function field(labelText, control) {
  return h("label", { class: "field" }, labelText, control);
}

export const empty = (glyph, text) => h("div", { class: "empty" }, h("span", { class: "glyph", text: glyph }), text);

// download helper (export files)
export function download(filename, text, type = "application/json") {
  const blob = new Blob([text], { type });
  const url = URL.createObjectURL(blob);
  const a = h("a", { href: url, download: filename });
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// ---- Theme ----
export const THEMES = [
  { value: "memento", label: "Memento" },
  { value: "carbon", label: "Carbon" },
  { value: "slate", label: "Slate" },
  { value: "system", label: "System" },
];
// Apply a theme by name: set [data-theme] on <html> and sync the PWA
// status-bar colour to the theme's ground. Unknown/corrupt values fall back
// to carbon so the app state and the Settings segment stay consistent.
export function applyTheme(name) {
  document.documentElement.dataset.theme = THEMES.some((t) => t.value === name) ? name : "carbon";
  const bg = getComputedStyle(document.documentElement).getPropertyValue("--bg").trim();
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta && bg) meta.setAttribute("content", bg);
}

// ---- Rotation-position glyph ----
// Where the program is in its rotation — four equal ticks with the current one
// lit. Mirrors the native RotationGlyph (Cadence/Views/Glyphs.swift).
//
// This replaced a rising-bar "wave" glyph that drew Volume / Load / Peak as
// climbing and recovery as a drop. That shape is a claim about the
// prescription, and the program-level indicator is shared by slots that have
// nothing to do with each other's: a novice linearFives slot and a 5/3/1 slot
// sit under the same counter and neither one waves. Position is the only thing
// this indicator actually knows, so it is the only thing it draws.
export function rotation(week) {
  // Clamp once, then use it for BOTH the lit tick and the label. rotationLabel
  // clamps internally, so reading `week` raw for the highlight let a corrupt or
  // hand-edited pointer announce "Rotation 1 of 4" while no tick was lit — the
  // sighted and the spoken interface disagreeing about the same value.
  const current = Number.isFinite(week) ? Math.min(Math.max(week, 1), C.DELOAD_WEEK) : 1;
  const label = C.rotationLabel(current);
  const el = h("span", { class: "rotation", title: label, role: "img", "aria-label": label });
  for (let i = 1; i <= C.DELOAD_WEEK; i += 1) {
    const tick = h("i");
    if (i === current) tick.classList.add("on");
    el.append(tick);
  }
  return el;
}

// What a program slot actually does — "Main · 5/3/1", "Complementary ·
// Secondary volume" — plus the current phase, but ONLY where the phase
// vocabulary describes the slot's prescription. Both strings come from shared
// core, so native and web cannot label the same slot differently.
// Mirrors the native SlotPrescriptionBadge (Cadence/Views/Glyphs.swift).
export function slotBadge(lift, rotationWeek, movementGroup = null, focus = "strength") {
  const role = lift.role || "main";
  const style = lift.prescription || "automatic";
  const badge = C.slotBadge(role, style, movementGroup, focus);
  const phase = C.slotPhaseLabel(rotationWeek, role, style, movementGroup, focus);
  const el = h("span", { class: "slot-badge" }, h("span", { class: "sub", text: badge }));
  if (phase) el.append(h("span", { class: "sub accent", text: phase }));
  return el;
}

// Sessions persist the phase for schedule/history reconstruction, even when a
// slot's prescription does not use phase names. Render that stored value only
// when the captured prescription style says the label is truthful. Old rows
// without a captured style keep their legacy label because they cannot be
// classified safely after the fact.
export function sessionPhaseLabel(entry, exercise) {
  if (!entry?.phase) return null;
  const style = entry.prescriptionStyle || entry.prescriptionStyleRaw;
  if (!style) return C.phaseLabel(entry.phase);
  return C.slotPhaseLabel(
    entry.phase, entry.programRole || "main", style,
    exercise?.movementGroup ?? null, "strength",
  );
}

const BLOCK_LABELS = {
  warmup: "warm-up", primer: "primer", topSingle: "top single", ramp: "ramp",
  work: "work", amrap: "+ set", backoff: "back-off", conditioning: "conditioning",
};

// The next four exposures a program slot will actually produce.
//
// The editor is a wall of pickers and steppers: it tells you what values were
// entered, never what they produce. A lifter setting a 190 lb base cannot see
// that it yields a 225 lb peak triple while 188 yields 220 — a whole plate step
// decided by which side of a rounding boundary the multiplication lands on.
//
// Every number comes from C.exposurePreview, which runs the shipped engine
// forward; there is no second implementation that could disagree with the
// session the lifter eventually starts. It costs no persisted state.
// Mirrors the native ExposurePreviewView (Cadence/Views/ExposurePreviewView.swift).
export function exposurePreview(lift, program, exercise, count = 4, schedule = null) {
  const movementGroup = exercise?.movementGroup ?? null;
  const style = C.resolvedPrescriptionStyle(lift.prescription || "automatic",
    movementGroup, lift.role || "main", program.focus);
  // The slot's own banked-but-unapplied grade, if a peak has already been
  // graded this cycle. Without it the next-cycle entries preview the old base.
  //
  // This client stores it as `lift.pending = { state, note }`; the native slot
  // spreads the same values across `pendingBaseWeightLb` and friends. Reading
  // the native field names here made the seeding silently dead on web and left
  // the two clients previewing different next-cycle bases for the same slot.
  const pendingState = lift.pending?.state ? { ...lift.pending.state } : null;
  const entries = C.exposurePreview({
    count,
    baseWeightLb: lift.baseWeightLb,
    estimatedMaxLb: lift.estimatedMaxLb ?? 0,
    stallCount: lift.stallCount ?? 0,
    cycleNumber: program.cycleNumber ?? 1,
    rotation: program.currentWeek ?? 1,
    programRoundingLb: program.roundingLb,
    exerciseType: exercise?.type ?? null,
    movementGroup,
    role: lift.role || "main",
    focus: program.focus,
    prescriptionStyle: lift.prescription || "automatic",
    configuration: { ...lift, workingSets: lift.doubleProgressionSets ?? 3 },
    pendingState,
    schedule,
  });

  const card = h("div", { class: "card sub" },
    h("div", { class: "section-title", text: `Next ${count} exposures` }));
  for (const entry of entries) {
    const work = entry.prescription.mainWork;
    const mainWorkIsAMRAP = entry.prescription.blocks.some((b) => b.kind === "amrap"
      && Math.abs(b.weightLb - work.weightLb) < 0.001
      && b.sets === work.sets && b.reps === work.reps);
    // Phase-independent styles are numbered exposures, not phases — labelling a
    // linearFives session "Peak" would assert something the engine does not do.
    const lead = entry.phaseName || `Session ${entry.exposureNumber}`;
    const row = h("div", { class: "row", style: { borderBottom: "0", padding: "3px 0", display: "block" } },
      h("div", { style: { display: "flex", gap: "8px", alignItems: "baseline" } },
        h("span", { class: entry.isRecovery ? "sub warn" : "sub", text: lead, style: { minWidth: "92px" } }),
        h("span", { class: "mono", text: fmtWeight(work.weightLb) }),
        h("span", { class: "sub mono", text: `${work.sets}×${work.reps}` }),
        mainWorkIsAMRAP ? h("span", { class: "sub warn", text: "+ set" }) : null));
    // Ramps, primers, top singles and the "+" set are real prescribed work. A
    // preview showing only the top line would hide most of a 5/3/1 session.
    let removedMainBlock = false;
    const extras = entry.prescription.blocks.filter((b) => {
      if (b.kind === "work") return false;
      if (!removedMainBlock && Math.abs(b.weightLb - work.weightLb) < 0.001
          && b.sets === work.sets && b.reps === work.reps) {
        removedMainBlock = true;
        return false;
      }
      return true;
    });
    if (extras.length) {
      row.append(h("div", { class: "sub mono", style: { opacity: "0.7" },
        text: extras.map((b) => `${BLOCK_LABELS[b.kind] || b.kind} ${fmtWeight(b.weightLb)} ${b.sets}×${b.reps}`).join(" · ") }));
    }
    if (entry.advanceNote) row.append(h("div", { class: "sub", text: entry.advanceNote }));
    card.append(row);
  }
  // A 5/3/1 slot's base is a training max, not a working weight, and saying so
  // is the difference between a preview that explains the prescription and one
  // that looks wrong.
  card.append(h("div", { class: "sub", style: { opacity: "0.7", paddingTop: "4px" },
    text: `${style === "fiveThreeOne" ? "Training max" : "Base"} ${fmtWeight(lift.baseWeightLb)}`
      + " · assumes each session is completed as prescribed." }));
  return card;
}

// Tiny inline sparkline (SVG polyline) for progress-at-a-glance rows; strokes
// with currentColor and dots the latest value.
export function spark(values, { width = 132, height = 30, pad = 3 } = {}) {
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.setAttribute("width", width); svg.setAttribute("height", height);
  svg.setAttribute("class", "spark");
  if (values.length < 2) return svg;
  const min = Math.min(...values), max = Math.max(...values);
  const x = (i) => pad + (i * (width - 2 * pad)) / (values.length - 1);
  const y = (v) => max === min ? height / 2 : height - pad - ((v - min) * (height - 2 * pad)) / (max - min);
  const line = document.createElementNS(NS, "polyline");
  line.setAttribute("points", values.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" "));
  line.setAttribute("fill", "none");
  line.setAttribute("stroke", "currentColor");
  line.setAttribute("stroke-width", "1.6");
  const dot = document.createElementNS(NS, "circle");
  dot.setAttribute("cx", x(values.length - 1).toFixed(1));
  dot.setAttribute("cy", y(values[values.length - 1]).toFixed(1));
  dot.setAttribute("r", "2.2");
  dot.setAttribute("fill", "currentColor");
  svg.append(line, dot);
  return svg;
}
