# Final application capture index

Original DP-1 application: `11895fb95cde9e4b938831098d00dd0350b45bc2`.
Candidate and proof harness: `78405bf4a12c32e5be65373b7006cb11c355d4e6`.

[Capture run](https://github.com/madhakish/cadence/actions/runs/36811839554). Original PNG bytes are retained unchanged; all data is synthetic.

Native is iPhone 17 Pro at 1206 × 2622 pixels (402 × 874 points); web is 390 × 844 and 1280 × 800. Favorites also has 320/430 CSS-pixel stress captures at CSS zoom 1/2 with reduced motion.

The original application has no selected-muscle, Favorites, duration-editor or two-state inspector interaction. Their absence is recorded, not reconstructed.

All 186 original PNGs and both audit text attachments were inspected. [Pixel review](../../PIXEL-REVIEW.md) records the findings: the mobile picker and unselected anatomy images do not reach their intended state, the native audio switch is below tab chrome, and layout/maximum-text/contrast limits remain. Filenames describe attempted scenarios, not successful acceptance. Source metadata and original image bytes remain intact.

## Accessibility evidence limits

Raw native audit advisories are linked below. They include unassociated hit-region/contrast findings and fixed-size ancillary labels. The audit filters platform chrome, decorative plate-face contrast and noninteractive regions; it does not prove complete AA or spoken VoiceOver. The clearance test inspects controls at the scrolled end, not every intermediate scroll position. CSS zoom is layout stress, not manual browser/pinch zoom. Physical Lock Screen/Dynamic Island, headphones and spoken VoiceOver remain acceptance gates.

## Every retained capture

| File | Source | Pixels | Test or scenario |
| --- | --- | --- | --- |
| [after-01-home-iphone.png](after/after-01-home-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test01HomeAndAdHocWork()` |
| [after-02-ad-hoc-work-iphone.png](after/after-02-ad-hoc-work-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test01HomeAndAdHocWork()` |
| [after-03-current-session-iphone.png](after/after-03-current-session-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test02CurrentSessionAndExactPlateStack()` |
| [after-03b-current-set-plates-iphone.png](after/after-03b-current-set-plates-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test02CurrentSessionAndExactPlateStack()` |
| [after-04-exercise-pane-iphone.png](after/after-04-exercise-pane-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test03ExercisePaneAndPreservedAnatomy()` |
| [after-04b-exercise-pane-tiers-open-iphone.png](after/after-04b-exercise-pane-tiers-open-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test03ExercisePaneAndPreservedAnatomy()` |
| [after-05-anatomy-unselected-iphone.png](after/after-05-anatomy-unselected-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test03ExercisePaneAndPreservedAnatomy()` |
| [after-06-anatomy-selected-iphone.png](after/after-06-anatomy-selected-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test03ExercisePaneAndPreservedAnatomy()` |
| [after-07-plate-calculator-iphone.png](after/after-07-plate-calculator-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test04PlateCalculatorHero()` |
| [after-09-settings-iphone.png](after/after-09-settings-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test05SettingsAndHistory()` |
| [after-10-history-ad-hoc-iphone.png](after/after-10-history-ad-hoc-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test05SettingsAndHistory()` |
| [after-11-body-end-clears-plate-button-iphone.png](after/after-11-body-end-clears-plate-button-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test08PlateButtonNeverCoversContent()` |
| [after-11-history-end-clears-plate-button-iphone.png](after/after-11-history-end-clears-plate-button-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test08PlateButtonNeverCoversContent()` |
| [after-11-program-end-clears-plate-button-iphone.png](after/after-11-program-end-clears-plate-button-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test08PlateButtonNeverCoversContent()` |
| [after-11-session-end-clears-plate-button-iphone.png](after/after-11-session-end-clears-plate-button-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test08PlateButtonNeverCoversContent()` |
| [after-11-settings-end-clears-plate-button-iphone.png](after/after-11-settings-end-clears-plate-button-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test08PlateButtonNeverCoversContent()` |
| [after-11-today-end-clears-plate-button-iphone.png](after/after-11-today-end-clears-plate-button-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test08PlateButtonNeverCoversContent()` |
| [after-12-audit-current-session-iphone.png](after/after-12-audit-current-session-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test12AccessibilityAudit()` |
| [after-12-audit-plate-calculator-iphone.png](after/after-12-audit-plate-calculator-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test12AccessibilityAudit()` |
| [after-12-audit-settings-iphone.png](after/after-12-audit-settings-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test12AccessibilityAudit()` |
| [after-12-audit-today-iphone.png](after/after-12-audit-today-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test12AccessibilityAudit()` |
| [after-13-session-after-set-iphone.png](after/after-13-session-after-set-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test13SetCompletionKeepsDominantBlockStill()` |
| [after-13-session-before-set-iphone.png](after/after-13-session-before-set-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test13SetCompletionKeepsDominantBlockStill()` |
| [after-14-calculator-target-accessibility-iphone.png](after/after-14-calculator-target-accessibility-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test14CalculatorTargetAtAccessibilityTextSize()` |
| [after-14-calculator-target-standard-iphone.png](after/after-14-calculator-target-standard-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test14CalculatorTargetAtAccessibilityTextSize()` |
| [after-15-theme-blackBumpersBand-assembled-iphone.png](after/after-15-theme-blackBumpersBand-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-blackBumpersBand-exploded-iphone.png](after/after-15-theme-blackBumpersBand-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-cadenceHouse-assembled-iphone.png](after/after-15-theme-cadenceHouse-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-cadenceHouse-exploded-iphone.png](after/after-15-theme-cadenceHouse-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-ipfCalibrated-assembled-iphone.png](after/after-15-theme-ipfCalibrated-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-ipfCalibrated-exploded-iphone.png](after/after-15-theme-ipfCalibrated-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-ipfCalibratedGloss-assembled-iphone.png](after/after-15-theme-ipfCalibratedGloss-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-ipfCalibratedGloss-exploded-iphone.png](after/after-15-theme-ipfCalibratedGloss-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-iwfCompetition-assembled-iphone.png](after/after-15-theme-iwfCompetition-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-iwfCompetition-exploded-iphone.png](after/after-15-theme-iwfCompetition-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-iwfTraining-assembled-iphone.png](after/after-15-theme-iwfTraining-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-iwfTraining-exploded-iphone.png](after/after-15-theme-iwfTraining-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-lbBlackIron-assembled-iphone.png](after/after-15-theme-lbBlackIron-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-lbBlackIron-exploded-iphone.png](after/after-15-theme-lbBlackIron-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-lbColourBumpers-assembled-iphone.png](after/after-15-theme-lbColourBumpers-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-lbColourBumpers-exploded-iphone.png](after/after-15-theme-lbColourBumpers-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-lbGreyHammertone-assembled-iphone.png](after/after-15-theme-lbGreyHammertone-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-lbGreyHammertone-exploded-iphone.png](after/after-15-theme-lbGreyHammertone-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-lbMachinedSteel-assembled-iphone.png](after/after-15-theme-lbMachinedSteel-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-15-theme-lbMachinedSteel-exploded-iphone.png](after/after-15-theme-lbMachinedSteel-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test15PlateThemesLoadedBar()` |
| [after-19-app-theme-carbon-calculator-iphone.png](after/after-19-app-theme-carbon-calculator-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-carbon-settings-iphone.png](after/after-19-app-theme-carbon-settings-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-memento-calculator-iphone.png](after/after-19-app-theme-memento-calculator-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-memento-settings-iphone.png](after/after-19-app-theme-memento-settings-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-slate-calculator-iphone.png](after/after-19-app-theme-slate-calculator-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-slate-settings-iphone.png](after/after-19-app-theme-slate-settings-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-system-calculator-iphone.png](after/after-19-app-theme-system-calculator-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-system-settings-iphone.png](after/after-19-app-theme-system-settings-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-titanium-calculator-iphone.png](after/after-19-app-theme-titanium-calculator-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-19-app-theme-titanium-settings-iphone.png](after/after-19-app-theme-titanium-settings-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test19AppThemeCanvases()` |
| [after-calculator-kg-change-iphone.png](after/after-calculator-kg-change-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test18DP1CalculatorStates()` |
| [after-calculator-lb-exact-iphone.png](after/after-calculator-lb-exact-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test18DP1CalculatorStates()` |
| [after-calculator-mixed-iphone.png](after/after-calculator-mixed-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test18DP1CalculatorStates()` |
| [after-calculator-reverse-iphone.png](after/after-calculator-reverse-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test18DP1CalculatorStates()` |
| [after-calculator-unreachable-iphone.png](after/after-calculator-unreachable-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test18DP1CalculatorStates()` |
| [after-duration-picker-iphone.png](after/after-duration-picker-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test05SettingsAndHistory()` |
| [after-settings-audio-iphone.png](after/after-settings-audio-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test05SettingsAndHistory()` |
| [after-settings-rest-iphone.png](after/after-settings-rest-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test05SettingsAndHistory()` |
| [after-web-ad-hoc-work-1280.png](after/after-web-ad-hoc-work-1280.png) | `78405bf4` | 1280 × 800 | `ad-hoc-work` |
| [after-web-ad-hoc-work-390.png](after/after-web-ad-hoc-work-390.png) | `78405bf4` | 390 × 844 | `ad-hoc-work` |
| [after-web-app-theme-carbon-settings-1280.png](after/after-web-app-theme-carbon-settings-1280.png) | `78405bf4` | 1280 × 800 | `app-theme-carbon-settings` |
| [after-web-app-theme-carbon-settings-390.png](after/after-web-app-theme-carbon-settings-390.png) | `78405bf4` | 390 × 844 | `app-theme-carbon-settings` |
| [after-web-app-theme-memento-settings-1280.png](after/after-web-app-theme-memento-settings-1280.png) | `78405bf4` | 1280 × 800 | `app-theme-memento-settings` |
| [after-web-app-theme-memento-settings-390.png](after/after-web-app-theme-memento-settings-390.png) | `78405bf4` | 390 × 844 | `app-theme-memento-settings` |
| [after-web-app-theme-slate-settings-1280.png](after/after-web-app-theme-slate-settings-1280.png) | `78405bf4` | 1280 × 800 | `app-theme-slate-settings` |
| [after-web-app-theme-slate-settings-390.png](after/after-web-app-theme-slate-settings-390.png) | `78405bf4` | 390 × 844 | `app-theme-slate-settings` |
| [after-web-app-theme-system-settings-1280.png](after/after-web-app-theme-system-settings-1280.png) | `78405bf4` | 1280 × 800 | `app-theme-system-settings` |
| [after-web-app-theme-system-settings-390.png](after/after-web-app-theme-system-settings-390.png) | `78405bf4` | 390 × 844 | `app-theme-system-settings` |
| [after-web-app-theme-titanium-settings-1280.png](after/after-web-app-theme-titanium-settings-1280.png) | `78405bf4` | 1280 × 800 | `app-theme-titanium-settings` |
| [after-web-app-theme-titanium-settings-390.png](after/after-web-app-theme-titanium-settings-390.png) | `78405bf4` | 390 × 844 | `app-theme-titanium-settings` |
| [after-web-calculator-kg-change-1280.png](after/after-web-calculator-kg-change-1280.png) | `78405bf4` | 1280 × 800 | `calculator-kg-change` |
| [after-web-calculator-kg-change-390.png](after/after-web-calculator-kg-change-390.png) | `78405bf4` | 390 × 844 | `calculator-kg-change` |
| [after-web-calculator-lb-exact-1280.png](after/after-web-calculator-lb-exact-1280.png) | `78405bf4` | 1280 × 800 | `calculator-lb-exact` |
| [after-web-calculator-lb-exact-390.png](after/after-web-calculator-lb-exact-390.png) | `78405bf4` | 390 × 844 | `calculator-lb-exact` |
| [after-web-calculator-reverse-1280.png](after/after-web-calculator-reverse-1280.png) | `78405bf4` | 1280 × 800 | `calculator-reverse` |
| [after-web-calculator-reverse-390.png](after/after-web-calculator-reverse-390.png) | `78405bf4` | 390 × 844 | `calculator-reverse` |
| [after-web-calculator-unreachable-1280.png](after/after-web-calculator-unreachable-1280.png) | `78405bf4` | 1280 × 800 | `calculator-unreachable` |
| [after-web-calculator-unreachable-390.png](after/after-web-calculator-unreachable-390.png) | `78405bf4` | 390 × 844 | `calculator-unreachable` |
| [after-web-duration-picker-1280.png](after/after-web-duration-picker-1280.png) | `78405bf4` | 1280 × 800 | `duration-picker` |
| [after-web-duration-picker-390.png](after/after-web-duration-picker-390.png) | `78405bf4` | 390 × 844 | `duration-picker` |
| [after-web-exercise-anatomy-1280.png](after/after-web-exercise-anatomy-1280.png) | `78405bf4` | 1280 × 800 | `exercise-anatomy` |
| [after-web-exercise-anatomy-390.png](after/after-web-exercise-anatomy-390.png) | `78405bf4` | 390 × 844 | `exercise-anatomy` |
| [after-web-exercise-anatomy-selected-1280.png](after/after-web-exercise-anatomy-selected-1280.png) | `78405bf4` | 1280 × 800 | `exercise-anatomy-selected` |
| [after-web-exercise-anatomy-selected-390.png](after/after-web-exercise-anatomy-selected-390.png) | `78405bf4` | 390 × 844 | `exercise-anatomy-selected` |
| [after-web-exercise-pane-1280.png](after/after-web-exercise-pane-1280.png) | `78405bf4` | 1280 × 800 | `exercise-pane` |
| [after-web-exercise-pane-390.png](after/after-web-exercise-pane-390.png) | `78405bf4` | 390 × 844 | `exercise-pane` |
| [after-web-exercise-pane-expanded-1280.png](after/after-web-exercise-pane-expanded-1280.png) | `78405bf4` | 1280 × 800 | `exercise-pane-expanded` |
| [after-web-exercise-pane-expanded-390.png](after/after-web-exercise-pane-expanded-390.png) | `78405bf4` | 390 × 844 | `exercise-pane-expanded` |
| [after-web-favorites-320-zoom1.png](after/after-web-favorites-320-zoom1.png) | `78405bf4` | 320 × 844 | `library-favorites` |
| [after-web-favorites-320-zoom2.png](after/after-web-favorites-320-zoom2.png) | `78405bf4` | 320 × 844 | `library-favorites` |
| [after-web-favorites-430-zoom1.png](after/after-web-favorites-430-zoom1.png) | `78405bf4` | 430 × 844 | `library-favorites` |
| [after-web-favorites-430-zoom2.png](after/after-web-favorites-430-zoom2.png) | `78405bf4` | 430 × 844 | `library-favorites` |
| [after-web-history-1280.png](after/after-web-history-1280.png) | `78405bf4` | 1280 × 800 | `history` |
| [after-web-history-390.png](after/after-web-history-390.png) | `78405bf4` | 390 × 844 | `history` |
| [after-web-library-1280.png](after/after-web-library-1280.png) | `78405bf4` | 1280 × 800 | `library` |
| [after-web-library-390.png](after/after-web-library-390.png) | `78405bf4` | 390 × 844 | `library` |
| [after-web-library-category-1280.png](after/after-web-library-category-1280.png) | `78405bf4` | 1280 × 800 | `library-category` |
| [after-web-library-category-390.png](after/after-web-library-category-390.png) | `78405bf4` | 390 × 844 | `library-category` |
| [after-web-library-composed-1280.png](after/after-web-library-composed-1280.png) | `78405bf4` | 1280 × 800 | `library-composed` |
| [after-web-library-composed-390.png](after/after-web-library-composed-390.png) | `78405bf4` | 390 × 844 | `library-composed` |
| [after-web-library-favorites-1280.png](after/after-web-library-favorites-1280.png) | `78405bf4` | 1280 × 800 | `library-favorites` |
| [after-web-library-favorites-390.png](after/after-web-library-favorites-390.png) | `78405bf4` | 390 × 844 | `library-favorites` |
| [after-web-library-no-results-1280.png](after/after-web-library-no-results-1280.png) | `78405bf4` | 1280 × 800 | `library-no-results` |
| [after-web-library-no-results-390.png](after/after-web-library-no-results-390.png) | `78405bf4` | 390 × 844 | `library-no-results` |
| [after-web-library-search-1280.png](after/after-web-library-search-1280.png) | `78405bf4` | 1280 × 800 | `library-search` |
| [after-web-library-search-390.png](after/after-web-library-search-390.png) | `78405bf4` | 390 × 844 | `library-search` |
| [after-web-plate-calculator-1280.png](after/after-web-plate-calculator-1280.png) | `78405bf4` | 1280 × 800 | `plate-calculator` |
| [after-web-plate-calculator-390.png](after/after-web-plate-calculator-390.png) | `78405bf4` | 390 × 844 | `plate-calculator` |
| [after-web-plate-inspection-1280.png](after/after-web-plate-inspection-1280.png) | `78405bf4` | 1280 × 800 | `plate-inspection` |
| [after-web-plate-inspection-390.png](after/after-web-plate-inspection-390.png) | `78405bf4` | 390 × 844 | `plate-inspection` |
| [after-web-plate-inspection-exploded-1280.png](after/after-web-plate-inspection-exploded-1280.png) | `78405bf4` | 1280 × 800 | `plate-inspection-exploded` |
| [after-web-plate-inspection-exploded-390.png](after/after-web-plate-inspection-exploded-390.png) | `78405bf4` | 390 × 844 | `plate-inspection-exploded` |
| [after-web-session-1280.png](after/after-web-session-1280.png) | `78405bf4` | 1280 × 800 | `session` |
| [after-web-session-390.png](after/after-web-session-390.png) | `78405bf4` | 390 × 844 | `session` |
| [after-web-session-picker-1280.png](after/after-web-session-picker-1280.png) | `78405bf4` | 1280 × 800 | `session-picker` |
| [after-web-session-picker-390.png](after/after-web-session-picker-390.png) | `78405bf4` | 390 × 844 | `session-picker` |
| [after-web-session-plates-1280.png](after/after-web-session-plates-1280.png) | `78405bf4` | 1280 × 800 | `session-plates` |
| [after-web-session-plates-390.png](after/after-web-session-plates-390.png) | `78405bf4` | 390 × 844 | `session-plates` |
| [after-web-settings-1280.png](after/after-web-settings-1280.png) | `78405bf4` | 1280 × 800 | `settings` |
| [after-web-settings-390.png](after/after-web-settings-390.png) | `78405bf4` | 390 × 844 | `settings` |
| [after-web-settings-rest-1280.png](after/after-web-settings-rest-1280.png) | `78405bf4` | 1280 × 800 | `settings-rest` |
| [after-web-settings-rest-390.png](after/after-web-settings-rest-390.png) | `78405bf4` | 390 × 844 | `settings-rest` |
| [after-web-today-1280.png](after/after-web-today-1280.png) | `78405bf4` | 1280 × 800 | `today` |
| [after-web-today-390.png](after/after-web-today-390.png) | `78405bf4` | 390 × 844 | `today` |
| [barbell-assembled-iphone.png](after/barbell-assembled-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test04PlateCalculatorHero()` |
| [barbell-bumper-exploded-iphone.png](after/barbell-bumper-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test04PlateCalculatorHero()` |
| [barbell-exploded-iphone.png](after/barbell-exploded-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test04PlateCalculatorHero()` |
| [barbell-workout-preview-inspection-iphone.png](after/barbell-workout-preview-inspection-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test09WorkoutPreviewInspection()` |
| [barbell-workout-preview-iphone.png](after/barbell-workout-preview-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test09WorkoutPreviewInspection()` |
| [dynamic-type-advisories-current-session.txt](after/dynamic-type-advisories-current-session.txt) | `78405bf4` | audit text | `VisualProofUITests/test12AccessibilityAudit()` |
| [dynamic-type-advisories-today.txt](after/dynamic-type-advisories-today.txt) | `78405bf4` | audit text | `VisualProofUITests/test12AccessibilityAudit()` |
| [favorites-01-library-empty-iphone.png](after/favorites-01-library-empty-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test16FavoritesInLibraryAndSessionPicker()` |
| [favorites-02-library-filtered-iphone.png](after/favorites-02-library-filtered-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test16FavoritesInLibraryAndSessionPicker()` |
| [favorites-03-library-starred-iphone.png](after/favorites-03-library-starred-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test16FavoritesInLibraryAndSessionPicker()` |
| [favorites-04-session-picker-iphone.png](after/favorites-04-session-picker-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test16FavoritesInLibraryAndSessionPicker()` |
| [favorites-accessibility-iphone.png](after/favorites-accessibility-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test17FavoritesAtAccessibilityTextSize()` |
| [favorites-library-category-iphone.png](after/favorites-library-category-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test16FavoritesInLibraryAndSessionPicker()` |
| [favorites-library-composed-iphone.png](after/favorites-library-composed-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test16FavoritesInLibraryAndSessionPicker()` |
| [favorites-library-no-results-iphone.png](after/favorites-library-no-results-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test16FavoritesInLibraryAndSessionPicker()` |
| [plank-countdown-accessibility-iphone.png](after/plank-countdown-accessibility-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test11PlankTimerAtAccessibilityTextSize()` |
| [plank-target-complete-iphone.png](after/plank-target-complete-iphone.png) | `78405bf4` | 1206 × 2622 | `VisualProofUITests/test10PlankCountdownAndLog()` |
| [before-01-home-iphone.png](before/before-01-home-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test01HomeAndAdHocWork()` |
| [before-02-ad-hoc-work-iphone.png](before/before-02-ad-hoc-work-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test01HomeAndAdHocWork()` |
| [before-03-current-session-iphone.png](before/before-03-current-session-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test02SessionAndExercisePane()` |
| [before-04-exercise-anatomy-iphone.png](before/before-04-exercise-anatomy-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test02SessionAndExercisePane()` |
| [before-05-plate-calculator-iphone.png](before/before-05-plate-calculator-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test03PlateCalculator()` |
| [before-06-settings-iphone.png](before/before-06-settings-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test04SettingsAndHistory()` |
| [before-07-history-ad-hoc-iphone.png](before/before-07-history-ad-hoc-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test04SettingsAndHistory()` |
| [before-calculator-kg-change-iphone.png](before/before-calculator-kg-change-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test06DP1CalculatorStates()` |
| [before-calculator-lb-exact-iphone.png](before/before-calculator-lb-exact-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test06DP1CalculatorStates()` |
| [before-calculator-mixed-iphone.png](before/before-calculator-mixed-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test06DP1CalculatorStates()` |
| [before-calculator-reverse-iphone.png](before/before-calculator-reverse-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test06DP1CalculatorStates()` |
| [before-calculator-unreachable-iphone.png](before/before-calculator-unreachable-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test06DP1CalculatorStates()` |
| [before-library-iphone.png](before/before-library-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test05Library()` |
| [before-settings-rest-iphone.png](before/before-settings-rest-iphone.png) | `11895fb9` | 1206 × 2622 | `BaselineVisualProofUITests/test04SettingsAndHistory()` |
| [before-web-ad-hoc-work-1280.png](before/before-web-ad-hoc-work-1280.png) | `11895fb9` | 1280 × 800 | `ad-hoc-work` |
| [before-web-ad-hoc-work-390.png](before/before-web-ad-hoc-work-390.png) | `11895fb9` | 390 × 844 | `ad-hoc-work` |
| [before-web-calculator-kg-change-1280.png](before/before-web-calculator-kg-change-1280.png) | `11895fb9` | 1280 × 800 | `calculator-kg-change` |
| [before-web-calculator-kg-change-390.png](before/before-web-calculator-kg-change-390.png) | `11895fb9` | 390 × 844 | `calculator-kg-change` |
| [before-web-calculator-lb-exact-1280.png](before/before-web-calculator-lb-exact-1280.png) | `11895fb9` | 1280 × 800 | `calculator-lb-exact` |
| [before-web-calculator-lb-exact-390.png](before/before-web-calculator-lb-exact-390.png) | `11895fb9` | 390 × 844 | `calculator-lb-exact` |
| [before-web-calculator-reverse-1280.png](before/before-web-calculator-reverse-1280.png) | `11895fb9` | 1280 × 800 | `calculator-reverse` |
| [before-web-calculator-reverse-390.png](before/before-web-calculator-reverse-390.png) | `11895fb9` | 390 × 844 | `calculator-reverse` |
| [before-web-calculator-unreachable-1280.png](before/before-web-calculator-unreachable-1280.png) | `11895fb9` | 1280 × 800 | `calculator-unreachable` |
| [before-web-calculator-unreachable-390.png](before/before-web-calculator-unreachable-390.png) | `11895fb9` | 390 × 844 | `calculator-unreachable` |
| [before-web-exercise-anatomy-1280.png](before/before-web-exercise-anatomy-1280.png) | `11895fb9` | 1280 × 800 | `exercise-anatomy` |
| [before-web-exercise-anatomy-390.png](before/before-web-exercise-anatomy-390.png) | `11895fb9` | 390 × 844 | `exercise-anatomy` |
| [before-web-exercise-pane-1280.png](before/before-web-exercise-pane-1280.png) | `11895fb9` | 1280 × 800 | `exercise-pane` |
| [before-web-exercise-pane-390.png](before/before-web-exercise-pane-390.png) | `11895fb9` | 390 × 844 | `exercise-pane` |
| [before-web-history-1280.png](before/before-web-history-1280.png) | `11895fb9` | 1280 × 800 | `history` |
| [before-web-history-390.png](before/before-web-history-390.png) | `11895fb9` | 390 × 844 | `history` |
| [before-web-library-1280.png](before/before-web-library-1280.png) | `11895fb9` | 1280 × 800 | `library` |
| [before-web-library-390.png](before/before-web-library-390.png) | `11895fb9` | 390 × 844 | `library` |
| [before-web-plate-calculator-1280.png](before/before-web-plate-calculator-1280.png) | `11895fb9` | 1280 × 800 | `plate-calculator` |
| [before-web-plate-calculator-390.png](before/before-web-plate-calculator-390.png) | `11895fb9` | 390 × 844 | `plate-calculator` |
| [before-web-session-1280.png](before/before-web-session-1280.png) | `11895fb9` | 1280 × 800 | `session` |
| [before-web-session-390.png](before/before-web-session-390.png) | `11895fb9` | 390 × 844 | `session` |
| [before-web-settings-1280.png](before/before-web-settings-1280.png) | `11895fb9` | 1280 × 800 | `settings` |
| [before-web-settings-390.png](before/before-web-settings-390.png) | `11895fb9` | 390 × 844 | `settings` |
| [before-web-settings-rest-1280.png](before/before-web-settings-rest-1280.png) | `11895fb9` | 1280 × 800 | `settings-rest` |
| [before-web-settings-rest-390.png](before/before-web-settings-rest-390.png) | `11895fb9` | 390 × 844 | `settings-rest` |
| [before-web-today-1280.png](before/before-web-today-1280.png) | `11895fb9` | 1280 × 800 | `today` |
| [before-web-today-390.png](before/before-web-today-390.png) | `11895fb9` | 390 × 844 | `today` |

[Full provenance](index.json) · [SHA-256](SHA256SUMS) · [Acceptance and constraint audit](../../FINAL-VERIFICATION.md)
