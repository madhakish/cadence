// Presentation-only reference profiles. Never written into exercise/gym data.
import * as C from "./core.js";
import { plateThemeGeometry } from "./plate-theme.js";

// The one spoken name for a plate on the bar, on both clients. Mirrors
// CadenceCore BarbellScene.Disc.accessibilityLabel.
export const discAccessibilityLabel = (disc) =>
  `${C.plateLabel(disc.plate)} plate, ${disc.index + 1} from inside, ${disc.side < 0 ? "left" : "right"} side`;

const BUMPER = {
  '25-kg': [450, 70], '20-kg': [450, 60], '15-kg': [450, 48], '10-kg': [450, 35], '5-kg': [450, 25],
  '55-lb': [450, 75], '45-lb': [450, 65], '35-lb': [450, 52], '25-lb': [450, 40], '10-lb': [450, 25],
};
const STEEL = {
  '25-kg': [450, 27], '20-kg': [450, 22], '15-kg': [400, 21], '10-kg': [325, 20], '5-kg': [230, 20],
  '55-lb': [450, 30], '45-lb': [450, 27], '35-lb': [400, 25], '25-lb': [325, 23], '10-lb': [230, 20],
};
const CHANGE = {
  '2.5-kg': [210, 19], '2-kg': [190, 19], '1.5-kg': [175, 18], '1.25-kg': [160, 16],
  '1-kg': [160, 16], '0.5-kg': [135, 12], '5-lb': [190, 19], '2.5-lb': [160, 16], '1.25-lb': [135, 12],
};
// The physical family a denomination belongs to in a style. Names the cell in
// the loadout summary; never changes geometry or mass. Mirrors CadenceCore
// PlateGeometry.family / familyLabel.
export function plateFamily(plate, style = 'steel') {
  const key = `${plate.value}-${plate.unit}`;
  if (style === 'bumper' && BUMPER[key]) return 'bumper';
  if (STEEL[key]) return 'steel';
  return 'change';
}
export const plateFamilyLabel = (family) => ({ bumper: 'Bumpers', steel: 'Steel', ipf: 'Steel', machined: 'Steel', iron: 'Iron' })[family] || 'Change';

export function plateGeometry(plate, style = 'steel') {
  const key = `${plate.value}-${plate.unit}`;
  const [diameter, thickness] = (style === 'bumper' ? BUMPER : STEEL)[key] || CHANGE[key] || [200, 20];
  return { diameter, thickness };
}
// Photographic face colourisation, mirrored from CadenceCore PlateFaceTint: a
// 5×4 colour matrix (row-major R, G, B, A rows of five) that rebuilds every
// channel from the texture's luminance, so the plate keeps its photographed
// shading and takes its hue from the palette fill.
export const PLATE_TINT_IDENTITY = [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];
// Share of the palette fill each pigment's median face reaches under the scene
// light, matched to the approved plate-loading mockups: coated rubber and
// painted iron read deep and matte (blue deepest), while yellow and white stay
// bright. Black iron keeps its own dark fill.
export const PLATE_TINT_TARGET = Object.freeze({ red: 0.62, blue: 0.49, green: 0.6, yellow: 0.72, white: 0.72, black: 1 });
export const plateTintTarget = (token) => PLATE_TINT_TARGET[token] ?? 0.6;
// Median face luminance of each rendered sprite family (measured, hub excluded).
export const plateTintLift = (style, token) => plateTintLiftForTarget(style, plateTintTarget(token));
const plateTintLiftForTarget = (style, target) => target / (style === "bumper" ? 0.459 : 0.453);
// A theme fill takes the target of the nearest palette pigment (sRGB
// distance): dark iron and black rubber land on black and keep their own fill,
// federation colours on their hue. Mirrors PlateFaceTint.target(forFill:).
export function plateTintTargetForFill(fill) {
  const rgb = (hex) => { const v = Number.parseInt(hex.slice(1), 16); return [16, 8, 0].map((s) => (v >> s) & 255); };
  const a = rgb(fill);
  let best = ["", Infinity];
  for (const token of ["red", "blue", "green", "yellow", "white", "black"]) {
    const b = rgb(C.PLATE_COLOURS[token].fill);
    const d = a.reduce((sum, x, i) => sum + (x - b[i]) * (x - b[i]), 0);
    if (d < best[1]) best = [token, d];
  }
  return plateTintTarget(best[0]);
}
export const PLATE_TINT_GREY_MIX = 0.04;
export function plateTintMatrix(token, style = "steel") {
  const fill = C.PLATE_COLOURS[token]?.fill;
  return fill ? plateTintMatrixForFill(fill, style, plateTintTarget(token)) : PLATE_TINT_IDENTITY;
}
// Colourises the face from any "#rrggbb" fill (a theme's colour rule). target
// overrides the pigment share; null takes the nearest pigment's.
export function plateTintMatrixForFill(fill, style = "steel", target = null) {
  const hex = Number.parseInt(fill.slice(1), 16);
  const channels = [16, 8, 0].map((shift) => ((hex >> shift) & 255) / 255);
  const lift = plateTintLiftForTarget(style, target ?? plateTintTargetForFill(fill)), grey = lift * PLATE_TINT_GREY_MIX;
  const luma = [0.2126, 0.7152, 0.0722];
  const rows = [];
  for (const channel of channels) {
    const weight = channel * lift + (1 - channel) * grey;
    rows.push(...luma.map((l) => l * weight), 0, 0);
  }
  rows.push(0, 0, 0, 1, 0);
  return rows;
}
// The colour a neutral texel of luminance l becomes: [r, g, b], clamped.
export const plateTintApply = (matrix, l) => [0, 5, 10].map((i) => Math.min(1, matrix[i] * l + matrix[i + 1] * l + matrix[i + 2] * l));
export function barbellScene(solution, style = 'steel', exploded = false, geometry = {}, theme = 'custom') {
  const angle = (exploded ? 38 : 18) * Math.PI / 180;
  const axisX = Math.cos(angle), axisY = -Math.sin(angle) * .24, faceScale = Math.sin(angle);
  const shoulder = (solution.bar.unit === 'kg' ? solution.bar.value === 15 : solution.bar.value === 35) ? 145 : 165;
  const plates = solution.perSide.flatMap(c => Array.from({ length: Math.max(0, c.count) }, () => c.plate));
  const discs = [];
  let cursor = shoulder + 8;
  let previousFaceRadius = 0;
  plates.forEach((plate, index) => {
    const shape = geometry[`${plate.value}-${plate.unit}`] || plateThemeGeometry(plate, theme, style);
    const radius = Math.max(1, shape.diameter) * .18, depth = Math.max(1, shape.thickness) * .36;
    const faceRadius = radius * faceScale;
    // Both adjacent faces must fit, especially large plates beside change plates.
    if (exploded) cursor += (previousFaceRadius + faceRadius + 22) / axisX;
    for (const side of [-1, 1]) {
      const center = side * (cursor + depth / 2);
      discs.push({ plate, side, index, x: center * axisX, y: center * axisY,
        radius, faceRadius, depth: depth * axisX, theme });
    }
    cursor += depth + (exploded ? 0 : 2);
    previousFaceRadius = faceRadius;
  });
  const collar = cursor + 8, end = Math.max(shoulder + 150, collar + 28);
  const width = Math.max(end * axisX + 25, ...discs.map(d => Math.abs(d.x) + d.faceRadius + d.depth)) * 2 + 24;
  const height = Math.max(110, ...discs.map(d => Math.abs(d.y) + d.radius)) * 2 + 40;
  discs.sort((a, b) => a.x - b.x);
  return { discs, width, height, shoulder, end, collar, axisX, axisY, faceScale };
}
