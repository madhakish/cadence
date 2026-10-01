# Application before/after — epic #177

These application captures come from the real native views and the production PWA. [Pixel review](PIXEL-REVIEW.md) records the images actually inspected and their findings. No mockups or generated replacement screens are used.

Before: `11895fb95cde9e4b938831098d00dd0350b45bc2`. After: `78405bf4a12c32e5be65373b7006cb11c355d4e6`. [Run](https://github.com/madhakish/cadence/actions/runs/36811839554) · [Every capture, source metadata and hash](proof/final-177/README.md) · [Acceptance, parity and protected-code audit](FINAL-VERIFICATION.md).

Both revisions use the same synthetic seed recipe. Store identities and relative timestamps are created for each run; baseline export schema 12 and candidate schema 16 reflect the actual application contracts. Web replays each revision's native fixture through its production importer.

The baseline checkout receives only the recorded in-memory bootstrap, UI-test target and calculator scenario startup arguments. Its layout, renderer, solver and application behavior are original; [original instrumentation patch (Base64)](proof/final-177/before/instrumentation.patch.b64) records the exact delta.

## iPhone pairs

Both use the original DP-1 iPhone 17 Pro viewport: 1206 × 2622 pixels / 402 × 874 points. These are not 390-point iPhone captures; the separate browser matrix uses the prescribed 390 × 844 viewport.

| Surface | Before | After |
| --- | --- | --- |
| Today | ![Today before](proof/final-177/before/before-01-home-iphone.png) | ![Today after](proof/final-177/after/after-01-home-iphone.png) |
| Ad-hoc work | ![Ad-hoc work before](proof/final-177/before/before-02-ad-hoc-work-iphone.png) | ![Ad-hoc work after](proof/final-177/after/after-02-ad-hoc-work-iphone.png) |
| Current session | ![Current session before](proof/final-177/before/before-03-current-session-iphone.png) | ![Current session after](proof/final-177/after/after-03-current-session-iphone.png) |
| Exercise information | ![Exercise information before](proof/final-177/before/before-04-exercise-anatomy-iphone.png) | ![Exercise information after](proof/final-177/after/after-04-exercise-pane-iphone.png) |
| Anatomy | ![Anatomy before](proof/final-177/before/before-04-exercise-anatomy-iphone.png) | ![Anatomy after](proof/final-177/after/after-05-anatomy-unselected-iphone.png) |
| Plate calculator / mixed units | ![Plate calculator / mixed units before](proof/final-177/before/before-05-plate-calculator-iphone.png) | ![Plate calculator / mixed units after](proof/final-177/after/after-07-plate-calculator-iphone.png) |
| Settings | ![Settings before](proof/final-177/before/before-06-settings-iphone.png) | ![Settings after](proof/final-177/after/after-09-settings-iphone.png) |
| History | ![History before](proof/final-177/before/before-07-history-ad-hoc-iphone.png) | ![History after](proof/final-177/after/after-10-history-ad-hoc-iphone.png) |
| Library / all categories | ![Library / all categories before](proof/final-177/before/before-library-iphone.png) | ![Library / all categories after](proof/final-177/after/favorites-01-library-empty-iphone.png) |
| Rest settings | ![Rest settings before](proof/final-177/before/before-settings-rest-iphone.png) | ![Rest settings after](proof/final-177/after/after-settings-rest-iphone.png) |
| Pure lb exact load | ![Pure lb exact load before](proof/final-177/before/before-calculator-lb-exact-iphone.png) | ![Pure lb exact load after](proof/final-177/after/after-calculator-lb-exact-iphone.png) |
| Mixed-unit fixture | ![Mixed-unit fixture before](proof/final-177/before/before-calculator-mixed-iphone.png) | ![Mixed-unit fixture after](proof/final-177/after/after-calculator-mixed-iphone.png) |
| kg change plates | ![kg change plates before](proof/final-177/before/before-calculator-kg-change-iphone.png) | ![kg change plates after](proof/final-177/after/after-calculator-kg-change-iphone.png) |
| Unreachable target / closest policy warning | ![Unreachable target / closest policy warning before](proof/final-177/before/before-calculator-unreachable-iphone.png) | ![Unreachable target / closest policy warning after](proof/final-177/after/after-calculator-unreachable-iphone.png) |
| Entered-stack reverse mode | ![Entered-stack reverse mode before](proof/final-177/before/before-calculator-reverse-iphone.png) | ![Entered-stack reverse mode after](proof/final-177/after/after-calculator-reverse-iphone.png) |

## Web pairs — 390 × 844

| Surface | Before | After |
| --- | --- | --- |
| Ad hoc work | ![Ad hoc work before](proof/final-177/before/before-web-ad-hoc-work-390.png) | ![Ad hoc work after](proof/final-177/after/after-web-ad-hoc-work-390.png) |
| Calculator kg change | ![Calculator kg change before](proof/final-177/before/before-web-calculator-kg-change-390.png) | ![Calculator kg change after](proof/final-177/after/after-web-calculator-kg-change-390.png) |
| Calculator lb exact | ![Calculator lb exact before](proof/final-177/before/before-web-calculator-lb-exact-390.png) | ![Calculator lb exact after](proof/final-177/after/after-web-calculator-lb-exact-390.png) |
| Calculator reverse | ![Calculator reverse before](proof/final-177/before/before-web-calculator-reverse-390.png) | ![Calculator reverse after](proof/final-177/after/after-web-calculator-reverse-390.png) |
| Calculator unreachable | ![Calculator unreachable before](proof/final-177/before/before-web-calculator-unreachable-390.png) | ![Calculator unreachable after](proof/final-177/after/after-web-calculator-unreachable-390.png) |
| Exercise anatomy | ![Exercise anatomy before](proof/final-177/before/before-web-exercise-anatomy-390.png) | ![Exercise anatomy after](proof/final-177/after/after-web-exercise-anatomy-390.png) |
| Exercise pane | ![Exercise pane before](proof/final-177/before/before-web-exercise-pane-390.png) | ![Exercise pane after](proof/final-177/after/after-web-exercise-pane-390.png) |
| History | ![History before](proof/final-177/before/before-web-history-390.png) | ![History after](proof/final-177/after/after-web-history-390.png) |
| Library | ![Library before](proof/final-177/before/before-web-library-390.png) | ![Library after](proof/final-177/after/after-web-library-390.png) |
| Plate calculator | ![Plate calculator before](proof/final-177/before/before-web-plate-calculator-390.png) | ![Plate calculator after](proof/final-177/after/after-web-plate-calculator-390.png) |
| Session | ![Session before](proof/final-177/before/before-web-session-390.png) | ![Session after](proof/final-177/after/after-web-session-390.png) |
| Settings | ![Settings before](proof/final-177/before/before-web-settings-390.png) | ![Settings after](proof/final-177/after/after-web-settings-390.png) |
| Settings rest | ![Settings rest before](proof/final-177/before/before-web-settings-rest-390.png) | ![Settings rest after](proof/final-177/after/after-web-settings-rest-390.png) |
| Today | ![Today before](proof/final-177/before/before-web-today-390.png) | ![Today after](proof/final-177/after/after-web-today-390.png) |

## Web pairs — 1280 × 800

| Surface | Before | After |
| --- | --- | --- |
| Ad hoc work | ![Ad hoc work before](proof/final-177/before/before-web-ad-hoc-work-1280.png) | ![Ad hoc work after](proof/final-177/after/after-web-ad-hoc-work-1280.png) |
| Calculator kg change | ![Calculator kg change before](proof/final-177/before/before-web-calculator-kg-change-1280.png) | ![Calculator kg change after](proof/final-177/after/after-web-calculator-kg-change-1280.png) |
| Calculator lb exact | ![Calculator lb exact before](proof/final-177/before/before-web-calculator-lb-exact-1280.png) | ![Calculator lb exact after](proof/final-177/after/after-web-calculator-lb-exact-1280.png) |
| Calculator reverse | ![Calculator reverse before](proof/final-177/before/before-web-calculator-reverse-1280.png) | ![Calculator reverse after](proof/final-177/after/after-web-calculator-reverse-1280.png) |
| Calculator unreachable | ![Calculator unreachable before](proof/final-177/before/before-web-calculator-unreachable-1280.png) | ![Calculator unreachable after](proof/final-177/after/after-web-calculator-unreachable-1280.png) |
| Exercise anatomy | ![Exercise anatomy before](proof/final-177/before/before-web-exercise-anatomy-1280.png) | ![Exercise anatomy after](proof/final-177/after/after-web-exercise-anatomy-1280.png) |
| Exercise pane | ![Exercise pane before](proof/final-177/before/before-web-exercise-pane-1280.png) | ![Exercise pane after](proof/final-177/after/after-web-exercise-pane-1280.png) |
| History | ![History before](proof/final-177/before/before-web-history-1280.png) | ![History after](proof/final-177/after/after-web-history-1280.png) |
| Library | ![Library before](proof/final-177/before/before-web-library-1280.png) | ![Library after](proof/final-177/after/after-web-library-1280.png) |
| Plate calculator | ![Plate calculator before](proof/final-177/before/before-web-plate-calculator-1280.png) | ![Plate calculator after](proof/final-177/after/after-web-plate-calculator-1280.png) |
| Session | ![Session before](proof/final-177/before/before-web-session-1280.png) | ![Session after](proof/final-177/after/after-web-session-1280.png) |
| Settings | ![Settings before](proof/final-177/before/before-web-settings-1280.png) | ![Settings after](proof/final-177/after/after-web-settings-1280.png) |
| Settings rest | ![Settings rest before](proof/final-177/before/before-web-settings-rest-1280.png) | ![Settings rest after](proof/final-177/after/after-web-settings-rest-1280.png) |
| Today | ![Today before](proof/final-177/before/before-web-today-1280.png) | ![Today after](proof/final-177/after/after-web-today-1280.png) |

## Additional current states

The complete index also retains the current-set loading readout; collapsed/expanded prescription; original gorilla selection states; Library category, search, composed/no-results and Favorites states; native and desktop session pickers; exact duration editor and attempted audio-setting viewport; assembled/exploded inspection across all ten equipment themes; native Settings/calculator and browser Settings under all five app palettes; maximum accessibility text; hold-timer and end-of-scroll clearance states.

All 186 original PNGs were inspected. The mobile browser picker capture did not open the picker, its nominal unselected anatomy capture is already selected, and the native audio switch remains below tab chrome. Desktop inline labels overlap in mixed stacks; some achieved totals are below the first viewport. Maximum-text chrome overlap and intermediate floating-button obstruction remain. [Pixel review](PIXEL-REVIEW.md) names the evidence and the incomplete acceptance conditions. Baseline native rest is the initial Form viewport; current rest is opened and scrolled, so this is not an identical-navigation comparison.

The pre-pass static anatomy has no selected-muscle state. It also has no Favorites, HH/MM/SS editor or two-state photographic inspector. These are current-only feature proofs, not invented baseline pairs.

## Render findings and corrections

- The original session puts completed warmups ahead of the current work. The candidate exposes the current set/load/action first, with a separate full loading capture.
- The old Library is a long flat catalog. The candidate opens with visible search, independent Favorites, Recent and count-bearing category disclosures; all calling pickers use the same browser.
- First candidate native pictures still had default Form containers despite plain List styling. Actual Lists now apply the intended divider/section composition on Settings, calculator and exercise detail.
- The inspected plain native Lists still inherited pure system black. Their canvas now uses each saved theme's existing web background token.
- Selected/unselected native anatomy showed ellipses in supporting-muscle names. Wider, wrapping cells now show the names, with one column at accessibility sizes; source artwork and masks are untouched.
- The native favorite failure regression retained a mutated bound object after rollback. The shared production save action restores its previous value explicitly.
- The first expanded programming capture clipped a set count; the weight and count now share a trailing stack. The first rest image caught a disclosure transition; the harness checks the expected control and saves settled pixels.
- Full native proof swipes oscillated past the rest control; small pans retain the full-row visibility assertion. Both browser Settings roots explicitly reset to the top, correcting the old mobile Library-entry scroll position.
- Web no-results styling overrode the hidden Clear filters control. The production CSS respects hidden, and both real browser engines pass.

The [older PR #188 comparison](BEFORE-AFTER-2026-09-05.md) remains a dated record. Its images and counts are not relabeled as proof for this candidate. Physical locked workout, Dynamic Island, headphone routing and manual assistive-technology acceptance remain explicitly unverified in the final checklist.
