// Place registered photographs in the camera that photographed the empty stage.
// The solver owns the load, and the shared physical model owns each millimetre.
import { both, perSideLabel, plateLabel } from "./core.js";
import { barbellLayout, BORE_RADIUS } from "./barbell-inspector.js";
import { discAccessibilityLabel } from "./barbell-scene.js";
import { faceFinish } from "./plate-art.js";
import { plateThemeColour, plateThemeDescription, plateThemeFamily, plateThemeGeometry } from "./plate-theme.js";

const NS = "http://www.w3.org/2000/svg";
const WIDTH = 1672, HEIGHT = 941;
const FACE_RATIO = .55;
let serial = 0;
function svgElement(tag, attributes = {}) {
  const node = document.createElementNS(NS, tag);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
  return node;
}

export const stageForTheme = theme => ({
  ipfCalibrated: "AstraPhotoStageWalnut", ipfCalibratedGloss: "AstraPhotoStageWalnut",
  blackBumpersBand: "AstraPhotoStageWhiteOak", iwfTraining: "AstraPhotoStageMaple",
}[theme] || "AstraPhotoStage");
const faces = { rubber: "Rubber", "black-rubber": "BlackRubber", powder: "Coated", gloss: "Gloss",
  "cast-iron": "Iron", hammertone: "Hammertone", machined: "Machined" };
const edges = { rubber: "Rubber", "black-rubber": "Rubber", powder: "Coated", gloss: "Coated",
  "cast-iron": "Iron", hammertone: "Iron", machined: "Iron" };
export const facePhoto = finish => "PhotoFace" + faces[finish];
export const edgePhoto = finish => "PhotoEdge" + edges[finish];

function photo(name, frame, attributes = {}) {
  const ext = name.startsWith("AstraPhotoStage") ? "jpg" : "png";
  return svgElement("image", { href: new URL(`../assets/photo/${name}.${ext}`, import.meta.url).href,
    preserveAspectRatio: "none", ...frame, ...attributes });
}

// The two 450 mm discs in study 03 measure 409 and 321 px; the near and far
// bores land at (357,446) and (1351,332) in its 1672 × 941 full frame.
export function stagePoint(mm, supportRadius = 225) {
  const t = (Math.max(-1120, Math.min(1120, mm)) + 765) / 1470;
  const k = 409 / 321 - 1, divider = 1 + k * t;
  const u = t * (1 + k) / divider;
  const scale = 409 / (450 * divider);
  let x = 357 + 994 * u, y = 446 - 114 * u;
  if (mm < -765) {
    const tip = (-765 - mm) / 355;
    x = 357 - 291 * tip;
    y = 446 + 34 * tip;
  } else if (mm > 705) {
    const tip = (mm - 705) / 415;
    x = 1351 + 199 * tip;
    y = 332 - 17 * tip;
  }
  return { x, y: y + (225 - supportRadius) * scale, scale };
}

function photoScene(solution, style, theme, explode) {
  const layout = barbellLayout(solution, style, 0, {}, theme);
  const { bar, collar } = layout;
  const support = Math.max(bar.shoulderRadius, collar.radius, ...layout.discs.map(d => d.radius));
  const near = layout.discs.filter(d => d.side < 0);
  const exploded = explode && near.length > 0;
  let width = WIDTH, height = HEIGHT;
  let point = mm => stagePoint(mm, support);
  const centers = new Map();
  let slope = .055;
  if (exploded) {
    // An exploded diagram is an inspection of the near sleeve. Move each
    // piece along the same axis without changing its diameter or thickness.
    height = 630;
    let cursor = 100 + collar.length;
    for (const disc of [...near].reverse()) {
      const half = Math.max(64, disc.radius * FACE_RATIO + disc.thickness * .42);
      centers.set(disc.index, cursor + half);
      cursor += half * 2 + 24;
    }
    width = Math.max(670, cursor + 150);
    slope = Math.min(.055, 90 / width);
    const inner = centers.get(0);
    point = mm => {
      const x = inner + (mm - near[0].centerX) * .83;
      return { x, y: 315 - (x - width / 2) * slope, scale: 1 };
    };
  }
  const discs = (exploded ? near : layout.discs).map(disc => {
    const worldFront = disc.centerX - disc.thickness / 2;
    const front = point(worldFront);
    const back = point(worldFront + disc.thickness);
    if (exploded) {
      front.x = centers.get(disc.index) - (back.x - front.x) / 2;
      front.y = 315 - (front.x - width / 2) * slope;
      back.x = front.x + disc.thickness * .83;
      back.y = front.y - disc.thickness * .83 * slope;
    }
    const faceRatio = exploded ? FACE_RATIO : FACE_RATIO + .17 * Math.max(0, Math.min(1, (worldFront + 765) / 1470));
    return { ...disc, x: front.x, y: front.y, rx: disc.radius * front.scale * faceRatio,
      ry: disc.radius * front.scale, scale: front.scale, back, worldFront };
  });
  // Long hand-entered stacks remain complete in their assembled overview.
  const reach = Math.max(...discs.flatMap(d => [WIDTH / 2 - d.x + d.rx + 28, d.x + d.rx - WIDTH / 2 + 28]), WIDTH / 2);
  const fit = exploded ? 1 : Math.min(1, WIDTH / (2 * reach + (reach > WIDTH / 2 ? collar.length * 2 : 0)));
  return { bar, collar, discs, point, width, height, fit, support, exploded, slope };
}

function pigment(defs, cache, id, fill) {
  if (cache.has(fill)) return cache.get(fill);
  const filter = svgElement("filter", { id: `${id}-fill-${fill.slice(1)}`, "color-interpolation-filters": "sRGB" });
  const transfer = svgElement("feComponentTransfer");
  for (const [index, channel] of ["R", "G", "B"].entries()) {
    const middle = parseInt(fill.slice(1 + index * 2, 3 + index * 2), 16) / 255;
    transfer.append(svgElement("feFunc" + channel, { type: "table", tableValues: `0 ${middle} 1` }));
  }
  filter.append(transfer);
  defs.append(filter);
  const ref = `url(#${filter.id})`;
  cache.set(fill, ref);
  return ref;
}

function registerFace(defs, group, { plate, radius, rx, ry }, theme, style, fillFilter, id, attributes = {}) {
  // All face photos are tightly registered to their outside diameter. Punch
  // the same physical bore through pigment and steel when the hub is capped.
  const bore = Math.min(.88, BORE_RADIUS / radius);
  const clip = svgElement("clipPath", { id: id + "-bore" });
  const hole = `M ${bore} 0 a ${bore} ${bore} 0 1 1 ${-2 * bore} 0 a ${bore} ${bore} 0 1 1 ${2 * bore} 0`;
  clip.append(svgElement("path", { d: `M -1 -1 h 2 v 2 h -2 Z ${hole}`, "clip-rule": "evenodd" }));
  defs.append(clip);
  const layer = svgElement("g", { transform: `scale(${rx} ${ry})`, "clip-path": `url(#${clip.id})` });
  const finish = faceFinish(plate, theme, style);
  layer.append(photo(facePhoto(finish), { x: -1, y: -1, width: 2, height: 2 }, {
    class: "barbell-plate-face", filter: fillFilter, "data-finish": finish, ...attributes }));
  const { band, ink, fill } = plateThemeColour(plate, theme, style);
  const [red, green, blue] = fill.slice(1).match(/../g).map(channel => parseInt(channel, 16));
  const warm = finish === "rubber" && radius >= 150 && blue > red * 1.3 && blue > green * 1.2;
  const family = plateThemeFamily(plate, theme, style);
  const ratio = { bumper: .40, steel: .20, ipf: .20, iron: .24, machined: .22, change: .25 }[family];
  const hub = Math.min(.55, Math.max(33 / radius, Math.min(ratio, 90 / radius)));
  const dark = ["castIron", "hammertone", "blackSteel"].includes(plateThemeDescription(theme).hubFinish);
  if (warm && hub * radius > 75) {
    // The warm 180 mm insert has a 60 mm recess. Its steel bore liner
    // continues down to the 50 mm sleeve through the recessed lip.
    const liner = 75 / radius;
    layer.append(photo("PhotoHub", { x: -liner, y: -liner, width: 2 * liner, height: 2 * liner }, { class: "barbell-bore-liner" }));
  }
  layer.append(photo(warm ? "PhotoHubWarm" : "PhotoHub", { x: -hub, y: -hub, width: 2 * hub, height: 2 * hub },
    { class: "barbell-plate-hub", ...(dark ? { style: "filter:brightness(.58)" } : {}) }));
  if (band) layer.append(svgElement("circle", { r: .91, fill: "none", stroke: band, "stroke-width": .027 }));
  if (plateThemeDescription(theme).details?.includes("hubRing")) {
    layer.append(svgElement("circle", { r: hub * 1.02, fill: "none", stroke: ink, "stroke-width": .016 }));
  }
  group.append(layer);
}

function markPlate(group, plate, ink, rx, ry, attrs, large, referencePrint) {
  // The artwork's name arcs above its insert and the actual denomination is
  // stamped below it. Tangent-plane lettering shares the face perspective.
  const print = svgElement("g", { fill: ink, opacity: .92, "font-family": "Arial Narrow, sans-serif",
    transform: `scale(${rx / ry} 1)`, "text-anchor": "middle", "font-weight": 700 });
  if (large) {
    group.append(photo("PhotoBrand", { x: -rx, y: -ry, width: rx * 2, height: ry * 2 }, { class: "barbell-brand" }));
  }
  const mark = { "45 lb": "PhotoMark45lb", "20 kg": "PhotoMark20kg", "15 kg": "PhotoMark15kg" }[plateLabel(plate)];
  if (mark) {
    const image = photo(mark, { x: -rx, y: -ry, width: rx * 2, height: ry * 2 }, {
      class: "barbell-plate-label", ...attrs,
      ...(mark === "PhotoMark15kg" && parseInt(ink.slice(1, 3), 16) > 180 ? { style: "filter:brightness(0) invert(.85)" } : {}),
    });
    const label = svgElement("title");
    label.textContent = plateLabel(plate);
    image.append(label);
    group.append(image);
    return;
  }
  const value = svgElement("text", { class: "barbell-plate-label", x: 0, y: ry * .72, "font-size": ry * .19,
    "letter-spacing": ry * .018, ...(referencePrint ? { fill: "#d7ae7d" } : {}), ...attrs });
  value.textContent = plateLabel(plate);
  value.style.textTransform = "uppercase";
  // Exact fractional denominations can be arbitrarily long.
  if (value.textContent.length > 7) {
    value.setAttribute("textLength", ry * 1.21);
    value.setAttribute("lengthAdjust", "spacingAndGlyphs");
  }
  print.append(value);
  group.append(print);
}

export function plateBadgeSVG(plate, style = "steel", { plateTheme = "custom" } = {}) {
  const id = "plate-key-" + ++serial;
  const svg = svgElement("svg", { class: `plate-badge ${style}`, viewBox: "-26 -26 52 52", "aria-hidden": "true", focusable: "false" });
  const colour = plateThemeColour(plate, plateTheme, style);
  const defs = svgElement("defs");
  svg.append(defs);
  const radius = plateThemeGeometry(plate, plateTheme, style).diameter / 2;
  registerFace(defs, svg, { plate, radius, rx: 25.5, ry: 25.5 }, plateTheme, style, pigment(defs, new Map(), id, colour.fill), id);
  markPlate(svg, plate, colour.ink, 25.5, 25.5, {}, radius >= 125, plateTheme === "lbColourBumpers");
  return svg;
}

function cylinder(root, name, part, from, to, radius, dark = false) {
  if (to.x <= from.x) return;
  const dx = to.x - from.x, dy = to.y - from.y;
  const length = Math.hypot(dx, dy);
  const r = radius * (from.scale + to.scale) / 2;
  root.append(photo(name, { x: 0, y: -r, width: length, height: 2 * r }, {
    class: `barbell-${part}`, transform: `translate(${from.x} ${from.y}) rotate(${Math.atan2(dy, dx) * 180 / Math.PI})`,
    ...(dark ? { style: "filter:brightness(.45)" } : {}),
  }));
}

// Study 03's lock has a closed lever and a punched-through aperture. Its
// near opening and the plate-side end of the lock are independently registered.
function fittedLock(art, rear, side, onSleeve) {
  const width = 450 * rear.scale * .2574, height = 450 * rear.scale * .2475;
  const group = svgElement("g", { transform: `translate(${rear.x} ${rear.y}) matrix(${-side} ${side > 0 ? .23 : 0} 0 1 0 0)` });
  if (onSleeve) {
    // The inside wall under the closed lock is in shadow; the continuous
    // chrome is overlaid up to the front lip after the clamp is seated.
    group.append(svgElement("ellipse", { cx: -.66 * width, cy: .109 * height,
      rx: .124 * width, ry: .257 * height, fill: "#171512" }));
  }
  group.append(photo(onSleeve ? "PhotoLock" : "PhotoCollar", { x: -.781 * width, y: -.416 * height, width, height },
    { class: side < 0 ? "barbell-collar-near" : "barbell-collar" }));
  art.append(group);
  return { x: rear.x + side * .662 * width, y: rear.y + .109 * height, scale: rear.scale };
}

// Repaint the same uninterrupted sleeve photo as far as the foreground bore.
// The ellipse ends inside the opening; the steel has no square cut across it.
function exposeSleeve(art, defs, sleeve, tip, entry, id, radius, part = "exposed-sleeve") {
  if (entry.x <= tip.x) return;
  const dx = entry.x - tip.x, dy = entry.y - tip.y, length = Math.hypot(dx, dy);
  const r = radius * entry.scale;
  const clip = svgElement("clipPath", { id: id + "-entry" });
  clip.append(svgElement("path", {
    transform: `translate(${tip.x} ${tip.y}) rotate(${Math.atan2(dy, dx) * 180 / Math.PI})`,
    d: `M -30 ${-r * 1.25} L ${length} ${-r} A ${r * FACE_RATIO} ${r} 0 0 1 ${length} ${r} L -30 ${r * 1.25} Z`,
  }));
  defs.append(clip);
  const foreground = svgElement("g", { "clip-path": `url(#${clip.id})` });
  const continuation = sleeve.cloneNode(false);
  continuation.setAttribute("class", "barbell-" + part);
  foreground.append(continuation);
  art.append(foreground);
}

function drawPlate(art, defs, d, style, theme, filter, id) {
  const { x, y, rx, ry, back, plate } = d;
  const dx = back.x - x, dy = back.y - y;
  const colour = plateThemeColour(plate, theme, style);
  const side = d.side < 0 ? "left" : "right";
  const key = `${id}-${side}-${d.index}`;
  const group = svgElement("g", { transform: `translate(${x} ${y}) matrix(1 0 .04 1 0 0)` });
  const rimClip = svgElement("clipPath", { id: key + "-rim" });
  rimClip.append(svgElement("path", { d: `M 0 ${-ry} L ${dx} ${dy - ry} A ${rx} ${ry} 0 0 1 ${dx} ${dy + ry} L 0 ${ry} A ${rx} ${ry} 0 0 0 0 ${-ry} Z` }));
  defs.append(rimClip);
  const finish = faceFinish(plate, theme, style);
  group.append(photo(edgePhoto(finish), { x: -.5, y: -ry + Math.min(0, dy), width: dx + rx + 1, height: ry * 2 + Math.abs(dy) }, {
    class: "barbell-plate-rim", filter: filter(colour.fill), "clip-path": `url(#${rimClip.id})` }));
  registerFace(defs, group, d, theme, style, filter(colour.fill), key, { "data-center-x": d.centerX });
  const attrs = { "data-side": side, "data-stack-index": d.index, "data-plate-value": plate.value, "data-plate-denomination": plateLabel(plate) };
  markPlate(group, plate, colour.ink, rx, ry, attrs, d.radius >= 125, theme === "lbColourBumpers");
  art.append(group);
  const target = svgElement("g", { class: "barbell-plate-body", tabindex: 0, role: "img", height: d.radius * 2,
    "data-center-x": d.centerX, "aria-label": discAccessibilityLabel(d), ...attrs });
  target.append(svgElement("ellipse", { class: "barbell-plate-target", cx: x, cy: y, rx, ry, fill: "transparent" }));
  return target;
}

export function photographicBar(solution, style, explode = false, theme = "custom") {
  const scene = photoScene(solution, style, theme, explode);
  const { bar, collar, point, discs, width, height, fit, exploded } = scene;
  const id = "bar-photo-" + ++serial;
  const stack = solution.perSide.length ? perSideLabel(solution.perSide) + " per side" : solution.collarLb > 0 ? "with collars, no plates" : "bar only";
  const svg = svgElement("svg", { id, class: `barbell full ${style} realistic`, viewBox: `0 0 ${width} ${height}`,
    role: "group", "aria-label": `${explode ? "Exploded" : "Assembled"} loaded bar, ${both(solution.totalLb)}, ${stack}`, "data-exploded": explode });
  if (!discs.length) {
    const title = svgElement("title");
    title.textContent = solution.collarLb > 0 ? "bar + collars" : "bar only";
    svg.append(title);
  }
  const defs = svgElement("defs");
  const cache = new Map();
  const filter = fill => pigment(defs, cache, id, fill);
  const blur = svgElement("filter", { id: id + "-shadow", x: "-100%", y: "-250%", width: "300%", height: "600%" });
  blur.append(svgElement("feGaussianBlur", { stdDeviation: 4 }));
  const spread = blur.cloneNode(true);
  spread.id = id + "-penumbra";
  spread.firstElementChild.setAttribute("stdDeviation", 13);
  defs.append(spread);
  defs.append(blur);
  svg.append(defs, photo(stageForTheme(theme), { x: 0, y: 0, width, height }, {
    class: "barbell-platform", preserveAspectRatio: "xMidYMid slice", "aria-hidden": true }));
  const root = svgElement("g", { transform: `translate(${width * (1 - fit) / 2} ${height * (1 - fit) / 2}) scale(${fit})` });
  const art = svgElement("g", { "aria-hidden": true });
  svg.append(root);
  root.append(art);
  const shadows = svgElement("g", { fill: "#100d0b", opacity: .72, filter: `url(#${blur.id})` });
  for (const d of discs) {
    const floor = d.y + (exploded ? 238 : scene.support * d.scale);
    const lift = Math.max(0, floor - (d.y + d.ry));
    const contact = Math.abs(scene.support - d.radius) < 1;
    if (!exploded && contact) {
      const cx = d.x + d.side * d.ry * .55, cy = floor + d.ry * .075;
      art.append(svgElement("ellipse", { cx, cy, rx: d.ry * .88, ry: d.ry * .12,
        transform: `rotate(${d.side * 8} ${cx} ${cy})`, fill: "#0b0808", opacity: .68, filter: `url(#${spread.id})` }));
    }
    shadows.append(svgElement("ellipse", { cx: d.x - 8 - lift * .21, cy: floor + 1.5,
      rx: d.rx * .62 + (d.back.x - d.x) / 2 + lift * .30, ry: 7 + lift * .05, opacity: .91 / (1 + lift * .012) }));
  }
  const end = bar.shoulderEnd + bar.sleeveLength;
  if (!discs.length) {
    for (const side of [-1, 1]) {
      const p = point(side * (collar.length ? Math.abs(collar.left) : bar.shoulderEnd));
      shadows.append(svgElement("ellipse", { cx: p.x - 8, cy: p.y + scene.support * p.scale, rx: 33, ry: 5 }));
    }
  }
  art.append(shadows);
  const hardware = (name, part, start, finish, radius, dark) => cylinder(art, name, part, point(start), point(finish), radius, dark);
  const targets = [];
  const paintSide = side => {
    for (const d of discs.filter(d => d.side === side).sort((a, b) => b.centerX - a.centerX)) {
      targets.push({ side, index: d.index, target: drawPlate(art, defs, d, style, theme, filter, id) });
    }
  };
  if (!exploded) {
    hardware("PhotoSleeve", "sleeve", bar.shoulderEnd, end, bar.sleeveRadius);
    if (collar.length) fittedLock(art, point(collar.right), 1, collar.right < end);
    paintSide(1);
    hardware("PhotoShoulder", "shoulder", bar.shaftHalfLength, bar.shoulderEnd, bar.shoulderRadius);
  }
  hardware("PhotoShaft", "shaft", -bar.shaftHalfLength, bar.shaftHalfLength, bar.shaftRadius, plateThemeDescription(theme).barFinish === "blackOxide");
  hardware("PhotoShoulder", "shoulder-near", -bar.shoulderEnd, -bar.shaftHalfLength, bar.shoulderRadius);
  hardware("PhotoSleeve", "sleeve-near", -end, -bar.shoulderEnd, bar.sleeveRadius);
  paintSide(-1);
  // The bore is open. Cover only the part of the near sleeve that actually
  // protrudes past the outer face. A floating exploded plate past the tip
  // must never sprout an extension made out of an SVG cylinder.
  const outer = discs.filter(d => d.side < 0).at(-1);
  const tip = point(-end);
  let entry = outer && !exploded ? point(outer.worldFront) : null;
  const sleeve = art.querySelector(".barbell-sleeve-near");
  if (entry && collar.length) {
    exposeSleeve(art, defs, sleeve, tip, entry, id + "-under-lock", bar.sleeveRadius, "sleeve-under-lock");
  }
  if (collar.length) {
    if (exploded) {
      const right = outer.x - outer.rx - 24, y = outer.y + (outer.x - right) * scene.slope;
      const h = collar.radius * 2.4, w = h * 375 / 384;
      art.append(photo("PhotoCollar", { x: right - w, y: y - h / 2, width: w, height: h }, { class: "barbell-collar-near" }));
    } else {
      entry = fittedLock(art, point(collar.left), -1, collar.left > -end);
    }
  }
  if (entry) exposeSleeve(art, defs, sleeve, tip, entry, id, bar.sleeveRadius);
  const r = bar.sleeveRadius * tip.scale;
  // When an exploded plate floats in front of the sleeve tip, its own bore
  // and photographed face must occlude that cap.
  const cap = photo("PhotoEndcap", { x: tip.x - r * FACE_RATIO, y: tip.y - r, width: r * 2 * FACE_RATIO, height: r * 2 }, { class: "barbell-endcap" });
  if (exploded) art.querySelector(".barbell-sleeve-near").after(cap);
  else if (!outer || tip.x <= outer.x) art.append(cap);
  targets.sort((a, b) => a.side - b.side || a.index - b.index).forEach(item => root.append(item.target));
  return { svg, solution, bar: solution.bar, plateStyle: style, plateTheme: theme, scene };
}
