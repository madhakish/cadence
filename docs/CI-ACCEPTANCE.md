# CI acceptance evidence

A passing compiler is necessary; it does not prove that a workout is usable.
The broader requirements audit is tracked in [#254](https://github.com/madhakish/cadence/issues/254).

## Required gates

| Gate | Trigger | Evidence |
| --- | --- | --- |
| Preflight | Every CI run | Hygiene, syntax, classifier, aggregate and topology regression checks |
| Core and web | Every CI run | Full existing suites on GitHub-hosted macOS |
| Browser feature acceptance | Every CI run and manual Pages recovery, inside the web gate | Five named journeys on Chromium and WebKit; all ten executions must pass without skips or retries |
| Production device compile | Native-affecting PR | Release build of the iOS device target |
| iPhone interactions | Native-affecting CI run | Four XCTest interactions; xcresult summary must show exactly four passed and zero failed/skipped |
| Native integration/migrations | Persistence-bearing production sources and shared CadenceCore | Hostless SwiftData suite, with required actual shipped-store fixtures |
| Release promotion | Successful full aggregate | Verified signed IPA, no rebuild during promotion |
| Normal Pages | Successful full aggregate | Same commit as tested; stamped Pages artifact |
| Manual Pages recovery | Main only; exact commit has successful validation | Full web regression suite before deployment |

The core check retains its old Linux display name for branch-protection
compatibility. Its actual runner is GitHub-hosted macOS.

## Mandatory iPhone interactions

These existing tests run without a visual-proof label:

- `test07FinalSetAdvancesToNextAuthoredExercise`
- `test10PlankCountdownAndLog`
- `test13SetCompletionKeepsDominantBlockStill`
- `test14CalculatorTargetAtAccessibilityTextSize`

They exercise the app through XCUIAutomation using synthetic, in-memory
fixtures. This is not proof of process-restart persistence or every product
requirement. The separate optional visual workflow provides broader captures
for human design review. A screenshot's existence is not approval of its design.

The interaction job retains its xcresult bundle and summary for 14 days,
including failed runs. An empty/partial/unknown result, a skipped interaction,
or a failed interaction fails the gate. If the required test set changes,
update its selection, expected count, and result-verifier regression tests.

## Required browser journeys

The real Pages tree is served under `/cadence/app/` on an isolated local origin.
Tests use the actual browser IndexedDB, Cache Storage and service worker. Only
the deployment build token is stamped; no worker or persistence mocks replace
production code. The offline journey cuts the actual origin connection and
asserts a direct request fails before reloading; it does not depend on WebKit
offline emulation or merely read a page that was already loaded. Workouts are synthetic and created/edited through visible UI
controls. Repository reads assert saved state in addition to rendered output.
Restore comparisons ignore only the export timestamp and explicitly expect
the documented backfill of missing legacy exercise IDs, checked against the
synthetic catalog. Identity and performed values stay in the comparison.

| Requirement ID | Behavioral assertion |
| --- | --- |
| WEB-WORKOUT-REOPEN | Edit reps, complete/undo/re-complete, retain planned work; reload and reopen in a new tab with identical session data |
| WEB-OFFLINE-RESUME | Disconnect the test origin at the TCP transport; reload from the worker, resume and bank work, inspect History, export it offline |
| WEB-UPDATE-RESUME | Install a second worker build, accept the production Refresh prompt; preserve active work and another project's cache while retiring the old app cache |
| WEB-BACKUP-ROUNDTRIP | Download JSON, import into a fresh browser context, reload and re-export all portable content with explicit legacy-ID repair assertions; an identical re-export reports no change |
| WEB-RESTORE-CONTENT | Same IDs/counts with changed reps require confirmation; Cancel preserves the original, Restore persists the changed value |

The committed `web/tests/browser/requirements.json` lists required IDs and
browser projects. `verify-feature-coverage.mjs` checks the **executed Playwright
JSON results**, including each ID/project pair, expected status, actual result,
uniqueness, and exactly one attempt. Missing/duplicate/unknown cases, skips,
expected failures, retries and interrupted runs fail. Runner exit status is
also mandatory. Never lower this gate or quarantine a critical journey to get
a release green; fix the behavior or explicitly review a changed requirement.

`web/test-results/` is retained for 14 days: machine-readable results plus
traces, DOM snapshots and screenshots on failure. This suite contains synthetic
data only. Playwright and its browser revisions are locked by `package-lock.json`.
WebKit exercises browser-engine compatibility; it does not certify iOS Safari's
OS suspension, eviction behavior, native HealthKit or Lock Screen controls.

Run locally from `web/`:

```sh
npm ci
npx --no-install playwright install chromium webkit
npm run test:browser
```

For focused diagnosis, `npx playwright test --project=chromium --grep WEB-OFFLINE`
runs a subset; it is not complete acceptance evidence. Full coverage verification
deliberately rejects a partial report. The test server is per-test so deployments
and caches cannot leak between concurrent browser projects.

## Feature coverage expansion

This is the first acceptance slice, not a claim of comprehensive coverage.
Keep a feature's deterministic rules in core tests, persistence contracts in
real-store tests, and a small set of complete user journeys in browser/XCTest.
Each new critical journey needs an explicit requirement, synthetic setup,
observable expected outcome, and required executed-result evidence.

| Feature area | Existing evidence | Next acceptance gap tracked in #254 |
| --- | --- | --- |
| Workout logging and timing | Core/web runtime tests; four required iPhone interactions; browser reopen/offline journeys | Multi-exercise skip/undo flow, rest/hold interruption, process relaunch and stale Lock Screen actions |
| Physical loading | Core parity/plate tests, native calculator accessibility interaction | Mixed-unit displayed stack → performed load → saved history/backup; warmup loading transitions |
| Scheduling | TFH integration and scheduler/core tests | Full Upper/Lower A/B rotation sequence through recovery and next cycle on both UIs |
| Progression/coaching | TFH/core/web tests | Two-cycle evidence, AMRAP, fixed DB increments and bodyweight modality through complete user flows |
| Persistence/backup | Shipped SwiftData migrations and web migration/restore suites; browser update/export/import | Native process restart, cross-client round trips, correction replay, program switching and rejected writes |
| Accessibility/visuals | jsdom axe, native large-text interaction, opt-in visual captures | Real contrast/layout, keyboard/VoiceOver, focus, narrow widths and theme review |

## Remaining gaps

The native integration suite covers real stores, but the full production
completion path still needs isolation from HealthKit to test it end-to-end.
The browser journeys above establish executed evidence for five requirements;
the other feature areas and durable release symbols/toolchain metadata remain
tracked in #254. The invariant registry's token scan is
traceability evidence, not proof that every cited assertion executed.

Administrative rulesets, classic branch protection, deployment restrictions,
and service-side security scanning must be verified with the required account
access. Workflow source alone cannot establish their enforcement.

Pages recovery checks the validation aggregate, not the overall CI conclusion.
A publishing failure may fail the overall run after validation succeeds; that
must remain recoverable without bypassing failed tests.
