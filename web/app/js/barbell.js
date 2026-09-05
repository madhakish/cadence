// Shared compact/full barbell graphics. Callers resolve the rack through core;
// this module renders their exact solution with core colour/size metadata.
import * as C from "./core.js";

const NS = "http://www.w3.org/2000/svg";
const FILL = { red: "#d23b3b", blue: "#2f6fed", green: "#1faa52", yellow: "#e8b008", white: "#ededed", black: "#1c1d22" };
const STROKE = { red: "#7a1f1f", blue: "#1b3f8f", green: "#10632f", yellow: "#8a6a04", white: "#9a9a9a", black: "#3a3b42" };
const el = (n, a = {}) => { const e = document.createElementNS(NS, n); for (const k in a) e.setAttribute(k, a[k]); return e; };

// A readable, face-on denomination key for calculator rows. The hero remains
// an honest edge-on load-order diagram, where a large horizontal number would
// imply physically impossible plate thickness. Mirrors PlateFaceBadge.
export function plateBadgeSVG(plate, style = "steel") {
  const token = C.plateColorToken(plate, style);
  const foreground = ["white", "yellow", "green"].includes(token) ? "#24262a" : "#fff";
  const svg = el("svg", { class: `plate-badge ${style}`, viewBox: "0 0 52 52",
    role: "img", "aria-label": `${C.plateLabel(plate)} plate` });
  svg.append(
    el("circle", { cx: 26, cy: 26, r: 24, fill: FILL[token] || "#888",
      stroke: STROKE[token] || "#333", "stroke-width": 2 }),
    el("circle", { cx: 26, cy: 26, r: 17, fill: "none", stroke: foreground,
      "stroke-width": 1, opacity: .34 }),
  );
  const value = el("text", { x: 26, y: 24, "text-anchor": "middle",
    "font-size": 15, "font-weight": 800, fill: foreground });
  value.textContent = C.trim(plate.value, 2);
  const unit = el("text", { x: 26, y: 36, "text-anchor": "middle",
    "font-size": 9, "font-weight": 700, fill: foreground });
  unit.textContent = plate.unit;
  svg.append(value, unit);
  return svg;
}

// The plate denominations of the chosen unit that exist at this gym. The bar is
// chosen separately (most bars are 45 lb regardless of which plates you load).
export function stationPlates(unit, gym, stationDenomination = null) {
  const rack = gym && Array.isArray(gym.plateToggles) && gym.plateToggles.length
    ? gym.plateToggles.filter((t) => t.enabled).map((t) => ({ value: t.value, unit: t.unit }))
    : (unit === "kg" ? C.STANDARD_KG : C.STANDARD_LB);
  // The lift's station preference (v8) filters the rack to its denomination.
  return C.stationPlates(stationDenomination, rack);
}

/// Human-readable explanation when rack-aware snapping changes a prescribed
/// target. Each line includes total load and the per-side stack.
export function prescriptionPlateDetails(targetLb, achievedLb, unit, bar, gym, stationDenomination = null) {
  if (!(targetLb > 0) || Math.abs(targetLb - achievedLb) <= 0.01) return [];
  const options = C.prescriptionPlateOptions(
    targetLb, bar, stationPlates(unit, gym, stationDenomination), 10,
    gym?.collarWeightLb || 0, gym?.loadingPolicy || "closest",
  );
  const fmt = (lb) => `${C.trim(unit === "kg" ? C.kgFromLb(lb) : lb)} ${unit}`;
  const lines = [{ kind: "target", text: `Target ${fmt(targetLb)} · load ${fmt(achievedLb)}` }];
  if (options.below) lines.push({
    kind: "alternative", text: `Below ${fmt(options.below.totalLb)} · ${C.perSideLabel(options.below.perSide)}/side`,
  });
  if (options.above && (!options.below || Math.abs(options.above.totalLb - options.below.totalLb) > 0.01)) lines.push({
    kind: "alternative", text: `Above ${fmt(options.above.totalLb)} · ${C.perSideLabel(options.above.perSide)}/side`,
  });
  return lines;
}

const plateWidth = (plate, style, scale = 1) => {
  const base = style === "bumper" ? 4.5 + 8.5 * C.plateThicknessFactor(plate, style)
    : 3.2 + 5 * C.plateThicknessFactor(plate, style);
  return Math.max(style === "bumper" ? 4.2 : 3.1, base) * scale;
};

const addPlateGradients = (defs, style) => {
  for (const token of Object.keys(FILL)) {
    const gradient = el("linearGradient", { id: `cadence-${style}-${token}`, x1: "0", y1: "0", x2: "1", y2: "0" });
    gradient.append(el("stop", { offset: "0", "stop-color": STROKE[token] }),
      el("stop", { offset: ".20", "stop-color": FILL[token] }),
      el("stop", { offset: ".68", "stop-color": FILL[token] }),
      el("stop", { offset: "1", "stop-color": STROKE[token] }));
    defs.append(gradient);
  }
};

const appendPlate = (svg, plate, { x, y, width, height, side, style, stackIndex = null,
  stackCount = null, prominent = false }) => {
  const token = C.plateColorToken(plate, style);
  const data = stackIndex == null ? {} : {
    "data-side": side, "data-stack-index": stackIndex,
    "data-plate-value": plate.value, "data-plate-unit": plate.unit,
  };
  svg.append(el("rect", { class: "barbell-plate-shadow", x: x + 1, y: y + 2,
    width, height, rx: style === "bumper" ? 2.4 : 1.2, fill: "#000", opacity: ".16" }));
  const body = el("rect", {
    class: `barbell-plate barbell-plate-body ${style}`, x, y, width, height,
    rx: style === "bumper" ? 2.4 : 1.2, fill: `url(#cadence-${style}-${token})`,
    stroke: STROKE[token], "stroke-width": 0.65, ...data,
    tabindex: "0", role: "img",
    "aria-label": `${side} plate${stackIndex == null ? "" : ` ${stackIndex + 1} of ${stackCount || "?"}`}, ${C.plateLabel(plate)}`,
    "data-plate-denomination": C.plateLabel(plate),
  });
  svg.append(body);

  // A shallow outside face makes the plate read as a disc rather than a UI
  // rectangle. The recessed ring and hub distinguish calibrated steel from a
  // rubber bumper even when the denomination colour is the same.
  const faceX = side === "left" ? x + Math.min(2.2, width * 0.32) : x + width - Math.min(2.2, width * 0.32);
  const faceRX = Math.min(2.5, Math.max(1.05, width * 0.32));
  const faceRY = Math.max(2, height / 2 - 1.4);
  svg.append(el("ellipse", { class: "barbell-plate-face", cx: faceX, cy: y + height / 2,
    rx: faceRX, ry: faceRY, fill: FILL[token], stroke: STROKE[token], "stroke-width": 0.65 }));
  if (style === "steel") {
    svg.append(el("ellipse", { class: "barbell-plate-recess", cx: faceX, cy: y + height / 2,
      rx: Math.max(.7, faceRX * .72), ry: Math.max(2, height * .31), fill: "none",
      stroke: token === "white" || token === "yellow" ? "#333" : "#fff", "stroke-width": .45, opacity: .4 }));
  } else {
    svg.append(el("ellipse", { class: "barbell-plate-rim", cx: faceX, cy: y + height / 2,
      rx: Math.max(.75, faceRX * .76), ry: Math.max(2, faceRY - 1.4), fill: "none",
      stroke: "#fff", "stroke-width": .55, opacity: .34 }));
  }
  svg.append(el("ellipse", { class: "barbell-plate-hub", cx: faceX, cy: y + height / 2,
    rx: Math.max(.75, faceRX * .62), ry: Math.max(2.2, Math.min(4.8, height * .1)),
    fill: "url(#cadence-bar-steel)", stroke: "#555b63", "stroke-width": .45 }));
  // Every drawn plate carries its exact denomination. Full-bar stages are
  // deliberately scroll-safe (rather than shrinking to dust on a phone), so
  // these marks remain readable even on fractional change plates.
  if (height >= 14) {
    const requestedOffset = stackCount > 1
      ? (prominent ? [-18, 18, 0] : [-7, 7, 0])[stackIndex % 3] : 0;
    const labelOffset = Math.max(-height * .22, Math.min(height * .22, requestedOffset));
    const labelY = y + height / 2 + labelOffset;
    const label = el("text", { class: "barbell-plate-label", x: x + width / 2, y: labelY,
      "text-anchor": "middle", "dominant-baseline": "central", "font-size": prominent ? "9" : "5.2",
      "font-weight": "800", fill: ["white", "yellow", "green"].includes(token) ? "#24262a" : "#fff",
      opacity: ".98", "aria-hidden": "true", "data-plate-denomination": C.plateLabel(plate),
      transform: `rotate(-90 ${x + width / 2} ${labelY})` });
    label.textContent = C.plateLabel(plate);
    svg.append(label);
  }
};

// Render a domain-produced solution verbatim. Solving, summing, ordering, and
// rack selection belong to core/callers; this function deliberately has no
// target or inventory arguments with which it could manufacture a second truth.
export function barbellSVG(solution, presentation = "compact", plateStyle = "steel") {
  if (!solution?.bar || !Array.isArray(solution?.perSide)) {
    throw new TypeError("barbellSVG requires a complete plate solution");
  }
  const bar = solution.bar;
  const plates = [];
  for (const pc of solution.perSide) for (let i = 0; i < pc.count; i += 1) plates.push(pc.plate);
  const barLabel = C.barLabel(bar);
  const accessibilityLoad = plates.length
    ? `${C.perSideLabel(solution.perSide)} per side on ${barLabel}${solution.collarLb > 0 ? ", including collars" : ""}`
    : solution.collarLb > 0 ? `${barLabel} with collars, no plates` : `${barLabel}, bar only`;

  if (presentation === "full") {
    const nominalGap = plateStyle === "bumper" ? 1.05 : .75;
    const nominalWidths = plates.map((plate) => plateWidth(plate, plateStyle));
    const nominalTotal = nominalWidths.reduce((sum, width) => sum + width, 0)
      + Math.max(0, plates.length - 1) * nominalGap;
    const minimumLegibleWidth = Math.max(320, 204 + 2 * nominalTotal);
    const W = minimumLegibleWidth, H = 124, midY = H / 2;
    const shoulder = Math.min(W / 2 - 84, Math.max(76, nominalTotal + 18));
    const rightShoulder = W - shoulder;
    const svg = el("svg", { class: `barbell full ${plateStyle}`, viewBox: `0 0 ${W} ${H}`,
      preserveAspectRatio: "xMidYMid meet", role: "img",
      "aria-label": `${plateStyle === "bumper" ? "Bumper" : "Steel"} barbell: ${accessibilityLoad}` });
    const defs = el("defs");
    const steel = el("linearGradient", { id: "cadence-bar-steel", x1: "0", y1: "0", x2: "0", y2: "1" });
    steel.append(el("stop", { offset: "0", "stop-color": "#5d626a" }),
      el("stop", { offset: ".48", "stop-color": "#d5d8dc" }),
      el("stop", { offset: "1", "stop-color": "#747a83" }));
    defs.append(steel);
    addPlateGradients(defs, plateStyle);
    svg.append(defs);
    svg.append(el("rect", { class: "barbell-shadow", x: 9, y: midY + 3, width: W - 18, height: 5, rx: 2.5 }));
    svg.append(el("rect", { x: 8, y: midY - 2, width: W - 16, height: 4, rx: 2, fill: "url(#cadence-bar-steel)" }));
    svg.append(el("rect", { x: 8, y: midY - 3, width: shoulder - 8, height: 6, rx: 3, fill: "url(#cadence-bar-steel)" }));
    svg.append(el("rect", { x: rightShoulder, y: midY - 3, width: shoulder - 8, height: 6, rx: 3, fill: "url(#cadence-bar-steel)" }));
    svg.append(el("rect", { x: shoulder - 3, y: midY - 11, width: 6, height: 22, rx: 2, fill: "url(#cadence-bar-steel)" }));
    svg.append(el("rect", { x: rightShoulder - 3, y: midY - 11, width: 6, height: 22, rx: 2, fill: "url(#cadence-bar-steel)" }));
    for (let x = shoulder + 14; x <= rightShoulder - 14; x += 7) {
      svg.append(el("line", { class: "barbell-knurl", x1: x, y1: midY - 1.7, x2: x + 1.8, y2: midY + 1.7 }));
    }
    svg.append(el("circle", { cx: 8, cy: midY, r: 3, fill: "#6c727a" }),
      el("circle", { cx: W - 8, cy: midY, r: 3, fill: "#6c727a" }));

    const available = shoulder - 18;
    const scale = nominalTotal > available ? available / nominalTotal : 1;
    const widths = plates.map((plate) => plateWidth(plate, plateStyle, scale));
    const gap = Math.max(.45, nominalGap * scale);
    let leftCursor = shoulder - 6, rightCursor = rightShoulder + 6;
    for (const [stackIndex, p] of plates.entries()) {
      const width = widths[stackIndex];
      const h = (H - 18) * C.plateDiameterFactor(p, plateStyle);
      const leftX = leftCursor - width;
      const rightX = rightCursor;
      // `plates` is collar → sleeve (heaviest first). Screen coordinates move
      // in opposite directions, so the right stack is not a copied left-to-
      // right list: both sides start at their collar and grow outboard.
      for (const { side, x } of [{ side: "left", x: leftX }, { side: "right", x: rightX }]) {
        const y = (H - h) / 2;
        appendPlate(svg, p, { x, y, width, height: h, side, style: plateStyle,
          stackIndex, stackCount: plates.length, prominent: true });
      }
      leftCursor = leftX - gap;
      rightCursor = rightX + width + gap;
    }
    if (solution.collarLb > 0) {
      for (const x of [leftCursor - 3.5, rightCursor]) {
        svg.append(el("rect", { class: "barbell-lock-collar", x, y: midY - 8, width: 3.5, height: 16,
          rx: 1, fill: "url(#cadence-bar-steel)", stroke: "#555b63", "stroke-width": .5 }));
      }
    }
    if (!plates.length) {
      const t = el("text", { x: W / 2, y: midY - 9, fill: "#98989f", "font-size": "10", "text-anchor": "middle" });
      t.textContent = solution.collarLb > 0 ? "bar + collars" : "bar only";
      svg.append(t);
    }
    return { svg, solution, bar, minimumLegibleWidth, baseLabelSize: 9 };
  }

  const H = 46, gap = plateStyle === "bumper" ? 1 : .7, sleeve = 18;
  const widths = plates.map((plate) => plateWidth(plate, plateStyle, .72));
  const stackWidth = widths.reduce((sum, width) => sum + width, 0) + Math.max(0, widths.length - 1) * gap;
  const W = Math.max(plates.length ? 50 : solution.collarLb > 0 ? 96 : 74,
    sleeve + 6 + stackWidth + 5); // empty sleeves need room for their truthful label
  const svg = el("svg", { class: `barbell ${plateStyle}`, viewBox: `0 0 ${W} ${H}`, height: H, preserveAspectRatio: "xMinYMid meet", role: "img",
    "aria-label": `${plateStyle === "bumper" ? "Bumper" : "Steel"} barbell: ${accessibilityLoad}` });
  const defs = el("defs");
  const steel = el("linearGradient", { id: "cadence-bar-steel", x1: "0", y1: "0", x2: "0", y2: "1" });
  steel.append(el("stop", { offset: "0", "stop-color": "#5d626a" }),
    el("stop", { offset: ".48", "stop-color": "#d5d8dc" }),
    el("stop", { offset: "1", "stop-color": "#747a83" }));
  defs.append(steel); addPlateGradients(defs, plateStyle); svg.append(defs);

  // bar shaft + sleeve face
  svg.append(el("rect", { x: 0, y: H / 2 - 1.5, width: sleeve + 4, height: 3, rx: 1.5, fill: "#9aa0aa" }));
  svg.append(el("rect", { x: sleeve, y: H / 2 - 6, width: 3, height: 12, rx: 1, fill: "#7c828c" }));

  let x = sleeve + 5;
  for (const [index, p] of plates.entries()) {
    const width = widths[index];
    const h = (H - 4) * C.plateDiameterFactor(p, plateStyle);
    appendPlate(svg, p, { x, y: (H - h) / 2, width, height: h, side: "right",
      style: plateStyle, stackIndex: index, stackCount: plates.length });
    x += width + gap;
  }
  if (solution.collarLb > 0) {
    svg.append(el("rect", { class: "barbell-lock-collar", x, y: H / 2 - 8, width: 3.5, height: 16,
      rx: 1, fill: "url(#cadence-bar-steel)", stroke: "#555b63", "stroke-width": .5 }));
  }
  if (!plates.length) {
    const t = el("text", { x: solution.collarLb > 0 ? x + 5 : sleeve + 7,
      y: H / 2 + 3.5, fill: "#98989f", "font-size": "10" });
    t.textContent = solution.collarLb > 0 ? "bar + collars" : "bar only";
    svg.append(t);
  }
  return { svg, solution, bar, minimumLegibleWidth: W, baseLabelSize: 5.2 };
}

// One responsive shell for every complete-bar presentation. Inline stages fit
// their container, keep denomination text at a legible physical size, and show
// Expand only when the solution-derived natural width does not fit. The focused
// expanded screen alone may scroll at natural scale.
export function barbellStage(rendered, {
  caption = "", emphasis = "standard", onExpand = null, containerWidth = null,
} = {}) {
  const stage = document.createElement("div");
  stage.className = `barbell-stage ${emphasis}`;
  stage.tabIndex = 0;
  stage.setAttribute("role", "group");
  stage.setAttribute("aria-label", "Barbell loading diagram");
  const track = document.createElement("div");
  track.className = "barbell-stage-track";
  track.style.setProperty("--barbell-natural-width", `${rendered.minimumLegibleWidth}px`);
  track.append(rendered.svg);
  stage.append(track);

  const footer = document.createElement("div");
  footer.className = "barbell-stage-footer";
  if (caption) footer.append(uiText("div", "sub barbell-caption", caption));
  const expand = onExpand ? uiText("button", "btn ghost sm barbell-expand", "Expand") : null;
  if (expand) {
    expand.type = "button";
    expand.hidden = true;
    expand.setAttribute("aria-label", "Expand loaded bar");
    expand.addEventListener("click", onExpand);
    footer.append(expand);
  }
  if (footer.childNodes.length) stage.append(footer);

  const syncLegibility = (measuredWidth = null) => {
    const width = Number.isFinite(measuredWidth) ? measuredWidth : stage.getBoundingClientRect().width;
    if (!(width > 0)) return;
    const expanded = emphasis === "expanded";
    const scale = expanded ? 1 : Math.min(1, width / rendered.minimumLegibleWidth);
    for (const label of rendered.svg.querySelectorAll(".barbell-plate-label")) {
      label.setAttribute("font-size", String(rendered.baseLabelSize / scale));
    }
    const constrained = !expanded && width + .5 < rendered.minimumLegibleWidth;
    stage.classList.toggle("constrained", constrained);
    if (expand) expand.hidden = !constrained;
    stage.setAttribute("aria-label", constrained
      ? "Barbell loading diagram; expanded view available"
      : "Barbell loading diagram");
  };
  syncLegibility(containerWidth);
  if (typeof ResizeObserver !== "undefined" && containerWidth == null) {
    const observer = new ResizeObserver((entries) => {
      syncLegibility(entries[0]?.contentRect?.width ?? null);
    });
    observer.observe(stage);
  }
  return stage;
}

const uiText = (tag, className, value) => {
  const node = document.createElement(tag);
  node.className = className;
  node.textContent = value;
  return node;
};

const dom = (tag, className = "", text = "") => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
};

const summaryRow = (label, value, warning = false) => {
  const row = dom("div", "load-summary-row");
  row.append(dom("span", "", label), dom("strong", `mono${warning ? " warn" : ""}`, value));
  return row;
};

// One totals block for the calculator and every in-session plate preview.
// Pounds are intentionally first regardless of the entry unit; `solution`
// is the exact object handed to the renderer, so the numbers and steel can
// never drift through a second calculation in the view.
export function loadoutSummary(requestedLb, solution, { compact = false } = {}) {
  const difference = requestedLb == null ? null : solution.totalLb - requestedLb;
  const sign = difference > .005 ? "+" : "";
  const summary = dom("div", `card load-summary${compact ? " compact" : ""}`);
  summary.append(dom("span", "eyebrow", "ACHIEVED · BAR INCLUDED"));
  const weights = dom("div", "dual-weight mono");
  weights.setAttribute("role", "group");
  weights.setAttribute("aria-label", `Achieved total, bar included, ${C.both(solution.totalLb)}`);
  for (const [value, unit, primary] of [
    [solution.totalLb, "lb", true],
    [C.kgFromLb(solution.totalLb), "kg", false],
  ]) {
    const measure = dom("span", `weight-measure${primary ? " primary" : ""}`);
    measure.append(dom("span", "weight-value", C.trim(value)), dom("span", "weight-unit", unit));
    weights.append(measure);
  }
  summary.append(weights);
  const grid = dom("div", "load-summary-grid");
  if (requestedLb != null) grid.append(summaryRow("Requested", C.both(requestedLb)));
  grid.append(summaryRow("Bar", C.both(C.barLb(solution.bar))),
    summaryRow("Plates / side", C.perSideLabel(solution.perSide)));
  if (solution.collarLb > 0) grid.append(summaryRow("Collars", C.both(solution.collarLb)));
  if (difference != null) grid.append(summaryRow("Difference",
    `${sign}${C.trim(difference, 2)} lb / ${sign}${C.trim(C.kgFromLb(difference), 2)} kg`,
    Math.abs(difference) > .01));
  summary.append(grid);
  return summary;
}

export function mixedEquipmentNote(solution) {
  const units = new Set((solution.perSide || []).map((count) => count.plate.unit));
  if (units.size < 2 && ![...units].some((plateUnit) => plateUnit !== solution.bar.unit)) return null;
  const note = dom("div", "mixed-unit-note");
  note.append(dom("strong", "", "Mixed equipment"),
    dom("span", "sub", `${C.barLabel(solution.bar)} + ${C.perSideLabel(solution.perSide)} per side. The achieved total already includes every conversion.`));
  return note;
}

// Compact dumbbell graphic for dumbbell lifts — the counterpart of the
// barbell's plate loadout: heads on both ends, the dumbbell's size (in the
// entered unit) stamped on the handle, so a glance says which pair to grab
// off the rack. Mirrors Cadence/Views/DumbbellView.swift (same geometry).
export function dumbbellSVG(weightLb, unit) {
  const W = 88, H = 30;
  const value = unit === "kg" ? C.kgFromLb(weightLb) : weightLb;
  const svg = el("svg", {
    viewBox: `0 0 ${W} ${H}`, width: W, height: H, class: "dumbbell",
    role: "img", "aria-label": `Dumbbell, ${C.trim(value)} ${unit}`,
  });
  const plate = (x, y, w, h) => el("rect", { x, y, width: w, height: h, rx: 1.5, fill: "#7C828C", stroke: "#3A3B42", "stroke-width": 0.75 });
  // handle (no stroke — matches the barbell shaft)
  svg.append(el("rect", { x: 15, y: H / 2 - 3, width: W - 30, height: 6, rx: 3, fill: "#9AA0AA" }));
  // heads: outer + inner plate each side
  svg.append(plate(0, 3, 7, 24), plate(8, 6, 6, 18));
  svg.append(plate(W - 7, 3, 7, 24), plate(W - 14, 6, 6, 18));
  const t = el("text", { x: W / 2, y: H / 2 + 4, "text-anchor": "middle", "font-size": 11, "font-weight": 700, fill: "currentColor" });
  t.textContent = C.trim(value);
  svg.append(t);
  return svg;
}
