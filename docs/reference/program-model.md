# Program model reference

A **Program** owns training **Days**; each day owns **Lifts**
(wave-progressed) and **Accessories** (rep-range-progressed). Exactly one
program is active at a time; program-owned exercises are excluded from
the standalone "Next up" tracks.

## Program

| Field | Meaning |
|---|---|
| `name` | Display name |
| `focus` | `strength` / `hypertrophy` / `maintain` — see table below |
| `cycleNumber` | Which 4-week cycle you're on (increments at rollover) |
| `currentWeek` | 1 volume · 2 load · 3 peak · 4 rest (deload) |
| `nextDayIndex` | The `order` of the day the Today screen offers next — a day's order value, not its position in the array |
| `roundingLb` | Default load granularity. Dumbbells use at most 5 lb per-hand steps, and above-base wave rotations stay within one 5 lb rack jump |
| `isActive` | Drives the Today screen |

### Focus

Ceiling and increment values live in
[Progression rules](progression-rules.md#what-each-grade-does-at-rollover)
— in short: strength pushes to 90% of est. 1RM with 2.5% increments,
hypertrophy to 78% with 1.5%, maintain never increments.

## Lift (per day)

Day `order` values address the rotation: banking a day advances to the next
day *by order*, and banking the highest-ordered day advances the week. The
editors keep orders tidy at `0..n-1`, but nothing else depends on that — a
gap or a duplicate (possible in a hand-edited or older backup, since orders
are validated as unique but never as contiguous) still walks correctly.

Orders are never renumbered behind the user's back, including on import. A
day's order is the identity every banked session's `programTag.dayIndex`
refers to, so quietly renumbering days would leave those sessions unable to
resume and would misattribute their work to the wrong day in history and
coaching. `nextDayIndex` is likewise validated as *a member of* the day
orders, not as an array index.

The ordered day matrix is the prescription source of truth. For example,
`Lower A: Back Squat/main + Deadlift/complementary` and
`Lower B: Deadlift/main + Back Squat/complementary` are four independent
slots even though the exercise names repeat. Preview and session creation read
the selected day's slots directly; they do not scan recent same-name sets to
reconstruct the program.

| Field | Meaning |
|---|---|
| `id` | Stable slot identity; completion uses this rather than exercise name/order |
| `role` | `main` (one per day, anchors it, rests longest) or `complementary` |
| `baseWeightLb` | Rotation-1 (volume week) working weight; the wave derives the other weeks |
| `estimatedMaxLb` | Smoothed Epley e1RM; seeds the ceiling, re-estimated from every banked peak |
| `stallCount` | Consecutive non-clean cycles; 2 triggers an automatic −10% deload |
| `lastIncrementLb` | What the last rollover added |
| `pending…` | Week-3 grade stashed until rollover |
| `revertToExerciseName` | Set by a cycle-scoped swap; the slot reverts to this name at rollover |

## Accessory (per day)

| Field | Meaning |
|---|---|
| `id` | Stable slot identity; completion uses this rather than exercise name/order |
| `sets` | Working sets |
| `minReps` / `maxReps` | The rep range to earn |
| `currentReps` | Today's target reps |
| `weightLb` | Current load |
| `incrementLb` | Load added when the range is earned; **0 = bodyweight** (climbs reps indefinitely, `maxReps` advisory) |
| `revertToExerciseName` | As for lifts |

## Sessions generated from a day

Starting a program day pre-fills one session exercise per lift and
accessory, tagged with the program, cycle, week, day, role, and exact slot ID.
Main barbell lifts get a full warmup ramp; main dumbbell lifts get a short
per-hand 40/60/80% ramp. A **complementary** lift that follows other work
assumes the lifter is already warm: with the automatic warmup policy it
bridges with the last **two** ramp steps only, then goes straight to its
working sets. A complementary slot ordered first in the day still ramps
fully, and an explicit per-slot warmup policy always wins.

Roles also shape the prescription itself. A main lift follows the phase wave
(5×5 → 5×3 → 3×3 → deload). A complementary lift on the automatic style is
**volume work, not a second miniature of that wave**: 3×8 at 90% of its base →
3×8 at 95% → 3×6 at 100% → deload 2×8 at 75% — always 5+ reps, never above
the slot's base weight.

Complementary/accessory barbell work snaps to a neat bar-loadable weight.
Plate math against the gym's rack is **loading guidance, not a new
prescription**: when the closest clean stack lands within the 2 lb
good-enough band of the programmed number (common when kg plates serve a lb
prescription), the session stores the neat programmed weight and the barbell
hint explains the actual plates; only a genuinely unreachable target stores
the achieved load. The program tag validates the schedule position and the
slot ID selects the progression record to advance — see
[Progression rules](progression-rules.md#stale-sessions).

Edits made in the logger belong to that session. Applying a weight/reps change
to the remaining planned sets also updates the session prescription, while
completed and skipped rows remain untouched. Completion therefore compares
performed work with the accepted, adjusted target rather than the originally
generated number.

Startup integrity repair is deliberately separate from prescription math. If
an older relationship-aliasing bug made one two-lift day an exact role-for-role
copy of another, Cadence can restore that day's role/order from its own newest
tagged completed session while leaving every slot ID and progression value
unchanged.
