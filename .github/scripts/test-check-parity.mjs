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

test("T6: unmarked members of a public extension are public", () => {
  const { status, out } = check((edit) => edit(map.modules.LoadSemantics.swift, (s) => `${s}
public extension LoadBasis {
    static func heaviest() -> LoadBasis { .totalBar }
    private static func hidden() -> Int { 0 }
    internal var note: String { "" }
}

extension LoadBasis {
    static func quiet() -> Int { 0 }
}

public extension Plate {
    var isChange: Bool { false }
}
`));
  assert.equal(status, 1);
  assert.match(out, /public Swift LoadBasis\.heaviest\(\) .* is not in the parity map/);
  assert.match(out, /public Swift Plate\.isChange .* is not in the parity map/);
  // Lower access wins, an internal extension stays internal, and extending a
  // type is not a declaration of it.
  assert.doesNotMatch(out, /LoadBasis\.(hidden|note|quiet)|public Swift Plate /);
});

test("T7: a public init is a selector like any func", () => {
  const scene = "BarbellScene.init(loadout:style:exploded:geometry:theme:)";
  const { status, out } = check((edit) => {
    edit(map.modules.BarbellScene.swift, (s) => s.replace(
      "    public init(diameter: Double, thickness: Double) {",
      "    public init?(side: Double) { self.init(diameter: side, thickness: side) }\n\n    public init(diameter: Double, thickness: Double) {"));
    editMap(edit, (m) => { delete m.BarbellScene.symbols[scene]; });
  });
  assert.equal(status, 1);
  assert.match(out, /public Swift PlateGeometry\.init\(side:\) .* is not in the parity map/);
  assert.ok(out.includes(`public Swift ${scene} `), out);
});

test("T8: modules sharing a JS file own its sections exhaustively", () => {
  const core = map.modules.LoadSemantics.js;
  const { status, out } = check((edit) => {
    edit(core, (s) => s
      .replace("// ---- Explicit set lifecycle", "export const loadNote = 1;\n// ---- Explicit set lifecycle")
      .replace("// ---- Health reconciliation", "export const carryNote = 1;\n// ---- Health reconciliation")
      .concat("\nexport const elsewhere = 1;\n"));
    editMap(edit, (m) => { delete m.LoadSemantics.webOnly.resolvedLoadBasis; });
  });
  assert.equal(status, 1);
  assert.match(out, /LoadSemantics: .* exports loadNote, which is neither a Swift twin nor webOnly/);
  assert.match(out, /LoadSemantics: .* exports resolvedLoadBasis, which is neither a Swift twin nor webOnly/);
  assert.match(out, /CardioFormat: .* exports carryNote, which is neither a Swift twin nor webOnly/);
  // Sections no mapped module owns stay outside the gate.
  assert.doesNotMatch(out, /elsewhere/);
});

test("T9: an owned section that no longer exists fails", () => {
  const { status, out } = check((edit) => edit(map.modules.LoadSemantics.js,
    (s) => s.replace("// ---- Load semantics ---", "// ---- Load meaning ---")));
  assert.equal(status, 1);
  assert.match(out, /LoadSemantics: .* has no exports under a "\/\/ ---- Load semantics ----" header/);
});

test("T10: a twin claimed by another module accounts for an export in an owned section", () => {
  // equipmentPolicyAllows sits under "Load semantics", which LoadSemantics owns,
  // and is ProgramPolicy's twin. Dropping that claim leaves it unaccounted for.
  const allows = "EquipmentPolicy.allows(exerciseType:)";
  const { status, out } = check((edit) => editMap(edit, (m) => {
    m.ProgramPolicy.symbols[allows] = { swiftOnly: "test: claim withdrawn" };
  }));
  assert.equal(status, 1);
  assert.match(out, /LoadSemantics: .* exports equipmentPolicyAllows, which is neither a Swift twin nor webOnly/);
});

test("T11: a twin claim is per JS file", () => {
  // A same-named export in another mapped file is a different export, so a
  // claim there must not satisfy the owner of the core.js section.
  const allows = "EquipmentPolicy.allows(exerciseType:)";
  const { status, out } = check((edit) => {
    edit(map.modules.PlateTheme.js, (s) => `${s}\nexport const equipmentPolicyAllows = 1;\n`);
    editMap(edit, (m) => {
      m.ProgramPolicy.js = m.PlateTheme.js;
      // Its other twins live in core.js; park them so only the claim under test remains.
      for (const key of Object.keys(m.ProgramPolicy.symbols)) {
        m.ProgramPolicy.symbols[key] = key === allows ? "equipmentPolicyAllows" : { swiftOnly: "test: twin lives in core.js" };
      }
    });
  });
  assert.equal(status, 1);
  assert.match(out, /LoadSemantics: .* exports equipmentPolicyAllows, which is neither a Swift twin nor webOnly/);
  assert.doesNotMatch(out, /PlateTheme: .* exports equipmentPolicyAllows/);
});

test("T12: a module with no owned section gates nothing in its JS file", () => {
  // ProgramPolicy's twins sit in sections other modules own (`jsSections: []`);
  // a new export in an unowned section is outside every module's gate.
  const { status, out } = check((edit) => edit(map.modules.ProgramPolicy.js,
    (s) => s.replace("// ---- Restore preview", "export const policyNote = 1;\n// ---- Restore preview")));
  assert.equal(status, 0, out);
  assert.doesNotMatch(out, /policyNote/);
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
