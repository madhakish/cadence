// The equipment look a gym has chosen: which real plate family fills the bar
// (dimensions, construction, finish, colour rule) for each unit. Presentation
// only — a theme never changes a plate's identity, recorded mass, inventory
// toggles, or the solver. Mirrors CadenceCore PlateTheme.swift 1:1.
//
// Ids are persisted on gym.plateTheme and in backups; append-only, never renamed.
import * as C from "./core.js";
import { plateFamily, plateGeometry } from "./barbell-scene.js";

export const PLATE_THEME_IDS = Object.freeze([
  "iwfCompetition", "iwfTraining", "ipfCalibrated", "ipfCalibratedGloss",
  "lbColourBumpers", "lbBlackIron", "lbGreyHammertone", "lbMachinedSteel",
  "blackBumpersBand", "cadenceHouse", "custom",
]);

export const PLATE_THEME_LABELS = Object.freeze({
  iwfCompetition: "IWF Competition",
  iwfTraining: "IWF Training",
  ipfCalibrated: "IPF Calibrated",
  ipfCalibratedGloss: "IPF Calibrated · gloss",
  lbColourBumpers: "lb Colour Bumpers",
  lbBlackIron: "lb Black Iron",
  lbGreyHammertone: "lb Grey Hammertone",
  lbMachinedSteel: "lb Machined Steel",
  blackBumpersBand: "Black Bumpers · colour band",
  cadenceHouse: "Cadence House",
  custom: "Custom",
});

const LB_PRIMARY = new Set(["lbColourBumpers", "lbBlackIron", "lbGreyHammertone", "lbMachinedSteel"]);
// The unit the theme was designed around; the other unit uses its sibling set.
export const plateThemePrimaryUnit = (id) => (LB_PRIMARY.has(id) ? "lb" : "kg");

export const isPlateThemeID = (id) => PLATE_THEME_IDS.includes(id);

// Migration default for a gym that has never chosen: a single-unit inventory
// reads as that unit's plainest real set, anything mixed stays custom.
export function inferredPlateTheme(units) {
  const set = new Set(units);
  if (set.size === 1 && set.has("lb")) return "lbBlackIron";
  if (set.size === 1 && set.has("kg")) return "iwfCompetition";
  return "custom";
}

// ---- theme descriptions ----
// Real-equipment dimensions (mm) per product line; sources in
// docs/design-pass/PLATE-REFERENCE.md. Keys are plateId spellings.
const IWF_BUMPER = { "25-kg": [450, 66], "20-kg": [450, 55], "15-kg": [450, 42], "10-kg": [450, 29] };
const IWF_CHANGE = { "5-kg": [230, 26], "2.5-kg": [210, 19], "2-kg": [190, 19], "1.5-kg": [175, 18],
  "1-kg": [160, 15], "0.5-kg": [135, 12.5], "1.25-kg": [160, 12] };
const IPF_STEEL = { "25-kg": [450, 27], "20-kg": [450, 22.5], "15-kg": [400, 21], "10-kg": [325, 21],
  "5-kg": [228, 21.5], "2.5-kg": [190, 16], "1.25-kg": [160, 12] };
const LB_BUMPER = { "55-lb": [450, 70], "45-lb": [450, 60], "35-lb": [450, 49], "25-lb": [450, 38], "10-lb": [450, 21] };
const LB_CHANGE_RUBBER = { "5-lb": [190, 19], "2.5-lb": [162, 15], "1.25-lb": [133, 10] };
const LB_IRON = { "45-lb": [450, 50], "35-lb": [360, 34.5], "25-lb": [276, 34.5], "10-lb": [229, 20],
  "5-lb": [190, 14.5], "2.5-lb": [162, 12] };
const LB_MACHINED = { "45-lb": [448, 38], "35-lb": [360, 38], "25-lb": [300, 38], "10-lb": [228, 31],
  "5-lb": [195, 21], "2.5-lb": [162, 16] };
const KG_IRON = { "20-kg": [450, 36], "15-kg": [400, 32], "10-kg": [345, 29], "5-kg": [275, 22],
  "2.5-kg": [225, 18], "1.25-kg": [170, 14] };

// Federation colour rules as they photograph (matte rubber / painted steel).
const IWF = { "25-kg": "#c6302c", "20-kg": "#234fae", "15-kg": "#e2b21c", "10-kg": "#1f8b45", "5-kg": "#e8e5df",
  "2.5-kg": "#c6302c", "2-kg": "#234fae", "1.5-kg": "#e2b21c", "1-kg": "#1f8b45", "0.5-kg": "#e8e5df", "1.25-kg": "#2a2b2f" };
const IWF_BRIGHT = { "25-kg": "#d63a34", "20-kg": "#2b63c9", "15-kg": "#f0c020", "10-kg": "#2ba552", "5-kg": "#efece6",
  "2.5-kg": "#d63a34", "2-kg": "#2b63c9", "1.5-kg": "#f0c020", "1-kg": "#2ba552", "0.5-kg": "#efece6", "1.25-kg": "#2a2b2f" };
const IPF = { "25-kg": "#b3262b", "20-kg": "#1e3f8c", "15-kg": "#d6a50f", "10-kg": "#196d3b", "5-kg": "#dad8d3",
  "2.5-kg": "#1e1f22", "1.25-kg": "#b9bcc0",
  "45-lb": "#1e3f8c", "35-lb": "#d6a50f", "25-lb": "#196d3b", "10-lb": "#dad8d3", "5-lb": "#1e1f22", "2.5-lb": "#b9bcc0" };
const IPF_GLOSS = { "25-kg": "#c22a2f", "20-kg": "#2148a6", "15-kg": "#e0ad12", "10-kg": "#1d7a42", "5-kg": "#e2e0dc",
  "2.5-kg": "#202126", "1.25-kg": "#c4c7cb",
  "45-lb": "#2148a6", "35-lb": "#e0ad12", "25-lb": "#1d7a42", "10-lb": "#e2e0dc", "5-lb": "#202126", "2.5-lb": "#c4c7cb" };
const ECHO = { "55-lb": "#c2332f", "45-lb": "#2358b4", "35-lb": "#e1b21a", "25-lb": "#23964b", "10-lb": "#e9e6e0",
  "5-lb": "#202124", "2.5-lb": "#202124", "1.25-lb": "#202124" };
// Black change plates carry no colour band; their numerals print light.
const UNBANDED = new Set(["#202124", "#2a2b2f"]);
const DARK_INK = "#1f2124", LIGHT_INK = "#f2f1ee", TABLE_FALLBACK = "#26272b";
const BAND_BODY = "#1f2023", BAND_FALLBACK = "#8a8d92", BAND_DARK_INK = "#d3d4d7";

const ids = (unit, values) => values.map((v) => `${v}-${unit}`);
const KG_FULL = ids("kg", [25, 20, 15, 10, 5, 2.5, 1.25]);
const LB_BUMPER_SET = ids("lb", [55, 45, 35, 25, 10, 5, 2.5]);
const LB_STANDARD = ids("lb", [45, 35, 25, 10, 5, 2.5]);
const KG_FROM_20 = ids("kg", [20, 15, 10, 5, 2.5, 1.25]);
const withFamily = (table, family) => Object.fromEntries(Object.entries(table).map(([k, [d, t]]) => [k, { diameter: d, thickness: t, family }]));
const RUBBER_PLATES = { ...withFamily(IWF_BUMPER, "bumper"), ...withFamily(IWF_CHANGE, "change"),
  ...withFamily(LB_BUMPER, "bumper"), ...withFamily(LB_CHANGE_RUBBER, "change") };
const CALIBRATED_PLATES = { ...withFamily(IPF_STEEL, "ipf"), ...withFamily(LB_MACHINED, "ipf") };
const IRON_PLATES = { ...withFamily(LB_IRON, "iron"), ...withFamily(KG_IRON, "iron") };
// Chrome change discs on the calibrated sets (1.25 kg, and 2.5 lb in pounds).
const CALIBRATED_CHROME = ["1.25-kg", "1.25-lb", "2.5-lb"];

// Every theme: sets per unit (heaviest first), plates (mm + family), colour
// rule, material, hub/rim ratios of the radius (hub = metal insert, photoHub =
// hub mask on a photographed face, rim = outer edge of the label band; null =
// the family default), hub finish, extra details, brand, bar finish, backdrop.
// `custom` is not listed: it is today's style-driven behaviour.
const DEFAULTS = { brand: "CADENCE", barFinish: "chrome", backdrop: "#17181b", hubFinish: "chrome", details: [],
  hub: null, photoHub: null, rim: null, chrome: [] };
export const PLATE_THEMES = Object.freeze({
  iwfCompetition: { ...DEFAULTS, sets: { kg: ids("kg", [25, 20, 15, 10, 5, 2.5, 2, 1.5, 1, 0.5]), lb: LB_BUMPER_SET },
    plates: RUBBER_PLATES, colour: { table: { ...IWF, ...ECHO } },
    material: { finish: "rubber", metal: 0, roughness: 0.72, changeRoughness: 0.6, photoFamily: "bumper" },
    hub: 0.5, details: ["boltedHub"] },
  iwfTraining: { ...DEFAULTS, sets: { kg: KG_FULL, lb: LB_BUMPER_SET },
    plates: RUBBER_PLATES, colour: { table: { ...IWF_BRIGHT, ...ECHO } },
    material: { finish: "rubber", metal: 0, roughness: 0.62, photoFamily: "bumper" },
    hub: 0.42, photoHub: 0.42, hubFinish: "blackSteel", details: ["chromeBoreRing"] },
  ipfCalibrated: { ...DEFAULTS, sets: { kg: KG_FULL, lb: LB_STANDARD },
    plates: CALIBRATED_PLATES, colour: { table: IPF },
    material: { finish: "powder", metal: 0.1, roughness: 0.38, photoFamily: "steel" },
    chrome: CALIBRATED_CHROME, chromeRoughness: 0.26,
    hub: 0.2, photoHub: 0.2, rim: 0.84, details: ["calibrationPlugs"] },
  ipfCalibratedGloss: { ...DEFAULTS, sets: { kg: KG_FULL, lb: LB_STANDARD },
    plates: CALIBRATED_PLATES, colour: { table: IPF_GLOSS },
    material: { finish: "gloss", metal: 0.12, roughness: 0.24, photoFamily: null },
    chrome: CALIBRATED_CHROME, chromeRoughness: 0.22,
    hub: 0.2, photoHub: 0.2, rim: 0.84, details: ["calibrationPlugs", "machinedRimRing"] },
  lbColourBumpers: { ...DEFAULTS, sets: { lb: ids("lb", [55, 45, 35, 25, 10, 5, 2.5, 1.25]), kg: KG_FULL },
    plates: RUBBER_PLATES, colour: { table: { ...ECHO, ...IWF } },
    material: { finish: "rubber", metal: 0, roughness: 0.66, photoFamily: "bumper" },
    hub: 0.36, photoHub: 0.36 },
  lbBlackIron: { ...DEFAULTS, sets: { lb: LB_STANDARD, kg: KG_FROM_20 },
    plates: IRON_PLATES, colour: { fill: "#25262a", ink: "#d3d4d7" },
    material: { finish: "castIron", metal: 0.18, roughness: 0.58, photoFamily: null },
    hub: 0.26, photoHub: 0.24, rim: 0.88, hubFinish: "castIron" },
  lbGreyHammertone: { ...DEFAULTS, sets: { lb: LB_STANDARD, kg: KG_FROM_20 },
    plates: IRON_PLATES, colour: { fill: "#6b6d72", ink: "#1a1b1e" },
    material: { finish: "hammertone", metal: 0.25, roughness: 0.52, photoFamily: null },
    hub: 0.26, photoHub: 0.24, rim: 0.88, hubFinish: "hammertone" },
  lbMachinedSteel: { ...DEFAULTS, sets: { lb: LB_STANDARD, kg: KG_FROM_20 },
    plates: { ...withFamily(LB_MACHINED, "machined"), ...withFamily(IPF_STEEL, "machined") }, colour: { fill: "#9a9da2", ink: "#1a1b1e" },
    material: { finish: "machined", metal: 1, roughness: 0.32, photoFamily: null },
    hub: 0.22, photoHub: 0.2 },
  blackBumpersBand: { ...DEFAULTS, sets: { kg: KG_FULL, lb: LB_BUMPER_SET },
    plates: RUBBER_PLATES, colour: { band: { ...IWF, ...ECHO } },
    material: { finish: "rubber", metal: 0, roughness: 0.7, photoFamily: "bumper" },
    hub: 0.42, photoHub: 0.42, hubFinish: "blackSteel", details: ["colourBand", "chromeBoreRing"] },
  // hubRing: a ring at the hub edge in the numeral colour.
  cadenceHouse: { ...DEFAULTS, sets: { kg: KG_FULL, lb: LB_BUMPER_SET },
    plates: RUBBER_PLATES, colour: { fill: "#2a2c30", ink: "#e0413c" },
    material: { finish: "rubber", metal: 0, roughness: 0.68, photoFamily: "bumper" },
    hub: 0.46, photoHub: 0.46, barFinish: "blackOxide", backdrop: "#101114", details: ["hubRing"] },
});
// Built on first use: core.js and barbell-scene.js import this module back,
// so core's constants may not exist yet while this one evaluates.
let custom;
export const plateThemeDescription = (theme = "custom") => PLATE_THEMES[theme]
  || (custom ??= { ...DEFAULTS, sets: { kg: C.STANDARD_KG.map(C.plateId), lb: C.STANDARD_LB.map(C.plateId) } });

// Label ink by sRGB luminance of the fill: dark on light plates, light on dark.
export function plateThemeInk(fill) {
  const v = Number.parseInt(fill.slice(1), 16);
  const r = v >> 16, g = (v >> 8) & 255, b = v & 255;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 150 ? DARK_INK : LIGHT_INK;
}

// The theme's plate list for a unit, heaviest first. custom = today's standard set.
export const plateThemeSet = (unit, theme = "custom") =>
  plateThemeDescription(theme).sets[unit].map((id) => ({ value: Number(id.split("-")[0]), unit }));

// Real dimensions (mm). A plate outside the theme's tables keeps today's style profile.
export function plateThemeGeometry(plate, theme = "custom", style = "steel") {
  const row = PLATE_THEMES[theme]?.plates[C.plateId(plate)];
  return row ? { diameter: row.diameter, thickness: row.thickness } : plateGeometry(plate, style);
}

// "bumper" | "steel" | "change" (custom), "ipf" | "iron" | "machined" (themes).
export function plateThemeFamily(plate, theme = "custom", style = "steel") {
  return PLATE_THEMES[theme]?.plates[C.plateId(plate)]?.family ?? plateFamily(plate, style);
}

// { fill, edge, ink } hex, plus band (colour-band hex or null).
export function plateThemeColour(plate, theme = "custom", style = "bumper") {
  const rule = PLATE_THEMES[theme]?.colour;
  if (!rule) return { ...C.plateColour(C.plateColorToken(plate, style)), band: null };
  const id = C.plateId(plate);
  if (rule.band) {
    const band = rule.band[id];
    const edge = band || BAND_FALLBACK;
    const ink = UNBANDED.has(edge) ? BAND_DARK_INK : edge;
    return { fill: BAND_BODY, edge, ink, band: band && !UNBANDED.has(band) ? band : null };
  }
  const fill = rule.fill || rule.table[id] || TABLE_FALLBACK;
  return { fill, edge: fill, ink: rule.ink || plateThemeInk(fill), band: null };
}

// { finish, metal, roughness, photoFamily }. finish: rubber | powder | gloss |
// castIron | hammertone | machined; photoFamily: the photographed face sprite
// family ("bumper" | "steel") or null for a procedural face.
export function plateThemeMaterial(plate, theme = "custom", style = "steel") {
  const t = PLATE_THEMES[theme];
  const family = plateThemeFamily(plate, theme, style);
  if (!t) {
    return family === "bumper"
      ? { finish: "rubber", metal: 0, roughness: 0.68, photoFamily: style }
      : { finish: "powder", metal: 0.08, roughness: 0.36, photoFamily: style };
  }
  const { finish, metal, roughness, changeRoughness, photoFamily } = t.material;
  if (t.chrome.includes(C.plateId(plate))) return { finish: "machined", metal: 1, roughness: t.chromeRoughness, photoFamily };
  return { finish, metal, roughness: family !== "bumper" && changeRoughness != null ? changeRoughness : roughness, photoFamily };
}

const STEEL_FAMILIES = new Set(["steel", "ipf", "machined"]);
// Fractions of the plate radius: metal hub insert, hub mask on a photographed
// face, and outer edge of the label band. Family defaults when the theme is silent.
export function plateThemeRatios(plate, theme = "custom", style = "steel") {
  const t = plateThemeDescription(theme);
  const family = plateThemeFamily(plate, theme, style);
  const familyHub = family === "bumper" ? 0.57 : 0.245;
  return {
    hub: t.hub ?? familyHub,
    photoHub: t.photoHub ?? familyHub,
    rim: t.rim ?? (family === "bumper" ? 0.9 : STEEL_FAMILIES.has(family) ? 0.86 : 1),
  };
}
