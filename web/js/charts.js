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
export function lineChart(series, { height = 200, fmtY = (v) => String(Math.round(v)) } = {}) {
  const W = 340, H = height, padL = 40, padR = 14, padT = 16, padB = 24;
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: "none", role: "img" });
  if (!series.length) return svg;

  const n = series.length;
  const ys = series.map((p) => p.y);
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
