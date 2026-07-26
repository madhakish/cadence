// Minimal SVG line chart — no dependencies. Used for progression and
// bodyweight trends. Y-domain tracks the data (not forced to zero), matching
// the native Swift Charts behaviour.
const NS = "http://www.w3.org/2000/svg";
const el = (name, attrs = {}, text) => {
  const n = document.createElementNS(NS, name);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
  if (text != null) n.textContent = text;
  return n;
};
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const tick = (t) => { const d = new Date(t); return `${MONTHS[d.getMonth()]} ${d.getDate()}`; };

// series: [{ t:number(ms), y:number, ann?:string }] — assumed sorted by t.
export function lineChart(series, { height = 200, fmtY = (v) => String(Math.round(v)), targetY = null, targetLabel = "Target" } = {}) {
  const W = 340, H = height, padL = 40, padR = 14, padT = 16, padB = 24;
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, role: "img" });
  if (!series.length) return svg;

  const n = series.length;
  const ys = series.map((p) => p.y);
  if (Number.isFinite(targetY)) ys.push(targetY);
  let ymin = Math.min(...ys), ymax = Math.max(...ys);
  if (ymin === ymax) { ymin -= 1; ymax += 1; }
  const padY = (ymax - ymin) * 0.12;
  ymin -= padY; ymax += padY;

  const xAt = (i) => padL + (W - padL - padR) * (n > 1 ? i / (n - 1) : 0.5);
  const yAt = (v) => padT + (H - padT - padB) * (1 - (v - ymin) / (ymax - ymin));

  // y grid + labels (min / mid / max)
  for (const v of [ymin + padY, (ymin + ymax) / 2, ymax - padY]) {
    const y = yAt(v);
    svg.append(el("line", { class: "axis", x1: padL, y1: y, x2: W - padR, y2: y, opacity: 0.5 }));
    svg.append(el("text", { class: "lbl", x: 4, y: y + 3 }, fmtY(v)));
  }

  if (Number.isFinite(targetY)) {
    const y = yAt(targetY);
    svg.append(el("line", { class: "target-line", x1: padL, y1: y, x2: W - padR, y2: y,
      style: "stroke:var(--accent);stroke-dasharray:5 4;opacity:.8" }));
    svg.append(el("text", { class: "ann", x: W - padR, y: y - 5, "text-anchor": "end" }, `${targetLabel} ${fmtY(targetY)}`));
  }

  // line path
  const d = series.map((p, i) => `${i ? "L" : "M"}${xAt(i).toFixed(1)} ${yAt(p.y).toFixed(1)}`).join(" ");
  svg.append(el("path", { class: "line", d }));

  // dots + annotations
  series.forEach((p, i) => {
    svg.append(el("circle", { class: "dot", cx: xAt(i), cy: yAt(p.y), r: n > 30 ? 1.6 : 3 }));
    if (p.ann) svg.append(el("text", { class: "ann", x: xAt(i), y: yAt(p.y) - 7, "text-anchor": "middle" }, p.ann));
  });

  // x labels: first & last
  svg.append(el("text", { class: "lbl", x: padL, y: H - 6 }, tick(series[0].t)));
  if (n > 1) svg.append(el("text", { class: "lbl", x: W - padR, y: H - 6, "text-anchor": "end" }, tick(series[n - 1].t)));
  return svg;
}

// Rotation → line colour. Rotations are ORDINAL, not nominal: R1 Volume → R2
// Load → R3 Peak is escalating intensity, so swapping them would change the
// meaning. That makes this a one-hue ramp with monotone lightness rather than a
// set of unrelated hues — the reader sees the sequence in the colour.
//
// It used to be green → yellow → red → grey, which was wrong twice over. Those
// are literally the app's --good/--warn/--hard status tokens, so "Peak" was
// painted the same red that means a hard stop in the logger; and R1 vs R3 sat at
// ΔE 5.8 under deuteranopia — below the ΔE 6 floor, i.e. unresolvable for ~8% of
// men, with no secondary encoding between two solid same-role lines.
//
// The ramp is a THEME token, not a constant, because the app ships a light theme
// as well as three dark ones and an ordinal ramp has to run the other way on a
// light surface. Measured per mode: the dark ramp's bright end is 4.09:1 on
// #0a0908 but only 1.60:1 on #f5f5f7 — a hard fail — so `system` gets its own
// inverted steps. Both directions pass the ordinal checks (monotone L, ΔL gaps
// ≥ 0.06, light end clears the surface, hue spread ≤ 5°); the dark ramp measures
// 12.2 all-pairs against the old 5.8. Values live in web/app/styles.css.
//
// Adjacent ramp steps are close BY DESIGN — that is what makes the order
// legible — so rotation identity never rests on colour alone: the legend and the
// per-rotation section headings name each one, and the table view carries values.
//
// ROTATION_RAMP is the documented instance the tests validate; ROTATION_COLORS
// is what the charts draw with. Mirrored in Cadence/Views/HistoryView.swift.
export const ROTATION_RAMP = {
  // dim → bright as intensity climbs, on a near-black surface
  dark: ["#96762f", "#c39a44", "#e8c67e", "#8fa0ad", "#676f76"],
  // light → dark as intensity climbs, on a near-white surface
  light: ["#cfa94f", "#9c7526", "#634c14", "#5f7080", "#8a9199"],
};

export const ROTATION_COLORS = {
  "R1 Volume": "var(--rot-1)", "R2 Load": "var(--rot-2)", "R3 Peak": "var(--rot-3)",
  // Out of ramp on purpose: a deload is a reset rather than a fourth intensity
  // step, and untracked work has no phase at all. Cool grey separates both from
  // the brass ramp by hue, not just lightness.
  "R4 Deload": "var(--rot-4)", "Untracked": "var(--rot-5)",
};

// Role → line style. A lift can occupy a MAIN slot on one day and a
// COMPLEMENTARY slot on another at a different base, so plotting both as one
// line produced a sawtooth between two unrelated progressions. Main stays
// solid and dominant; complementary is dashed and lighter, so the two read as
// foreground and background rather than competing for the same eye.
export const ROLE_DASH = { main: null, complementary: "5 4" };

// The progression chart: optional volume BARS on their own right-hand scale,
// with load lines drawn in front on the real weight axis.
//
// Weight and estimated 1RM share a unit, so they belong on one axis and the
// gap between them is itself the signal — an e1RM climbing while the top set
// stays flat means the reps are improving. Volume is a different quantity
// entirely and two orders of magnitude larger, so it gets its own scale and a
// recessive mark: bars behind, never a third line competing with the two that
// are genuinely comparable.
//
// lines: [{ key, label, color, dash, points: [{ t, y }] }]
// bars:  { label, points: [{ t, y }], color }   (optional)
export function progressionChart({
  lines = [], bars = null, height = 220, fmtY = (v) => String(Math.round(v)),
  fmtBar = (v) => String(Math.round(v)), targetY = null, targetLabel = "Target",
  caption = null,
} = {}) {
  const W = 340, H = height, padL = 40, padT = 16, padB = 26;
  const padR = bars ? 42 : 14;
  const wrap = document.createElement("div");
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, role: "img" });
  wrap.append(svg);

  const drawn = lines.filter((l) => l.points && l.points.length);
  const barPoints = bars?.points?.filter((p) => Number.isFinite(p.y)) || [];
  const everyPoint = [...drawn.flatMap((l) => l.points), ...barPoints];
  if (!everyPoint.length) return wrap;

  const tmin = Math.min(...everyPoint.map((p) => p.t));
  const tmax = Math.max(...everyPoint.map((p) => p.t));
  const xAt = (t) => padL + (W - padL - padR) * (tmax > tmin ? (t - tmin) / (tmax - tmin) : 0.5);

  // Load axis spans only the load lines; volume must never stretch it.
  const loadValues = drawn.flatMap((l) => l.points.map((p) => p.y));
  if (Number.isFinite(targetY)) loadValues.push(targetY);
  let ymin = loadValues.length ? Math.min(...loadValues) : 0;
  let ymax = loadValues.length ? Math.max(...loadValues) : 1;
  if (ymin === ymax) { ymin -= 1; ymax += 1; }
  const padY = (ymax - ymin) * 0.12;
  ymin -= padY; ymax += padY;
  const yAt = (v) => padT + (H - padT - padB) * (1 - (v - ymin) / (ymax - ymin));

  // Volume bars sit on their own floor-at-zero scale — tonnage is a magnitude,
  // so a non-zero baseline would exaggerate small differences.
  const barMax = barPoints.length ? Math.max(...barPoints.map((p) => p.y)) : 0;
  const baseline = H - padB;
  if (barPoints.length && barMax > 0) {
    const span = Math.max(6, (W - padL - padR) / Math.max(barPoints.length, 1) * 0.55);
    for (const p of barPoints) {
      const h = (H - padT - padB) * (p.y / barMax) * 0.82;
      svg.append(el("rect", {
        class: "vol-bar", x: (xAt(p.t) - span / 2).toFixed(1), y: (baseline - h).toFixed(1),
        width: span.toFixed(1), height: Math.max(0, h).toFixed(1), rx: 1.5,
        style: `fill:${bars.color || "var(--accent)"}`,
      }));
    }
    for (const [frac, v] of [[0, 0], [1, barMax]]) {
      svg.append(el("text", { class: "lbl", x: W - padR + 4, y: baseline - (H - padT - padB) * frac * 0.82 + 3 },
        fmtBar(v)));
    }
  }

  for (const v of [ymin + padY, (ymin + ymax) / 2, ymax - padY]) {
    const y = yAt(v);
    svg.append(el("line", { class: "axis", x1: padL, y1: y, x2: W - padR, y2: y, opacity: 0.45 }));
    svg.append(el("text", { class: "lbl", x: 4, y: y + 3 }, fmtY(v)));
  }
  if (Number.isFinite(targetY)) {
    const y = yAt(targetY);
    svg.append(el("line", { class: "target-line", x1: padL, y1: y, x2: W - padR, y2: y,
      style: "stroke:var(--accent);stroke-dasharray:5 4;opacity:.8" }));
    svg.append(el("text", { class: "ann", x: W - padR, y: y - 5, "text-anchor": "end" }, `${targetLabel} ${fmtY(targetY)}`));
  }

  for (const line of drawn) {
    const pts = [...line.points].sort((a, b) => a.t - b.t);
    const d = pts.map((p, i) => `${i ? "L" : "M"}${xAt(p.t).toFixed(1)} ${yAt(p.y).toFixed(1)}`).join(" ");
    const stroke = line.color || "var(--accent)";
    svg.append(el("path", {
      class: "line", d,
      style: `stroke:${stroke}${line.dash ? `;stroke-dasharray:${line.dash}` : ""}`,
    }));
    for (const p of pts) {
      svg.append(el("circle", { class: "dot", cx: xAt(p.t), cy: yAt(p.y), r: pts.length > 30 ? 1.6 : 2.6, style: `fill:${stroke}` }));
    }
  }

  svg.append(el("text", { class: "lbl", x: padL, y: H - 6 }, tick(tmin)));
  if (tmax > tmin) svg.append(el("text", { class: "lbl", x: W - padR, y: H - 6, "text-anchor": "end" }, tick(tmax)));

  const legendItems = [...drawn.map((l) => ({ label: l.label || l.key, color: l.color, dash: l.dash })),
    ...(barPoints.length ? [{ label: bars.label || "Volume", color: bars.color, bar: true }] : [])];
  if (legendItems.length > 1) {
    const legend = document.createElement("div");
    legend.className = "chart-legend";
    for (const item of legendItems) {
      const span = document.createElement("span");
      const swatch = document.createElement("i");
      swatch.style.background = item.color || "var(--accent)";
      if (item.bar) { swatch.style.height = "8px"; swatch.style.width = "6px"; swatch.style.opacity = ".55"; }
      else if (item.dash) { swatch.style.background = "none"; swatch.style.borderTop = `3px dashed ${item.color}`; }
      span.append(swatch, document.createTextNode(item.label));
      legend.append(span);
    }
    wrap.append(legend);
  }
  if (caption) {
    const note = document.createElement("div");
    note.className = "muted";
    note.style.textAlign = "center";
    note.style.fontSize = "12px";
    note.textContent = caption;
    wrap.append(note);
  }
  return wrap;
}

// Tiny trend line — no axes, just the shape of the last few sessions.
// Mirrors the native Sparkline (Cadence/Views/Glyphs.swift).
export function sparkline(values, { width = 64, height = 20 } = {}) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.setAttribute("width", width); svg.setAttribute("height", height);
  svg.classList.add("spark");
  if (values.length < 2) return svg;
  const min = Math.min(...values), max = Math.max(...values);
  const y = (v) => (max === min ? height / 2 : height - 2 - ((v - min) / (max - min)) * (height - 4));
  const x = (i) => 1 + (i / (values.length - 1)) * (width - 4);
  const pts = values.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ");
  const line = document.createElementNS("http://www.w3.org/2000/svg", "polyline");
  line.setAttribute("points", pts);
  line.setAttribute("fill", "none");
  line.setAttribute("stroke", "var(--accent)");
  line.setAttribute("stroke-width", "2");
  line.setAttribute("stroke-linejoin", "round");
  line.setAttribute("stroke-linecap", "round");
  svg.append(line);
  const dot = document.createElementNS("http://www.w3.org/2000/svg", "circle");
  dot.setAttribute("cx", x(values.length - 1).toFixed(1));
  dot.setAttribute("cy", y(values[values.length - 1]).toFixed(1));
  dot.setAttribute("r", "2.4");
  dot.setAttribute("fill", "var(--accent)");
  svg.append(dot);
  return svg;
}

// Multi-series line chart: one line per key (time-positioned x, shared y
// scale) + an HTML legend. Used by the rotation-split progression view —
// compare this cycle's R1 against last cycle's R1 instead of reading a
// sawtooth. Mirrors the native splitByRotation chart.
export function multiLineChart(seriesByKey, { height = 200, fmtY = (v) => String(Math.round(v)), colors = ROTATION_COLORS,
  targetY = null, targetLabel = "Target" } = {}) {
  const W = 340, H = height, padL = 40, padR = 14, padT = 16, padB = 24;
  const wrap = document.createElement("div");
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, role: "img" });
  wrap.append(svg);
  const keys = Object.keys(seriesByKey).filter((k) => seriesByKey[k].length);
  const all = keys.flatMap((k) => seriesByKey[k]);
  if (!all.length) return wrap;

  const values = all.map((p) => p.y);
  if (Number.isFinite(targetY)) values.push(targetY);
  let ymin = Math.min(...values), ymax = Math.max(...values);
  if (ymin === ymax) { ymin -= 1; ymax += 1; }
  const padY = (ymax - ymin) * 0.12;
  ymin -= padY; ymax += padY;
  const tmin = Math.min(...all.map((p) => p.t)), tmax = Math.max(...all.map((p) => p.t));
  const xAt = (t) => padL + (W - padL - padR) * (tmax > tmin ? (t - tmin) / (tmax - tmin) : 0.5);
  const yAt = (v) => padT + (H - padT - padB) * (1 - (v - ymin) / (ymax - ymin));

  for (const v of [ymin + padY, (ymin + ymax) / 2, ymax - padY]) {
    const y = yAt(v);
    svg.append(el("line", { class: "axis", x1: padL, y1: y, x2: W - padR, y2: y, opacity: 0.5 }));
    svg.append(el("text", { class: "lbl", x: 4, y: y + 3 }, fmtY(v)));
  }
  if (Number.isFinite(targetY)) {
    const y = yAt(targetY);
    svg.append(el("line", { class: "target-line", x1: padL, y1: y, x2: W - padR, y2: y,
      style: "stroke:var(--accent);stroke-dasharray:5 4;opacity:.8" }));
    svg.append(el("text", { class: "ann", x: W - padR, y: y - 5, "text-anchor": "end" }, `${targetLabel} ${fmtY(targetY)}`));
  }
  for (const k of keys) {
    const color = colors[k] || "#888";
    const pts = [...seriesByKey[k]].sort((a, b) => a.t - b.t);
    const d = pts.map((p, i) => `${i ? "L" : "M"}${xAt(p.t).toFixed(1)} ${yAt(p.y).toFixed(1)}`).join(" ");
    svg.append(el("path", { class: "line", d, style: `stroke:${color}` }));
    for (const p of pts) svg.append(el("circle", { class: "dot", cx: xAt(p.t), cy: yAt(p.y), r: pts.length > 30 ? 1.6 : 2.6, style: `fill:${color}` }));
  }
  svg.append(el("text", { class: "lbl", x: padL, y: H - 6 }, tick(tmin)));
  if (tmax > tmin) svg.append(el("text", { class: "lbl", x: W - padR, y: H - 6, "text-anchor": "end" }, tick(tmax)));

  const legend = document.createElement("div");
  legend.className = "chart-legend";
  for (const k of keys) {
    const item = document.createElement("span");
    const swatch = document.createElement("i");
    swatch.style.background = colors[k] || "#888";
    item.append(swatch, document.createTextNode(k));
    legend.append(item);
  }
  wrap.append(legend);
  return wrap;
}

// ---------------------------------------------------------------------------
// Hover + table twins
//
// An SVG chart in a browser is interactive, so every chart below ships a hover
// tooltip; and because a tooltip must never be the ONLY way to read a value,
// each also ships a collapsed table twin. That pairing is what lets these
// charts drop the "number on every point" clutter without losing the numbers.
// ---------------------------------------------------------------------------

// One tooltip element per chart wrapper, positioned from pointer coordinates.
function tipLayer(wrap) {
  const tip = document.createElement("div");
  tip.className = "chart-tip";
  tip.hidden = true;
  wrap.append(tip);
  return {
    show(html, x, y) {
      tip.innerHTML = html;
      tip.hidden = false;
      // Clamp inside the wrapper so a tooltip near the right edge stays legible.
      const w = wrap.clientWidth || 320;
      tip.style.left = `${Math.min(Math.max(x, 4), Math.max(4, w - 4))}px`;
      tip.style.top = `${Math.max(y, 0)}px`;
    },
    hide() { tip.hidden = true; },
  };
}

// The WCAG-clean equivalent of any chart: collapsed by default, so it informs
// without competing with the plot.
export function chartTable(columns, rows, { label = "Table view" } = {}) {
  const details = document.createElement("details");
  details.className = "chart-table";
  const summary = document.createElement("summary");
  summary.textContent = label;
  details.append(summary);
  const table = document.createElement("table");
  const thead = document.createElement("thead");
  const hrow = document.createElement("tr");
  for (const col of columns) {
    const th = document.createElement("th");
    th.textContent = col;
    hrow.append(th);
  }
  thead.append(hrow);
  table.append(thead);
  const tbody = document.createElement("tbody");
  for (const row of rows) {
    const tr = document.createElement("tr");
    row.forEach((cell, i) => {
      const td = document.createElement("td");
      td.textContent = cell;
      if (i) td.className = "mono";
      tr.append(td);
    });
    tbody.append(tr);
  }
  table.append(tbody);
  details.append(table);
  return details;
}

// ---------------------------------------------------------------------------
// Small multiples — every main lift at a glance
//
// The per-lift dropdown can only answer "how is THIS lift going". The question
// a lifter actually opens History with is "what is moving and what is stuck",
// which is a comparison across lifts. Stacking eight lifts onto one axis would
// need eight hues and would put pounds of squat next to pounds of press as if
// they were comparable; faceting asks the eye to compare SHAPES instead, so
// every panel keeps its own y-domain and needs exactly one colour.
//
// panels: [{ label, points: [{ t, y }], value?:string, delta?:number }]
// ---------------------------------------------------------------------------
export function smallMultiples(panels, { fmtY = (v) => String(Math.round(v)), unit = "" } = {}) {
  const wrap = document.createElement("div");
  wrap.className = "chart-grid";
  // A lift with exactly one session is kept, not dropped: its panel head is a
  // stat tile (label + value), which is the honest form for a single number —
  // and dropping it would hide that the lift has been trained at all. With one
  // point the path has only a moveto, so no line is drawn and no trend is
  // claimed; only an empty series is filtered out.
  const drawn = panels.filter((p) => (p.points || []).length);
  if (!drawn.length) return wrap;

  for (const panel of drawn) {
    const pts = [...panel.points].sort((a, b) => a.t - b.t);
    const cell = document.createElement("div");
    cell.className = "mini";

    const head = document.createElement("div");
    head.className = "mini-head";
    const name = document.createElement("span");
    name.className = "mini-name";
    name.textContent = panel.label;
    head.append(name);

    const last = pts[pts.length - 1];
    const first = pts[0];
    const value = document.createElement("span");
    // Proportional figures on the panel value: it stands alone rather than
    // aligning down a column, so tabular digits would just read loose.
    value.className = "mini-value";
    value.textContent = panel.value ?? `${fmtY(last.y)}${unit}`;
    head.append(value);
    cell.append(head);

    const W = 120, H = 40, pad = 3;
    const svg = el("svg", { class: "chart mini-plot", viewBox: `0 0 ${W} ${H}`, role: "img" });
    svg.append(el("title", {}, `${panel.label}: ${pts.length} points, latest ${fmtY(last.y)}${unit}`));
    const ys = pts.map((p) => p.y);
    let lo = Math.min(...ys), hi = Math.max(...ys);
    if (lo === hi) { lo -= 1; hi += 1; }
    const tlo = first.t, thi = last.t;
    const xAt = (t) => pad + (W - pad * 2) * (thi > tlo ? (t - tlo) / (thi - tlo) : 0.5);
    const yAt = (v) => pad + (H - pad * 2) * (1 - (v - lo) / (hi - lo));

    const d = pts.map((p, i) => `${i ? "L" : "M"}${xAt(p.t).toFixed(1)} ${yAt(p.y).toFixed(1)}`).join(" ");
    svg.append(el("path", { class: "line mini-line", d }));
    // Only the endpoint gets a marker: selective, not a dot per point.
    svg.append(el("circle", { class: "dot", cx: xAt(last.t).toFixed(1), cy: yAt(last.y).toFixed(1), r: 2.4 }));
    cell.append(svg);

    const tip = tipLayer(cell);
    // Hit bands are full panel height and at least ~24px wide in CSS pixels, so
    // a fingertip never has to find a 2px line.
    const band = (W - pad * 2) / pts.length;
    pts.forEach((p, i) => {
      const hit = el("rect", {
        class: "hit", x: (pad + band * i).toFixed(1), y: 0,
        width: Math.max(band, 4).toFixed(1), height: H,
      });
      const label = `${tick(p.t)} · ${fmtY(p.y)}${unit}`;
      hit.addEventListener("pointerenter", () => tip.show(label, xAt(p.t) / W * (cell.clientWidth || W), 0));
      hit.addEventListener("pointerleave", () => tip.hide());
      svg.append(hit);
    });

    if (pts.length > 1) {
      const change = last.y - first.y;
      const trend = document.createElement("div");
      // Direction is stated in words as well as sign, so it is never colour-only.
      trend.className = `mini-trend ${change > 0 ? "up" : change < 0 ? "down" : ""}`;
      trend.textContent = change === 0 ? "flat"
        : `${change > 0 ? "up" : "down"} ${fmtY(Math.abs(change))}${unit}`;
      cell.append(trend);
    }
    wrap.append(cell);
  }
  return wrap;
}

// ---------------------------------------------------------------------------
// Bar series — counts over time (sessions per week, sets per rotation)
//
// A count is a magnitude, so the baseline is zero and the bars are one colour:
// bar length already encodes the value, and colouring each bar by its own
// height would spend the identity channel re-encoding it.
// ---------------------------------------------------------------------------
export function barSeries(points, {
  height = 140, fmtY = (v) => String(Math.round(v)), label = "", unit = "",
  fmtX = (p) => p.label ?? "",
} = {}) {
  const wrap = document.createElement("div");
  wrap.className = "chart-wrap";
  const data = points.filter((p) => Number.isFinite(p.y));
  if (!data.length) return wrap;

  const W = 340, H = height, padL = 30, padR = 8, padT = 12, padB = 22;
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, role: "img" });
  svg.append(el("title", {}, `${label}: ${data.length} periods`));
  wrap.append(svg);

  const max = Math.max(...data.map((p) => p.y), 1);
  const baseline = H - padB;
  const slot = (W - padL - padR) / data.length;
  // A 2px surface gap between neighbours instead of a stroke around each bar.
  const barW = Math.max(2, slot - 2);

  for (const v of [0, max / 2, max]) {
    const y = baseline - (baseline - padT) * (v / max);
    svg.append(el("line", { class: "axis", x1: padL, y1: y.toFixed(1), x2: W - padR, y2: y.toFixed(1), opacity: v === 0 ? 0.8 : 0.4 }));
    svg.append(el("text", { class: "lbl", x: 4, y: (y + 3).toFixed(1) }, fmtY(v)));
  }

  const tip = tipLayer(wrap);
  data.forEach((p, i) => {
    const h = (baseline - padT) * (p.y / max);
    const x = padL + slot * i + (slot - barW) / 2;
    const bar = el("rect", {
      class: "count-bar", x: x.toFixed(1), y: (baseline - h).toFixed(1),
      width: barW.toFixed(1), height: Math.max(0, h).toFixed(1), rx: 2,
    });
    svg.append(bar);
    const hit = el("rect", { class: "hit", x: (padL + slot * i).toFixed(1), y: padT, width: slot.toFixed(1), height: baseline - padT });
    hit.addEventListener("pointerenter", () =>
      tip.show(`${fmtX(p)} · <b>${fmtY(p.y)}${unit}</b>`, (x + barW / 2) / W * (wrap.clientWidth || W), 0));
    hit.addEventListener("pointerleave", () => tip.hide());
    svg.append(hit);
  });

  if (data.length) {
    svg.append(el("text", { class: "lbl", x: padL, y: H - 6 }, fmtX(data[0])));
    if (data.length > 1) {
      svg.append(el("text", { class: "lbl", x: W - padR, y: H - 6, "text-anchor": "end" }, fmtX(data[data.length - 1])));
    }
  }
  return wrap;
}

// ---------------------------------------------------------------------------
// Set-quality mix — the one legitimate status-coloured chart here
//
// clean / grindy / wobble is a STATE, not an identity, so it takes the reserved
// status scale rather than a categorical slot — and like every status encoding
// it ships with a written label, never colour alone. This is also the data the
// autoregulation actually runs on: more than one flagged working set holds the
// weight instead of adding it, so the mix explains why a lift stalled.
//
// groups: [{ label, parts: [{ key, label, value, tone }] }]  tone: good|warn|hard
// ---------------------------------------------------------------------------
export function stackedBars(groups, { height = 150, unit = " sets" } = {}) {
  const wrap = document.createElement("div");
  wrap.className = "chart-wrap";
  const data = groups.filter((g) => (g.parts || []).some((p) => p.value > 0));
  if (!data.length) return wrap;

  const W = 340, H = height, padL = 30, padR = 8, padT = 12, padB = 22;
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, role: "img" });
  wrap.append(svg);

  const totals = data.map((g) => g.parts.reduce((s, p) => s + p.value, 0));
  const max = Math.max(...totals, 1);
  const baseline = H - padB;
  const slot = (W - padL - padR) / data.length;
  const barW = Math.max(3, slot - 3);
  const TONE = { good: "var(--good)", warn: "var(--warn)", hard: "var(--hard)" };

  for (const v of [0, max]) {
    const y = baseline - (baseline - padT) * (v / max);
    svg.append(el("line", { class: "axis", x1: padL, y1: y.toFixed(1), x2: W - padR, y2: y.toFixed(1), opacity: v === 0 ? 0.8 : 0.4 }));
    svg.append(el("text", { class: "lbl", x: 4, y: (y + 3).toFixed(1) }, String(Math.round(v))));
  }

  const tip = tipLayer(wrap);
  data.forEach((g, i) => {
    const x = padL + slot * i + (slot - barW) / 2;
    let cursor = baseline;
    for (const part of g.parts) {
      if (!(part.value > 0)) continue;
      const h = (baseline - padT) * (part.value / max);
      // 2px surface gap between segments — a gap, not a border.
      svg.append(el("rect", {
        class: "stack-seg", x: x.toFixed(1), y: (cursor - h).toFixed(1),
        width: barW.toFixed(1), height: Math.max(0.5, h - 2).toFixed(1), rx: 2,
        style: `fill:${TONE[part.tone] || "var(--muted)"}`,
      }));
      cursor -= h;
    }
    const rows = g.parts.filter((p) => p.value > 0)
      .map((p) => `${p.label} ${p.value}`).join(" · ");
    const hit = el("rect", { class: "hit", x: (padL + slot * i).toFixed(1), y: padT, width: slot.toFixed(1), height: baseline - padT });
    hit.addEventListener("pointerenter", () =>
      tip.show(`<b>${g.label}</b><br>${rows}`, (x + barW / 2) / W * (wrap.clientWidth || W), 0));
    hit.addEventListener("pointerleave", () => tip.hide());
    svg.append(hit);
  });

  svg.append(el("text", { class: "lbl", x: padL, y: H - 6 }, data[0].label));
  if (data.length > 1) svg.append(el("text", { class: "lbl", x: W - padR, y: H - 6, "text-anchor": "end" }, data[data.length - 1].label));

  const legend = document.createElement("div");
  legend.className = "chart-legend";
  for (const [tone, text] of [["good", "clean"], ["warn", "grindy"], ["hard", "wobble"]]) {
    const span = document.createElement("span");
    const swatch = document.createElement("i");
    swatch.style.background = TONE[tone];
    span.append(swatch, document.createTextNode(text));
    legend.append(span);
  }
  wrap.append(legend);
  return wrap;
}
