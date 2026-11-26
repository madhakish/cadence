// Shared compact/full barbell graphics. Callers resolve the rack through core;
// this module renders their exact solution with core colour/size metadata.
import * as C from "./core.js";
import { plateFamilyLabel } from "./barbell-scene.js";
import { artURL } from "./plate-art.js";
import { plateThemeFamily } from "./plate-theme.js";
import { photographicBar, plateBadgeSVG } from "./barbell-photo.js";
export { plateBadgeSVG };

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
export function barbellSVG(solution, presentation = "compact", plateStyle = "steel", { emphasis = "standard", plateTheme = "custom" } = {}) {
  if (!solution?.bar || !Array.isArray(solution?.perSide)) {
    throw new TypeError("barbellSVG requires a complete plate solution");
  }
  const rendered = photographicBar(solution, plateStyle, false, plateTheme);
  rendered.svg.classList.add(`emphasis-${emphasis}`);
  if (presentation !== "full") {
    rendered.svg.classList.remove("full");
    rendered.svg.classList.add("compact");
    rendered.svg.setAttribute("viewBox", `0 155 ${rendered.scene.width} 570`);
    rendered.svg.setAttribute("width", "100%");
  }
  return rendered;
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
  const surface = uiText("div", "barbell-inspection-surface", "");
  const captions = uiText("div", "barbell-disc-captions", "");
  const discs = rendered.solution.perSide.flatMap(({ plate, count }) => Array.from({ length: count }, () => plate));
  const labels = discs.map((plate, index) => {
    const label = uiText("span", "barbell-disc-caption", `${plate.value} ${plate.unit}`);
    label.dataset.stackIndex = String(index);
    label.tabIndex = 0;
    label.setAttribute("role", "img");
    label.setAttribute("aria-label", `${plate.value} ${plate.unit} plate, ${index + 1} from inside, one side shown`);
    captions.append(label);
    return label;
  });
  const positionCaption = (index, x, y) => {
    const label = labels[index], bounds = label.getBoundingClientRect();
    const half = bounds.width / 2 + 2;
    label.style.left = `clamp(${half}px, ${x}%, calc(100% - ${half}px))`;
    label.style.top = `clamp(4px, ${y}%, calc(100% - ${bounds.height + 4}px))`;
  };
  const paint = () => {
    const drawing = exploded ? photographicBar(rendered.solution, rendered.plateStyle, true, rendered.plateTheme) : rendered;
    captions.hidden = !exploded;
    if (inspection) {
      if (exploded) {
        drawing.svg.setAttribute("aria-hidden", "true");
        for (const plate of drawing.svg.querySelectorAll("[tabindex]")) plate.removeAttribute("tabindex");
      }
      surface.style.setProperty("--photo-aspect", String(drawing.scene.width / drawing.scene.height));
      surface.replaceChildren(drawing.svg, captions);
      track.replaceChildren(surface);
      const minimum = exploded ? discs.length * 112 + 32 : 0;
      surface.style.minWidth = `${minimum}px`;
      for (const disc of drawing.scene.discs.filter(d => d.side < 0)) {
        positionCaption(disc.index, disc.x / drawing.scene.width * 100, 86);
      }
    } else {
      track.replaceChildren(drawing.svg);
    }
    stage.classList.toggle("exploded", exploded);
  };
  paint();
  stage.append(track);
  if (!inspection) stage.append(barbellReadout(rendered.solution));
  if (inspection) {
    // One quiet line says which view this is and what a tap does; the same
    // control is the accessible toggle. Tapping the artwork toggles too.
    const wording = () => exploded ? "Assemble stack" : "Inspect plates";
    const toggle = uiText("button", "btn ghost sm barbell-explode", wording());
    toggle.type = "button";
    toggle.setAttribute("aria-pressed", "false");
    toggle.setAttribute("aria-label", `${toggle.textContent}. Explode plates`);
    const swipe = uiText("span", "sub", "Scroll for more plates");
    swipe.hidden = true;
    const focusNote = uiText("span", "sub barbell-focus-note", "");
    focusNote.setAttribute("aria-hidden", "true");
    const flip = () => {
      exploded = !exploded;
      paint();
      toggle.textContent = wording();
      toggle.setAttribute("aria-label", `${toggle.textContent}. ${exploded ? "Assemble bar" : "Explode plates"}`);
      toggle.setAttribute("aria-pressed", String(exploded));
      swipe.hidden = !exploded || track.scrollWidth <= track.clientWidth + 1;
    };
    toggle.addEventListener("click", flip);
    // A plate is focusable so its name can be read; activating it must not
    // flip the view under a screen-reader user.
    let down = null;
    track.addEventListener("pointerdown", event => { down = { x: event.clientX, y: event.clientY }; });
    track.addEventListener("click", (event) => {
      if (event.target.closest(".barbell-disc-caption")) return;
      if (event.detail === 0 && event.target.closest(".barbell-plate-body")) return;
      if (down && Math.hypot(event.clientX - down.x, event.clientY - down.y) > 8) { down = null; return; }
      down = null;
      flip();
    });
    // Keep the focused plate's description visible alongside the diagram.
    track.addEventListener("focusin", (event) => { focusNote.textContent = event.target.getAttribute?.("aria-label") || ""; });
    track.addEventListener("focusout", () => { focusNote.textContent = ""; });
    footer.append(toggle, swipe, focusNote);

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
      row.append(plateBadgeSVG(count.plate, rendered.plateStyle || "steel", { exact: true, plateTheme: rendered.plateTheme || "custom" }),
        uiText("span", "mono", `${count.plate.value} ${count.plate.unit} × ${count.count} per side`));
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
export function loadoutSummary(requestedLb, solution, { compact = false, plateStyle = "steel", plateTheme = "custom" } = {}) {
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
      dom("span", "sub", plateFamilyLabel(plateThemeFamily(count.plate, plateTheme, plateStyle))));
    cell.append(plateBadgeSVG(count.plate, plateStyle, { plateTheme }), text);
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
  const value = unit === "kg" ? C.kgFromLb(weightLb) : weightLb;
  const amount = `${C.trim(value)} ${unit} each`;
  const row = uiText("span", "dumbbell", "");
  row.setAttribute("role", "img");
  row.setAttribute("aria-label", `Dumbbell, ${amount}`);
  const image = document.createElement("img");
  image.src = artURL("dumbbell.png");
  image.alt = "";
  image.width = 58; image.height = 38;
  row.append(image, uiText("span", "", amount));
  return row;
}
