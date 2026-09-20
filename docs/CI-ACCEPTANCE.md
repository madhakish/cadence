# CI acceptance evidence

A passing compiler is necessary; it does not prove that a workout is usable.
The broader requirements audit is tracked in [#254](https://github.com/madhakish/cadence/issues/254).

## Required gates

| Gate | Trigger | Evidence |
| --- | --- | --- |
| Preflight | Every CI run | Hygiene, syntax, classifier, aggregate and topology regression checks |
| Core and web | Every CI run | Full existing suites on GitHub-hosted macOS |
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

## Remaining gaps

The native integration suite covers real stores, but the full production
completion path still needs isolation from HealthKit to test it end-to-end.
Real-browser IndexedDB/service-worker/offline/update journeys, explicit
requirement-to-executed-test reporting, and durable release symbols/toolchain
metadata remain tracked in #254. The invariant registry's token scan is
traceability evidence, not proof that every cited assertion executed.

Administrative rulesets, classic branch protection, deployment restrictions,
and service-side security scanning must be verified with the required account
access. Workflow source alone cannot establish their enforcement.

Pages recovery checks the validation aggregate, not the overall CI conclusion.
A publishing failure may fail the overall run after validation succeeds; that
must remain recoverable without bypassing failed tests.
