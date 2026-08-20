# Progression rules reference

<!-- MUST MATCH the constants in
     CadenceCore/Sources/CadenceCore/ProgramProgression.swift (tmFraction,
     incrementFraction, qualityFlagTolerance, stallLimit,
     deloadRebuildFraction, recoverySessionLimit, recoveryWindow,
     belowPlanLoad, rebuildHeadroomBand, fineHeadroomBand,
     standingBestDays) ≡ web/app/js/core.js. tmFraction now
     seeds peak singles and places a new program's base; it no longer caps the
     increment. Update this page
     when tuning them. -->

The engine is deterministic: same performance in, same decision out.
Numbers below are the shipped constants (source of truth:
`ProgramProgression.swift` and its `core.js` mirror — this page is the
owner table for docs; other pages link here rather than restating).

## Three progression rotations and a recovery bridge

The Strength — Upper/Lower wave is a **cycle-based program**. It advances by
completed passes through the authored days, not by elapsed calendar weeks:

- Rotation 1 — **Volume:** base weight, higher reps.
- Rotation 2 — **Load:** heavier, fewer reps.
- Rotation 3 — **Peak:** top work; this is what gets graded.
- Phase 4 — **Recovery:** at most one representative lower and one
  representative upper exposure, then rollover.

Week-bound programs are valid too; this recovery-bridge change neither defines
nor alters their calendar behavior. Timing basis belongs to the program. It is
not inferred from a lift's prescription style or template name. The persisted
field `currentWeek` predates that terminology and remains a compatibility wire
name. In this cycle-based wave, its value is a phase/rotation index.

The recovery prescription for a wave-family main lift is 2×3 at the slot's
own **deload multiplier** — default 77.5% of the rotation-1 base, adjustable
from 50% to 90% per slot in the program editor. The editor shows the stepper
only where the resolved style honours it (the wave and offset-wave families);
a complementary lift on the automatic style uses 1×5 at its fixed 75%.
Every accessory is reduced to one easy set. A lifter who wants a heavier
recovery exposure — say 85% — can raise intensity without adding volume.

For an upper/lower program, the bridge selects the first authored squat/hinge
main day and the first authored press/pull main day. It uses movement metadata,
never strings such as "Upper A" or "Lower B". If the program is Olympic,
full-body, conditioning-only, damaged, or otherwise ambiguous, Cadence keeps
the complete authored pass rather than guessing which work to remove.

Banking the highest-ordered day of rotations 1–3 advances the rotation.
Recovery closes when its selected exposures are banked, when as many recovery
sessions as the bridge is long have been banked, or when seven elapsed days
have passed since the last completed hard phase. The session cap covers an old or
manually positioned pointer that prescribed non-selected A/B days; it is the
bridge's own length with a floor of two, so a program keeping its complete
authored pass is never truncated by the guard. The elapsed value is only a
stale-bridge expiry guard: it does not group training into weeks, count
calendar weeks, or advance Volume/Load/Peak without completed cycles. It
measures from the final Peak completion. A reduced exposure does not restart
the clock and stretch a seven-day bridge into thirteen days. If an early-recovery
decision skipped Peak, the last completed hard rotation is the anchor instead.
Reconciliation never runs while a **session is open**, because advancing the program beneath a
workout in progress would make banking it fail its stale-tag check. Closing Recovery applies all stashed grades and starts
the next mesocycle at rotation 1, day 1. Rotation 3 or recovery is the only
phase the wave can be in when a cycle ends,
with one exception: after two consecutive red rotations the program cuts the
cycle short and jumps to recovery from rotation 1 or 2 (see
`docs/reference/coaching-rules.md`). Every cycle-graded slot is handed an
explicit **hold** as it jumps, so a peak that never ran is never mistaken for a
peak that was missed. The schedule steps between days by `order` value, not by position
in the list, so a program whose orders are not a contiguous `0..n-1` — a
gap or a duplicate from an older backup — still reaches every day. The
next prescription is always `nextDayIndex` → that exact day's stable
slots → the current phase formula. Main, complementary, and unprogrammed extra
work are separate records; recent same-name history never substitutes for a
program slot.

## The estimated max

`estimatedMaxLb` is a smoothed Epley estimate, and it updates on **every**
progression rotation, not only the graded one:

- On rotation 3 the peak is a test, so the grade moves the estimate in either
  direction.
- On rotations 1 and 2 the prescription is deliberately submaximal, so a light
  set is not evidence the max fell — it is evidence the program asked for less.
  Those rotations can therefore only **raise** the estimate, and only when the
  performed work beats it.
- Recovery is intentionally observation-free: it never raises or lowers e1RM.

The set that supplies the sample is the best Epley among the performed working
sets, not the heaviest one, and sets past ten reps are excluded from that
ranking because the formula drifts high there. So a set taken past its
prescription — the last set of the load rotation carried to 6 instead of 3 —
is what feeds the estimate, while a long back-off set cannot masquerade as a
max.

A load-rotation sample is also the only honest estimate of the two. An
estimate taken from the peak set alone is a fixed multiple of the base — the
peak *is* 1.175 × base — so it tells you what the program prescribed rather
than what you are capable of. Earned reps at a weight the peak did not set do
not have that problem.

The estimate no longer caps the increment. It used to: the increment scaled by
headroom to a training-max ceiling of 90%/78% of the estimate. Measured across
10,560 realistic base/estimate pairs, that produced exactly two outcomes — one
plate step or nothing — and the "nothing" was unreachable after a clean peak,
because a peak at 1.175 × base outruns a 0.90 × estimate ceiling by
construction. A ceiling derived from the base cannot bound the base. Drift is
bounded by performance instead: two stalls rebuild at 90%.

## Grading a lift's peak (rotation 3)

| Grade | Condition |
|---|---|
| **success** | Every prescribed set hit target reps **at the prescribed weight**, nothing stopped early, no dropped load, at most **1** grindy/wobble set |
| **hold** | Reps and load were there, but **2+** sets flagged grindy/wobble |
| **fail** | Missed sets/reps, stopped early, dropped load, or worked below plan |

Notes:
- *Below plan* means fewer at-plan working sets than prescribed, with a
  tolerance of **half a rounding step** (kg-entry noise is fine; a full
  plate step down is a drop) — and a load that is the plate-for-plate
  **kg denomination twin** of the plan counts as at plan regardless of the
  drift ([INV-PLATES-ARE-THE-CURRENCY](invariants.md)): 2×20 kg a side on a
  45 bar is the 225 plan, even seven pounds adrift at four pairs. Twin
  forgiveness applies to **total-bar work only** — machines and dumbbells
  have no bar to read, so they grade on the numbers alone. Extra
  back-off sets beyond the prescription never hurt the grade.
- Manual weight edits and explicit autoregulation drops grade the same.
- Heavier than prescribed is always fine.

## What each grade does at rollover

- **success** → stall count resets; weight increases by the focus
  increment (2.5% strength / 1.5% hypertrophy of the current base),
  floored at plate granularity so a clean cycle always earns at least one
  loadable step. If the peak's top set was performed **above** its own plan
  by at least the half-step tolerance, the base first rides that overshoot
  as a ratio — a lifter whose rack lands them a stack over every lb
  prescription (kg plates) trains ahead of the programmed number, and the
  increment lands on what the bar actually carried
  ([INV-PROGRESSION-RIDES-PERFORMED](invariants.md)). Below plan already
  fails the grade, so the ratio can never move the base down, and a
  performance with no recorded plan advances exactly as before. The advance
  also rides the graded cycle's own **performed volume exposure** — on every
  grade, not only success: the week-1 working weight, read from the log as
  its canonical grid label under the bar that session actually used, becomes
  the floor the base lands on. A hold or fail zeroes the earned-increment
  flag, so without this resync the stale label would strand and the same
  plates would be prescribed yet again. Total-bar work only, never downward
  ([INV-ADVANCE-BUYS-PLATES](invariants.md)).

### An earned advance must buy plates

An advance computed in label space can prescribe the very plates the lifter
already lifted: in a kg rack, 215 and 225 both solve to the identical
2×20 kg stack. Every planning surface (the Today card, the workout preview,
the program overview, the session builder, and the resume comparison)
therefore plans from the **honest base**: when the lift's last advance
earned weight (`lastIncrementLb > 0`) and the raw performed volume weight
from **before the cycle being planned** cleared the pre-advance base past
the half-step tolerance — but sits no more than one increment above the
stored base — the plan is the performed stack's canonical label plus that
earned increment, capped one increment above the stored base, floored at
the stored base, and applied to total-bar lifts only. The cycle scoping is
what keeps a clean lifter clean: their own banked week-1, performed exactly
at the honestly advanced base, is not evidence the advance was stale.
Labels are computed constructively from the plates (`performedLabel`
decomposes the side into kg denominations and reads the lb twins back), and
the evidence is matched to the slot **and** the movement, windowed to the
prescribed sets, and labeled under its own session's bar. A heavier working
set the lifter **added past the prescription** is separate evidence: it
never touches grading, but it arms one staged increment of catch-up above
the stored base (the step the lift's regime currently earns — a rebuild
lift catches up in 10 lb classes), clamped per cycle so the base chases
demonstrated capability without teleporting to one good day. Editing a base by
hand — or rotating the slot to a new variation — clears the earned
increment, so a hand-set number or a fresh movement is never "repaired"
(bases hand-set before this behavior shipped are protected by the
one-increment window) ([INV-ADVANCE-BUYS-PLATES](invariants.md)). The
motivating log: a deadlift stuck prescribing 2×20 kg for a third cycle at
"225" now plans 235 — the 232.4 kg twin stack, a genuinely heavier bar.
- **hold / fail** → weight holds, stall count +1 — and the needle still
  moves: the next **volume** rotation carries **one added set** at the held
  load, derived from the persisted stall so the Home card and the created
  session agree by construction
  ([INV-NEEDLE-ALWAYS-MOVES](invariants.md)). Load and peak keep their
  shapes; a later clean grade resets the stall and the volume returns with
  the weight jump. `maximumAddedSetsPerRotation` is the rotation-wide
  budget: stalled slots rank in stable program order (day order, then slot
  order) and receive one set each until it is spent; zero turns the
  fallback off entirely.
- **2 stalls** → automatic deload: base × 0.90 (rounded), stall reset,
  explanatory note in History.
- **Peak never banked** → counts as a stall (with the same deload rule).

### Staged increments (headroom to the logged prior best)

The focus increment is **staged** by where the lifter stands against their
own log, graded at the peak from the best e1RM recorded before the session
being banked:

- **Rebuild** (current estimate below 90% of the logged prior best, OR a
  total-bar base at/below **85% of the lifter's own current estimated
  max**): the increment rounds **up** to the clean 10 lb class — a 5 lb
  bump needs 2.5 lb change plates, which are noise this far from the
  ceiling. The own-max axis exists because a young log's prior best rises
  with every cycle, so the drawdown test never fires for the rebuilding
  lifter it was written for; base-to-capability headroom is visible in the
  log right now. Barbell lifts only — dumbbell and machine steps never
  inherit plate-class jumps — and the axis stands down past 85%.
- **Standard** (no logged evidence, or inside the normal band): the focus
  increment, untouched — today's behavior.
- **Fine** (within 2.5% of a **standing** prior best — one that has stood
  35+ days): the step halves down to the program's own half-grid
  (`roundingLb / 2` — 2.5 lb at the default rounding), which is where
  change plates become the correct tool. Prescriptions still round at the
  program's rounding, so at 5 lb rounding the banked halves surface every
  second cycle; a rack that really has change plates says so by setting
  the program rounding to 2.5, and both the fine step and every
  prescription follow it down.

The prior best is sampled with the same rep ceiling as
`strengthSampleIndex` (Epley drifts high past ten reps) and only from
sessions completed **before** the one being graded, so a long back-off set
cannot fake a ceiling and out-of-order banking cannot see the future.

A fresh log rising through its own all-time best never reads as at-max:
without a standing ceiling the regime stays standard, so a rebuilding
lifter whose old numbers predate the app is never handed change-plate
increments by mistake.

Est. 1RM updates every graded peak: Epley (weight × (1 + reps/30)),
smoothed 70% old / 30% new.

## Accessories (every progression bank, not recovery)

Double progression: all sets at the current rep target, at the planned
load, none stopped early, at most **1** grindy/wobble set, and **no body
signal** → target +1 rep. At the top of the range with a load step → add
the step, reset to the range bottom. Load step 0 (bodyweight) keeps
adding reps; the range top is advisory.

Reps and load never move in the same exposure, whatever the slot's stored
window says: the rep target rises only at a held load, and the load rises only
with the target held or dropped. The load-step branch takes the lower of the
window bottom and the target it just graded, so it cannot raise reps even from
a nonsensical window — the guarantee does not depend on enumerating which
configurations are reachable.

Alongside that, the rep window is read as an **unordered pair** of endpoints
and the current target is clamped inside it, so the number that is prescribed
is the number that is graded. The endpoints are two independently edited
values and the editors let them cross; read literally, a crossed window
(minimum 8, maximum 5) put the target at the top of its own range while it sat
at the bottom, so a slot showing 3×5 banked one clean exposure and came back
at 3×8 with the load stepped as well. Swapping
the ends preserves the runway the lifter configured — collapsing the maximum
up to the minimum would leave a window with no rep runway, where every clean
exposure adds load. The stored endpoints are not rewritten; the program
editor's existing "minimum reps exceed its maximum" warning is what asks the
lifter to correct them, and the steppers now carry one endpoint with the other
so new crossings are not created. A window whose ends are deliberately equal
is a fixed-rep linear slot and keeps working as one. A slot with **no loadable
increment** is floored at the window bottom but never capped at its top: with
no weight to add, reps are the only way it progresses, so it keeps climbing —
pulling its target back into the window would peg it one rep above the maximum
forever.

Anything short of that holds the target and counts a stall. A rotation
deliberately cut by an accepted red-readiness proposal is a hold, not a
missed exposure — it never counts against the accessory. Phase-4 recovery
work is exposure only: it never advances or stalls the target.

## Methodology styles

Some prescription styles replace the wave rules above with a
published methodology's own progression (full details in
[Training methodologies](training-methodologies.md)):

- **Per-exposure styles** (`linearFives`, the three Texas day styles, and
  `maxEffort`) act
  like double progression's schedule: they advance their base after
  every banked exposure that completes as prescribed, never participate
  in Peak grading, and deload after their style's own stall limit of
  *consecutive* misses (3 → −10% novice; 2 → −5% Texas). A grindy but
  fully completed session holds the weight and breaks the miss chain. Max
  effort uses its own rule instead: a made daily-max single anchors the next
  +5/+10 target, a miss holds, and the special exercise rotates weekly.
  Slots that repeat the same lift and style across days (novice A/B
  squat, Texas A/B pairs) stay synchronized while they remain in
  lockstep; a manually edited or deliberately diverged slot keeps its
  own progression from then on — re-align it by setting the bases equal.
  For a 3×5 upper press, the completed 10% rebuild also unlocks an explicit
  coaching proposal to use 5×3. Apply changes only that slot's set/rep shape;
  Not now keeps 3×5 and records the decision. A held weight or one miss is not
  enough evidence: the latest three stamped exposures must be the failed run.
  The slot must also allow coached set changes with a maximum of at least five;
  lower-body schedule changes are not guessed.
- **Multi-step styles** (`fiveThreeOne`, `dynamicEffort`) interpret the
  style-neutral rotation pointer through their own loops. 5/3/1 grades its
  third step and applies +10 lb lower / +5 lb upper at rollover. A missed
  5/3/1 minimum resets the TM three cycles back, and
  two consecutive compromised cycles (reps made only at reduced load)
  apply the same correction; all dynamic-effort work holds. A skipped graded
  step holds rather than stalling toward the
  wave-family 10% rebuild. Dynamic-effort sets never update the e1RM
  estimate.

## Stale sessions

A banked session only advances the program if it was started from the
program's **current** cycle/week/day. Duplicates and leftovers still
bank into history — with a note — but can't advance the schedule or
accessories twice. A session whose saved slot roles no longer match the current
day is likewise history-only. Starting a day while an unchanged session is
already open resumes it; a day whose **composition** changed (a lift swapped,
added, or removed in the editor) builds a fresh session. A pure position move
does not — display order is derived role-first, and reordering must never
orphan an in-flight session with logged sets.
