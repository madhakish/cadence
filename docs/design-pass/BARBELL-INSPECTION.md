# Photographic barbell inspection

The previously demonstrated plate faces are now production inputs, not static
mockups placed over a fictitious load. Native and web project the exact solver
or reverse-mode stack through `BarbellScene` / `barbell-scene.js`.

## Asset provenance

The loaded bar is composed from rendered sprites (September 19, 2026): one
greyscale plate per shape (diameter × thickness) at each scene angle, plus a
shaft, far and near sleeves, and collars, produced by
`web/tools/render-plate-sprites.py` (a deterministic signed-distance ray
marcher with a studio rig) and installed byte-for-byte into
`web/app/assets/plates/` and `Cadence/Assets.xcassets/PlateSprites` by
`web/tools/install-plate-sprites.mjs`, with placement metadata generated into
`plate-sprites.js` and `PlateSprites.swift`. The sprites carry no denomination,
so the renderer stamps the actual plate value without changing the artwork.

The owner-approved September 6, 2026 photographs (`PlateSteel` /
`plate-steel.png`, `PlateBumper` / `plate-bumper.png`) remain in both clients
unchanged but are no longer drawn by the diagram. No gorilla emboss is added;
the existing Vitruvian artwork is unchanged. Coloured faces are colourised
from the sprite's luminance by the shared matrix and retain an untinted metal
hub. SVG paint-server identifiers are unique per view.

## Shared behavior

- Every normal hero bar offers **Inspect plates**, not just overflowing stacks.
- The calculator, current workout set, and contextual exercise pane open the
  same inspector: straight ahead and assembled first; a tap explodes it (the
  solid swings to 35° and frames the near stack; the sprite scene shows 38°).
- Assemble/explode is view-local. It never saves to SwiftData or IndexedDB.
- The same dimensions feed both camera views. Explicit reference catalogs
  replace threshold-based plate sizes. Full-size 5 kg training bumpers stay
  full size; explicit geometry can represent a different change-plate profile.
- The input's plate order, identity, mass, bar, and collars remain authoritative.
  Reverse-mode order is preserved. Painter order is separate from loading order.
- The enlarged exploded scene scrolls inside its own track. Exact per-side
  denomination/count rows remain readable below it.
- Where Metal (iOS) or WebGL2 (web) is available, the inspection is a real-time
  solid built from the shared `BarbellInspector` model: drag orbits, pinch or
  wheel zooms, a tap explodes or assembles with an animated cut, double tap or
  **Reset view** returns to the front view, and Studio / Dark / Paper backdrops
  switch the lighting mood. Without it the sprite scene above is the inspection.
- The explode cut is instant under Reduce Motion / `prefers-reduced-motion` on
  both clients. The sprite view's assemble/explode remains immediate on web.
- The solid keeps every plate exposed to assistive technology: native reuses
  the per-plate accessibility children; web keeps the sprite SVG over the canvas
  as an invisible, focusable plate layer and names the focused plate in a note.
- Compact rows use the same rendered sprite scene as full views on both clients.
- Native and web colourise the full face with the same luminance matrix and
  restore the untinted metal hub; the camera sits at the −x end, so far parts
  paint first and near parts last, and every plate bore is open in the sprites
  so the shaft shows through wherever the plate's own thickness lets it. Native accessibility exposes each plate's side,
  position and exact denomination independently of the inspection button.
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
  SVGs with the actual shipped sprite bytes at 390 and 1280 pixels. These are
  renderer proofs, not iPhone app screenshots.
- `node web/tests/plate-sprites.test.mjs` proves the sprite family is
  byte-identical on both clients and that both placement manifests agree.
- `node web/tests/barbell-inspector.test.mjs` and `BarbellInspectorTests` prove
  the 3D layout, explode fraction, camera limits, and lathe profiles agree
  through `web/tests/fixtures/barbell-3d.json`; `barbell-gl.test.mjs` covers
  the lathe meshes, the camera fit, and the no-WebGL fallback.
- `web/tools/capture-web-proof.mjs` runs Chromium with software WebGL, reports
  which renderer produced `web-plate-inspection-*.png`, and also captures the
  orbited and Paper-backdrop states.
- `CadenceVisualProofUITests.test04PlateCalculatorHero` opens inspection for a
  normal load, captures the exploded and assembled states, and — when the solid
  is present — orbits it, switches to the Paper backdrop, and resets through the
  control. Use the iPhone visual-proof workflow to capture it.

## Opt-in iPhone capture

Add the `visual-proof` label to a same-repository PR to capture the current-set,
exercise-detail, calculator (steel and bumper), and workout-preview screens.
The workflow waits for the latest CI attempt for that exact head to succeed
before starting the simulator. New commits cancel stale captures. Removing
the label stops captures on future updates. Ordinary PRs keep one native build.
Manual dispatch remains available.

Each screenshot artifact includes `commit.txt` and includes its source SHA in
the artifact name. Inspect the images before declaring visual verification.
XCTest also checks individual plate accessibility and the inspect/toggle path;
this does not claim a manual spoken VoiceOver session.

CI and actual capture results belong in the PR. Compilation alone does not
claim device rendering or VoiceOver verification.

The assembled overview keeps a 16px/body-size loading key inside the figure.
Exploded artwork scrolls at natural scale with 14px/pt denomination numerals;
unit and count remain in the adjacent exact load list. Text is never compressed
with SVG textLength, and expanding never changes the solver result.
