import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Each case mutates a copy of the mapped sources and map, never the checkout.
const ROOT = new URL("../../", import.meta.url).pathname;
const CHECKER = join(ROOT, ".github/scripts/check-parity.mjs");
const MAP = "docs/reference/parity-map.json";
const map = JSON.parse(readFileSync(join(ROOT, MAP), "utf8"));
const FILES = [MAP, ...new Set(Object.values(map.modules).flatMap((m) => [m.swift, m.js]))];

function check(mutate = () => {}) {
  const dir = mkdtempSync(join(tmpdir(), "parity-"));
  try {
    for (const f of FILES) cpSync(join(ROOT, f), join(dir, f), { recursive: true });
    const edit = (f, fn) => {
      const before = readFileSync(join(dir, f), "utf8");
      const after = fn(before);
      assert.notEqual(after, before, `mutation of ${f} changed nothing`);
      writeFileSync(join(dir, f), after);
    };
    mutate(edit);
    const run = spawnSync(process.execPath, [CHECKER, dir, join(dir, MAP)], { encoding: "utf8" });
    return { status: run.status, out: run.stdout + run.stderr };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const editMap = (edit, fn) => edit(MAP, (s) => { const m = JSON.parse(s); fn(m.modules); return JSON.stringify(m, null, 2); });

test("the committed map matches the sources", () => {
  const { status, out } = check();
  assert.equal(status, 0, out);
  assert.match(out, /0 failing/);
});

test("T1: a public Swift symbol with no map entry fails", () => {
  const { status, out } = check((edit) => editMap(edit, (m) => { delete m.CardioFormat.symbols["CardioFormat.miles(fromYards:)"]; }));
  assert.equal(status, 1);
  assert.match(out, /public Swift CardioFormat\.miles\(fromYards:\) .* is not in the parity map/);
});

test("T2: renaming a mapped JS twin fails", () => {
  const { status, out } = check((edit) => edit("web/app/js/plate-theme.js",
    (s) => s.replace("export function plateThemeInk(", "export function plateThemeInkColor(")));
  assert.equal(status, 1);
  assert.match(out, /PlateTheme\.ink\(for:\) -> plateThemeInk, but .* does not export plateThemeInk/);
  assert.match(out, /exports plateThemeInkColor, which is neither a Swift twin nor webOnly/);
});

test("T3: a new unmapped public Swift func fails", () => {
  const { status, out } = check((edit) => edit(map.modules.LoadSemantics.swift, (s) => s.replace(
    "    public static func compatible(",
    "    public static func isAssisted(_ basis: LoadBasis) -> Bool { basis == .assisted }\n\n    public static func compatible(")));
  assert.equal(status, 1);
  assert.match(out, /public Swift LoadSemantics\.isAssisted\(_:\) .* is not in the parity map/);
});

test("T4: a new unmapped JS export in an exhaustive module fails", () => {
  const { status, out } = check((edit) => edit(map.modules.BarbellInspector.js,
    (s) => `${s}\nexport const inspectorZoom = 1;\n`));
  assert.equal(status, 1);
  assert.match(out, /exports inspectorZoom, which is neither a Swift twin nor webOnly/);
});

test("T5: relabelling a Swift selector fails as both unmapped and stale", () => {
  const { status, out } = check((edit) => edit(map.modules.CardioFormat.swift, (s) => s.replace(
    "public static func durationSeconds(flights: Double?,", "public static func durationSeconds(flightCount: Double?,")));
  assert.equal(status, 1);
  assert.match(out, /public Swift CardioFormat\.durationSeconds\(flightCount:pacePerMinute:\) .* is not in the parity map/);
  assert.match(out, /map entry CardioFormat\.durationSeconds\(flights:pacePerMinute:\) matches no public Swift symbol/);
});

test("one-sided entries need a reason", () => {
  const { status, out } = check((edit) => editMap(edit, (m) => {
    m.LoadSemantics.symbols["LoadSemantics.compatible(_:_:)"] = { swiftOnly: " " };
    m.PlateTheme.webOnly.isPlateThemeID = "";
  }));
  assert.equal(status, 1);
  assert.match(out, /LoadSemantics\.compatible\(_:_:\) is swiftOnly without a reason/);
  assert.match(out, /webOnly isPlateThemeID has no reason/);
});
