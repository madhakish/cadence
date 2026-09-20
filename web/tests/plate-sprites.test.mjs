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
const toNumber = (value) => Number.parseFloat(value);
const parseNativeManifest = (source) => {
  const unitMatch = source.match(/static let unit: Double = ([0-9.]+)/);
  assert.ok(unitMatch, "native manifest declares scene unit");
  const plates = Object.fromEntries([...source.matchAll(/"([^"]+)": "([^"]+)"/g)].map(([, key, value]) => [key, value]));
  const sprites = {};
  const barEntry = /"([^"]+)": \.bar\(kind: "([^"]+)", angle: "([^"]+)", size: CGSize\(width: ([0-9.]+), height: ([0-9.]+)\), axisStart: CGPoint\(x: ([0-9.]+), y: ([0-9.]+)\), axisEnd: CGPoint\(x: ([0-9.]+), y: ([0-9.]+)\), spanUnits: ([0-9.]+)\),/g;
  for (const [, key, kind, angle, width, height, axisStartX, axisStartY, axisEndX, axisEndY, spanUnits] of source.matchAll(barEntry)) {
    sprites[key] = {
      kind,
      angle,
      size: [toNumber(width), toNumber(height)],
      axisStart: [toNumber(axisStartX), toNumber(axisStartY)],
      axisEnd: [toNumber(axisEndX), toNumber(axisEndY)],
      spanUnits: toNumber(spanUnits),
    };
  }
  const plateEntry = /"([^"]+)": \.plate\(family: "([^"]+)", shape: "([^"]+)", angle: "([^"]+)", size: CGSize\(width: ([0-9.]+), height: ([0-9.]+)\), faceCenter: CGPoint\(x: ([0-9.]+), y: ([0-9.]+)\), faceRadius: ([0-9.]+), hubRadius: ([0-9.]+)\),/g;
  for (const [, key, family, shape, angle, width, height, faceCenterX, faceCenterY, faceRadius, hubRadius] of source.matchAll(plateEntry)) {
    sprites[key] = {
      family,
      shape,
      angle,
      size: [toNumber(width), toNumber(height)],
      faceCenter: [toNumber(faceCenterX), toNumber(faceCenterY)],
      faceRadius: toNumber(faceRadius),
      hubRadius: toNumber(hubRadius),
    };
  }
  return { unit: toNumber(unitMatch[1]), plates, sprites };
};

const files = readdirSync(webDir).filter((f) => f.endsWith(".png")).sort();
assert.ok(files.length >= 16, "the sprite family is installed");
const swift = readFileSync(new URL("Cadence/Views/PlateSprites.swift", root), "utf8");
const native = parseNativeManifest(swift);
for (const file of files) {
  const name = file.replace(/\.png$/, "");
  const twin = new URL(`${name}.imageset/${file}`, iosDir);
  assert.ok(existsSync(twin), `${file} has an asset-catalog twin`);
  assert.equal(sha(readFileSync(twin)), sha(readFileSync(new URL(file, webDir))), `${file} is byte-identical on both clients`);
  assert.ok(PLATE_SPRITES.sprites[name], `${file} is in the web manifest`);
}
assert.deepEqual(Object.keys(native.sprites).sort(), Object.keys(PLATE_SPRITES.sprites).sort(), "native/web manifests share the exact sprite key set");
assert.deepEqual(native.plates, PLATE_SPRITES.plates, "native/web manifests share plate-to-shape mapping");
assert.equal(native.unit, PLATE_SPRITES.unit, "both manifests share the scene unit");
for (const [key, meta] of Object.entries(PLATE_SPRITES.sprites)) {
  const nativeMeta = native.sprites[key];
  assert.ok(nativeMeta, `${key} is in the native manifest`);
  if (meta.kind) {
    assert.deepEqual(nativeMeta, {
      kind: meta.kind,
      angle: meta.angle,
      size: meta.size,
      axisStart: meta.axisStart,
      axisEnd: meta.axisEnd,
      spanUnits: meta.spanUnits,
    }, `${key} placement metadata matches native`);
  } else {
    assert.deepEqual(nativeMeta, {
      family: meta.family,
      shape: meta.shape,
      angle: meta.angle,
      size: meta.size,
      faceCenter: meta.faceCenter,
      faceRadius: meta.faceRadius,
      hubRadius: meta.hubRadius,
    }, `${key} placement metadata matches native`);
  }
}
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
