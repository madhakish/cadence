// The plate theme model (plate-theme.js) against the shared parity fixture
// that PlateThemeTests holds CadenceCore to, plus the facts the themes exist
// for: federation colours, pound Echo colours, monochrome iron, and custom
// reproducing today's style-driven look exactly.
// Run: node tests/plate-themes.test.mjs
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import * as T from "../app/js/plate-theme.js";
import * as C from "../app/js/core.js";
import { plateFamily, plateGeometry } from "../app/js/barbell-scene.js";
import { normalizedPlateThemes, LAYOUT_LOADOUT } from "./plate-themes-fixture.mjs";
import { barbellLayout } from "../app/js/barbell-inspector.js";
import { barbellScene, plateTintMatrix, plateTintMatrixForFill, plateTintTarget } from "../app/js/barbell-scene.js";

const fixture = JSON.parse(readFileSync(new URL("./fixtures/plate-themes.json", import.meta.url), "utf8"));
assert.deepEqual(normalizedPlateThemes(), fixture,
  "plate themes match the shared parity fixture (regenerate via web/tools/generate-plate-themes-fixture.mjs)");
assert.deepEqual(fixture.themes.map((t) => t.id), [...T.PLATE_THEME_IDS], "every theme id has a fixture entry");

const plateOf = (id) => { const [value, unit] = id.split("-"); return { value: Number(value), unit }; };
const fill = (theme, id) => T.plateThemeColour(plateOf(id), theme).fill;

// IWF: 25 red · 20 blue · 15 yellow · 10 green · 5 white; change plates follow.
const IWF_ORDER = { "25-kg": "#c6302c", "20-kg": "#234fae", "15-kg": "#e2b21c", "10-kg": "#1f8b45", "5-kg": "#e8e5df",
  "2.5-kg": "#c6302c", "2-kg": "#234fae", "1.5-kg": "#e2b21c", "1-kg": "#1f8b45", "0.5-kg": "#e8e5df" };
for (const [id, hex] of Object.entries(IWF_ORDER)) assert.equal(fill("iwfCompetition", id), hex, `IWF ${id}`);
assert.equal(T.plateThemeFamily(plateOf("2.5-kg"), "iwfCompetition"), "change");
assert.equal(T.plateThemeGeometry(plateOf("25-kg"), "iwfCompetition").thickness, 66, "Rogue KG Competition 25 kg width");

// IPF: 25 red · 20 blue · 15 yellow by rule; 2.5 kg black, 1.25 kg chrome by convention.
assert.equal(fill("ipfCalibrated", "25-kg"), "#b3262b");
assert.equal(fill("ipfCalibrated", "20-kg"), "#1e3f8c");
assert.equal(fill("ipfCalibrated", "15-kg"), "#d6a50f");
assert.equal(fill("ipfCalibrated", "2.5-kg"), "#1e1f22");
assert.equal(T.plateThemeMaterial(plateOf("1.25-kg"), "ipfCalibrated").finish, "machined", "IPF 1.25 kg is chrome");
assert.equal(T.plateThemeMaterial(plateOf("1.25-kg"), "ipfCalibrated").metal, 1);
assert.deepEqual(T.plateThemeSet("kg", "ipfCalibrated").map((p) => T.plateThemeGeometry(p, "ipfCalibrated").diameter),
  [450, 450, 400, 325, 228, 190, 160], "calibrated steel steps down with mass (Rogue Calibrated KG)");

// lb Echo: 55 red · 45 blue · 35 yellow · 25 green · 10 white · black change plates.
const ECHO = { "55-lb": "#c2332f", "45-lb": "#2358b4", "35-lb": "#e1b21a", "25-lb": "#23964b", "10-lb": "#e9e6e0",
  "5-lb": "#202124", "2.5-lb": "#202124", "1.25-lb": "#202124" };
for (const [id, hex] of Object.entries(ECHO)) assert.equal(fill("lbColourBumpers", id), hex, `Echo ${id}`);

// Iron and machined themes: one finish for every denomination, in both units.
for (const theme of ["lbBlackIron", "lbGreyHammertone", "lbMachinedSteel", "cadenceHouse"]) {
  const plates = [...T.plateThemeSet("lb", theme), ...T.plateThemeSet("kg", theme)];
  assert.equal(new Set(plates.map((p) => JSON.stringify(T.plateThemeColour(p, theme)))).size, 1, `${theme} is monochrome`);
}
for (const theme of ["lbBlackIron", "lbGreyHammertone"]) {
  for (const p of T.plateThemeSet("lb", theme)) assert.equal(T.plateThemeFamily(p, theme), "iron");
}

// Colour band: black body, IWF/Echo band and numerals; black change plates unbanded.
assert.deepEqual(T.plateThemeColour(plateOf("20-kg"), "blackBumpersBand"),
  { fill: "#1f2023", edge: "#234fae", ink: "#234fae", band: "#234fae" });
assert.equal(T.plateThemeColour(plateOf("5-lb"), "blackBumpersBand").band, null);

// Every theme resolves every plate in both sets to a real table row.
for (const theme of T.PLATE_THEME_IDS.filter((t) => t !== "custom")) {
  for (const unit of ["kg", "lb"]) {
    for (const p of T.plateThemeSet(unit, theme)) {
      assert.ok(T.PLATE_THEMES[theme].plates[C.plateId(p)], `${theme} has dimensions for ${C.plateId(p)}`);
      if (T.PLATE_THEMES[theme].colour.table) assert.ok(T.PLATE_THEMES[theme].colour.table[C.plateId(p)], `${theme} colours ${C.plateId(p)}`);
    }
  }
}

// custom (and the default parameter) is today's behaviour, value for value.
const everyId = [...new Set(fixture.themes.flatMap((t) => [...t.sets.kg, ...t.sets.lb]))];
for (const id of everyId) {
  const p = plateOf(id);
  for (const style of ["bumper", "steel"]) {
    assert.deepEqual(T.plateThemeGeometry(p, "custom", style), plateGeometry(p, style), `custom geometry ${id} ${style}`);
    assert.equal(T.plateThemeFamily(p, "custom", style), plateFamily(p, style), `custom family ${id} ${style}`);
    assert.deepEqual(T.plateThemeColour(p, "custom", style), { ...C.plateColour(C.plateColorToken(p, style)), band: null });
  }
  assert.deepEqual(T.plateThemeGeometry(p), plateGeometry(p));
  assert.equal(T.plateThemeFamily(p), plateFamily(p));
  assert.deepEqual(T.plateThemeColour(p), { ...C.plateColour(C.plateColorToken(p)), band: null });
}
assert.deepEqual(T.plateThemeSet("kg"), C.STANDARD_KG.map(({ value, unit }) => ({ value, unit })));
assert.deepEqual(T.plateThemeSet("lb"), C.STANDARD_LB.map(({ value, unit }) => ({ value, unit })));

// Shared layouts take the theme; the default is today's layout, disc for disc.
const strip = (discs) => discs.map(({ theme, ...rest }) => rest);
assert.deepEqual(strip(barbellLayout(LAYOUT_LOADOUT, "bumper", 0.5, {}, "custom").discs),
  strip(barbellLayout(LAYOUT_LOADOUT, "bumper", 0.5).discs));
assert.deepEqual(barbellScene(LAYOUT_LOADOUT, "bumper", true, {}, "custom"), barbellScene(LAYOUT_LOADOUT, "bumper", true));
const iron = barbellLayout(LAYOUT_LOADOUT, "steel", 0, {}, "lbBlackIron").discs.find((d) => d.plate.value === 20);
assert.deepEqual([iron.radius, iron.thickness, iron.family, iron.theme], [225, 36, "iron", "lbBlackIron"]);
assert.equal(T.plateThemeFamily(plateOf("20-kg"), "ipfCalibrated"), "ipf");
assert.equal(T.plateThemeFamily(plateOf("45-lb"), "lbMachinedSteel"), "machined");
assert.equal(T.plateThemeRatios(plateOf("20-kg"), "lbMachinedSteel").rim, 0.86, "machined takes the steel rim");
assert.deepEqual(fixture.familyLabels, { bumper: "Bumpers", steel: "Steel", change: "Change", ipf: "Steel", iron: "Iron", machined: "Steel" });

// Fill tint: token versions are the fill versions at the pigment's own target;
// dark theme fills (iron, band body) take black's target, colours their hue's.
for (const token of Object.keys(C.PLATE_COLOURS)) for (const style of ["bumper", "steel"]) {
  assert.deepEqual(plateTintMatrix(token, style), plateTintMatrixForFill(C.PLATE_COLOURS[token].fill, style, plateTintTarget(token)));
}
assert.deepEqual(fixture.tints.map((t) => t.target), [plateTintTarget("blue"), plateTintTarget("red"), 1, 1]);
const ipfScene = barbellScene(LAYOUT_LOADOUT, "steel", false, {}, "ipfCalibrated");
assert.ok(ipfScene.discs.every((d) => d.theme === "ipfCalibrated"));
assert.equal(ipfScene.discs.find((d) => d.plate.value === 5).radius, 228 * 0.18, "scene disc follows the theme's 5 kg diameter");

console.log("plate-themes: ok");
