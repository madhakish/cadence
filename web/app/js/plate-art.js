// Shared by the readout, the projected SVG bar and the live WebGL inspector.
// Colour, geometry and the exact denomination remain properties of the plate.
import { LOAD_BASES, resolvedLoadBasis } from "./core.js";
import { plateThemeMaterial } from "./plate-theme.js";

export const artURL = name => new URL(`../assets/astra/${name}`, import.meta.url).href;

export function faceFinish(plate, theme, style) {
  const { finish } = plateThemeMaterial(plate, theme, style);
  if (finish === "rubber" && (theme === "blackBumpersBand" || theme === "cadenceHouse")) return "black-rubber";
  return finish === "castIron" ? "cast-iron" : finish;
}

export function printedBumper(plate, theme, style) {
  const rubber = theme === "lbColourBumpers" || (theme === "custom" && style === "bumper");
  return rubber && plate.unit === "lb" && [10, 25, 35, 45, 55].includes(plate.value)
    ? `bumper-${plate.value}lb.png` : null;
}

// The wood is a load-independent property of the equipment studio.
export function platformPhoto(theme) {
  const wood = { ipfCalibrated: "walnut", ipfCalibratedGloss: "walnut", blackBumpersBand: "white-oak", iwfTraining: "maple" };
  return `platform-${wood[theme] || "oak"}.webp`;
}


// Old records can predate the set's load-basis stamp. A captured basis wins
// over later library edits. Machine and bodyweight rows have no loading photo.
export function equipmentArtKind(exercise, set = null) {
  const basis = LOAD_BASES.includes(set?.loadBasis) ? set.loadBasis : resolvedLoadBasis(exercise);
  if (exercise?.type === "barbell" && basis === "totalBar") return "barbell";
  if (exercise?.type === "dumbbell" && basis === "perImplement") return "dumbbell";
  return null;
}


// The lathed sides use millimetre-scale grain distinct from the face artwork.
export const rimMaterial = {
  rubber: ["grain-rubber.webp", .40], "black-rubber": ["grain-black-rubber.webp", .40],
  powder: ["grain-coating.webp", .25], gloss: ["grain-coating.webp", .14],
  "cast-iron": ["grain-iron.webp", .35],
};
