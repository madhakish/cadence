# Photographic barbell inspection

The September 20, 2026 refinement presents one loaded sleeve in two authored
views: assembled and nearly straight ahead, then closer and angled with the
plates separated. The solver or reverse-mode loadout remains the source of
plate identity, order, count, mass, bar and collars. Inspection state stays in
the view and never writes to SwiftData, IndexedDB or a backup.

## Rendering and asset provenance

Where Metal (iOS) or WebGL2 (web) is available, `BarbellInspector` /
`barbell-inspector.js` supplies the shared physical layout, camera endpoints,
framing, spacing and minimum diagram width. SceneKit and WebGL render the near
sleeve with beveled edges, machining detail, restrained knurling, brushed steel,
a fixed studio environment, and an annular lock collar when configured.

Plate faces combine the solid geometry with two original AI-generated,
photographic-style orthographic textures. The 768-pixel PNGs are paired
byte-for-byte across clients:

| Face | Web asset | Native image set |
| --- | --- | --- |
| Bumper | `web/app/assets/plates/bumper-face-detail.png` | `PlateBumperFaceDetail` |
| Steel/change | `web/app/assets/plates/steel-face-detail.png` | `PlateSteelFaceDetail` |

Runtime tinting applies the existing denomination palette to the coated body
while retaining the photographed chrome hub. The renderer clips the physical
bore and prints the actual value and unit over the face. A constant face
material preserves the texture's baked studio illumination; the solid supplies
thickness and silhouette. Original CADENCE stamps do not imply a manufacturer
or federation certification. These textures are generated artwork, not scraped
manufacturer photographs. See [the face-texture provenance](PLATE-FACE-TEXTURES.md)
for the source and installation record.

Compact rows, inline full-bar diagrams and the no-3D fallback retain the
September 19, 2026 rendered sprites: one greyscale plate per shape and scene
angle, plus shaft, near/far sleeves and collars. These were produced by
`web/tools/render-plate-sprites.py`, a deterministic signed-distance ray marcher,
and installed into both clients by `web/tools/install-plate-sprites.mjs` with
placement metadata in `plate-sprites.js` and `PlateSprites.swift`. Their shared
luminance matrix restores the untinted hub, and the renderer adds denominations.
This refinement does not regenerate those sprites.

The owner-approved September 6 photographs (`PlateSteel` / `plate-steel.png`
and `PlateBumper` / `plate-bumper.png`) remain unchanged. They are separate from
the new face-detail textures and are not the diagram's sprite inputs. The
Vitruvian artwork and anatomy highlighting are unchanged.

## Shared behavior

- The calculator, current workout set and contextual exercise pane open the
  same inspector. A normal stack offers inspection even when it fits inline.
- The initial 3D camera has yaw 8° and pitch 6°. A tap changes it to yaw 50°,
  pitch 10°, frames the near stack and separates adjacent discs. Another tap
  returns to the initial state. The first disc stays against the bar shoulder.
- The camera endpoints are fixed. There is no orbit drag, pinch/wheel zoom,
  double-tap reset, reset button or backdrop picker. The studio lighting stays
  fixed. Page gestures remain available.
- The native and web 3D cut lasts 260 ms. Reduce Motion /
  `prefers-reduced-motion` makes the state change immediate. The offline sprite
  fallback uses its existing fixed angles with the same two-state interaction.
- Each exploded disc has a screen-space value-and-unit caption, including
  duplicates and custom precision such as 0.625 kg. These captions are distinct
  from the smaller printed face stamps and do not shrink with camera distance.
  Native captions follow Dynamic Type. The per-side denomination/count list
  remains below the artwork.
- Long exploded diagrams scroll horizontally within their own track. Scrolling
  does not change the camera, order or loadout. The assembled view fits its
  container; sparse inspections crop unused sleeve space.
- The toggle button supplies the keyboard and VoiceOver action. Native keeps
  individual plate accessibility children. Web makes the visible exploded
  captions focusable and exposes denomination and inside-to-outside position;
  the decorative canvas or fallback SVG is hidden from assistive technology.
  There is no invisible focusable SVG overlay on the 3D artwork.
- The same physical dimensions feed both views. Full-size 5 kg training bumpers
  remain full size; steel and change plates retain their reference profiles.
  Geometry, input order, identity and mass do not change during the transition.
- Kilogram colours retain the shared IWF/IPF-aware denomination conventions;
  pound colours remain manufacturer conventions. Existing inventories, solving
  policies, totals and collar inclusion are unchanged.

These are illustrative equipment profiles, not manufacturer measurements or a
sleeve-capacity check. Unknown custom denominations keep their exact labels and
use a neutral reference shape. Persisting manufacturer-specific dimensions or
named gym profiles (#55) remains a separate feature requiring a migration.
This refinement changes no persisted schema or backup format.

## Verification and evidence

Run the appropriate checks from this checkout:

- `cd web && npm test` covers geometry, solution identity, input ordering,
  inspector interaction, exact denominations, collars, fallback and offline
  asset inclusion.
- `cd CadenceCore && swift test` verifies the shared native model, profiles,
  authored camera endpoints, framing and JSON fixture on a Swift toolchain.
- `node web/tests/barbell-inspector.test.mjs` and `BarbellInspectorTests` compare
  both models through `web/tests/fixtures/barbell-3d.json`.
- `node web/tests/barbell-gl.test.mjs` covers meshes, camera fit and the
  no-WebGL path; `barbell-inspection.test.mjs` covers inspection interaction.
- `node web/tests/plate-sprites.test.mjs` checks the unchanged sprite pairs and
  placement manifests. The new detail textures are separately paired assets.
- `node web/tools/render-barbell-proof.mjs /absolute/output` rasterizes the
  production sprite SVGs. Those are diagram proofs, not the photographic 3D
  inspector or iPhone screenshots.
- `web/tools/capture-web-proof.mjs` captures the app with Chromium software
  WebGL and reports which renderer produced the images. Inspect the assembled,
  exploded and returned-to-assembled states, plus narrow and heavy-stack cases.
- `CadenceVisualProofUITests.test04PlateCalculatorHero` opens a normal load,
  checks individual plate accessibility, toggles assembled/exploded and back,
  checks the removed controls are absent, and captures steel and bumper states.

The local browser evidence for this September 20 pass is in
`/home/madhakish/git/cadence-review-2026-09-20/plate-stack/final/`.
It is synthetic browser evidence, not native proof. This Linux workspace has
no Swift compiler or Xcode simulator; the new native renderer and updated UI
proof have not been compiled or captured here. A source review or a passing
web test is not a substitute for that platform verification.

The committed `docs/design-pass/after/plate-inspector-3d-*` screenshots are
historical evidence from the earlier free-camera renderer. Their orbit/Paper
states predate this refinement, and the iPhone captures came from visual-proof
run `0810ca0`. They do not demonstrate the new two-state interaction, materials
or captions. The earlier simulator observation about missing floor shadows and
knurl detail is also historical; current native rendering remains unverified.

## iPhone capture

Add the `visual-proof` label to a same-repository PR, or manually dispatch the
visual-proof workflow, to capture current-set, exercise-detail, calculator and
workout-preview screens. The workflow gates capture on the exact head's fast
CI suites; the macOS device build remains the merge gate. New commits cancel
stale captures. Removing the label stops captures on future updates.

Artifacts include `commit.txt` and the source SHA in their names. Inspect the
actual images before declaring visual verification. XCTest's accessibility
checks do not claim a manual spoken VoiceOver session. Record exact-head CI,
simulator capture and any device checks with the review; compilation alone
proves neither rendering quality nor VoiceOver behavior.
