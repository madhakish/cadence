// Automated accessibility audit of every rendered web surface under jsdom.
// axe-core runs the name/role/value, forms, ARIA, and text-alternative rules
// (colour contrast needs layout, which jsdom does not have). Run:
//   node tests/axe.test.mjs
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";

const dom = new JSDOM(`<!doctype html><html><body>
  <header id="topbar"><h1 id="screen-title"></h1><div id="topbar-actions"></div></header>
  <main id="view"></main><button id="fab"></button><nav id="tabbar"></nav>
  <div id="overlays"></div><div id="toast"></div></body></html>`,
{ url: "http://localhost/cadence/app/" });
global.window = dom.window;
global.document = dom.window.document;
global.Node = dom.window.Node;
global.localStorage = dom.window.localStorage;

const axe = (await import("axe-core")).default;
const db = await import("../app/js/db.js");
const ui = await import("../app/js/ui.js");
const home = await import("../app/js/views/home.js");
const programView = await import("../app/js/views/program.js");
const history = await import("../app/js/views/history.js");
const body = await import("../app/js/views/body.js");
const signals = await import("../app/js/views/signals.js");
const settings = await import("../app/js/views/settings.js");
const session = await import("../app/js/views/session.js");
const plates = await import("../app/js/views/plates.js");
const activity = await import("../app/js/views/activity.js");
const tfh = await import("../app/js/views/tfh.js");

const tick = () => new Promise((resolve) => setTimeout(resolve, 60));
const host = () => document.getElementById("view");
const overlays = () => document.getElementById("overlays");
const topScreen = () => overlays().lastElementChild;

let pass = 0, fail = 0;
const RULE_TAGS = ["cat.name-role-value", "cat.forms", "cat.aria", "cat.text-alternatives"];

async function audit(name, root) {
  const results = await axe.run(root, { runOnly: { type: "tag", values: RULE_TAGS } });
  if (results.violations.length === 0) { pass++; return; }
  fail++;
  console.error(`FAIL: ${name} has ${results.violations.length} accessibility violation(s)`);
  for (const violation of results.violations) {
    for (const node of violation.nodes) {
      console.error(`  ${violation.id} (${violation.impact}): ${violation.help}`);
      console.error(`    ${node.target.join(" ")} — ${node.html.slice(0, 160)}`);
    }
  }
}

// Canary: the gate must actually see an unlabeled control before its clean
// results mean anything.
{
  host().replaceChildren(ui.h("input", { type: "text" }));
  const canary = await axe.run(host(), { runOnly: { type: "tag", values: RULE_TAGS } });
  if (canary.violations.some((violation) => violation.id === "label")) pass++;
  else { fail++; console.error("FAIL: axe canary did not flag an unlabeled input"); }
}

await db.ensureSeeded();
// Fictional fixture state so every tab renders real rows, never a first-launch seed.
const cyc = (exerciseName, role, baseWeightLb, estimatedMaxLb) =>
  ({ exerciseName, role, baseWeightLb, estimatedMaxLb, stallCount: 0, lastIncrementLb: 0 });
const acc = (exerciseName, weightLb, incrementLb = 5) =>
  ({ exerciseName, sets: 3, minReps: 8, maxReps: 12, currentReps: 8, weightLb, incrementLb, stallCount: 0 });
await db.Programs.save({
  name: "Fixture Lower", focus: "strength", cycleNumber: 1, currentWeek: 1,
  nextDayIndex: 0, roundingLb: 5, isActive: true,
  days: [{ name: "Lower A", order: 0,
    lifts: [cyc("Back Squat", "main", 175, 204), cyc("Deadlift", "complementary", 185, 255)],
    accessories: [acc("Walking Lunges", 0, 0), acc("Plank", 0, 0)] }],
});
const tabs = { Today: home, Program: programView, History: history, Body: body, Signals: signals, Settings: settings };
for (const [name, view] of Object.entries(tabs)) {
  host().replaceChildren();
  await view.render(host()); await tick();
  await audit(`${name} tab`, host());
}

const program = await db.Programs.active();
const day = [...program.days].sort((a, b) => a.order - b.order)[0];
const sessionID = await session.createSessionFromProgramDay(program, day);
const pushed = {
  "Exercise library": async () => settings.exerciseLibrary(await db.Exercises.all()),
  "Plate calculator": () => plates.openPlateCalculator(),
  "Current session": () => session.openSession(sessionID),
  "Activity log": () => activity.openActivityLog(),
  "TFH editor": () => tfh.tfhEditor(program),
};
for (const [name, open] of Object.entries(pushed)) {
  overlays().replaceChildren();
  await open(); await tick();
  if (!topScreen()) { fail++; console.error(`FAIL: ${name} did not push a screen`); continue; }
  await audit(name, topScreen());
}

console.log(`axe: ${pass} surfaces clean, ${fail} with violations`);
process.exit(fail ? 1 : 0);
