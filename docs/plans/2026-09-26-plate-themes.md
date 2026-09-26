# Plate themes implementation plan (issue #55)

**Goal:** The loaded bar shows real equipment. A gym selects one plate theme —
IWF competition bumpers, IPF calibrated steel, lb colour bumpers, lb iron
(black/grey), or custom — and every plate on the bar takes that theme's real
diameter, thickness, construction, finish and colour for its denomination.
The exercise's unit picks the theme's kg or lb set. Both clients, iOS first.

**Architecture:** One `PlateTheme` model in `CadenceCore`, mirrored 1:1 in
`web/app/js/core.js`, carries per-denomination geometry (mm), the colour rule,
and the finish for each theme. `PlateGeometry.reference` / `plateGeometry`,
`Plate.colorToken` / `plateColorToken`, and `PlateGeometry.family` become
theme-driven; `PlateVisualStyle` (bumper/steel) is retired in favour of the
theme's finish. The sprite renderer gains one family per theme finish. The
theme is persisted on the gym record. Solver, load semantics, recorded mass,
backups' existing fields and the inspector are unchanged.

**Tech stack:** Foundation `CadenceCore` + XCTest; SwiftUI (`SettingsView`,
`BarbellView`); SwiftData schema V14 + `CadenceMigrationTests`; vanilla JS +
IndexedDB (`DB_VERSION` 10) + fake-indexeddb tests; numpy/PIL sprite renderer;
Node test suites; native CI captures.

**Reference:** `docs/design-pass/PLATE-REFERENCE.md` (new) — cited real
dimensions, colours as photographed, and construction per brand. Every number
in the theme tables traces to a line in that document. (Filled from the
research pass; nothing is inferred from earlier mockups.)

**Sequencing:** built on `main` after PR #263 merges. `BarbellSceneView` /
the inspector are out of scope until then and get the theme in a follow-up.

## Product contract

- Themes: `iwf` (competition bumpers, kg), `ipf` (calibrated steel discs,
  kg), `bumperLb` (colour bumpers, lb), `ironLb` (cast/machined iron, lb),
  `custom` (keeps today's mixed behaviour). Names are descriptive, not a rules
  claim (#55 acceptance).
- Unit rule: a kg exercise on an `ironLb` gym shows the theme's kg
  counterpart set (iron kg), an lb exercise on an `iwf` gym shows lb colour
  bumpers — each theme names its cross-unit sibling. Inventory toggles apply
  within the chosen set; the solver keeps using the enabled plates only.
- Colour comes from the theme's rule, not the value alone: IPF 2.5 kg is
  black and 1.25 kg is chrome; IWF change plates follow the main colours;
  lb iron is one finish for every denomination.
- Face print: value over unit on the face, condensed heavy type, scaled with
  the plate (already in this branch). Exact per-side list stays below the bar.
- Existing gyms migrate to a theme inferred from their inventory
  (all-lb → `ironLb`, all-kg → `iwf`, mixed → `custom`) without losing any
  toggle. The inference is a default, editable in the gym settings.

## Persistence (both clients, one PR)

- Native: `Gym.plateThemeRaw: String = "custom"` (migration-safe literal
  default). Freeze V13 as `PersistenceSchemaV13.swift`, add `CadenceSchemaV14`
  with a lightweight stage, extend every production plan and the
  `AppBootstrap` fallback. Post-open backfill infers the theme once for gyms
  still at the literal default whose inventory is single-unit; idempotent.
- Native test: `CadenceMigrationTests` — create a real V13 store with two
  gyms (all-lb, mixed toggles, a custom bar and collar weight), open with the
  V14 production schema + plan, assert toggles/bar/collars survive, the
  backfill infers `ironLb` for the lb gym and leaves `custom` on the mixed
  one, and a second run changes nothing.
- Web: `DB_VERSION` 10, `migrateToV10` cursor-updates `gyms` with
  `plateTheme` (same inference), `normalizeGym` defaults it, new gyms in
  `settings.js` and `seed.js` carry it. Test `db-v10-migration.test.mjs`
  builds a v9 database with the same two gyms and asserts the raw store was
  upgraded, not just normalised on read.
- Backup: `BackupContract.currentSchemaVersion` / `BACKUP_SCHEMA_VERSION`
  15; `plateTheme` validated against `BACKUP_ENUMS.plateThemes` for v≥15,
  optional below. Older importers reject v15 on the version gate (existing
  rule). SemVer: `feat!:` with a BREAKING CHANGE footer (persistence change).

## Tasks and verification

1. **Reference spec** — commit `docs/design-pass/PLATE-REFERENCE.md` from the
   research pass; DECISIONS.md entry "Plate themes, <date>". Verify: every
   table row has a source; the owner reviews the photo references.
2. **Theme model** — `CadenceCore/Plates.swift`: `PlateTheme` enum + tables;
   `BarbellScene.swift`: `PlateGeometry.reference(_:theme:)`,
   `family(_:theme:)`; `core.js` + `barbell-scene.js` mirrors. Tests on both
   clients from one shared fixture `web/tests/fixtures/plate-themes.json`
   (theme × denomination → diameter, thickness, colour token, finish, family)
   generated from the JS model and asserted by `BarbellSceneTests`. Verify:
   `swift test` + `npm test` green; fixture diff reviewed against the spec.
3. **Persistence** — as above. Verify: migration tests on both clients;
   `CadenceMigrationTests` scheme runs in CI.
4. **Sprites** — `render-plate-sprites.py` reads the theme tables (generated
   `plate-themes.json`) and renders one family per finish (rubber bumper,
   painted calibrated steel with raised lip and plugs, cast iron with
   hammertone, machined iron); `install-plate-sprites.mjs` installs all.
   Verify: sprite test asserts every theme × denomination resolves a sprite;
   budget ≤ 8 MB web; byte parity web/native.
5. **Renderers** — `BarbellView.swift` / `barbell.js` take the gym's theme
   (and the exercise unit) instead of a `PlateVisualStyle`; tint targets per
   finish from the spec's photographed values. Verify: F1–F8 fixtures
   re-rendered through `render-barbell-proof.mjs`; native CI captures
   (`Capture iPhone surfaces`) inspected at 390 × 844.
6. **Settings** — native `Picker("Plate theme")` in the gym section with a
   one-line description per theme; web equivalent in `settings.js`. Verify:
   XCUI toggle + smoke test; VoiceOver labels.
7. **Docs** — `docs/how-to/plate-calculator.md` (choosing a theme), README
   for the sprite assets (provenance: procedural from the cited dimensions).

## Not in this PR

- Inspector / `BarbellSceneView` theme support (after #263).
- New photographs or generated textures (#263's two stay as they are).
- Brand logos or certification marks on plates.
