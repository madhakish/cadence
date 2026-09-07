import assert from "node:assert/strict";
import test from "node:test";
import { readFile, mkdtemp, readdir, rm } from "node:fs/promises";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { JSDOM } from "jsdom";
import { figureSVG, muscleLegend, MUSCLE_NAMES } from "../app/js/anatomy.js";

const dom = new JSDOM("<!doctype html><body></body>");
globalThis.document = dom.window.document;
const read = (path) => readFile(new URL(`../../${path}`, import.meta.url), "utf8");
const all = figureSVG({ primary: Object.keys(MUSCLE_NAMES), secondary: [] });
const masks = [...all.querySelectorAll("image.anatomy-region-mask")];

test("proof renderer runs using only locked development dependencies", async () => {
  const out = await mkdtemp(join(tmpdir(), "cadence-anatomy-test-"));
  const { NODE_PATH, ...env } = process.env;
  try {
    execFileSync(process.execPath, [fileURLToPath(new URL("../tools/render-anatomy-registration.mjs", import.meta.url)), out],
      { env, timeout: 60000, stdio: "pipe" });
    assert.equal((await readdir(out)).filter(name => name.endsWith(".jpg")).length, 12);
  } finally { await rm(out, { recursive: true, force: true }); }
});

test("legacy exported anatomy geometry remains source compatible, not a renderer input", async () => {
  const legacy = (await import("../app/js/anatomy.js")).VITRUVIAN_FRONT_REGIONS;
  assert.equal(legacy?.length, 21);
  assert.deepEqual(legacy[0].points[0], [80, 67]);
  assert.equal(legacy.filter(region => region.id === "forearms").length, 4);
  assert.equal(all.querySelectorAll("path").length, 0);
});

// Sample the authored cubic curves, not the retired midpoint control loops.
// Deliberately supports only the M/L/C/Z commands used by these static masks.
function contours(svg) {
  return [...svg.matchAll(/ d="([^"]+)"/g)].map(([, d]) => {
    const tokens = d.match(/[MLCZ]|-?\d+(?:\.\d+)?/g);
    const points = [];
    let x = 0, y = 0, i = 0;
    while (i < tokens.length) {
      const command = tokens[i++];
      if (command === "M" || command === "L") {
        x = Number(tokens[i++]); y = Number(tokens[i++]); points.push([x, y]);
      } else if (command === "C") {
        const [x1, y1, x2, y2, x3, y3] = tokens.slice(i, i + 6).map(Number); i += 6;
        for (let step = 1; step <= 24; step++) {
          const t = step / 24, u = 1 - t;
          points.push([u ** 3 * x + 3 * u ** 2 * t * x1 + 3 * u * t ** 2 * x2 + t ** 3 * x3,
            u ** 3 * y + 3 * u ** 2 * t * y1 + 3 * u * t ** 2 * y2 + t ** 3 * y3]);
        }
        x = x3; y = y3;
      } else assert.equal(command, "Z", "unsupported mask command");
    }
    return points;
  });
}
function contains(polygons, [x, y]) {
  return polygons.some(points => {
    let inside = false;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
      const [xi, yi] = points[i], [xj, yj] = points[j];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  });
}

test("exact source artwork and registered native/web masks stay byte-identical", async () => {
  const hashes = { front: "ec95ffe80e86263a441f31e01e7e5fcf6b9312d3b2d7a3e6fc3a9ae36bfd1006",
    back: "940bbc7bf72794778d3304d226cf5ca3d265e68985bc0ffa72cb198c743a51f5" };
  const swift = await read("Cadence/Views/AnatomyFigureView.swift");
  const worker = await read("web/app/sw.js");
  assert.equal(masks.length, 18);
  for (const [view, hash] of Object.entries(hashes)) {
    const title = view[0].toUpperCase() + view.slice(1);
    const filename = `vitruvian-${view}.jpeg`;
    const web = await readFile(new URL(`../app/assets/${filename}`, import.meta.url));
    const native = await readFile(new URL(`../../Cadence/Assets.xcassets/Vitruvian${title}.imageset/${filename}`, import.meta.url));
    assert.deepEqual(native, web);
    assert.equal(createHash("sha256").update(web).digest("hex"), hash);
  }
  for (const mask of masks) {
    const href = mask.getAttribute("href");
    const [, view, id] = /vitruvian-(front|back)-(\w+)\.svg/.exec(href);
    const name = `Vitruvian${view[0].toUpperCase() + view.slice(1)}${id[0].toUpperCase() + id.slice(1)}`;
    const svg = await read(`web/app/${href}`);
    assert.equal(svg, await read(`Cadence/Assets.xcassets/${name}.imageset/${href.split("/").at(-1)}`));
    assert.ok(swift.includes(`"${id}": "${name}"`), `${name} is consumed by SwiftUI`);
    assert.ok(worker.includes(`"${href}"`), `${href} is available offline`);
    const contents = JSON.parse(await read(`Cadence/Assets.xcassets/${name}.imageset/Contents.json`));
    assert.equal(contents.images[0].filename, href.split("/").at(-1));
    assert.match(svg, /viewBox="0 0 1254 1254"/);
    assert.doesNotMatch(svg, /<image|<filter|<script|transform=/, "no substitute image, blur, or mirroring inside masks");
    assert.ok(contours(svg).flat().every(([x, y]) => x >= 0 && y >= 0 && x <= 1254 && y <= 1254));
  }
  assert.doesNotMatch(swift, /addQuadCurve|vitruvianFrontRegions/);
  assert.equal(all.querySelectorAll("path").length, 0, "presentation does not redraw or re-smooth the masks");
});

// Coordinates are reviewed landmarks on the original 1254px artwork, not a
// claim of medical accuracy. See docs/design-pass/anatomy-registration/README.md.
const landmarks = {
  "front-traps": [[541, 392], [714, 392]],
  "front-delts": [[520, 383], [501, 428], [734, 383], [753, 428]],
  "front-biceps": [[434, 355], [409, 446], [820, 355], [845, 446]],
  "front-forearms": [[319, 304], [282, 457], [935, 304], [972, 457]],
  "front-chest": [[576, 494], [677, 494]],
  "front-abs": [[594, 600], [660, 600]],
  "front-obliques": [[538, 605], [716, 605]],
  "front-quads": [[545, 790], [473, 785], [709, 790], [781, 785]],
  "front-adductors": [[590, 818], [664, 818]],
  "back-traps": [[627, 390], [578, 430], [676, 430]],
  "back-delts": [[514, 426], [511, 376], [740, 426], [743, 376]],
  "back-triceps": [[423, 369], [415, 462], [831, 369], [839, 462]],
  "back-forearms": [[323, 319], [283, 464], [931, 319], [971, 464]],
  "back-lats": [[542, 540], [712, 540]],
  "back-lowerback": [[594, 611], [660, 611]],
  "back-glutes": [[576, 704], [678, 704]],
  "back-hamstrings": [[560, 831], [473, 785], [694, 831], [781, 785]],
  "back-calves": [[533, 973], [395, 947], [721, 973], [859, 947]],
};
test("each visible limb pose is registered; joint, hand, face and parchment landmarks stay clear", async () => {
  const exclusions = [[627, 300], [142, 471], [1111, 471], [230, 205], [1024, 205],
    [535, 890], [719, 890], [441, 867], [813, 867], [300, 650], [950, 650], [627, 840], [627, 1100]];
  for (const [key, positive] of Object.entries(landmarks)) {
    const polygons = contours(await read(`web/app/assets/vitruvian-${key}.svg`));
    for (const p of positive) assert.ok(contains(polygons, p), `${key} includes muscle landmark ${p}`);
    for (const p of exclusions) assert.ok(!contains(polygons, p), `${key} excludes landmark ${p}`);
    if (/biceps|forearms|quads|triceps|hamstrings|calves/.test(key)) assert.equal(polygons.length, 4, `${key} covers four visible limbs`);
  }
  for (const view of ["front", "back"]) {
    const arm = contours(await read(`web/app/assets/vitruvian-${view}-${view === "front" ? "biceps" : "triceps"}.svg`));
    for (const p of landmarks[`${view}-delts`]) assert.ok(!contains(arm, p), "upper-arm wash must not cover shoulder cap");
  }
});

test("keyboard focus, hover, tap and clear keep the same artwork and selected muscle", () => {
  const figure = figureSVG({ primary: ["quads", "glutes"], secondary: ["abs", "hamstrings"] });
  const legend = muscleLegend({ primary: ["quads", "glutes"], secondary: ["abs", "hamstrings"] }, figure);
  document.body.replaceChildren(figure, legend);
  const button = legend.querySelector('[data-muscle="quads"]');
  button.focus();
  assert.equal(figure.querySelectorAll(".is-selected").length, 1);
  assert.match(figure.querySelector(".is-selected").getAttribute("href"), /front-quads/);
  button.click(); assert.equal(button.getAttribute("aria-pressed"), "true");
  button.blur(); assert.equal(figure.querySelectorAll(".is-selected").length, 1);
  button.click(); assert.equal(button.getAttribute("aria-pressed"), "false");
  assert.equal(figure.querySelectorAll(".is-muted").length, 0);
  button.dispatchEvent(new dom.window.Event("pointerenter"));
  assert.equal(figure.querySelectorAll(".is-selected").length, 1);
  button.dispatchEvent(new dom.window.Event("pointerleave"));
  assert.equal(figure.querySelectorAll(".is-selected").length, 0);
  assert.equal(figure.querySelectorAll(".anatomy-reference").length, 2);
});

test("shared rear-deltoid mask is painted once, with primary priority and alias-aware selection", () => {
  const profile = { primary: ["reardelts"], secondary: ["delts"] };
  const figure = figureSVG(profile), legend = muscleLegend(profile, figure);
  assert.equal(figure.querySelectorAll('[href="assets/vitruvian-back-delts.svg"]').length, 1);
  assert.ok(figure.querySelector('[href="assets/vitruvian-back-delts.svg"]').classList.contains("primary"));
  legend.querySelector('[data-muscle="delts"]').click();
  assert.ok(figure.querySelector('[href="assets/vitruvian-back-delts.svg"]').classList.contains("is-selected"));
  assert.equal(figureSVG(null).querySelectorAll(".anatomy-region-mask").length, 0);
});
