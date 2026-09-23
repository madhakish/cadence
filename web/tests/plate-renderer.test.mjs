import { JSDOM } from "jsdom";

const dom = new JSDOM("<!doctype html><html><body></body></html>", { url: "http://localhost/" });
global.window = dom.window;
global.document = dom.window.document;
global.Node = dom.window.Node;

const C = await import("../app/js/core.js");
const B = await import("../app/js/barbell.js");

let passed = 0;
let failed = 0;
const ok = (condition, message) => {
  if (condition) passed += 1;
  else { failed += 1; console.error("FAIL:", message); }
};

const solve = (targetLb, bar, plates, collarLb = 0, policy = "closest") =>
  C.solve(targetLb, bar, plates, 10, collarLb, policy);

// DP-3's mandatory solver/render fixtures. The renderer receives these exact
// objects and has no target/rack arguments with which to derive another stack.
const fixtures = {
  F1: solve(C.lbFromKg(100), C.BARS.bar20kg, C.STANDARD_KG),
  F2: solve(225, C.BARS.bar45lb, C.STANDARD_LB),
  F3: solve(139, C.BARS.bar45lb, C.STANDARD_KG),
  F4: solve(C.lbFromKg(22.5), C.BARS.bar20kg, C.STANDARD_KG),
  F5: C.enteredPlateSolution(C.BARS.bar45lb, [45, 10, 25, 2.5].map((value) => ({
    plate: { value, unit: "lb" }, count: 1,
  }))),
  F6: solve(200, C.BARS.bar45lb, [{ value: 45, unit: "lb" }], 0, "exact"),
  F7: solve(195, C.BARS.bar45lb, C.STANDARD_LB),
  F8: solve(50, C.BARS.bar45lb, C.STANDARD_LB, 5),
};

const flattened = (solution) => solution.perSide.flatMap((count) =>
  Array.from({ length: count.count }, () => count.plate));

for (const [name, solution] of Object.entries(fixtures)) {
  const before = JSON.stringify(solution);
  const rendered = B.barbellSVG(solution, "full", name === "F7" ? "bumper" : "steel");
  const bodies = [...rendered.svg.querySelectorAll(".barbell-plate-body")];
  const labels = [...rendered.svg.querySelectorAll(".barbell-plate-label")];
  const expectedVisible = flattened(solution).length * 2;
  ok(rendered.solution === solution, `${name}: renderer returns the caller's exact solution object`);
  ok(JSON.stringify(solution) === before, `${name}: rendering does not sort, sum, stamp, or mutate the solution`);
  ok(bodies.length === expectedVisible, `${name}: every entered plate is mirrored exactly once`);
  ok(labels.length === bodies.length, `${name}: every visible plate has one visible denomination`);
  ok(bodies.every((body) => body.dataset.plateDenomination
      && body.getAttribute("aria-label")?.includes(body.dataset.plateDenomination)
      && body.tabIndex === 0),
  `${name}: every plate is focusable and named with its exact denomination`);
  const bodyFor = (label) => rendered.svg.querySelector(
    `.barbell-plate-body[data-side="${label.dataset.side}"][data-stack-index="${label.dataset.stackIndex}"]`);
  ok(labels.every((label) => label.textContent === C.trim(Number(bodyFor(label).dataset.plateValue), 2)
      && label.dataset.plateDenomination === bodyFor(label).dataset.plateDenomination),
    `${name}: printed value and accessible unit come from authoritative plate metadata`);
  // Keyboard and assistive order is the order both clients speak: the left
  // side from the collar outward, then the right — never the painter order.
  const spoken = bodies.map((body) => `${body.dataset.side}:${body.dataset.stackIndex}`);
  const leftCount = flattened(solution).length;
  const expectedSpoken = [...Array(leftCount).keys()].map((i) => `left:${i}`)
    .concat([...Array(leftCount).keys()].map((i) => `right:${i}`));
  ok(spoken.join(",") === expectedSpoken.join(","),
    `${name}: focus order runs each side collar-outward, left then right`);
  ok(bodies.every((body) => body.querySelector(".barbell-plate-target") && !body.querySelector("image")),
    `${name}: focusable plate groups carry a hit target, not the artwork`);
}

ok(fixtures.F1.bar.unit === "kg" && fixtures.F1.perSide.every((count) => count.plate.unit === "kg")
    && Math.abs(fixtures.F1.deviationLb) < 1e-8,
"F1: kg bar and kg plates solve exactly");
ok(fixtures.F2.bar.unit === "lb" && fixtures.F2.perSide.every((count) => count.plate.unit === "lb")
    && Math.abs(fixtures.F2.deviationLb) < 1e-8,
"F2: lb bar and lb plates solve exactly");
ok(fixtures.F3.bar.unit === "lb" && fixtures.F3.perSide.every((count) => count.plate.unit === "kg")
    && Math.abs(fixtures.F3.deviationLb) > .01,
"F3: a lb bar keeps the kg-only rack and reports the non-exact result");
ok(flattened(fixtures.F4).some((plate) => C.plateLabel(plate) === "1.25 kg"),
  "F4: a 1.25 kg plate remains 1.25 kg");
// Sprites paint far to near, so read the stack by its index, not DOM order.
const byStack = (svg, side) => [...svg.querySelectorAll(`.barbell-plate-body[data-side="${side}"]`)]
  .sort((a, b) => Number(a.dataset.stackIndex) - Number(b.dataset.stackIndex));
const f5Right = byStack(B.barbellSVG(fixtures.F5, "full").svg, "right")
  .map((plate) => Number(plate.dataset.plateValue));
ok(JSON.stringify(f5Right) === JSON.stringify([45, 10, 25, 2.5]),
  "F5: reverse mode preserves entered collar-to-sleeve order");
ok(fixtures.F6.satisfiesPolicy === false && fixtures.F6.policy === "exact",
  "F6: unreachable exact load keeps its policy warning evidence");
const f7Steel = B.barbellSVG(fixtures.F7, "full", "steel").svg;
const f7Bumper = B.barbellSVG(fixtures.F7, "full", "bumper").svg;
ok(Number(byStack(f7Steel, "right")[0].getAttribute("height"))
    !== Number(byStack(f7Steel, "right")[1].getAttribute("height"))
    && Number(byStack(f7Bumper, "right")[0].getAttribute("height"))
      === Number(byStack(f7Bumper, "right")[1].getAttribute("height")),
"F7: calibrated steel and bumpers retain distinct diameter geometry");
ok(B.barbellSVG(fixtures.F8, "full").svg.querySelectorAll("image.barbell-collar, image.barbell-collar-near").length === 2,
  "F8: configured collars render on both mirrored sleeves");
{
  // Every disc is a rendered sprite placed from the scene: the face image's
  // frame scales the sprite's face radius to the disc radius, far plates paint first.
  const svg = B.barbellSVG(fixtures.F1, "full", "bumper").svg;
  const faces = [...svg.querySelectorAll("image.barbell-plate-face")];
  ok(faces.length === svg.querySelectorAll(".barbell-plate-body").length && faces.length > 0
    && faces.every((face) => /^plate-bumper-/.test(face.dataset.sprite) && face.dataset.sprite.endsWith("-assembled")),
    "F1: each disc is a bumper sprite at the assembled angle");
  const order = faces.map((face) => Number(face.dataset.centerX));
  ok(order.every((x, i) => i === 0 || x <= order[i - 1]), "discs paint from the far (+x) end to the near end");
  ok(svg.querySelectorAll("image.barbell-shaft").length === 1
    && svg.querySelectorAll("image.barbell-sleeve, image.barbell-sleeve-near").length === 2,
    "the bar is one shaft sprite and two sleeve sprites");
}

const B2 = await import("../app/js/barbell-scene.js");
ok(B2.discAccessibilityLabel({ plate: { value: 20, unit: "kg" }, index: 0, side: -1 }) === "20 kg plate, 1 from inside, left side",
  "one spoken plate name on both clients (mirrors BarbellScene.Disc.accessibilityLabel)");
const muted = B.barbellSVG(fixtures.F2, "compact", "steel", { emphasis: "muted" }).svg;
const current = B.barbellSVG(fixtures.F2, "compact", "steel", { emphasis: "current" }).svg;
ok(muted.classList.contains("emphasis-muted") && current.classList.contains("emphasis-current")
    && muted.getAttribute("viewBox") === current.getAttribute("viewBox")
    && muted.querySelectorAll(".barbell-plate-body").length === current.querySelectorAll(".barbell-plate-body").length,
  "emphasis is a state class only: geometry and plate count are identical across states");
const S = await import("../app/js/barbell-scene.js");
ok(S.plateFamily({ value: 5, unit: "kg" }, "bumper") === "bumper" && S.plateFamily({ value: 5, unit: "kg" }, "steel") === "steel"
    && S.plateFamily({ value: 2.5, unit: "kg" }, "bumper") === "change" && S.plateFamily({ value: 45, unit: "lb" }, "steel") === "steel"
    && S.plateFamily({ value: 5, unit: "lb" }, "bumper") === "change" && S.plateFamilyLabel("bumper") === "Bumpers",
  "plate family names the summary cell (mirrors PlateGeometry.family)");
{
  const summary = B.loadoutSummary(225, fixtures.F2, { plateStyle: "steel" });
  const cells = [...summary.querySelectorAll(".loadout-cell")];
  ok(cells.length === 1 && cells[0].textContent.includes("4 × 45 lb") && cells[0].textContent.includes("Steel")
      && cells[0].querySelector("svg.plate-badge"),
    "the summary states one cell per denomination, counting both sleeves, with its family");
  ok(summary.querySelector(".loadout-line")?.textContent.includes("/ side")
      && summary.querySelector(".loadout-line")?.textContent.includes("45 lb bar"),
    "the summary names the bar and what is on each side");
  const collars = B.loadoutSummary(null, fixtures.F8, { plateStyle: "steel" });
  ok([...collars.querySelectorAll(".loadout-cell")].some((cell) => cell.textContent.includes("2 collars") && cell.textContent.includes("Outermost")),
    "configured collars are a cell of their own");
  ok(!collars.querySelector(".loadout-delta"), "with nothing requested there is no delta");
  const off = B.loadoutSummary(139, fixtures.F3, { plateStyle: "steel" });
  ok(off.querySelector(".loadout-delta")?.textContent.includes("from 139 lb") && off.querySelector(".loadout-delta.warn"),
    "an off-target result shows its difference from the request");
}

for (const value of [1.25, 2.5, 45]) {
  ok(C.plateLabel({ value, unit: "kg" }) === `${value} kg`,
    `formatter preserves exact denomination ${value}`);
}

const summary = B.loadoutSummary(fixtures.F3.targetLb, fixtures.F3);
const measures = [...summary.querySelectorAll(".weight-measure")];
ok(measures.length === 2 && measures[0].textContent.endsWith("lb") && measures[1].textContent.endsWith("kg"),
  "achieved total always presents pounds first and kilograms second");
ok(summary.querySelector(".loadout-delta")?.textContent.includes("from ")
    && summary.querySelector(".loadout-line")?.textContent.includes(" bar")
    && summary.querySelector(".loadout-line")?.textContent.includes("/ side")
    && summary.querySelector(".loadout-delta strong")?.textContent.includes(" lb"),
"summary distinguishes requested, achieved, bar, plates per side, and difference");

let expanded = false;
const typical = B.barbellSVG(fixtures.F2, "full");
const typicalStage = B.barbellStage(typical, {
  caption: "Mirrored", onExpand: () => { expanded = true; }, containerWidth: 390,
});
ok(!typicalStage.querySelector(".barbell-expand").hidden,
  "typical two-plate stack exposes inspection without waiting for overflow");

const heavy = C.enteredPlateSolution(C.BARS.bar20kg, C.STANDARD_KG.map((plate) => ({ plate, count: 8 })));
const heavyRendered = B.barbellSVG(heavy, "full", "bumper");
const heavyStage = B.barbellStage(heavyRendered, {
  caption: "Mirrored", onExpand: () => { expanded = true; }, containerWidth: 390,
});
const expandButton = heavyStage.querySelector(".barbell-expand");
ok(heavyRendered.minimumLegibleWidth > 390 && !expandButton.hidden,
"dense stack retains its computed geometry and inspection action");
expandButton.click();
ok(expanded, "expanded-view affordance is immediate and wired to its caller");
ok([...heavyStage.querySelectorAll(".barbell-plate-label")]
  .every((label) => Number(label.getAttribute("font-size")) >= 9),
"constrained preview compensates denomination text instead of shrinking it below the floor");

let rejected = false;
try { B.barbellSVG({ perSide: [] }, "full"); } catch { rejected = true; }
ok(rejected, "renderer refuses incomplete presentation-only loadout data");

console.log(`\n${passed} focused plate-renderer assertions passed, ${failed} failed`);
if (failed) process.exitCode = 1;
