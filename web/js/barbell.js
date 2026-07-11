// Compact one-side barbell graphic: renders the actual loaded plates for a
// weight at a given station (lb rack vs kg platform), coloured to the gym scheme.
// Reuses the plate solver + colour/size tokens from core.js.
import * as C from "./core.js";

const NS = "http://www.w3.org/2000/svg";
const FILL = { red: "#d23b3b", blue: "#2f6fed", green: "#1faa52", yellow: "#e8b008", white: "#ededed", black: "#1c1d22" };
const STROKE = { red: "#7a1f1f", blue: "#1b3f8f", green: "#10632f", yellow: "#8a6a04", white: "#9a9a9a", black: "#3a3b42" };
const el = (n, a = {}) => { const e = document.createElementNS(NS, n); for (const k in a) e.setAttribute(k, a[k]); return e; };

// The plate denominations of the chosen unit that exist at this gym. The bar is
// chosen separately (most bars are 45 lb regardless of which plates you load).
export function stationPlates(unit, gym) {
  let list = gym && gym.plateToggles ? gym.plateToggles.filter((t) => t.enabled).map((t) => ({ value: t.value, unit: t.unit })) : C.ALL_STANDARD;
  list = list.filter((p) => p.unit === unit);
  if (!list.length) list = unit === "kg" ? C.STANDARD_KG : C.STANDARD_LB;
  return list;
}

// Returns { svg, solution }. svg is a per-side barbell (heaviest plate inboard).
// `bar` is explicit (selectable); `unit` only chooses the plate denominations.
// Pass `preSolved` to DRAW an existing solution (or user-entered stack) instead
// of re-solving — the plate calculator's hero must match its own answer, which
// may span both unit systems.
export function barbellSVG(weightLb, unit, bar, gym, preSolved = null) {
  const solution = preSolved || C.solve(weightLb, bar, stationPlates(unit, gym));
  const plates = [];
  for (const pc of solution.perSide) for (let i = 0; i < pc.count; i += 1) plates.push(pc.plate);

  const H = 30, plateW = 7, gap = 1.5, sleeve = 18;
  const W = Math.max(plates.length ? 46 : 74, sleeve + 6 + plates.length * (plateW + gap) + 4); // bar-only needs room for its label
  const svg = el("svg", { class: "barbell", viewBox: `0 0 ${W} ${H}`, height: H, preserveAspectRatio: "xMinYMid meet", role: "img" });

  // bar shaft + sleeve face
  svg.append(el("rect", { x: 0, y: H / 2 - 1.5, width: sleeve + 4, height: 3, rx: 1.5, fill: "#9aa0aa" }));
  svg.append(el("rect", { x: sleeve, y: H / 2 - 6, width: 3, height: 12, rx: 1, fill: "#7c828c" }));

  let x = sleeve + 5;
  for (const p of plates) {
    const tok = C.plateColorToken(p);
    const h = (H - 4) * C.plateSizeFactor(p);
    svg.append(el("rect", {
      x, y: (H - h) / 2, width: plateW, height: h, rx: 1.5,
      fill: FILL[tok] || "#888", stroke: STROKE[tok] || "rgba(0,0,0,0.3)", "stroke-width": 0.75,
    }));
    x += plateW + gap;
  }
  if (!plates.length) {
    const t = el("text", { x: sleeve + 7, y: H / 2 + 3.5, fill: "#98989f", "font-size": "10" });
    t.textContent = "bar only";
    svg.append(t);
  }
  return { svg, solution, bar };
}
