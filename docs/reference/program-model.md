# Program model reference

A **Program** owns training **Days**; each day owns individually prescribed
**Lifts** and rep-range/duration-progressed **Accessories**. Exactly one
program is active at a time; program-owned exercises are excluded from
the standalone "Next up" tracks.

## Program

| Field | Meaning |
|---|---|
| `name` | Display name |
| `focus` | `strength` / `hypertrophy` / `maintain` — see table below |
| `equipmentPolicy` | `any` preserves unrestricted legacy selection; `freeWeightsOnly` limits automatic candidates to barbell, dumbbell, kettlebell, bodyweight, and timed-hold work |
| `cycleNumber` | Which mesocycle you're on (increments after recovery) |
| `currentWeek` | Persisted compatibility name for the style-neutral rotation pointer (1…4); each lift prescription interprets the position itself |
| `nextDayIndex` | The `order` of the day the Today screen offers next — a day's order value, not its position in the array |
| `roundingLb` | Default load granularity. Dumbbells use at most 5 lb per-hand steps, and above-base wave rotations stay within one 5 lb rack jump |
| `isActive` | Drives the Today screen |

### Focus

Ceiling and increment values live in
[Progression rules](progression-rules.md#what-each-grade-does-at-rollover)
— in short: strength pushes to 90% of est. 1RM with 2.5% increments,
hypertrophy to 78% with 1.5%, maintain never increments.

## Day

A day carries an explicit `trainingIntent`: `general`, `heavy`, `volume`,
`technique`, or `explosive`. This describes the quality the authored day is
meant to express inside the evolving cycle; the cycle still owns rotation,
adaptation, recovery, and fatigue position. Intent is not inferred from the
day name or whichever lift happens to sort first. Existing programs migrate
to `general`, preserving their behavior without reinterpretation.

The deterministic coach carries both fields into its slot view. Equipment
policy filters automatic add-pattern, capacity, rotation, and promotion
candidates. Capacity growth does not add sets to `technique` or `explosive`
days; legacy `general` days retain the previous behavior. Manual edits remain
under the lifter's control.

## Lift (per day)

Day `order` values address the rotation: banking a day advances to the next
day *by order*, and banking the highest-ordered day advances rotations 1–3. The
recovery bridge instead walks its selected representative day orders. The
editors keep orders tidy at `0..n-1`, but nothing else depends on that — a
gap or a duplicate (possible in a hand-edited or older backup, since orders
are validated as unique but never as contiguous) still walks correctly.

Orders are never renumbered behind the user's back, including on import. A
day's order is the identity every banked session's `programTag.dayIndex`
refers to, so quietly renumbering days would leave those sessions unable to
resume and would misattribute their work to the wrong day in history and
coaching. `nextDayIndex` is likewise validated as *a member of* the day
orders, not as an array index.

Slot orders *within* a day are gentler: nothing banked points at them — the
slot `id` is the identity — so they only decide the sequence a day runs in.
Distinct slot orders survive import verbatim, but when every lift (or every
accessory) in an imported day carries the same order, the tie is read as "the
sequence the file was written in is the sequence the author programmed" and
array positions are stamped instead. Otherwise the tie falls to the
alphabetical display fallback and an authored hardest-first day quietly runs
in dictionary order. See
[Program files](program-file.md) for the rule's authorship.

Resident web stores get the same repair, not just imports: normalization
stamps an all-tied day at read time and the launch read persists it (older
databases get it inside the V4 upgrade rewrite). Native legacy stores keep
their documented main-first fallback instead — SwiftData's to-many
relationships are unordered, so a pre-#69 store never kept an authored
sequence to recover.

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
| `baseWeightLb` | Rotation-1 volume working weight; the wave derives the other phases |
| `deloadMultiplier` | Recovery intensity for wave-family styles, as a fraction of `baseWeightLb` (default 0.775, editable 0.50–0.90) — see [Progression rules](progression-rules.md#three-progression-rotations-and-a-recovery-bridge) |
| `estimatedMaxLb` | Smoothed Epley e1RM; seeds the ceiling, re-estimated from every banked peak |
| `stallCount` | Consecutive non-clean cycles; 2 triggers an automatic −10% deload |
| `lastIncrementLb` | What the last rollover added |
| `pending…` | Rotation-3 grade stashed until rollover |
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

## Vertical pulling is main work

Pull-ups and chin-ups are **Main**-category exercises, not accessories. That
is what makes them selectable in the progression charts, eligible for the
forward projection, and gradeable against the rotation — an accessory is
excluded from all three.

Unloaded and weighted are **separate library entries**, because they disagree
about what their number means:

| Exercise | Load basis | Earns load PR / tonnage |
|---|---|---|
| `Pull-ups`, `Chin-ups` | `bodyweight` | No — reps and scheme only ([INV-NO-LOAD-WITHOUT-RESISTANCE](invariants.md)) |
| `Weighted Pull-up`, `Weighted Chin-up` | `externalTotal` | Yes — belt weight is real resistance |

One entry could only be honest about one of them: as bodyweight it would never
credit real belt weight, and as external resistance an unweighted set would
record `0 lb` and become eligible for exactly the meaningless PR that invariant
prevents. Load basis is explicit and never inferred from the exercise name, and
each set snapshots the basis it was logged under, so old records keep their
meaning.

`Assisted Pull-up` stays an accessory. It is a regression *toward* a pull-up
and its progression runs backwards — less assistance is harder.

A main-category exercise does not have to ride the Volume/Load/Peak wave.
Bodyweight pull-ups suit `doubleProgression` — a rep window at a held load —
which is one of the styles that builds its own session shape and so carries no
phase name.

## Sessions generated from a day

Starting a program day pre-fills one session exercise per lift and
accessory, tagged with the program, cycle, week, day, role, and exact slot ID.
Main barbell lifts get a full warmup ramp; main dumbbell lifts get a short
per-hand 40/60/80% ramp. A **complementary** lift that follows other work
assumes the lifter is already warm: with the automatic warmup policy it
bridges with the last **two** ramp steps only, then goes straight to its
working sets. A complementary slot ordered first in the day still ramps
fully, and an explicit per-slot warmup policy always wins.

Roles shape the default prescription, not every program. A main lift left on
`automatic` follows the phase wave
(5×5 → 5×3 → 3×3 → deload). A complementary lift on the automatic style is
**volume work, not a second miniature of that wave**: 3×8 at 90% of its base →
3×8 at 95% → 3×6 at 100% → deload 2×8 at 75% — always 5+ reps, never above
the slot's base weight.

### What the interface may claim about a slot

The rotation counter is program-wide, but the phase **names** are a claim about
one slot's prescription, and for most styles that claim is false. Cadence
renders a Volume / Load / Peak / Recovery name only against slots whose style
comes out of the shared phase-shaped table — the wave family plus `secondary`,
`hypertrophy` and `technique`. `linearFives`, the three Texas days,
`doubleProgression`, `fiveThreeOne`, `maxEffort` and `dynamicEffort` build
their own session shapes and never carry one; the program-level indicator
reports position (`Rotation 3 of 4`) and nothing more.

Each slot instead carries a badge naming what it actually does — `Main · 5/3/1`,
`Complementary · Secondary volume`, `Main · Linear`. The badge names the
**resolved** style, so a slot left on `automatic` advertises the style the
engine will really run.

Every program slot also previews the next four exposures it will produce: the
loads, sets and reps, the ramps and "+" sets around the graded work, the base
or training max they derive from, and what the engine will do to the slot after
a clean session. The preview is generated by running the shipped engine
forward, not by a second implementation, and stores nothing. Phase-independent
styles preview numbered **exposures** rather than pretending to be four phases.

Both surfaces read the same shared-core predicates on native and web, so the
two clients cannot label the same slot differently.

Complementary/accessory barbell work snaps to a neat bar-loadable weight.
Plate math against the gym's rack is **loading guidance, not a new
prescription**: when the closest clean stack lands within the 2 lb
good-enough band of the programmed number (common when kg plates serve a lb
prescription), the session stores the neat programmed weight and the barbell
hint explains the actual plates; only a genuinely unreachable target stores
the achieved load. The program tag validates the schedule position and the
slot ID selects the progression record to advance — see
[Progression rules](progression-rules.md#stale-sessions).

Edits made in the logger belong to that session. Reps and weight propagate
independently — each has its own opt-in toggle, both off by default, so
changing one never resets the other and opening a set to add a body flag
rewrites nothing. Completed and skipped rows are never touched.

Propagating an edit changes the work you are about to do; it does **not**
move the bar the session is graded against. The prescription snapshot stays
put, so dropping the load and applying it to the remaining sets is recorded
as performed work but still grades as below plan. That is deliberate: a
target that follows the weight down would let the base weight climb on work
that was never done — see
[Progression rules](progression-rules.md#grading-a-lifts-peak-week-3) and
[How progression decides](../explanation/how-progression-decides.md).

Startup integrity repair is deliberately separate from prescription math. If
an older relationship-aliasing bug made one two-lift day an exact role-for-role
copy of another, Cadence can restore that day's role/order from its own newest
tagged completed session while leaving every slot ID and progression value
unchanged.
