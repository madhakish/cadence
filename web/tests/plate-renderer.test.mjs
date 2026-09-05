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
  ok(labels.every((label) => label.textContent === label.dataset.plateDenomination),
    `${name}: denomination text comes from authoritative plate metadata`);
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
const f5Right = [...B.barbellSVG(fixtures.F5, "full").svg
  .querySelectorAll('.barbell-plate-body[data-side="right"]')]
  .map((plate) => Number(plate.dataset.plateValue));
ok(JSON.stringify(f5Right) === JSON.stringify([45, 10, 25, 2.5]),
  "F5: reverse mode preserves entered collar-to-sleeve order");
ok(fixtures.F6.satisfiesPolicy === false && fixtures.F6.policy === "exact",
  "F6: unreachable exact load keeps its policy warning evidence");
const f7Steel = B.barbellSVG(fixtures.F7, "full", "steel").svg;
const f7Bumper = B.barbellSVG(fixtures.F7, "full", "bumper").svg;
ok(Number(f7Steel.querySelectorAll('[data-side="right"]')[0].getAttribute("height"))
    !== Number(f7Steel.querySelectorAll('[data-side="right"]')[1].getAttribute("height"))
    && Number(f7Bumper.querySelectorAll('[data-side="right"]')[0].getAttribute("height"))
      === Number(f7Bumper.querySelectorAll('[data-side="right"]')[1].getAttribute("height")),
"F7: calibrated steel and bumpers retain distinct diameter geometry");
ok(B.barbellSVG(fixtures.F8, "full").svg.querySelectorAll(".barbell-lock-collar").length === 2,
  "F8: configured collars render on both mirrored sleeves");

for (const value of [1.25, 2.5, 45]) {
  ok(C.plateLabel({ value, unit: "kg" }) === `${value} kg`,
    `formatter preserves exact denomination ${value}`);
}

const summary = B.loadoutSummary(fixtures.F3.targetLb, fixtures.F3);
const measures = [...summary.querySelectorAll(".weight-measure")];
ok(measures.length === 2 && measures[0].textContent.endsWith("lb") && measures[1].textContent.endsWith("kg"),
  "achieved total always presents pounds first and kilograms second");
ok(summary.textContent.includes("Requested") && summary.textContent.includes("Bar")
    && summary.textContent.includes("Plates / side") && summary.textContent.includes("Difference"),
"summary distinguishes requested, achieved, bar, plates per side, and difference");

let expanded = false;
const typical = B.barbellSVG(fixtures.F2, "full");
const typicalStage = B.barbellStage(typical, {
  caption: "Mirrored", onExpand: () => { expanded = true; }, containerWidth: 390,
});
ok(typical.minimumLegibleWidth <= 390 && typicalStage.querySelector(".barbell-expand").hidden,
  "typical two-plate-per-side stack fits 390pt without an expand control");

const heavy = C.enteredPlateSolution(C.BARS.bar20kg, C.STANDARD_KG.map((plate) => ({ plate, count: 8 })));
const heavyRendered = B.barbellSVG(heavy, "full", "bumper");
const heavyStage = B.barbellStage(heavyRendered, {
  caption: "Mirrored", onExpand: () => { expanded = true; }, containerWidth: 390,
});
const expandButton = heavyStage.querySelector(".barbell-expand");
ok(heavyRendered.minimumLegibleWidth > 390 && !expandButton.hidden
    && heavyStage.classList.contains("constrained"),
"dense stack uses its computed legibility floor and exposes focused expansion");
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
