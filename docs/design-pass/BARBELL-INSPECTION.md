# Photographic barbell inspection

The previously demonstrated plate faces are now production inputs, not static
mockups placed over a fictitious load. Native and web project the exact solver
or reverse-mode stack through `BarbellScene` / `barbell-scene.js`.

## Asset provenance

The owner-approved September 6, 2026 assets are copied byte-for-byte into both
clients. They contain no baked-in denomination, so the renderer stamps the
actual plate value and unit without changing the underlying artwork.

- `PlateSteel` / `plate-steel.png` — Charcoal calibrated powerlifting plate.
- `PlateBumper` / `plate-bumper.png` — Realistic Black Olympic Bumper Plate.

These are intentional shipped source assets. No gorilla emboss is added; the
existing Vitruvian artwork is unchanged. Coloured faces tint the texture and
retain an untinted metal hub. SVG paint-server identifiers are unique per view.

## Shared behavior

- Every normal hero bar offers **Inspect plates**, not just overflowing stacks.
- The calculator, current workout set, and contextual exercise pane open the
  same inspector, initially exploded at 38°.
- Assemble/explode is view-local. It never saves to SwiftData or IndexedDB.
- The same dimensions feed both camera views. Explicit reference catalogs
  replace threshold-based plate sizes. Full-size 5 kg training bumpers stay
  full size; explicit geometry can represent a different change-plate profile.
- The input's plate order, identity, mass, bar, and collars remain authoritative.
  Reverse-mode order is preserved. Painter order is separate from loading order.
- The enlarged exploded scene scrolls inside its own track. Exact per-side
  denomination/count rows remain readable below it.
- Native transition respects Reduce Motion. Web changes states immediately.
- Existing plate references, inventory, and solving policy are unchanged.

These illustrative dimensions are not a new physical inventory contract.
Persisting manufacturer-specific dimensions and named gym profiles (#55) is a
separate feature requiring a migration. This implementation changes no store
or backup schema and needs no migration.

## Reproduce verification

- `cd web && npm test` covers geometry, mirrored ordering, five-kilogram shape,
  original solution identity, inspect/toggle interactions, multiple diagrams,
  exact denominations, collars, and offline asset inclusion.
- `cd CadenceCore && swift test` verifies the same scene and shared JSON fixture.
- `node web/tools/render-barbell-proof.mjs /absolute/output` rasterizes production
  SVGs with the actual shipped texture bytes at 390 and 1280 pixels. These are
  renderer proofs, not iPhone app screenshots.
- `CadenceVisualProofUITests.test04PlateCalculatorHero` opens inspection for a
  normal load and captures both exploded and assembled native states. Use the
  existing manual iPhone visual-proof workflow to capture it.

CI and actual capture results belong in the PR. Compilation alone does not
claim device rendering or VoiceOver verification.
