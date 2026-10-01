# Application pixel review — 1 October 2026

Inspected **all 186 original PNGs** retained in [the capture index](proof/final-177/README.md):
14 native and 28 browser baseline images, then 78 native and 66 browser candidate
images. The two native audit text attachments were also read. Images were viewed
at their original dimensions; this record contains no substituted mockups,
resized composites or generated screens.

Before source: `11895fb95cde9e4b938831098d00dd0350b45bc2`.
After source: `78405bf4a12c32e5be65373b7006cb11c355d4e6`.
[Capture run](https://github.com/madhakish/cadence/actions/runs/36811839554)
passed both jobs. Native captures are iPhone 17 Pro, 1206 × 2622 pixels /
402 × 874 points. Browser captures are 390 × 844 and 1280 × 800, plus
320/430 CSS-pixel Favorites stress at CSS zoom 1/2 with reduced motion.
The documentation commit retains evidence for that application source; its
own required CI must pass before PR #271 becomes ready for review.

[Before/after pairs](BEFORE-AFTER.md), [acceptance and data audit](FINAL-VERIFICATION.md),
[material decisions](DECISIONS.md) and [asset inventory](ASSET-INVENTORY.md)
provide the accompanying context. **Inspected does not mean every capture
meets its intended acceptance condition.** The failures and limits below are
part of the retained evidence.

## Baseline comparison

- Original native Settings and calculator use rounded Form groups. The candidate
  uses actual plain Lists, divider rows and the saved app-theme canvas. Native
  row fills remain platform surfaces; matching canvas tokens does not make
  browser and native row colors identical.
- The original session foregrounds warmups/progress and gym context. The current
  session foregrounds set 2 of 3, 6 reps, 138.7 lb / 62.9 kg and its action.
  A separate scrolled native loading image makes achieved totals and counts
  readable; it does not show the entire bar and every control simultaneously.
- The original Library is a long catalog. Normal-size candidate Library and
  picker states show search, an independent star, Favorites before Recent,
  counted category disclosures and composed filters. Categories retain their
  42 / 98 / 19 fixture counts; no-results is an explicit state.
- Normal native anatomy now shows full Lower back and Hamstrings names, and
  selected Quads with a clear-selection action. The original gorilla bytes and
  registered masks remain unchanged. The baseline has no selected-muscle
  interaction, Favorites, duration editor or two-state plate inspector.
- Expanded native programming keeps both load and set count readable: R1/R2
  138.7 lb with 4 × 10 / 4 × 8; R3 144.2 lb with 3 × 8; R4 111.1 lb with 1 × 5.
- Latest baseline 139 / 135 / 22.5 calculator inputs are readable. Earlier
  transient input clipping is not attributed to these new baseline captures.
- The baseline native rest image retains the initial long Form viewport: its
  complementary/accessory controls are visible, while the squat main rest is
  below the fold. The current rest image opens the disclosure and scrolls to
  that control. These are different navigation states, not identical viewports.

## Loading and imagery

| Scenario | Inspected result and boundary |
| --- | --- |
| 135 lb exact | 135 lb / 61.2 kg; 45 lb bar and 45 lb per side. |
| 139 lb mixed | 138.7 lb / 62.9 kg; 45 lb bar and 20 kg + 1.25 kg per side. |
| 22.5 kg change plates | 49.6 lb / 22.5 kg; 20 kg bar and 1.25 kg per side. Mobile browser capture is scrolled to the achieved summary, so its target is above the viewport. |
| Entered stack | 50.5 lb / 22.9 kg; 45 lb bar and 1.25 kg per side. |
| Unreachable 200 lb | 225 lb / 102.1 kg, +25 lb; two 45 lb plates per side. Native scrolled capture shows both policy warnings; browser first viewport does not establish their complete legibility. |
| Ten equipment themes | All assembled/exploded native theme images inspected. Silhouettes, local material faces, exploded captions and denomination/count lists are present. Assembled stacks occlude stamps; gray/black face text does not establish AA. |
| Inline diagram versus inspector | Inline diagrams show both sleeves. The inspector deliberately frames the near sleeve and cuts to separated plates; the mobile inspector's shaft extends out of its viewport. It is not proof of a whole-bar inspection view. |
| Five application palettes | Native Settings/calculator and browser Settings inspected for Carbon, Memento, Titanium, Slate and System. System is captured in light appearance on both clients; both OS appearances are not established. |

The `barbell-bumper-exploded` native filename still has a Steel fixture summary;
its name alone does not prove a bumper selection. The explicit test15 equipment
theme captures supply the bumper variants. The exact original gorilla hashes
and all 158 equipment PNGs are documented separately in the asset inventory.
Library/History remain text-led; this PR does not add the broader movement and
implement illustration family requested by #198.

## Remaining visual and capture defects

These remain actionable work under #187/#198 and keep the epic open.

| Evidence | Finding | Acceptance boundary |
| --- | --- | --- |
| `after-settings-audio-iphone.png` | Attempted audio-setting viewport still has the switch under the bottom tab blur. | Does not establish a fully readable audio setting, headphone routing or audible completion. |
| `after-web-session-picker-390.png` | Shows the underlying session and Add exercise button rather than an open picker. | Not valid mobile picker-state proof. The 1280 modal and native picker are valid inspected states; browser engine tests are separate evidence. |
| `after-web-exercise-anatomy-390.png` | Nominal unselected capture already shows Quads selected. | Not proof of a cleared mobile anatomy state. Native and 1280 captures show unselected states. |
| Desktop mixed inline diagrams: `after-web-plate-calculator-1280.png`, `after-web-exercise-pane-1280.png`, `after-web-session-plates-1280.png` | Small near-hub denomination labels overlap. | Exact per-side text remains outside the artwork, but these labels need layout work. |
| Desktop forward calculator and `after-web-session-plates-1280.png` | Large bar diagram pushes achieved totals below the first viewport. | Does not establish simultaneous full-bar and complete-loading readability in that viewport. |
| `favorites-accessibility-iphone.png` | Maximum-text search/query and some rows sit under system navigation chrome; the query is clipped. | The separate 44-point-star test passes, but full unclipped maximum-text browsing is not established. |
| Native intermediate Library category scrolling; `after-web-settings-rest-390.png` | Floating plate button can cover an intermediate row/count/star; mobile rest capture obscures part of Olympic rest. | End-of-scroll clearance is verified only at the tested endpoints. It does not prove clearance at every scroll position. |
| `after-14-calculator-target-accessibility-iphone.png` and maximum-text hold state | Target and countdown/action remain readable; large heading/help content is partly outside the viewport. | Targeted interaction success does not establish all-surface large-text acceptance. |
| Favorites CSS zoom 2 stress captures | Wrapped rows and star remain usable in the shown scrolled state; search and filters are outside that viewport. | CSS layout stress is not actual browser/pinch zoom or a complete full-flow accessibility review. |

Native normal rest shows 00:05:00 / 00:03:00 / 00:01:30 and the Olympic/other
main values. Both native and browser duration editors show separate Hours,
Minutes and Seconds, 0 / 5 / 0, 00:05:00, Off, Cancel, Save and carry guidance.
Browser Settings roots are at the top in both widths. These observations do
not turn the incomplete mobile rest/audio viewports into successful evidence.

## Accessibility and physical limits

The raw native [current-session audit](proof/final-177/after/dynamic-type-advisories-current-session.txt)
retains two unassociated small-hit-region findings, one unassociated contrast
finding and fixed-type advisories, including load/repetition labels and the
exercise-info button. The [Today audit](proof/final-177/after/dynamic-type-advisories-today.txt)
retains a fixed-type ad-hoc-work explanation. Audit filters do not establish
complete AA, every plate-face contrast ratio or spoken VoiceOver.

Automated source gates passed 504 core tests, 81 migration/backup tests, 14
Chromium/WebKit acceptance cases, an unsigned device build and four native
interactions with zero skips. That proves the listed automated paths, not
physical Lock Screen/Dynamic Island workout progression, headphone/music
routing, manual VoiceOver, all native widths or actual 200% browser/pinch zoom.
No such physical evidence is present in these artifacts.

## Individually inspected images

The tables below enumerate every PNG actually viewed. Source, test/scenario,
viewport, fixture schema and original-byte SHA-256 are in the capture index.
Findings above qualify the filenames; an entry is not a blanket pass.

### Before native

| Inspected image | Pixels |
| --- | --- |
| [before-01-home-iphone.png](proof/final-177/before/before-01-home-iphone.png) | 1206 × 2622 |
| [before-02-ad-hoc-work-iphone.png](proof/final-177/before/before-02-ad-hoc-work-iphone.png) | 1206 × 2622 |
| [before-03-current-session-iphone.png](proof/final-177/before/before-03-current-session-iphone.png) | 1206 × 2622 |
| [before-04-exercise-anatomy-iphone.png](proof/final-177/before/before-04-exercise-anatomy-iphone.png) | 1206 × 2622 |
| [before-05-plate-calculator-iphone.png](proof/final-177/before/before-05-plate-calculator-iphone.png) | 1206 × 2622 |
| [before-06-settings-iphone.png](proof/final-177/before/before-06-settings-iphone.png) | 1206 × 2622 |
| [before-07-history-ad-hoc-iphone.png](proof/final-177/before/before-07-history-ad-hoc-iphone.png) | 1206 × 2622 |
| [before-calculator-kg-change-iphone.png](proof/final-177/before/before-calculator-kg-change-iphone.png) | 1206 × 2622 |
| [before-calculator-lb-exact-iphone.png](proof/final-177/before/before-calculator-lb-exact-iphone.png) | 1206 × 2622 |
| [before-calculator-mixed-iphone.png](proof/final-177/before/before-calculator-mixed-iphone.png) | 1206 × 2622 |
| [before-calculator-reverse-iphone.png](proof/final-177/before/before-calculator-reverse-iphone.png) | 1206 × 2622 |
| [before-calculator-unreachable-iphone.png](proof/final-177/before/before-calculator-unreachable-iphone.png) | 1206 × 2622 |
| [before-library-iphone.png](proof/final-177/before/before-library-iphone.png) | 1206 × 2622 |
| [before-settings-rest-iphone.png](proof/final-177/before/before-settings-rest-iphone.png) | 1206 × 2622 |

### Before browser

| Inspected image | Pixels |
| --- | --- |
| [before-web-ad-hoc-work-1280.png](proof/final-177/before/before-web-ad-hoc-work-1280.png) | 1280 × 800 |
| [before-web-ad-hoc-work-390.png](proof/final-177/before/before-web-ad-hoc-work-390.png) | 390 × 844 |
| [before-web-calculator-kg-change-1280.png](proof/final-177/before/before-web-calculator-kg-change-1280.png) | 1280 × 800 |
| [before-web-calculator-kg-change-390.png](proof/final-177/before/before-web-calculator-kg-change-390.png) | 390 × 844 |
| [before-web-calculator-lb-exact-1280.png](proof/final-177/before/before-web-calculator-lb-exact-1280.png) | 1280 × 800 |
| [before-web-calculator-lb-exact-390.png](proof/final-177/before/before-web-calculator-lb-exact-390.png) | 390 × 844 |
| [before-web-calculator-reverse-1280.png](proof/final-177/before/before-web-calculator-reverse-1280.png) | 1280 × 800 |
| [before-web-calculator-reverse-390.png](proof/final-177/before/before-web-calculator-reverse-390.png) | 390 × 844 |
| [before-web-calculator-unreachable-1280.png](proof/final-177/before/before-web-calculator-unreachable-1280.png) | 1280 × 800 |
| [before-web-calculator-unreachable-390.png](proof/final-177/before/before-web-calculator-unreachable-390.png) | 390 × 844 |
| [before-web-exercise-anatomy-1280.png](proof/final-177/before/before-web-exercise-anatomy-1280.png) | 1280 × 800 |
| [before-web-exercise-anatomy-390.png](proof/final-177/before/before-web-exercise-anatomy-390.png) | 390 × 844 |
| [before-web-exercise-pane-1280.png](proof/final-177/before/before-web-exercise-pane-1280.png) | 1280 × 800 |
| [before-web-exercise-pane-390.png](proof/final-177/before/before-web-exercise-pane-390.png) | 390 × 844 |
| [before-web-history-1280.png](proof/final-177/before/before-web-history-1280.png) | 1280 × 800 |
| [before-web-history-390.png](proof/final-177/before/before-web-history-390.png) | 390 × 844 |
| [before-web-library-1280.png](proof/final-177/before/before-web-library-1280.png) | 1280 × 800 |
| [before-web-library-390.png](proof/final-177/before/before-web-library-390.png) | 390 × 844 |
| [before-web-plate-calculator-1280.png](proof/final-177/before/before-web-plate-calculator-1280.png) | 1280 × 800 |
| [before-web-plate-calculator-390.png](proof/final-177/before/before-web-plate-calculator-390.png) | 390 × 844 |
| [before-web-session-1280.png](proof/final-177/before/before-web-session-1280.png) | 1280 × 800 |
| [before-web-session-390.png](proof/final-177/before/before-web-session-390.png) | 390 × 844 |
| [before-web-settings-1280.png](proof/final-177/before/before-web-settings-1280.png) | 1280 × 800 |
| [before-web-settings-390.png](proof/final-177/before/before-web-settings-390.png) | 390 × 844 |
| [before-web-settings-rest-1280.png](proof/final-177/before/before-web-settings-rest-1280.png) | 1280 × 800 |
| [before-web-settings-rest-390.png](proof/final-177/before/before-web-settings-rest-390.png) | 390 × 844 |
| [before-web-today-1280.png](proof/final-177/before/before-web-today-1280.png) | 1280 × 800 |
| [before-web-today-390.png](proof/final-177/before/before-web-today-390.png) | 390 × 844 |

### After native

| Inspected image | Pixels |
| --- | --- |
| [after-01-home-iphone.png](proof/final-177/after/after-01-home-iphone.png) | 1206 × 2622 |
| [after-02-ad-hoc-work-iphone.png](proof/final-177/after/after-02-ad-hoc-work-iphone.png) | 1206 × 2622 |
| [after-03-current-session-iphone.png](proof/final-177/after/after-03-current-session-iphone.png) | 1206 × 2622 |
| [after-03b-current-set-plates-iphone.png](proof/final-177/after/after-03b-current-set-plates-iphone.png) | 1206 × 2622 |
| [after-04-exercise-pane-iphone.png](proof/final-177/after/after-04-exercise-pane-iphone.png) | 1206 × 2622 |
| [after-04b-exercise-pane-tiers-open-iphone.png](proof/final-177/after/after-04b-exercise-pane-tiers-open-iphone.png) | 1206 × 2622 |
| [after-05-anatomy-unselected-iphone.png](proof/final-177/after/after-05-anatomy-unselected-iphone.png) | 1206 × 2622 |
| [after-06-anatomy-selected-iphone.png](proof/final-177/after/after-06-anatomy-selected-iphone.png) | 1206 × 2622 |
| [after-07-plate-calculator-iphone.png](proof/final-177/after/after-07-plate-calculator-iphone.png) | 1206 × 2622 |
| [after-09-settings-iphone.png](proof/final-177/after/after-09-settings-iphone.png) | 1206 × 2622 |
| [after-10-history-ad-hoc-iphone.png](proof/final-177/after/after-10-history-ad-hoc-iphone.png) | 1206 × 2622 |
| [after-11-body-end-clears-plate-button-iphone.png](proof/final-177/after/after-11-body-end-clears-plate-button-iphone.png) | 1206 × 2622 |
| [after-11-history-end-clears-plate-button-iphone.png](proof/final-177/after/after-11-history-end-clears-plate-button-iphone.png) | 1206 × 2622 |
| [after-11-program-end-clears-plate-button-iphone.png](proof/final-177/after/after-11-program-end-clears-plate-button-iphone.png) | 1206 × 2622 |
| [after-11-session-end-clears-plate-button-iphone.png](proof/final-177/after/after-11-session-end-clears-plate-button-iphone.png) | 1206 × 2622 |
| [after-11-settings-end-clears-plate-button-iphone.png](proof/final-177/after/after-11-settings-end-clears-plate-button-iphone.png) | 1206 × 2622 |
| [after-11-today-end-clears-plate-button-iphone.png](proof/final-177/after/after-11-today-end-clears-plate-button-iphone.png) | 1206 × 2622 |
| [after-12-audit-current-session-iphone.png](proof/final-177/after/after-12-audit-current-session-iphone.png) | 1206 × 2622 |
| [after-12-audit-plate-calculator-iphone.png](proof/final-177/after/after-12-audit-plate-calculator-iphone.png) | 1206 × 2622 |
| [after-12-audit-settings-iphone.png](proof/final-177/after/after-12-audit-settings-iphone.png) | 1206 × 2622 |
| [after-12-audit-today-iphone.png](proof/final-177/after/after-12-audit-today-iphone.png) | 1206 × 2622 |
| [after-13-session-after-set-iphone.png](proof/final-177/after/after-13-session-after-set-iphone.png) | 1206 × 2622 |
| [after-13-session-before-set-iphone.png](proof/final-177/after/after-13-session-before-set-iphone.png) | 1206 × 2622 |
| [after-14-calculator-target-accessibility-iphone.png](proof/final-177/after/after-14-calculator-target-accessibility-iphone.png) | 1206 × 2622 |
| [after-14-calculator-target-standard-iphone.png](proof/final-177/after/after-14-calculator-target-standard-iphone.png) | 1206 × 2622 |
| [after-15-theme-blackBumpersBand-assembled-iphone.png](proof/final-177/after/after-15-theme-blackBumpersBand-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-blackBumpersBand-exploded-iphone.png](proof/final-177/after/after-15-theme-blackBumpersBand-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-cadenceHouse-assembled-iphone.png](proof/final-177/after/after-15-theme-cadenceHouse-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-cadenceHouse-exploded-iphone.png](proof/final-177/after/after-15-theme-cadenceHouse-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-ipfCalibrated-assembled-iphone.png](proof/final-177/after/after-15-theme-ipfCalibrated-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-ipfCalibrated-exploded-iphone.png](proof/final-177/after/after-15-theme-ipfCalibrated-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-ipfCalibratedGloss-assembled-iphone.png](proof/final-177/after/after-15-theme-ipfCalibratedGloss-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-ipfCalibratedGloss-exploded-iphone.png](proof/final-177/after/after-15-theme-ipfCalibratedGloss-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-iwfCompetition-assembled-iphone.png](proof/final-177/after/after-15-theme-iwfCompetition-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-iwfCompetition-exploded-iphone.png](proof/final-177/after/after-15-theme-iwfCompetition-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-iwfTraining-assembled-iphone.png](proof/final-177/after/after-15-theme-iwfTraining-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-iwfTraining-exploded-iphone.png](proof/final-177/after/after-15-theme-iwfTraining-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-lbBlackIron-assembled-iphone.png](proof/final-177/after/after-15-theme-lbBlackIron-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-lbBlackIron-exploded-iphone.png](proof/final-177/after/after-15-theme-lbBlackIron-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-lbColourBumpers-assembled-iphone.png](proof/final-177/after/after-15-theme-lbColourBumpers-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-lbColourBumpers-exploded-iphone.png](proof/final-177/after/after-15-theme-lbColourBumpers-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-lbGreyHammertone-assembled-iphone.png](proof/final-177/after/after-15-theme-lbGreyHammertone-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-lbGreyHammertone-exploded-iphone.png](proof/final-177/after/after-15-theme-lbGreyHammertone-exploded-iphone.png) | 1206 × 2622 |
| [after-15-theme-lbMachinedSteel-assembled-iphone.png](proof/final-177/after/after-15-theme-lbMachinedSteel-assembled-iphone.png) | 1206 × 2622 |
| [after-15-theme-lbMachinedSteel-exploded-iphone.png](proof/final-177/after/after-15-theme-lbMachinedSteel-exploded-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-carbon-calculator-iphone.png](proof/final-177/after/after-19-app-theme-carbon-calculator-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-carbon-settings-iphone.png](proof/final-177/after/after-19-app-theme-carbon-settings-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-memento-calculator-iphone.png](proof/final-177/after/after-19-app-theme-memento-calculator-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-memento-settings-iphone.png](proof/final-177/after/after-19-app-theme-memento-settings-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-slate-calculator-iphone.png](proof/final-177/after/after-19-app-theme-slate-calculator-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-slate-settings-iphone.png](proof/final-177/after/after-19-app-theme-slate-settings-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-system-calculator-iphone.png](proof/final-177/after/after-19-app-theme-system-calculator-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-system-settings-iphone.png](proof/final-177/after/after-19-app-theme-system-settings-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-titanium-calculator-iphone.png](proof/final-177/after/after-19-app-theme-titanium-calculator-iphone.png) | 1206 × 2622 |
| [after-19-app-theme-titanium-settings-iphone.png](proof/final-177/after/after-19-app-theme-titanium-settings-iphone.png) | 1206 × 2622 |
| [after-calculator-kg-change-iphone.png](proof/final-177/after/after-calculator-kg-change-iphone.png) | 1206 × 2622 |
| [after-calculator-lb-exact-iphone.png](proof/final-177/after/after-calculator-lb-exact-iphone.png) | 1206 × 2622 |
| [after-calculator-mixed-iphone.png](proof/final-177/after/after-calculator-mixed-iphone.png) | 1206 × 2622 |
| [after-calculator-reverse-iphone.png](proof/final-177/after/after-calculator-reverse-iphone.png) | 1206 × 2622 |
| [after-calculator-unreachable-iphone.png](proof/final-177/after/after-calculator-unreachable-iphone.png) | 1206 × 2622 |
| [after-duration-picker-iphone.png](proof/final-177/after/after-duration-picker-iphone.png) | 1206 × 2622 |
| [after-settings-audio-iphone.png](proof/final-177/after/after-settings-audio-iphone.png) | 1206 × 2622 |
| [after-settings-rest-iphone.png](proof/final-177/after/after-settings-rest-iphone.png) | 1206 × 2622 |
| [barbell-assembled-iphone.png](proof/final-177/after/barbell-assembled-iphone.png) | 1206 × 2622 |
| [barbell-bumper-exploded-iphone.png](proof/final-177/after/barbell-bumper-exploded-iphone.png) | 1206 × 2622 |
| [barbell-exploded-iphone.png](proof/final-177/after/barbell-exploded-iphone.png) | 1206 × 2622 |
| [barbell-workout-preview-inspection-iphone.png](proof/final-177/after/barbell-workout-preview-inspection-iphone.png) | 1206 × 2622 |
| [barbell-workout-preview-iphone.png](proof/final-177/after/barbell-workout-preview-iphone.png) | 1206 × 2622 |
| [favorites-01-library-empty-iphone.png](proof/final-177/after/favorites-01-library-empty-iphone.png) | 1206 × 2622 |
| [favorites-02-library-filtered-iphone.png](proof/final-177/after/favorites-02-library-filtered-iphone.png) | 1206 × 2622 |
| [favorites-03-library-starred-iphone.png](proof/final-177/after/favorites-03-library-starred-iphone.png) | 1206 × 2622 |
| [favorites-04-session-picker-iphone.png](proof/final-177/after/favorites-04-session-picker-iphone.png) | 1206 × 2622 |
| [favorites-accessibility-iphone.png](proof/final-177/after/favorites-accessibility-iphone.png) | 1206 × 2622 |
| [favorites-library-category-iphone.png](proof/final-177/after/favorites-library-category-iphone.png) | 1206 × 2622 |
| [favorites-library-composed-iphone.png](proof/final-177/after/favorites-library-composed-iphone.png) | 1206 × 2622 |
| [favorites-library-no-results-iphone.png](proof/final-177/after/favorites-library-no-results-iphone.png) | 1206 × 2622 |
| [plank-countdown-accessibility-iphone.png](proof/final-177/after/plank-countdown-accessibility-iphone.png) | 1206 × 2622 |
| [plank-target-complete-iphone.png](proof/final-177/after/plank-target-complete-iphone.png) | 1206 × 2622 |

### After browser

| Inspected image | Pixels |
| --- | --- |
| [after-web-ad-hoc-work-1280.png](proof/final-177/after/after-web-ad-hoc-work-1280.png) | 1280 × 800 |
| [after-web-ad-hoc-work-390.png](proof/final-177/after/after-web-ad-hoc-work-390.png) | 390 × 844 |
| [after-web-app-theme-carbon-settings-1280.png](proof/final-177/after/after-web-app-theme-carbon-settings-1280.png) | 1280 × 800 |
| [after-web-app-theme-carbon-settings-390.png](proof/final-177/after/after-web-app-theme-carbon-settings-390.png) | 390 × 844 |
| [after-web-app-theme-memento-settings-1280.png](proof/final-177/after/after-web-app-theme-memento-settings-1280.png) | 1280 × 800 |
| [after-web-app-theme-memento-settings-390.png](proof/final-177/after/after-web-app-theme-memento-settings-390.png) | 390 × 844 |
| [after-web-app-theme-slate-settings-1280.png](proof/final-177/after/after-web-app-theme-slate-settings-1280.png) | 1280 × 800 |
| [after-web-app-theme-slate-settings-390.png](proof/final-177/after/after-web-app-theme-slate-settings-390.png) | 390 × 844 |
| [after-web-app-theme-system-settings-1280.png](proof/final-177/after/after-web-app-theme-system-settings-1280.png) | 1280 × 800 |
| [after-web-app-theme-system-settings-390.png](proof/final-177/after/after-web-app-theme-system-settings-390.png) | 390 × 844 |
| [after-web-app-theme-titanium-settings-1280.png](proof/final-177/after/after-web-app-theme-titanium-settings-1280.png) | 1280 × 800 |
| [after-web-app-theme-titanium-settings-390.png](proof/final-177/after/after-web-app-theme-titanium-settings-390.png) | 390 × 844 |
| [after-web-calculator-kg-change-1280.png](proof/final-177/after/after-web-calculator-kg-change-1280.png) | 1280 × 800 |
| [after-web-calculator-kg-change-390.png](proof/final-177/after/after-web-calculator-kg-change-390.png) | 390 × 844 |
| [after-web-calculator-lb-exact-1280.png](proof/final-177/after/after-web-calculator-lb-exact-1280.png) | 1280 × 800 |
| [after-web-calculator-lb-exact-390.png](proof/final-177/after/after-web-calculator-lb-exact-390.png) | 390 × 844 |
| [after-web-calculator-reverse-1280.png](proof/final-177/after/after-web-calculator-reverse-1280.png) | 1280 × 800 |
| [after-web-calculator-reverse-390.png](proof/final-177/after/after-web-calculator-reverse-390.png) | 390 × 844 |
| [after-web-calculator-unreachable-1280.png](proof/final-177/after/after-web-calculator-unreachable-1280.png) | 1280 × 800 |
| [after-web-calculator-unreachable-390.png](proof/final-177/after/after-web-calculator-unreachable-390.png) | 390 × 844 |
| [after-web-duration-picker-1280.png](proof/final-177/after/after-web-duration-picker-1280.png) | 1280 × 800 |
| [after-web-duration-picker-390.png](proof/final-177/after/after-web-duration-picker-390.png) | 390 × 844 |
| [after-web-exercise-anatomy-1280.png](proof/final-177/after/after-web-exercise-anatomy-1280.png) | 1280 × 800 |
| [after-web-exercise-anatomy-390.png](proof/final-177/after/after-web-exercise-anatomy-390.png) | 390 × 844 |
| [after-web-exercise-anatomy-selected-1280.png](proof/final-177/after/after-web-exercise-anatomy-selected-1280.png) | 1280 × 800 |
| [after-web-exercise-anatomy-selected-390.png](proof/final-177/after/after-web-exercise-anatomy-selected-390.png) | 390 × 844 |
| [after-web-exercise-pane-1280.png](proof/final-177/after/after-web-exercise-pane-1280.png) | 1280 × 800 |
| [after-web-exercise-pane-390.png](proof/final-177/after/after-web-exercise-pane-390.png) | 390 × 844 |
| [after-web-exercise-pane-expanded-1280.png](proof/final-177/after/after-web-exercise-pane-expanded-1280.png) | 1280 × 800 |
| [after-web-exercise-pane-expanded-390.png](proof/final-177/after/after-web-exercise-pane-expanded-390.png) | 390 × 844 |
| [after-web-favorites-320-zoom1.png](proof/final-177/after/after-web-favorites-320-zoom1.png) | 320 × 844 |
| [after-web-favorites-320-zoom2.png](proof/final-177/after/after-web-favorites-320-zoom2.png) | 320 × 844 |
| [after-web-favorites-430-zoom1.png](proof/final-177/after/after-web-favorites-430-zoom1.png) | 430 × 844 |
| [after-web-favorites-430-zoom2.png](proof/final-177/after/after-web-favorites-430-zoom2.png) | 430 × 844 |
| [after-web-history-1280.png](proof/final-177/after/after-web-history-1280.png) | 1280 × 800 |
| [after-web-history-390.png](proof/final-177/after/after-web-history-390.png) | 390 × 844 |
| [after-web-library-1280.png](proof/final-177/after/after-web-library-1280.png) | 1280 × 800 |
| [after-web-library-390.png](proof/final-177/after/after-web-library-390.png) | 390 × 844 |
| [after-web-library-category-1280.png](proof/final-177/after/after-web-library-category-1280.png) | 1280 × 800 |
| [after-web-library-category-390.png](proof/final-177/after/after-web-library-category-390.png) | 390 × 844 |
| [after-web-library-composed-1280.png](proof/final-177/after/after-web-library-composed-1280.png) | 1280 × 800 |
| [after-web-library-composed-390.png](proof/final-177/after/after-web-library-composed-390.png) | 390 × 844 |
| [after-web-library-favorites-1280.png](proof/final-177/after/after-web-library-favorites-1280.png) | 1280 × 800 |
| [after-web-library-favorites-390.png](proof/final-177/after/after-web-library-favorites-390.png) | 390 × 844 |
| [after-web-library-no-results-1280.png](proof/final-177/after/after-web-library-no-results-1280.png) | 1280 × 800 |
| [after-web-library-no-results-390.png](proof/final-177/after/after-web-library-no-results-390.png) | 390 × 844 |
| [after-web-library-search-1280.png](proof/final-177/after/after-web-library-search-1280.png) | 1280 × 800 |
| [after-web-library-search-390.png](proof/final-177/after/after-web-library-search-390.png) | 390 × 844 |
| [after-web-plate-calculator-1280.png](proof/final-177/after/after-web-plate-calculator-1280.png) | 1280 × 800 |
| [after-web-plate-calculator-390.png](proof/final-177/after/after-web-plate-calculator-390.png) | 390 × 844 |
| [after-web-plate-inspection-1280.png](proof/final-177/after/after-web-plate-inspection-1280.png) | 1280 × 800 |
| [after-web-plate-inspection-390.png](proof/final-177/after/after-web-plate-inspection-390.png) | 390 × 844 |
| [after-web-plate-inspection-exploded-1280.png](proof/final-177/after/after-web-plate-inspection-exploded-1280.png) | 1280 × 800 |
| [after-web-plate-inspection-exploded-390.png](proof/final-177/after/after-web-plate-inspection-exploded-390.png) | 390 × 844 |
| [after-web-session-1280.png](proof/final-177/after/after-web-session-1280.png) | 1280 × 800 |
| [after-web-session-390.png](proof/final-177/after/after-web-session-390.png) | 390 × 844 |
| [after-web-session-picker-1280.png](proof/final-177/after/after-web-session-picker-1280.png) | 1280 × 800 |
| [after-web-session-picker-390.png](proof/final-177/after/after-web-session-picker-390.png) | 390 × 844 |
| [after-web-session-plates-1280.png](proof/final-177/after/after-web-session-plates-1280.png) | 1280 × 800 |
| [after-web-session-plates-390.png](proof/final-177/after/after-web-session-plates-390.png) | 390 × 844 |
| [after-web-settings-1280.png](proof/final-177/after/after-web-settings-1280.png) | 1280 × 800 |
| [after-web-settings-390.png](proof/final-177/after/after-web-settings-390.png) | 390 × 844 |
| [after-web-settings-rest-1280.png](proof/final-177/after/after-web-settings-rest-1280.png) | 1280 × 800 |
| [after-web-settings-rest-390.png](proof/final-177/after/after-web-settings-rest-390.png) | 390 × 844 |
| [after-web-today-1280.png](proof/final-177/after/after-web-today-1280.png) | 1280 × 800 |
| [after-web-today-390.png](proof/final-177/after/after-web-today-390.png) | 390 × 844 |
