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
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: "none", role: "img" });
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

// Rotation → line colour: escalating heat to Peak, muted Recovery. Mirrors the
// native ProgressionChartsView.rotationPalette.
//
// These keys must be the labels `C.chartRotationLabel` produces. Rotation 4 was
// renamed Deload → Recovery with the recovery bridge; the stale key here meant
// R4 missed the palette and fell through to the neutral default.
export const ROTATION_COLORS = {
  "R1 Volume": "#5ba06a", "R2 Load": "#e8b008", "R3 Peak": "#ef4444",
  "R4 Recovery": "#8b9196", "Untracked": "#666b71",
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
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: "none", role: "img" });
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
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: "none", role: "img" });
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
