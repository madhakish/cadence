# Progression rules reference

The engine is deterministic: same performance in, same decision out.
Numbers below are the shipped constants.

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

## Stale sessions

A banked session only advances the program if it was started from the
program's **current** cycle/week/day. Duplicates and leftovers still
bank into history — with a note — but can't advance the schedule or
accessories twice. Starting a day while its session is already open
resumes the open session.
