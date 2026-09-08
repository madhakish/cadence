# TFH method: useful capability with room to use it

**Status: research and pure policy prototype.** The native and web domain
functions are implemented and tested. Program activation, session planning,
logging, coaching, recovery scheduling, and persistence integration are still
required. This document does not describe an enabled app feature.

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
The pure prescription function returns a light-work candidate for R4; it does
not implement the session-count or scheduling rule.

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
  review. This is a conservative prototype guard, not a measured capacity
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
  development intent. The eventual logger must replace the final work set,
  record its stop reason and actual conditions, and permit opting out. This
  controller must not prescribe AMRAPs for explosive or technical practice.
- The R4 candidate halves the set count, rounding up, and uses the minimum
  reps. External load is reduced to 80% and rounded down to the authored step;
  bodyweight and assisted work reduce volume only. These are provisional dose
  policies. Equipment availability and a suitable light movement still need
  the program adapter's review.
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

## Integration required before activation

1. Add explicit TFH program selection, per-slot intent, immutable anchor and
   cohort identity, and reviewable initial targets. Preserve stable program,
   slot, exercise, and session identities and manual settings.
2. Snapshot the selected policy and actual benchmark context in sessions.
   Planned work and performed work remain separate. Historical sessions
   without context cannot become retrospective capacity tests.
3. Freeze the shipped SwiftData schema before adding model fields. Add the
   new schema, every production migration path, real on-disk migration tests,
   IndexedDB upgrade, and compatible portable-backup changes together.
4. Wire the same pure function into both clients' previews, session builders,
   completion, recovery, and coaching. TFH must bypass legacy percentage-wave
   and mutable stall-counter decisions. Corrections and restores must produce
   the same result from canonical history.
5. Account for other activities with their own duration, distance, rounds,
   effort, and conditions. Do not convert them into invented lifting sets or
   use tonnage to stand in for power, skill, or recovery.
6. Verify activation, manual changes, recovery completion, corrections,
   export/restore, and native/web parity before enabling the feature. Existing
   authored methods must retain their behavior.

The prototype deliberately represents only strength-endurance candidates. It
does not optimize all sports or control the overall workload allocation yet.

## Verification

Run the existing `swift test` in `CadenceCore` and `npm test` in `web`.
`TFHProgressionTests.swift` and `tfh.test.mjs` include matching regressions for
bounded reps, real load steps, recent difficult work, maintenance, practice,
selected benchmarks, incomplete and duplicate history, changed conditions,
later declines, and bodyweight semantics. Native validation also requires the
repository's exact-commit Darwin tests and unsigned device build.
