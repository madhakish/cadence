// Static registration proof, NOT browser/native screenshots. Uses production
// figureSVG and its exact assets; Sharp only composites the transparent washes.
// Run: node web/tools/render-anatomy-registration.mjs <output-directory>
import { readFile, mkdir } from "node:fs/promises";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { JSDOM } from "jsdom";
const sharp = createRequire(import.meta.url)("sharp");
import { figureSVG, muscleProfile, MUSCLE_NAMES } from "../app/js/anatomy.js";
globalThis.document = new JSDOM("<!doctype html>").window.document;
const out = resolve(process.argv[2] || "docs/design-pass/anatomy-registration");
await mkdir(out, { recursive: true });
const asset = (name) => readFile(new URL(`../app/${name}`, import.meta.url));
const profiles = ["Front Squat", "Romanian Deadlift", "Barbell Bench", "Overhead Press", "Face Pulls"];
const sizes = [180, 626];
async function panel(figure, view, size) {
  const g = figure.querySelectorAll("g.anatomy-figure-panel")[view === "front" ? 0 : 1];
  const layers = [];
  for (const region of g.querySelectorAll("[data-muscle]")) {
    const primary = region.classList.contains("primary");
    const fill = primary ? "#e0453a" : "#a6abb2";
    const isImage = region.tagName === "image";
    const opacity = isImage ? (primary ? .50 : .32) : Number(region.getAttribute("fill-opacity"));
    const svg = isImage
      ? (await asset(region.getAttribute("href"))).toString().replace(/<svg\b/, `<svg fill="${fill}"`).replaceAll('fill="black"', `fill="${fill}"`)
      : `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 210 210"><path d="${region.getAttribute("d")}" fill="${fill}"/></svg>`;
    const { data, info } = await sharp(Buffer.from(svg)).resize(size, size).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    for (let i = 3; i < data.length; i += 4) data[i] = Math.round(data[i] * opacity);
    layers.push({ input: await sharp(data, { raw: info }).png().toBuffer(), blend: "multiply" });
  }
  return sharp(await asset(`assets/vitruvian-${view}.jpeg`)).resize(size, size).composite(layers).png().toBuffer();
}
for (const size of sizes) {
  for (const name of profiles) {
    const figure = figureSVG(muscleProfile(name));
    const panels = await Promise.all(["front", "back"].map(view => panel(figure, view, size)));
    await sharp({ create: { width: size * 2 + 12, height: size, channels: 3, background: "#202226" } })
      .composite(panels.map((input, i) => ({ input, left: i * (size + 12), top: 0 })))
      .jpeg({ quality: 88, chromaSubsampling: "4:4:4" }).toFile(resolve(out, `${name.toLowerCase().replaceAll(" ", "-")}-${size}.jpg`));
  }
}
// Separate muscle selections make contamination between adjacent regions visible.
for (const view of ["front", "back"]) {
  const cells = [];
  for (const id of Object.keys(MUSCLE_NAMES)) {
    const figure = figureSVG({ primary: [id], secondary: [] });
    const g = figure.querySelectorAll("g.anatomy-figure-panel")[view === "front" ? 0 : 1];
    if (!g.querySelector("[data-muscle]")) continue;
    const size = 314;
    const label = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="314" height="32"><text x="12" y="22" fill="#eee" font-family="sans-serif" font-size="16">${MUSCLE_NAMES[id]}</text></svg>`);
    cells.push(await sharp({ create: { width: size, height: size + 32, channels: 3, background: "#202226" } })
      .composite([{ input: label, top: 0, left: 0 }, { input: await panel(figure, view, size), top: 32, left: 0 }]).png().toBuffer());
  }
  await sharp({ create: { width: 314 * 3, height: 346 * Math.ceil(cells.length / 3), channels: 3, background: "#202226" } })
    .composite(cells.map((input, i) => ({ input, left: (i % 3) * 314, top: Math.floor(i / 3) * 346 })))
    .jpeg({ quality: 88, chromaSubsampling: "4:4:4" }).toFile(resolve(out, `${view}-isolated.jpg`));
}
console.log(`Registration renders: ${out}`);
