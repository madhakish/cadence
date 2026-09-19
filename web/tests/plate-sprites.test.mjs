// The rendered loaded-bar sprites ship to both clients from one install step:
// every web sprite has a byte-identical twin in the asset catalog, the two
// generated placement manifests name the same sprites, the precache lists
// them, and every plate shape both geometry tables know has a sprite at each
// scene angle. Run: node tests/plate-sprites.test.mjs
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import assert from "node:assert/strict";
import { PLATE_SPRITES } from "../app/js/plate-sprites.js";
import { plateGeometry } from "../app/js/barbell-scene.js";

const root = new URL("../../", import.meta.url);
const webDir = new URL("web/app/assets/plates/", root);
const iosDir = new URL("Cadence/Assets.xcassets/PlateSprites/", root);
const sha = (buffer) => createHash("sha256").update(buffer).digest("hex");

const files = readdirSync(webDir).filter((f) => f.endsWith(".png")).sort();
assert.ok(files.length >= 16, "the sprite family is installed");
for (const file of files) {
  const name = file.replace(/\.png$/, "");
  const twin = new URL(`${name}.imageset/${file}`, iosDir);
  assert.ok(existsSync(twin), `${file} has an asset-catalog twin`);
  assert.equal(sha(readFileSync(twin)), sha(readFileSync(new URL(file, webDir))), `${file} is byte-identical on both clients`);
  assert.ok(PLATE_SPRITES.sprites[name], `${file} is in the web manifest`);
}
const swift = readFileSync(new URL("Cadence/Views/PlateSprites.swift", root), "utf8");
for (const name of Object.keys(PLATE_SPRITES.sprites)) assert.ok(swift.includes(`"${name}":`), `${name} is in the native manifest`);
assert.ok(swift.includes(`static let unit: Double = ${PLATE_SPRITES.unit}`), "both manifests share the scene unit");
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
// The manifest's shapes agree with the shared geometry: diameter × thickness from plateGeometry.
for (const [key, shape] of Object.entries(PLATE_SPRITES.plates)) {
  const [family, id] = key.split(":");
  const [value, unit] = id.split("-");
  const geometry = plateGeometry({ value: Number(value), unit }, family === "bumper" ? "bumper" : "steel");
  assert.equal(shape, `${family}-${geometry.diameter}x${geometry.thickness}`, `${key} sprite shape matches plateGeometry`);
}
console.log(`plate sprites: ${files.length} sprites, byte-identical on both clients, manifests aligned`);
