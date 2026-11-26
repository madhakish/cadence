import { LOAD_BASES, resolvedLoadBasis } from "./core.js";
import { plateThemeMaterial } from "./plate-theme.js";

export const artURL = name => new URL(`../assets/astra/${name}`, import.meta.url).href;

export function faceFinish(plate, theme, style) {
  const { finish } = plateThemeMaterial(plate, theme, style);
  if (finish === "rubber" && (theme === "blackBumpersBand" || theme === "cadenceHouse")) return "black-rubber";
  return finish === "castIron" ? "cast-iron" : finish;
}

// Old records can predate the set's load-basis stamp. A captured basis wins
// over later library edits. Machine and bodyweight rows have no loading photo.
export function equipmentArtKind(exercise, set = null) {
  const basis = LOAD_BASES.includes(set?.loadBasis) ? set.loadBasis : resolvedLoadBasis(exercise);
  if (exercise?.type === "barbell" && basis === "totalBar") return "barbell";
  if (exercise?.type === "dumbbell" && basis === "perImplement") return "dumbbell";
  return null;
}
