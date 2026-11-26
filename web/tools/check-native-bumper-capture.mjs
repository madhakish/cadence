// Compare iPhone RenderLab's one-pair and two-pair photographs to the Astra camera.
import assert from "node:assert/strict";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const captures = process.argv[2];
assert(captures, "Pass the directory of native RenderLab PNGs");
const reference = fileURLToPath(new URL("../../docs/design-pass/astra-2026-11-01/03-platform-oak-blue.png", import.meta.url));
const regions = { near: [175, 110, 600, 710], far: [1110, 110, 1580, 710] };

async function measure(path) {
  const width = 1672, height = 941;
  const rgb = await sharp(path).resize(width, height, { fit: "fill" }).removeAlpha().toColourspace("srgb").raw().toBuffer();
  const bounds = {};
  for (const [name, [left, top, right, bottom]] of Object.entries(regions)) {
    let x0 = right, y0 = bottom, x1 = left, y1 = top, count = 0;
    for (let y = top; y < bottom; y++) {
      for (let x = left; x < right; x++) {
        const i = 3 * (y * width + x);
        const b = rgb[i + 2];
        if (b <= 1.36 * rgb[i] || b <= 1.15 * rgb[i + 1] || b <= 28) continue;
        x0 = Math.min(x0, x);
        y0 = Math.min(y0, y);
        x1 = Math.max(x1, x);
        y1 = Math.max(y1, y);
        count++;
      }
    }
    assert(count >= 100, `${path} has no visible ${name} blue bumper`);
    bounds[name] = { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
  }
  return bounds;
}

const [source, single, double] = await Promise.all([
  measure(reference),
  measure(join(captures, "21-hero-135-lbColourBumpers.png")),
  measure(join(captures, "03-hero-225-lbColourBumpers.png")),
]);
const errors = [];
for (const name of Object.keys(regions)) {
  const r = source[name], s = single[name], d = double[name];
  console.log(`${name}: Astra ${r.w}×${r.h} at ${r.x},${r.y}; 135 lb ${s.w}×${s.h} at ${s.x},${s.y}; 225 lb width ${d.w}`);
  // A missing sidewall leaves only the thin front plane. Tolerate small physical
  // differences between the reference and the gym's bumper, including bevels.
  if (Math.abs(s.w / s.h - r.w / r.h) > 0.085) errors.push(`${name} silhouette aspect differs from source`);
  if (Math.max(Math.abs(s.x - r.x), Math.abs(s.y - r.y), Math.abs(s.h - r.h)) > 0.09 * r.h) {
    errors.push(`${name} bumper missed its registered position or diameter`);
  }
  if (d.w <= s.w + 0.035 * s.h) errors.push(`${name} stack did not gain width with a second plate`);
}
assert.equal(errors.length, 0, errors.join("\n"));
