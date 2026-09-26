// Shared compact/full barbell graphics. Callers resolve the rack through core;
// this module renders their exact solution with core colour/size metadata.
import * as C from "./core.js";
import { barbellScene, discAccessibilityLabel, plateFamily, plateFamilyLabel, plateTintMatrix } from "./barbell-scene.js";
import { PLATE_SPRITES } from "./plate-sprites.js";
import { barbellGL, BACKDROPS } from "./barbell-gl.js";

// Rendered loaded-bar sprites (web/tools/render-plate-sprites.py): one per
// plate shape and scene angle, plus shaft, sleeves, and collars. Placement
// comes from the same BarbellScene geometry both clients share.
const spriteURL = (name) => new URL(`../assets/plates/${name}.png`, import.meta.url).href;
export function plateSpriteName(plate, style, exploded) {
  const family = plateFamily(plate, style);
  const angle = exploded ? "exploded" : "assembled";
  const shape = PLATE_SPRITES.plates[`${family}:${plate.value}-${plate.unit}`];
  const name = `plate-${shape}-${angle}`;
  if (shape && PLATE_SPRITES.sprites[name]) return name;
  // An unknown shape borrows the family's first sprite; geometry still scales it.
  return Object.keys(PLATE_SPRITES.sprites).find((key) => key.startsWith(`plate-${family}-`) && key.endsWith(`-${angle}`));
}
// Map a bar sprite's axis reference points onto two scene points. Thickness
// comes from the sprite's nominal span (so an exploded scene's longer sleeve
// stretches along the bar, never fattens); the stretch runs along the bar axis.
function placeBarSprite(name, from, to, axisLength) {
  const meta = PLATE_SPRITES.sprites[name];
  const [ax, ay] = meta.axisStart, [bx, by] = meta.axisEnd;
  const spritePx = Math.hypot(bx - ax, by - ay);
  const k = meta.spanUnits * axisLength / spritePx;                  // scene units per sprite px
  const stretch = Math.hypot(to.x - from.x, to.y - from.y) / (meta.spanUnits * axisLength);
  const sceneDeg = Math.atan2(to.y - from.y, to.x - from.x) * 180 / Math.PI;
  const spriteDeg = Math.atan2(by - ay, bx - ax) * 180 / Math.PI;
  return el('image', { class: `barbell-${meta.kind}`, href: spriteURL(name), width: meta.size[0], height: meta.size[1],
    transform: `translate(${from.x} ${from.y}) rotate(${sceneDeg.toFixed(3)}) scale(${(k * stretch).toFixed(5)} ${k.toFixed(5)}) rotate(${(-spriteDeg).toFixed(3)}) translate(${-ax} ${-ay})` });
}

const NS = "http://www.w3.org/2000/svg";
const el = (n, a = {}) => { const e = document.createElementNS(NS, n); for (const k in a) e.setAttribute(k, a[k]); return e; };


// A readable, face-on denomination key for calculator rows. The hero remains
// an honest edge-on load-order diagram, where a large horizontal number would
// imply physically impossible plate thickness. Decorative: callers provide
// the adjacent denomination label. Mirrors PlateFaceBadge.
export function plateBadgeSVG(plate, style = "steel") {
  const colour = C.plateColour(C.plateColorToken(plate, style));
  const foreground = colour.ink;
  const svg = el("svg", { class: `plate-badge ${style}`, viewBox: "0 0 52 52",
    "aria-hidden": "true", focusable: "false" });
  svg.append(
    el("circle", { cx: 26, cy: 26, r: 24, fill: colour.fill,
      stroke: colour.edge, "stroke-width": 2 }),
    el("circle", { cx: 26, cy: 26, r: 17, fill: "none", stroke: foreground,
      "stroke-width": 1, opacity: .34 }),
  );
  const value = el("text", { x: 26, y: 24, "text-anchor": "middle",
    "font-size": 15, "font-weight": 800, fill: foreground });
  value.textContent = String(plate.value);
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

// Render the exact domain solution through one scene in both presentations.
// `presentation` is chosen by the SURFACE (a set row vs the current set's
// stage); `emphasis` is the state (current / standard / muted) and changes
// only opacity — never geometry, order, or labels.
export function barbellSVG(solution, presentation = "compact", plateStyle = "steel", { emphasis = "standard" } = {}) {
  if (!solution?.bar || !Array.isArray(solution?.perSide)) {
    throw new TypeError("barbellSVG requires a complete plate solution");
  }
  const rendered = realisticBarbellSVG(solution, plateStyle);
  rendered.svg.classList.add(`emphasis-${emphasis}`);
  if (presentation !== "full") {
    rendered.svg.classList.remove("full");
    rendered.svg.classList.add("compact");
    rendered.svg.setAttribute("height", "84");
    rendered.svg.setAttribute("width", "100%");
  }
  return rendered;
}

let sceneID = 0;
function realisticBarbellSVG(solution, style, exploded = false) {
  const scene = barbellScene(solution, style, exploded);
  const id = `bar-art-${++sceneID}`;
  const stackLabel = solution.perSide.length ? `${C.perSideLabel(solution.perSide)} per side` : solution.collarLb > 0 ? "with collars, no plates" : "bar only";
  const svg = el('svg', { id, class: `barbell full ${style} realistic`,
    viewBox: `0 0 ${scene.width} ${scene.height}`, role: 'group',
    'aria-label': `${exploded ? 'Exploded' : 'Assembled'} loaded bar, ${C.both(solution.totalLb)}, ${stackLabel}`,
    'data-exploded': exploded });
  const minimumLegibleWidth = Math.max(320, scene.width * 12 / (exploded ? 14 : 10));
  if (!exploded) {
    const visibility = el('style');
    visibility.textContent = `@container plate-stage (width < ${minimumLegibleWidth}px) { #${id} .barbell-plate-label { display: none; } }`;
    svg.append(visibility);
  }
  const defs = el('defs');
  const angle = exploded ? 'exploded' : 'assembled';
  for (const token of Object.keys(C.PLATE_COLOURS)) {
    const filter = el('filter', { id: `${id}-${token}`, 'color-interpolation-filters': 'sRGB' });
    // Colourise the rendered greyscale sprite from its luminance; the hub is
    // redrawn unfiltered.
    filter.append(el('feColorMatrix', { type:'matrix', values: plateTintMatrix(token, style).join(' ') }));
    defs.append(filter);
  }
  svg.append(defs);
  const root = el('g', { transform: `translate(${scene.width/2} ${scene.height/2})` });
  svg.append(root);
  const point = x => ({ x: x * scene.axisX, y: x * scene.axisY });
  // The bar goes under everything: every plate bore is open in the sprites, so
  // the sleeves and shaft show through wherever the plate's thickness lets them. The camera sits at the −x end,
  // so the far (+x) collar precedes the plates and the near one follows them.
  const axisLength = Math.hypot(scene.axisX, scene.axisY);
  root.append(placeBarSprite(`bar-sleeve-${angle}`, point(scene.shoulder), point(scene.end), axisLength));
  root.append(placeBarSprite(`bar-shaft-${angle}`, point(-scene.shoulder), point(scene.shoulder), axisLength));
  root.append(placeBarSprite(`bar-sleeve-near-${angle}`, point(-scene.end), point(-scene.shoulder), axisLength));
  if (solution.collarLb > 0) {
    const half = PLATE_SPRITES.sprites[`bar-collar-${angle}`].spanUnits / 2;
    root.append(placeBarSprite(`bar-collar-${angle}`, point(scene.collar - half), point(scene.collar + half), axisLength));
  }
  // Far plates first (+x), then near (−x): painter's order for that camera.
  // The artwork paints in that order; the focusable plate groups are appended
  // afterwards in the spoken order both clients share (each side from the
  // collar outward), so keyboard traversal never follows paint order.
  const art = el('g', { class:'barbell-plate-art', 'aria-hidden':'true' });
  root.append(art);
  const focusable = [];
  for (const d of [...scene.discs].sort((a, b) => b.x - a.x)) {
    const token = C.plateColorToken(d.plate, style);
    const colour = C.plateColour(token);
    const side = d.side < 0 ? 'left' : 'right';
    // The sprite's front face is the −x face; the scene's disc extends ±depth/2.
    const x = d.x - d.depth/2;
    const group = el('g', { class:'barbell-plate-body', tabindex:0, role:'img',
      'data-side':side, 'data-plate-value':d.plate.value, 'data-plate-denomination':C.plateLabel(d.plate),
      'data-stack-index':d.index, 'data-center-x':d.x, height:d.radius*2,
      'aria-label':discAccessibilityLabel(d) });
    // Transparent hit target over the face: focus ring, pointer, and the
    // inspection's plate activation all land here.
    group.append(el('ellipse', { class:'barbell-plate-target', cx:x, cy:d.y, rx:d.faceRadius, ry:d.radius, fill:'transparent' }));
    focusable.push({ side: d.side, index: d.index, group });
    const name = plateSpriteName(d.plate, style, exploded);
    const meta = PLATE_SPRITES.sprites[name];
    const k = d.radius / meta.faceRadius;
    const frame = { x: x - meta.faceCenter[0] * k, y: d.y - meta.faceCenter[1] * k, width: meta.size[0] * k, height: meta.size[1] * k };
    art.append(el('image', { class:'barbell-plate-face', href:spriteURL(name), ...frame, 'data-sprite':name,
      'data-center-x':d.x, preserveAspectRatio:'none', filter:`url(#${id}-${token})` }));
    const clipID = `${id}-hub-${side}-${d.index}`;
    const clip = el('clipPath', { id:clipID });
    clip.append(el('ellipse', { cx:x, cy:d.y, rx:d.faceRadius*meta.hubRadius, ry:d.radius*meta.hubRadius }));
    defs.append(clip);
    art.append(el('image', { class:'barbell-plate-hub', href:spriteURL(name), ...frame,
      preserveAspectRatio:'none', 'clip-path':`url(#${clipID})` }));
    const labelSize = exploded ? 14 : 10;
    const label = el('text', { class:'barbell-plate-label', x, y:d.y-d.radius*.48,
      'text-anchor':'middle', 'font-size':labelSize, 'font-weight':800,
      fill:colour.ink, 'data-side':side, 'data-stack-index':d.index, 'data-plate-value':d.plate.value,
      'data-plate-denomination':C.plateLabel(d.plate) });
    label.textContent = d.plate.unit === solution.bar.unit ? String(d.plate.value) : C.plateLabel(d.plate);
    art.append(label);
  }
  focusable.sort((a, b) => (a.side - b.side) || (a.index - b.index));
  for (const { group } of focusable) root.append(group);
  if (solution.collarLb > 0) {
    const half = PLATE_SPRITES.sprites[`bar-collar-near-${angle}`].spanUnits / 2;
    root.append(placeBarSprite(`bar-collar-near-${angle}`, point(-scene.collar - half), point(-scene.collar + half), axisLength));
  }
  if (!scene.discs.length) {
    const label = el('text', { x:0, y:35, fill:'currentColor', 'font-size':14, 'text-anchor':'middle' });
    label.textContent = solution.collarLb > 0 ? 'bar + collars' : 'bar only';
    root.append(label);
  }
  return { svg, solution, bar:solution.bar, plateStyle:style, scene,
    minimumLegibleWidth, baseLabelSize: exploded ? 14 : 10 };
}

// One responsive shell for every complete-bar presentation. Inline stages fit
// their container and always offer inspection. The focused expanded screen
// alone may scroll at natural scale; its exact stack list stays readable.
export function barbellStage(rendered, {
  caption = "", emphasis = "standard", onExpand = null,
} = {}) {
  const stage = document.createElement("div");
  stage.className = `barbell-stage ${emphasis}`;
  stage.setAttribute("role", "group");
  stage.setAttribute("aria-label", "Loaded bar inspection");
  const track = document.createElement("div");
  track.className = "barbell-stage-track";
  const footer = uiText("div", "barbell-stage-footer", "");
  const inspection = emphasis === "expanded";
  // The inspection opens straight ahead, assembled; a tap explodes it.
  let exploded = false;
  // The inspection shows the solid where WebGL2 exists; the sprite SVG then
  // becomes the focusable, spoken layer over it (same plates, same order).
  const solid = inspection ? barbellGL(rendered.solution, rendered.plateStyle || "steel", { exploded }) : null;
  const live = solid?.supported ? solid : null;
  stage.classList.toggle("solid", Boolean(live));
  const paint = () => {
    const drawing = realisticBarbellSVG(rendered.solution, rendered.plateStyle || "steel", exploded);
    if (live) {
      drawing.svg.classList.add("barbell-a11y-layer");
      track.replaceChildren(live.canvas, drawing.svg);
      live.setExploded(exploded);
    } else {
      track.replaceChildren(drawing.svg);
    }
    track.style.setProperty("--barbell-natural-width", `${exploded ? drawing.scene.width : 0}px`);
    stage.classList.toggle("exploded", exploded);
  };
  paint();
  stage.append(track);
  if (!inspection) stage.append(barbellReadout(rendered.solution));
  if (inspection) {
    // One quiet line says which view this is and what a tap does; the same
    // control is the accessible toggle. Tapping the artwork toggles too.
    const wording = () => live
      ? (exploded ? "Exploded · tap to assemble" : "Assembled · tap to explode")
      : (exploded ? "38° inspection · tap to collapse" : "Front view · tap to inspect");
    const toggle = uiText("button", "btn ghost sm barbell-explode", wording());
    toggle.type = "button";
    toggle.setAttribute("aria-pressed", "false");
    toggle.setAttribute("aria-label", `${toggle.textContent}. Explode plates`);
    const swipe = uiText("span", "sub", "Swipe across · inside → outside");
    swipe.hidden = true;
    const focusNote = uiText("span", "sub barbell-focus-note", "");
    focusNote.setAttribute("aria-hidden", "true");
    const flip = () => {
      exploded = !exploded;
      paint();
      toggle.textContent = wording();
      toggle.setAttribute("aria-label", `${toggle.textContent}. ${exploded ? "Assemble bar" : "Explode plates"}`);
      toggle.setAttribute("aria-pressed", String(exploded));
      swipe.hidden = !exploded || Boolean(live);
    };
    toggle.addEventListener("click", flip);
    // A plate is focusable so its name can be read; activating it must not
    // flip the view under a screen-reader user.
    track.addEventListener("click", (event) => { if (event.target.closest("[tabindex]")) return; flip(); });
    // Keyboard users see which hidden plate holds focus over the solid.
    track.addEventListener("focusin", (event) => { focusNote.textContent = event.target.getAttribute?.("aria-label") || ""; });
    track.addEventListener("focusout", () => { focusNote.textContent = ""; });
    footer.append(toggle, swipe, focusNote);
    if (live) {
      // Backdrop and reset are the keyboard path for what drag, wheel, and
      // pinch do by hand; the solid itself is not a control.
      live.canvas.setAttribute("aria-hidden", "true");
      const controls = uiText("div", "barbell-scene-controls", "");
      const group = uiText("div", "barbell-backdrop", "");
      group.setAttribute("role", "group");
      group.setAttribute("aria-label", "Backdrop");
      let current = "studio";
      for (const [name, preset] of Object.entries(BACKDROPS)) {
        const button = uiText("button", "btn ghost sm", preset.label);
        button.type = "button";
        button.dataset.backdrop = name;
        button.setAttribute("aria-pressed", String(name === current));
        button.addEventListener("click", () => {
          current = name;
          live.setBackdrop(name);
          for (const other of group.querySelectorAll("button")) other.setAttribute("aria-pressed", String(other.dataset.backdrop === name));
        });
        group.append(button);
      }
      const reset = uiText("button", "btn ghost sm barbell-reset-view", "Reset view");
      reset.type = "button";
      reset.setAttribute("aria-label", "Reset view. Returns the camera to the front view");
      reset.addEventListener("click", () => live.reset());
      controls.append(group, reset);
      stage.append(controls);
    }
  } else if (onExpand) {
    const button = uiText("button", "btn ghost sm barbell-expand", "Larger view ↗");
    button.type = "button";
    button.setAttribute("aria-label", "Inspect loaded bar and explode plates");
    button.addEventListener("click", onExpand);
    track.addEventListener("click", onExpand);
    track.addEventListener("keydown", event => {
      if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onExpand(); }
    });
    footer.append(uiText("span", "sub", caption || "Tap to inspect"), button);
  } else {
    footer.append(uiText("span", "sub", caption));
  }
  stage.append(footer);
  if (inspection) {
    const list = uiText("ol", "barbell-stack-list", "");
    list.setAttribute("aria-label", "Plates per side, inside to outside");
    for (const count of rendered.solution.perSide) {
      const row = uiText("li", "", "");
      row.append(plateBadgeSVG(count.plate, rendered.plateStyle || "steel"),
        uiText("span", "mono", `${C.plateLabel(count.plate)} × ${count.count} per side`));
      list.append(row);
    }
    if (!rendered.solution.perSide.length) list.append(uiText("li", "", rendered.solution.collarLb > 0 ? "Bar + collars" : "Bar only"));
    stage.append(list);
  }
  return stage;
}

// Exact collar-outward order on both mirrored sleeves. SVG face stamps scale
// with the physical bar; this companion text stays at a readable CSS size.
export function barbellReadout(solution) {
  const readout = uiText("div", "barbell-plate-readout", "");
  if (!solution.perSide.length) return readout;
  // The SVG already exposes each plate as a focusable, precisely named item.
  readout.setAttribute("aria-hidden", "true");
  readout.append(uiText("span", "barbell-plate-direction", "Each side · inside → outside"));
  let index = 0;
  for (const { plate, count } of solution.perSide) for (let n = 0; n < count; n++) {
    const item = uiText("span", "barbell-plate-denomination", C.plateLabel(plate));
    item.dataset.stackIndex = ++index;
    readout.append(item);
  }
  return readout;
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

// The one totals composition used anywhere Cadence explains a solved or
// entered bar — the calculator, the current set, the exercise pane, the
// workout preview. What was achieved, pounds first, kilograms after; how far
// from what was asked; which bar and what is on each side; and one cell per
// plate family so the rack is readable at a glance. `solution` is the exact
// object handed to the renderer, so the numbers and steel can never drift
// through a second calculation in the view. Mirrors native LoadoutSummaryView.
export function loadoutSummary(requestedLb, solution, { compact = false, plateStyle = "steel" } = {}) {
  const difference = requestedLb == null ? null : solution.totalLb - requestedLb;
  const sign = difference > .005 ? "+" : "";
  const summary = dom("div", `card load-summary${compact ? " compact" : ""}`);
  const hero = dom("div", "loadout-hero");
  const achieved = dom("div", "loadout-achieved");
  achieved.append(dom("span", "eyebrow accent", "Achieved with bar"));
  const weights = dom("div", "dual-weight mono");
  weights.setAttribute("role", "group");
  weights.setAttribute("aria-label", `Achieved total, bar included, ${C.both(solution.totalLb)}`);
  for (const [value, unit, primary] of [
    [solution.totalLb, "lb", true],
    [C.kgFromLb(solution.totalLb), "kg", false],
  ]) {
    const measure = dom("span", `weight-measure${primary ? " primary" : ""}`);
    measure.append(dom("span", primary ? "weight-value load-numeral" : "weight-value", C.trim(value)), dom("span", "weight-unit", unit));
    weights.append(measure);
  }
  achieved.append(weights);
  hero.append(achieved);
  if (difference != null) {
    const delta = dom("div", `loadout-delta mono${Math.abs(difference) > .01 ? " warn" : ""}`);
    delta.append(dom("strong", "", `${sign}${C.trim(difference, 2)} lb`), dom("span", "sub", `from ${C.trim(requestedLb)} lb`));
    hero.append(delta);
  }
  summary.append(hero);
  const line = dom("div", "loadout-line");
  line.append(dom("span", "sub", C.barLabel(solution.bar)),
    dom("strong", "mono", solution.perSide.length ? `${C.perSideLabel(solution.perSide)} / side`
      : solution.collarLb > 0 ? "Bar + collars" : "Bar only"));
  summary.append(line);
  const cells = dom("div", "loadout-cells");
  cells.setAttribute("role", "list");
  for (const count of solution.perSide) {
    const cell = dom("div", "loadout-cell");
    cell.setAttribute("role", "listitem");
    const text = dom("div", "loadout-cell-text");
    text.append(dom("strong", "mono", `${count.count * 2} × ${C.plateLabel(count.plate)}`),
      dom("span", "sub", plateFamilyLabel(plateFamily(count.plate, plateStyle))));
    cell.append(plateBadgeSVG(count.plate, plateStyle), text);
    cells.append(cell);
  }
  if (solution.collarLb > 0) {
    const cell = dom("div", "loadout-cell");
    cell.setAttribute("role", "listitem");
    const text = dom("div", "loadout-cell-text");
    text.append(dom("strong", "mono", "2 collars"), dom("span", "sub", "Outermost"));
    cell.append(text);
    cells.append(cell);
  }
  if (cells.childElementCount) summary.append(cells);
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
