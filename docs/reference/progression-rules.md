# Progression rules reference

<!-- MUST MATCH the constants in
     CadenceCore/Sources/CadenceCore/ProgramProgression.swift (tmFraction,
     incrementFraction, qualityFlagTolerance, stallLimit,
     deloadRebuildFraction, belowPlanLoad) ≡ web/js/core.js. Update this page
     when tuning them. -->

The engine is deterministic: same performance in, same decision out.
Numbers below are the shipped constants (source of truth:
`ProgramProgression.swift` and its `core.js` mirror — this page is the
owner table for docs; other pages link here rather than restating).

## The 4-week wave

| Week | Phase | What happens |
|---|---|---|
| 1 | Volume | Base weight, higher reps |
| 2 | Load | Heavier, fewer reps |
| 3 | **Peak** | Top work — **this is what gets graded** |
| 4 | Rest | Deload prescriptions; at its last day the cycle **rolls over** |

Banking the last day of a week advances the week; banking the last day
of week 4 applies all stashed grades and starts the next cycle at week 1.

## Grading a lift's peak (week 3)

| Grade | Condition |
|---|---|
| **success** | Every prescribed set hit target reps **at the prescribed weight**, nothing stopped early, no dropped load, at most **1** grindy/wobble set |
| **hold** | Reps and load were there, but **2+** sets flagged grindy/wobble |
| **fail** | Missed sets/reps, stopped early, dropped load, or worked below plan |

Notes:
- *Below plan* means fewer at-plan working sets than prescribed, with a
  tolerance of **half a rounding step** (kg-entry noise is fine; a full
  plate step down is a drop). Extra back-off sets beyond the
  prescription never hurt the grade.
- Manual weight edits and explicit autoregulation drops grade the same.
- Heavier than prescribed is always fine.

## What each grade does at rollover

- **success** → stall count resets; weight increases by the focus
  increment × headroom to the ceiling (90%/78% of est. 1RM), floored at
  plate granularity, tapering to 0 as you approach the ceiling.
- **hold / fail** → weight holds, stall count +1.
- **2 stalls** → automatic deload: base × 0.90 (rounded), stall reset,
  explanatory note in History.
- **Peak never banked** → counts as a stall (with the same deload rule).

Est. 1RM updates every graded peak: Epley (weight × (1 + reps/30)),
smoothed 70% old / 30% new.

## Accessories (every bank, not just peaks)

Double progression: all sets at the current rep target and none stopped
early → target +1 rep. At the top of the range with a load step → add
the step, reset to the range bottom. Load step 0 (bodyweight) keeps
adding reps; the range top is advisory.

## Methodology styles

Some prescription styles replace the tapered wave rules above with a
published methodology's own progression (full details in
[Training methodologies](training-methodologies.md)):

- **Per-exposure styles** (`linearFives`, the three Texas day styles) act
  like double progression's schedule: they advance their own base after
  every banked exposure that completes as prescribed, never participate
  in Peak grading, and deload after their style's own stall limit
  (3 misses → −10% novice; 2 misses → −5% Texas).
- **Cycle styles** (`fiveThreeOne`, `maxEffort`, `dynamicEffort`) still
  grade at week 3 and apply at rollover, but with fixed increments:
  +10 lb lower / +5 lb upper for 5/3/1 training maxes and made max-effort
  singles; a missed 5/3/1 minimum resets the TM three cycles back; missed
  singles and all dynamic-effort work hold. Dynamic-effort sets never
  update the e1RM estimate.

## Stale sessions

A banked session only advances the program if it was started from the
program's **current** cycle/week/day. Duplicates and leftovers still
bank into history — with a note — but can't advance the schedule or
accessories twice. Starting a day while its session is already open
resumes the open session.
