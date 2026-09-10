# TFH method: useful capability with room to use it

**Status: opt-in native and web program method.** Open the existing program's
editor and choose **Set up TFH method**. Review the starting load, bounded rep
range, set count, smallest equipment step, and purpose of each slot. Saving
starts a new evidence cohort without rewriting existing history.

## Objective

TFH develops useful strength, explosive power, endurance, body control, and
sport skill while preserving time and energy to use those capabilities. A
single lift, race time, tonnage total, or combined score cannot represent that
objective. Maintaining one ability while another develops is a successful
outcome when that is the selected intent.

Each capability has an explicit development, maintenance, or practice intent.
Choose a primary development emphasis and, when recoverable, a secondary
emphasis for a cycle. That allocation is a proposed TFH policy, not a proven
optimal number. Reallocate optional work before adding more total work. Hard
sport sessions belong in the workload context; skill practice needs its own
execution evidence. A strength PR cannot establish better sport skill.

## Evidence and limits

- Concurrent strength and endurance training can improve both, while rapid
  force production may respond differently. Track power separately:
  [Hakkinen et al., 2003](https://link.springer.com/article/10.1007/s00421-002-0751-9).
- A small cyclist trial retained acquired strength with a reduced maintenance
  frequency. Maintenance is a valid purpose; the trial does not establish a
  universal dose:
  [Ronnestad et al., 2010](https://link.springer.com/article/10.1007/s00421-010-1622-4).
- Repetition and load progression both produced useful adaptations in a short
  comparison. It does not validate TFH's exact increment algorithm:
  [Plotkin et al., 2022](https://pubmed.ncbi.nlm.nih.gov/36199287/).
- Repetition tests contain measurement error. One extra clean rep is positive
  evidence, not a universal threshold for a physiological change:
  [Mitter et al., 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9070879/).
- Competition archives describe diminishing cohort gains; they do not supply
  an individual's lifetime ceiling or training prescription:
  [Latella et al., 2024](https://pubmed.ncbi.nlm.nih.gov/38060089/).

No fitted growth curve, age-based strength ceiling, universal recovery score,
or validated claim of optimality is implemented. Age, body size, training
history, and recovery can inform expectations. Observed performance must earn
the next prescription.

## Cycle contract

Retain the ordered Upper A / Lower A / Upper B / Lower B composition. A
rotation is one completed pass; a cycle contains three build rotations followed
by shared recovery. Compare R1 with earlier R1, R2 with R2, and R3 with R3.
The first cycle can use its preceding build exposure while those references
are being established. A phase is not a calendar week.

Recovery is two or three light sessions, normally one to three days apart.
That is the authored TFH structure, not an experimentally established optimum.
Sport workload also matters during recovery. Time alone cannot complete it.
`TFHSchedule` / `tfhPosition` advances through the actual completed session
tags. Deleting a counted session exposes the missing position again. Duplicate
positions require review. An empty bank or off-program recovery interval does
not satisfy a training day.

## Current strength-endurance policy

`TFHProgression.project` and `tfhProject` consume an immutable slot/cohort
anchor and canonical completed exposures. They return a candidate and evidence
IDs without changing stored progression state.

- Starting targets preserve authored load, set count, and individual rep
  targets. Successful work can earn one additional **total** rep inside the
  authored range. Set count does not grow automatically.
- A load candidate requires the latest two matching phases in consecutive
  cycles to complete the top of the range. It takes one authored equipment
  step and restarts at the minimum reps, preserving the set count.
- A candidate step greater than 10% of the entered load is withheld for
  review. This is a conservative policy guard, not a measured capacity
  threshold; being below it does not prove a jump is appropriate.
- Per-implement, total external, bodyweight, and assisted load retain distinct
  semantics. Bodyweight has zero added load; decreasing assistance is harder.
  Changing variation, intent, or load convention requires a new cohort.
- Recent difficult or incomplete work prevents an older successful phase from
  earning an increase or a benchmark. Missing explicit quality does not count
  as clean evidence. Current comparable planned targets remain available to
  repeat after a difficult exposure.
- Maintenance and practice do not receive automatic workload increases.
  `notAssessing` means no plateau verdict, not proof that maintenance is
  succeeding. Deteriorating maintenance still needs separate monitoring.
- Technical benchmarks require explicit selection and only occur in R3 for
  development intent. The logger marks the final work set, records optional
  stop reason and actual rest, and permits opting out. This
  controller must not prescribe AMRAPs for explosive or technical practice.
- The R4 candidate halves the set count, rounding up, and uses the minimum
  reps. External load is reduced to 80% and rounded down to the authored step;
  bodyweight and assisted work reduce volume only. The minimum available load
  is retained when rounding would create zero. These are provisional dose
  policies. Barbell plans use the selected gym's plate solver. Timed practice
  uses one half-duration set in recovery, without treating it as lifting volume.
- Duplicate phase records, missing target data, mixed prescribed loads, or
  targets outside the anchor's range cause abstention (`nil` / `null`). The
  adapter must surface the need for review and preserve the current program;
  it must never interpret abstention as permission to reset to starting
  weights or complete recovery automatically.

The plateau function needs the latest complete baseline and two subsequent
complete comparable cycles. Improved performed work interrupts a flat
sequence; a subsequent comparable decline takes priority over earlier gains.
Changed context, capped tests, missing benchmark evidence, stale cycles, or
ambiguous history cannot establish a plateau. A possible plateau prompts a
review; it cannot automatically swap an exercise or cut weight.

## Integration and data compatibility

The program keeps a typed `TFHProgramPolicy`, including stable slot anchors and
the authored day/role/order layout. Sessions carry the cohort ID, immutable
anchor and planned sets, and optional benchmark/context facts. Changing the
composition or load convention requires reviewing setup and starting a new
cohort. Names remain presentation metadata. Clones receive new cohort, slot,
and anchor identities.

TFH bypasses the legacy percentage-wave, pending-load, stall-counter, and
calendar-expiry paths. Completion commits the session and next position in the
existing transaction. Future plans and coaching read canonical corrected sets,
so they do not need to replay legacy mutable grades. A deliberate uniform load
adjustment holds that performed load for the following prescription, even when
later sets are skipped. Only completed sets establish that adjustment; mixed
performed loads require review.

Barbell and dumbbell lifts retain the existing warmup ramps and each slot's
automatic, full, short, or no-warmup policy. Current-set guidance begins with
the first unfinished warmup.

SwiftData V13 follows a frozen V12 schema through every supported migration
path. IndexedDB V9 adds opt-in metadata to existing V8 records. Neither upgrade
invents TFH evidence for old sessions. Backup version 14 carries the typed
policy and evidence on both clients; all supported older backups still import.
Malformed TFH data rejects the restore before committing any changes. Restore
previews include policy and benchmark changes. Use a full backup to move TFH
between devices: the separate shared-program file format remains version 2 and
explicitly refuses to export TFH as an ordinary legacy program.

The logger's clean-work action is an explicit athlete report, not a default
derived from checking a set complete. Missing quality, rest, or comparison
conditions stays unknown. Coaching describes capacity evidence without
claiming that it establishes today's readiness, and never applies a plateau
cut or exercise rotation automatically.

This controller governs strength-endurance slots. Timed work and conditioning
retain authored practice targets and their own measurements in accessory slots.
Move duration-based exercises out of lift slots and set their duration before
enabling TFH; setup rejects unsupported lift slots without changing the program.
It does not infer
sport skill, optimize all sports, or automate total workload allocation.

## Verification

Run the existing `swift test` in `CadenceCore` and `npm test` in `web`.
`TFHProgressionTests.swift` and `tfh.test.mjs` include matching regressions for
bounded reps, real load steps, recent difficult work, maintenance, practice,
selected benchmarks, incomplete and duplicate history, changed conditions,
later declines, and bodyweight semantics. Native validation also requires the
repository's exact-commit Darwin tests and unsigned device build.

`TFHIntegrationTests` exercises the production native builder and TFH completion
boundary, correction, recovery, backup restore, and an on-disk V12 migration.
`tfh-integration.test.mjs` drives the web builder and full completion transaction,
correction, recovery, previews, and portable round trips. `db-v9-migration.test.mjs`
starts with an actual V8 IndexedDB database and verifies manual work survives.
