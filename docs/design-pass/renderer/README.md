# Plate denomination proof — #180 / PR #262

## Sources and reproduction

Captured on 2026-09-26 with Chromium 153.0.8010.0, device scale 1,
Carbon theme, 390 × 844 and 1280 × 800 viewports. Full-page captures are
868/824 px tall because the isolated fixture uses a 24 px page margin.

- Before: `487a563fafff045ee5091bd455ba551f3cb13ce2` (main).
- After application source: `650a9845f2544ead5921fe960a7262ef1b85d09d`;
  capture harness uses the epic’s 844/800 px viewport heights in this proof commit.
- Harness: `web/tests/browser/plate-labels.spec.mjs`; actual production
  renderer, solution functions, summary, sprites, and stylesheet.
- Command: `cd web && npx playwright test tests/browser/plate-labels.spec.mjs`.
  CI runs both Chromium and WebKit and retains their attached screenshots.
  Local captures used Chromium from a temporary test installation because the
  pinned browser download failed; no application dependency changed.
- Before images use the same fixture inputs, viewport, margin, and renderer
  calls against the main worktree. Assertions for the new behavior were omitted.

The files here are renderer fixtures in a browser, not full calculator screens
or native screenshots. F6 intentionally captures the renderer/summary of the
unreachable result; its caller's policy warning is outside this harness.

## Fixture matrix

| Fixture | Input | Phone | Desktop |
| --- | --- | --- | --- |
| F1 | 100 kg, 20 kg bar, kg rack | [390](F1-390.png) | [1280](F1-1280.png) |
| F2 | 225 lb, 45 lb bar, lb rack | [390](F2-390.png) | [1280](F2-1280.png) |
| F3 | 139 lb, 45 lb bar, kg rack | [390](F3-390.png) | [1280](F3-1280.png) |
| F4 | 22.5 kg, change plates | [390](F4-390.png) | [1280](F4-1280.png) |
| F5 | Entered order: 45, 10, 25, 2.5 lb | [390](F5-390.png) | [1280](F5-1280.png) |
| F6 | Unreachable 200 lb, exact policy, 45 lb plates | [390](F6-390.png) | [1280](F6-1280.png) |
| F7 | 195 lb, bumper style | [390](F7-390.png) | [1280](F7-1280.png) |
| F8 | 45 lb bar + 5 lb collars | [390](F8-390.png) | [1280](F8-1280.png) |

## Comparable before/after inspection

| Case | Before | After | Finding |
| --- | --- | --- | --- |
| Mixed units, phone | [Before](before-F3-390.png) | [After](F3-390.png) | Tiny face stamps replaced by exact 14 px readout; lb/kg totals no longer collide or clip the lb unit. |
| Mixed units, desktop | [Before](before-F3-1280.png) | [After](F3-1280.png) | Face stamps include kg on the lb bar; readout also names both positions. |
| Entered order, phone | [Before](before-F5-390.png) | [After](F5-390.png) | Summary now agrees with the stack order. Readout scrolls within the stage; partial next chip indicates more content. |
| Entered order, desktop | [Before](before-F5-1280.png) | [After](F5-1280.png) | All four exact labels and the summary retain 45, 10, 25, 2.5 order. |

All F1–F8 captures were visually inspected. Phone labels remain outside the
scaled artwork; wide face labels are retained only above the final 12 px
floor. Occluded far-side plates remain named in the unscaled readout and in
the per-disc accessibility tree. The browser test measures final transformed
text size, label order, lb-before-kg totals, and non-overlapping total bounds.

This proof does not establish loadout-change motion, native F1–F8 parity,
manual VoiceOver traversal, or the epic-wide comparable capture matrix.

## Native inspection

Source: `650a9845f2544ead5921fe960a7262ef1b85d09d`, Xcode 26.6,
iPhone 17 Pro simulator, [visual run 36247112214](https://github.com/madhakish/cadence/actions/runs/36247112214).
All 10 capture tests passed, including exact mixed-unit accessibility labels,
inspection controls, button clearance, and the calculator target at large text.

- [Calculator](calculator-iphone.png): the 20 kg and 1.25 kg readout fits below
  the artwork without compressed text.
- [Exploded inspector](inspector-exploded-iphone.png): kg stamps and exact
  per-side list remain visible; lb total precedes kg.
- [Exercise pane before count wrap](before-count-wrap-iphone.png): inspection
  caught the existing count cells truncating to “2 × 2…” and “2 × 1…”. This
  proof commit removes the one-line/shrinking constraint so those counts wrap.
  Final-head native verification and the resulting screenshot review are
  recorded in [PR #262](https://github.com/madhakish/cadence/pull/262).

The standard current-session screenshot places the readout below the fold,
and the largest-text calculator capture only shows the target and artwork.
These captures do not prove readout traversal at accessibility text sizes.
The accessibility audit also retains advisories for small targets and the
fixed-size MAIN/SQUAT/R2 LOAD labels; its green result is not a clean manual
VoiceOver audit. Those broader checks remain in #187.
