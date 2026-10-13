---
name: cadence-native-proof
description: Establish Cadence native barbell visual evidence with real app captures, geometry checks and exact load math; use for renderer review or visual acceptance, not mockup generation.
---

Read `AGENTS.md`, the current task/PR and `docs/design-pass/BARBELL-INSPECTION.md`.
Renderer ownership can be active on another branch: inspect it before proposing
changes. Work from the actual target SHA, never silently substitute main or
an older capture. Do not port a renderer during a review-only task.

## Three independent proof layers

1. **Math:** derive each expected load from the solver result, canonical-pound
   bar mass, both sleeves and collars. Keep denomination/unit exact; verify
   mixed units, empty bar, fractional plates and unreachable targets. Use
   `CadenceCore` tests and equivalent web fixtures for shared logic. A correct
   total does not prove geometry or appearance.
2. **Geometry:** check both sides from the same camera. Project bore centres
   and sleeve axis into screen space; measure perpendicular alignment error
   and inspect depth/occlusion. Check mesh winding agrees with normals,
   perspective, thickness, ordering, sleeve capacity, collar position and
   exploded spacing. State tolerances and units before interpreting results;
   do not invent a universal pixel threshold or turn a source regex into proof.
3. **Pixels:** open actual simulator/device PNGs from the tested head at their
   native scale. Inspect plate/bar occlusion, denomination legibility, materials,
   lighting/reflections, camera framing, shadows, clipping and app integration.
   Approved artwork is a comparison target, never execution evidence. Browser
   screenshots cannot establish native quality. CI green and accessible labels
   do not prove that visible pixels are correct.

Choose the matrix from the requested acceptance: themes, mixed/empty/heavy
loadouts, row/stage/calculator/inspector, assembled/exploded, compact/large
widths, Dynamic Type and reduced motion as applicable. Compare fixed inputs,
camera, viewport, scale and lighting. Include negative controls that make the
relevant defect fail; never weaken a pixel check to label presence.

## Evidence handoff

Record source SHA, capture run/artifact, simulator/device and OS, viewport and
scale, fixture/loadout/theme/view, command, observed defects and untested cells.
Use `scripts/capture_inventory.py --source-sha <40-hex> --platform native
--root <capture-directory> <relative.png> ...` to hash an explicit PNG list.
Redirect JSON into a temporary evidence folder, not application assets.
This helper records bytes and caller-supplied provenance only: it does not
decode images, authenticate their origin, judge quality or prove matrix coverage.
Open/inspect each image separately and retain the capture run's own SHA record.

Do not call the task visually accepted until requested device/owner acceptance
is recorded. If Xcode/captures are unavailable, report exactly what is pending;
keep geometry/math findings separate and do not substitute web polish.
