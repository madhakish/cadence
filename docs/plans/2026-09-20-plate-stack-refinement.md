# Plate stack refinement implementation plan

**Goal:** A realistic, legible loaded sleeve with exactly two authored views:
front assembled and an angled, closer exploded inspection toggled by a tap.

**Architecture:** Preserve the solver's loadout, shared denomination palette,
and physical plate geometry. Refine the existing SceneKit/WebGL renderers;
retain the offline sprite fallback. Both platforms consume the same fixed
camera, framing, and spacing model. No camera drag, pinch, wheel zoom, reset,
or lighting selector remains. Existing training data and anatomy are untouched.

**Tech stack:** SwiftUI/SceneKit, Foundation CadenceCore, vanilla JS/WebGL2,
existing sprite SVG fallback, Node test suites, browser screenshot verification.

The owner's explicit two-view description supplies the design direction.
iOS is the primary product and visual acceptance target; web remains a
functional secondary client. This refinement covers the inspection portions
of #180 and #198, without claiming completion of either broader issue.

## Visual and interaction contract

- The near sleeve fills the stage, with enough shaft to read as a barbell.
- One tap rotates and separates that same ordered stack. Another tap returns.
- Brushed steel sleeves, restrained knurling, chamfered edges, broad softbox
  reflections, recessed plate faces and distinguishable rubber/powder coating.
- Manufacturer-inspired construction, without invented manufacturer logos or
  certification marks. Kilogram color conventions remain IWF/IPF aware; lb
  colors remain manufacturer conventions.
- Every exploded disc receives its exact value and unit, including duplicates
  and custom precision. Heavy stacks may scroll horizontally in the diagram;
  scrolling never moves the camera or changes the saved loadout.
- Keep the per-side list and totals. Preserve actual entered order and collars.
- One keyboard/VoiceOver action for the same toggle. Reduced motion switches
  states immediately. Page gestures stay available.

## Tasks and verification

1. Shared inspection model (`BarbellInspector.swift`, `barbell-inspector.js`,
   shared fixture and both model tests): specify fixed cameras, near-side
   framing, non-occluding explosion gaps, and minimum stage width. Add failing
   regressions first, implement both mirrors, regenerate the reviewed fixture.
2. Native renderer (`BarbellSceneView.swift`, inspection portion of
   `BarbellView.swift`): remove free camera/control state; adopt shared framing,
   spacing and readable captions; refine geometry/materials/light. Compile and
   test through Darwin CI and capture the actual iPhone inspection. Source
   review and browser proof do not replace native visual acceptance.
3. Web renderer (`barbell-gl.js`, `barbell.js`, `styles.css`): same two states,
   material detail and fixed presentation; simplify handlers and controls.
   Regress tap/keyboard, scroll behavior, interrupted animation and fallback.
4. Verify actual browser output at 390 and 1280 widths, steel and bumper,
   assembled and exploded, sparse and heavy stacks, custom/mixed units, empty
   bar, reduced motion, keyboard, offline asset paths and console errors.
   Inspect a bounded batch, correct material findings, recapture.
5. Run the full web suite, one Impeccable detector pass, independent source and
   visual review. Record native proof limits and before/after evidence. Update
   `docs/how-to/plate-calculator.md` and renderer provenance/design notes.

## References

- IWF equipment colors: https://iwf.sport/weightlifting_/equipment/
- IPF rules (March 2026): https://www.powerlifting.sport/rules/codes/info/technical-rules
- Eleiko calibrated steel: https://eleiko.com/en-us/equipment/plates/powerlifting/3060350-25-eleiko-ipf-powerlifting-competition-plate-25-kg
- Rogue competition bumpers: https://www.roguefitness.com/rogue-kg-competition-plates-iwf

Use manufacturer imagery as construction reference. Ship original procedural
geometry/materials with original generated photographic face textures;
see `docs/design-pass/PLATE-FACE-TEXTURES.md` for provenance. No manufacturer
photographs or logos are bundled.
