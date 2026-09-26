// Language-neutral snapshot of the plate theme model (plate-theme.js), shared
// with CadenceCore PlateThemeTests. One row per theme × plate id in its kg and
// lb sets; `custom` rows cover every plate id any theme uses, in both styles,
// because custom is the style-driven legacy look.
import * as T from "../app/js/plate-theme.js";
import { barbellLayout } from "../app/js/barbell-inspector.js";
import { plateFamilyLabel, plateTintMatrixForFill, plateTintTargetForFill } from "../app/js/barbell-scene.js";

const plateOf = (id) => { const [value, unit] = id.split("-"); return { value: Number(value), unit }; };

function row(id, theme, style) {
  const plate = plateOf(id);
  const { diameter, thickness } = T.plateThemeGeometry(plate, theme, style);
  const { fill, edge, ink, band } = T.plateThemeColour(plate, theme, style);
  const { finish, metal, roughness, photoFamily } = T.plateThemeMaterial(plate, theme, style);
  const { hub, photoHub, rim } = T.plateThemeRatios(plate, theme, style);
  return { plate: id, style, diameter, thickness, family: T.plateThemeFamily(plate, theme, style),
    fill, edge, ink, band, finish, metal, roughness, photoFamily, hub, photoHub, rim };
}

function normalizedThemes() {
  const setIds = (theme) => ["kg", "lb"].flatMap((unit) => T.plateThemeSet(unit, theme).map((p) => `${p.value}-${p.unit}`));
  const everyId = [...new Set(T.PLATE_THEME_IDS.flatMap(setIds))];
  return T.PLATE_THEME_IDS.map((id) => {
    const t = T.plateThemeDescription(id);
    const rows = id === "custom"
      ? ["bumper", "steel"].flatMap((style) => everyId.map((plate) => row(plate, id, style)))
      : setIds(id).map((plate) => row(plate, id, "steel"));
    return {
      id, label: T.PLATE_THEME_LABELS[id], primaryUnit: T.plateThemePrimaryUnit(id),
      sets: { kg: t.sets.kg, lb: t.sets.lb },
      brand: t.brand, barFinish: t.barFinish, backdrop: t.backdrop, hubFinish: t.hubFinish, details: t.details,
      rows,
    };
  });
}

// The shared inspector layout under a theme: one fixed kg loadout (25 kg is
// outside the iron tables, so lbBlackIron also pins the style fallback).
export const LAYOUT_LOADOUT = { bar: { value: 20, unit: "kg" }, collarLb: 0,
  perSide: [25, 20, 10, 5, 2.5, 1.25].map((value) => ({ plate: { value, unit: "kg" }, count: 1 })) };
export const LAYOUT_THEMES = ["custom", "ipfCalibrated", "lbBlackIron"];

function normalizedLayouts() {
  return LAYOUT_THEMES.map((theme) => ({
    theme, style: "steel",
    discs: barbellLayout(LAYOUT_LOADOUT, "steel", 0, {}, theme).discs.map((d) => ({
      plate: `${d.plate.value}-${d.plate.unit}`, side: d.side, index: d.index, family: d.family,
      centerX: d.centerX, radius: d.radius, thickness: d.thickness, theme: d.theme })),
  }));
}

// Face tint from theme fills (nearest-pigment target) and the family labels.
export const TINT_FILLS = [["#234fae", "bumper"], ["#b3262b", "steel"], ["#25262a", "steel"], ["#1f2023", "bumper"]];
export const FAMILIES = ["bumper", "steel", "change", "ipf", "iron", "machined"];
const normalizedTints = () => TINT_FILLS.map(([fill, style]) =>
  ({ fill, style, target: plateTintTargetForFill(fill), matrix: plateTintMatrixForFill(fill, style) }));

export const normalizedPlateThemes = () => ({
  themes: normalizedThemes(), layouts: normalizedLayouts(), tints: normalizedTints(),
  familyLabels: Object.fromEntries(FAMILIES.map((f) => [f, plateFamilyLabel(f)])),
});
