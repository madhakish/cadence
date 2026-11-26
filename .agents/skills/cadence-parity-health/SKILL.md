---
name: cadence-parity-health
description: Review Cadence native/web domain parity and Apple Health timing, save outcomes and permission boundaries using synthetic cases and truthful current-state reporting.
---

Read `AGENTS.md`, the complete parity and privacy sections of
`docs/AGENT-GUIDE.md`, `docs/reference/parity-map.json`, and
`docs/reference/apple-health.md`. Reconcile documentation with the actual
service and call sites at the target SHA before describing shipped behavior.
Check current issues/PRs so pending documentation or feature work stays separate.

## Shared behavior versus platform edges

`CadenceCore` and `web/app/js/core.js` mirror domain rules; HealthKit is an iOS
edge, not a missing web feature. Use the parity map to find twins and reasoned
one-sided entries. `node .github/scripts/check-parity.mjs` checks names, not
outcomes. Run equivalent synthetic boundary fixtures on both implementations
for changed shared behavior; do not regenerate expected fixtures just to pass.
Preserve canonical pounds, stable IDs, logged/performed values and backup
compatibility. Read the full migration protocol before changing persisted data.

## Health outcome review

Trace the bank/save call through `Cadence/Services/HealthKitService.swift` and
the summary UI. Keep local Cadence save success separate from Health export:
not requested, saving, success, missing permission, unreliable timing and
unconfirmed/error outcomes must not collapse into one success banner.
The documented current flow is one-shot, with no durable retry queue,
historical sync or correction reconciliation. Verify that remains true at the
reviewed head; propose additions separately rather than documenting a promise.

Use `HealthWorkoutTimingTests`, `HealthComparisonTests` and
`HealthRuckStepsTests` under `CadenceCore/Tests/CadenceCoreTests` as entry points.
Cover pause/resume, banking while paused, relaunch, display reset, missing/legacy
start, backdating, delayed save, permission denial and unavailable reads with
synthetic records. Native service/UI and real-device permission behavior require
separate evidence; pure tests alone do not establish them.

Check write, comparison-read and measured-ruck-step-read opt-ins independently.
Read authorization completion does not prove access. Missing/zero/denied steps
are not measured zero; cumulative Health statistics avoid raw multi-source
summing. The captured ruck window includes interior pauses and is not an
active-only count. No guessed distance-to-steps conversion, Health readings in
backups, automatic overwrite of logs or real health data in fixtures/artifacts.

Report a compact matrix: behavior, native outcome, web twin or justified N/A,
source SHA, actual evidence and remaining device checks. Distinguish Cadence's
local handling from Apple-controlled Health sync; preserve pending wording
fixes rather than duplicating their diff.
