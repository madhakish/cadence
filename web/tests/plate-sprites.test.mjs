// The rendered loaded-bar sprites ship to the web client from one install
// step: the generated placement manifest names every sprite, the precache
// lists them, and every plate shape the geometry tables know has a sprite at
// each scene angle. iOS renders the SceneKit studio instead (#316) and ships
// no sprites. Run: node tests/plate-sprites.test.mjs
import { readFileSync, readdirSync, existsSync } from "node:fs";
import assert from "node:assert/strict";
import { PLATE_SPRITES } from "../app/js/plate-sprites.js";
import { plateGeometry } from "../app/js/barbell-scene.js";

const root = new URL("../../", import.meta.url);
const webDir = new URL("web/app/assets/plates/", root);
const files = readdirSync(webDir).filter((f) => f.endsWith(".png")).sort();
const faceDetails = { "bumper-face-detail.png": true, "steel-face-detail.png": true };
assert.ok(files.length >= 16, "the sprite family is installed");
for (const file of files) {
  if (!faceDetails[file]) assert.ok(PLATE_SPRITES.sprites[file.replace(/\.png$/, "")], `${file} is in the web manifest`);
}
for (const file of Object.keys(faceDetails)) assert.ok(files.includes(file), `${file} photographic detail is installed`);
assert.ok(!existsSync(new URL("Cadence/Assets.xcassets/PlateSprites", root)), "iOS ships no sprite family");
assert.ok(!existsSync(new URL("Cadence/Views/PlateSprites.swift", root)), "iOS has no sprite manifest");
const worker = readFileSync(new URL("web/app/sw.js", root), "utf8");
for (const file of files) assert.ok(worker.includes(`"assets/plates/${file}"`), `${file} is precached`);

// Placement metadata is complete and sane.
for (const [name, meta] of Object.entries(PLATE_SPRITES.sprites)) {
  if (meta.kind) {
    assert.ok(meta.axisStart && meta.axisEnd && meta.spanUnits > 0, `${name} carries axis reference points`);
  } else {
    assert.ok(meta.faceRadius > 0 && meta.faceCenter.length === 2 && meta.hubRadius > 0 && meta.hubRadius < 0.5, `${name} carries face placement`);
  }
}
// Every shape the geometry tables know maps to a sprite at both angles (a
// prototype install may still fall back; the full family must not).
const missing = [];
for (const [key, shape] of Object.entries(PLATE_SPRITES.plates)) {
  for (const angle of ["assembled", "exploded"]) if (!PLATE_SPRITES.sprites[`plate-${shape}-${angle}`]) missing.push(`${key} → ${shape} (${angle})`);
}
if (files.length > 20) assert.deepEqual(missing, [], "the full family covers every plate shape at both angles");
// The manifest's custom-set shapes agree with the shared geometry: diameter ×
// thickness from plateGeometry. Theme families carry their own real-equipment sets.
for (const [key, shape] of Object.entries(PLATE_SPRITES.plates)) {
  const [family, id] = key.split(":");
  if (!["bumper", "steel", "change"].includes(family)) continue;
  const [value, unit] = id.split("-");
  const geometry = plateGeometry({ value: Number(value), unit }, family === "bumper" ? "bumper" : "steel");
  assert.equal(shape, `${family}-${geometry.diameter}x${geometry.thickness}`, `${key} sprite shape matches plateGeometry`);
}
// Every construction the plate themes need is rendered at both angles, and
// the theme families map every plate of their kg and lb sets.
const FAMILIES = ["bumper", "steel", "ipf", "iron", "machined", "change"];
const plateSprites = Object.values(PLATE_SPRITES.sprites).filter((meta) => !meta.kind);
for (const meta of plateSprites) {
  assert.ok(FAMILIES.includes(meta.family), `${meta.file} has a known family`);
  // Names spell mm with integers bare and fractions as 22p5: no dot in any asset name.
  const spell = (value) => String(value).replace(".", "p");
  assert.equal(meta.shape, `${spell(meta.diameter)}x${spell(meta.thickness)}`, `${meta.file} shape key spells its millimetres`);
  assert.ok(!meta.file.replace(/\.png$/, "").includes("."), `${meta.file} has no dot in its asset name`);
  assert.equal(meta.file, `plate-${meta.family}-${meta.shape}-${meta.angle}.png`, `${meta.file} is named by family, shape and angle`);
}
if (files.length > 20) {
  for (const family of FAMILIES) for (const angle of ["assembled", "exploded"]) {
    assert.ok(plateSprites.some((meta) => meta.family === family && meta.angle === angle), `${family} has ${angle} sprites`);
  }
  const themeSets = {
    ipf: ["25-kg", "20-kg", "15-kg", "10-kg", "5-kg", "2.5-kg", "1.25-kg", "45-lb", "35-lb", "25-lb", "10-lb", "5-lb", "2.5-lb"],
    iron: ["20-kg", "15-kg", "10-kg", "5-kg", "2.5-kg", "1.25-kg", "45-lb", "35-lb", "25-lb", "10-lb", "5-lb", "2.5-lb"],
    machined: ["25-kg", "20-kg", "15-kg", "10-kg", "5-kg", "2.5-kg", "1.25-kg", "45-lb", "35-lb", "25-lb", "10-lb", "5-lb", "2.5-lb"],
  };
  for (const [family, ids] of Object.entries(themeSets)) for (const id of ids) {
    const shape = PLATE_SPRITES.plates[`${family}:${id}`];
    assert.ok(shape?.startsWith(`${family}-`), `${family}:${id} maps to a ${family} shape`);
  }
  // Theme bumper/change shapes that differ from the custom set resolve from mm via `shapes`.
  const shapeFor = (family, diameter, thickness) => PLATE_SPRITES.shapes.find((s) => s.family === family && s.diameter === diameter && s.thickness === thickness);
  for (const [family, d, t] of [["bumper", 450, 55], ["bumper", 450, 21], ["change", 230, 26], ["change", 135, 12.5], ["ipf", 450, 22.5], ["iron", 360, 34.5]]) {
    const name = `plate-${shapeFor(family, d, t)?.key}`;
    for (const angle of ["assembled", "exploded"]) assert.ok(PLATE_SPRITES.sprites[`${name}-${angle}`], `${name}-${angle} is rendered`);
  }
  // Cast iron keeps no chrome: only the bore is left untinted.
  for (const meta of plateSprites.filter((m) => m.family === "iron")) {
    const radiusMm = meta.diameter / 2;
    assert.ok(Math.abs(meta.hubRadius - 25.25 / radiusMm) < 1e-3, `${meta.file} untints only the bore`);
  }
}
for (const shape of PLATE_SPRITES.shapes) for (const angle of ["assembled", "exploded"]) {
  if (files.length > 20) assert.ok(PLATE_SPRITES.sprites[`plate-${shape.key}-${angle}`], `${shape.key} has a ${angle} sprite`);
}
for (const [key, shape] of Object.entries(PLATE_SPRITES.plates)) assert.ok(PLATE_SPRITES.shapes.some((s) => s.key === shape), `${key} maps to a listed shape`);
// Byte budget for the rendered family (the face-detail textures are separate).
const spriteBytes = files.filter((f) => /^(plate|bar)-/.test(f)).reduce((sum, f) => sum + readFileSync(new URL(f, webDir)).length, 0);
assert.ok(spriteBytes <= 9_000_000, `sprite PNGs total ${spriteBytes} bytes, within 9 MB`);
console.log(`plate sprites: ${files.length} web sprites, manifest aligned`);
