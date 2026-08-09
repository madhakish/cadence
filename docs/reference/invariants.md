# Behavioural invariants

Rules that must not silently change. Each was written because the opposite
behaviour shipped and cost something real — a fabricated milestone, a stranded
schedule, a workout that timed itself.

This file is the readable specification. It is also **machine-checked**:
`.github/scripts/check-invariants.mjs` verifies that every rule below is
asserted by at least one test on every platform it applies to, and that no
test cites a rule that does not exist here. It runs in `npm test` and in CI.

## How to use it

Tag an assertion with the rule ID in its message or an adjacent comment:

```js
ok(scheme === "1×5", "[INV-SCHEME-PERFORMED] a top set plus a fatigue set is one five");
```

```swift
// [INV-SCHEME-PERFORMED]
XCTAssertEqual(PRDetection.topScheme(fatigued)?.reps, 5)
```

Adding a rule means adding tests on every platform in its `platforms` list.
Deleting a rule is a deliberate act: say in the commit why the behaviour is no
longer required.

`platforms` values are `core` (CadenceCore + `web/app/js/core.js` parity),
`web` (JS runtime/UI), and `native` (SwiftUI). Native UI rules cannot be
asserted in this workspace and are marked `unverifiable` — they are documented
here so a reviewer can check them by hand, and are excluded from the coverage
gate rather than being silently absent.

---

## Prescription and loading

### INV-LOAD-STORED-NEAT
*platforms: core*

When the closest achievable rack load lands within `PlateMath.toleranceLb` of
the programmed target — or is the plate-for-plate **denomination twin** of it
(`INV-PLATES-ARE-THE-CURRENCY`) — the session stores the **programmed** number,
not the achieved one. Only a genuinely unreachable, non-twin target stores what
the rack can do.

> Rack near-misses used to overwrite the prescription, so a kg clean stack
> turned 220 lb into 221.4 lb, and the fraction then compounded through the
> stepper and into progression.

### INV-PLATES-ARE-THE-CURRENCY
*platforms: core*

A performed load that is the plate-for-plate **kg twin** of its lb plan — the
greedy stack's plates swapped for their kg denominations (20↔45, 15↔35,
10↔25, 5↔10, 2.5↔5, 1.25↔2.5), on the same bar or the bar's own twin — IS the
plan. Equivalence compares **plate counts, not masses**: the performed side's
greedy heaviest-first kg stack must carry exactly the count the plan's greedy
lb stack carries at every twin rank. A short stack is not the plan, a long one
is not either, and mass-aliased stacks resolve to the greedy reading — 10 kg
of plates a side on a 45 bar is one 10 kg plate, so it meets the 95 plan
(25 lb ↔ 10 kg), never the 85 plan (10 lb pair ↔ 5 kg pair), whose finer stack
is not what the number reads as. The twin grades at plan, never as a
below-plan miss, and stores the canonical programmed number. The equivalence
is a **barbell concept**: it invents a bar-and-plates reading of the number,
so only total-bar work may claim it — machine and dumbbell loads grade on the
numbers alone — and it maths against the bar's **denomination label**
(`Bar.labelLb` / `barLabelLb`: a 35 bar is 35, a 20 kg bar is the 45), never
the bar's converted mass. A non-twin shortfall still grades below plan, and an
overshoot is not an equivalence — it belongs to
`INV-PROGRESSION-RIDES-PERFORMED`.

> Lifters switching racks go by plates, not decimals: 2×20 kg a side on a 45
> bar is "225" in every sense that matters below a max attempt. The flat 2 lb
> tolerance died exactly as plates stacked — each 20 kg pair is 1.8 lb light,
> so a four-pair deadlift was ~7 lb "adrift" — and the app graded honestly
> loaded sessions as misses, stalling cycles for training that happened
> exactly as prescribed.

### INV-COMP-IS-VOLUME
*platforms: core*

A complementary lift on the automatic style is volume work: every rotation
prescribes **5 or more reps at or below the slot's base weight**. It never
mirrors the main lift's 5×5 → 5×3 → 3×3 wave.

### INV-COMP-WARMUP-BRIDGE
*platforms: web*

A complementary lift that **follows other work** bridges with the last two
ramp steps only. A complementary slot ordered **first** in its day still ramps
fully — nothing has warmed the lifter yet. An explicit per-slot warmup policy
always wins over both.

### INV-WARMUP-RESYNC-KEEPS-POLICY
*platforms: native · unverifiable*

Re-syncing warmups after a bar, gym, or working-weight change refreshes their
**weights** without changing **how many** a programmed entry owns. An
equipment-changing swap is the exception: it rebuilds the ramp, because the old
one described a different implement.

### INV-CARDIO-SOLVES-THE-THIRD
*platforms: core*

Distance, duration, and speed are one relationship — `distance = speed × time`
— so the logger accepts whichever **two** the lifter actually knows and derives
the third. Only distance and duration are persisted; a distance computed from a
speed must read back as that same speed.

> A treadmill or a rucking plan is set by pace and time; the belt does not tell
> you a distance until it stops. Requiring distance as an input meant doing the
> arithmetic mid-workout or leaving the field empty, and an empty distance is
> lost volume. Storing speed as a third column instead would create a value
> that can disagree with the two it came from.

### INV-STAIRS-COUNT-FLIGHTS
*platforms: core, native, web*

Conditioning measured in **climbed flights** logs a count and a duration, and
derives its pace in **flights per minute** — `flights = pace × time`, the same
solve-the-third rule distance keeps, against a yardstick that is not ground
covered. Which measure a movement uses is a named property of the movement, not
a guess from its name, and a set already holding the other measure keeps it: a
stair climb logged in miles before flights existed stays visible and editable,
and migration adds the column without inventing a count for it.

> A stair climber's belt goes nowhere, so a distance and a miles-per-hour
> describe it with a unit it does not have. The console counts floors and the
> training variable is how many and how fast, so a climb logged as "1.5 mi at
> 4 mph" recorded a number the machine never reported and could not be compared
> against the next one.

### INV-RUCK-CARRIES-ITS-LOAD
*platforms: core*

Loaded carries — a ruck, a sled — keep a logged load where unloaded cardio
zeroes it. A ruck defaults to a **20 lb** pack and moves in **10 lb** steps,
and its carried weight leads the set label.

> Conditioning zeroed every set's weight on the way out of the logger, so a
> 60 lb ruck and a stroll around the block recorded identically. The pack is
> the training variable — progressing it is the entire point of rucking — and
> barbell-sized 2.5 lb steps are the wrong instrument for loading one.

### INV-ANATOMY-EXPLICIT
*platforms: web*

Every seeded exercise carries an explicit primary/secondary muscle profile,
every muscle it cites is a named muscle, and every named muscle has a region on
the figure to highlight. The movement-group fallback is for user-created
exercises only.

> 84 of 141 seeded exercises inherited a coarse group default — vague for most
> and wrong for several. A leg curl inherited "hinge" and so claimed glutes;
> hip adduction inherited "squat" and claimed quads. Adductors and rear delts
> had no region at all, so that work could not be drawn truthfully.

---

## Health

### INV-HEALTH-IS-A-SECOND-OPINION
*platforms: core*

Apple Health is compared against, never merged in. Reading it produces a
verdict naming **both** numbers; adopting one is an explicit act by the
lifter. A session with nothing in Health is not a discrepancy, and no
comparison ever rewrites a logged set on its own.

> The log is the source of truth and the only copy that a backup can restore.
> A watch left on the charger would otherwise silently erase a ruck, and a GPS
> track through a parking garage would silently inflate one. Both instruments
> are honest and neither is authoritative, so the disagreement is reported and
> the person who did the work decides.

Matching is by majority overlap with the **session** window, because a set
carries no timestamp. Claiming a per-set match would be precision the data
cannot support.

**A read never counts Cadence's own writes. Comparing the log against a mirror
of itself is not a second opinion.**

> Cadence mirrors workouts, conditioning distance, bodyweight and body fat into
> Health. Every read must exclude that source, or the cross-check finds those
> writes and agrees perfectly every time — which reads as corroboration and is
> worse than showing nothing. A sample whose source cannot be identified counts
> as foreign: dropping one we cannot prove is ours would silently discard a real
> second opinion, where the opposite mistake is visible the first time the app
> offers the lifter their own number back.

---

## Milestones

### INV-SCHEME-PERFORMED
*platforms: core*

A session's top scheme is the largest group of top-weight sets sharing one rep
count, breaking ties toward the higher count. It never reports a scheme nobody
performed.

> Reporting the minimum reps across all top-weight sets described `225×5` plus
> a fatigue `225×2` as "2×2" — and that fabricated string was then banked as
> the baseline every later session was compared against.

### INV-NO-LOAD-WITHOUT-RESISTANCE
*platforms: core*

Bodyweight and assisted work earn scheme milestones but never a heaviest-set or
volume PR, and their milestone labels **omit the weight** rather than quoting a
meaningless `0 lb`.

---

## Schedule

### INV-SCHEDULE-WALKS-ORDERS
*platforms: core*

Banking a day steps to the next day by **order value**, and the highest-ordered
day is the last day. Day orders that are not a contiguous `0..n-1` — a gap or a
duplicate — still reach every day.

> Index-space arithmetic over the raw relationship array meant a gap made the
> last day unrecognisable: the week stopped advancing, the cycle never rolled
> over, stashed grades sat unapplied, and days past the gap became unreachable.

### INV-ROTATION-JUDGED-AS-RUN
*platforms: core*

Only the **current** rotation is measured against the program's live day set. A
rotation the schedule has already moved past is closed and is judged by the
days it actually ran.

> A program that gains days — adding a complementary lift, moving from a 2-day
> to a 4-day split — had today's day list read back over every earlier
> rotation, so finished work reported "1/4 days banked" forever. The shape a
> closed rotation ran under is not recoverable from a program that has since
> changed, and inventing one it was never held to is worse than reporting what
> it ran.

### INV-DAY-ORDERS-PRESERVED
*platforms: web*

Day orders are never renumbered on the user's behalf, including on import. A
day's order is the identity every banked session's `programTag.dayIndex` refers
to; renumbering would strand those sessions and misattribute their work.

### INV-NEXTDAY-IS-AN-ORDER
*platforms: web*

`nextDayIndex` names a day's **order**, so it is validated as a member of the
day orders — never range-checked against the day count.

### INV-SLOT-ID-IS-UNIQUE
*platforms: core*

A slot id is never live on two programs at once.

A **program-file** import that would adopt an id another program already holds
is refused, naming the id and the holder. A **backup** restore repairs instead:
the first occurrence keeps its id, later ones are re-issued, and the count is
reported. The difference is deliberate — a program file is additive and opt-in,
so refusing costs nothing, while a backup is the recovery path of last resort
and refusing one would strand data the app itself may have written.

> A slot id is what banked sessions point at through `programSlotID`. Two live
> slots sharing one makes that history permanently ambiguous, and nothing
> repairs it: the launch-time repair scopes its duplicate detection to a single
> program. Re-minting instead would be worse than refusing — identity
> preservation is opt-in, so the lifter asked for *those* ids, and a silent
> re-mint would hand back something that looks preserved but is not.

### INV-TIED-ORDER-IS-AUTHORED
*platforms: core*

A day whose slots all carry the same order was written in the sequence the
author programmed: the tie holds no information, and the array position is
stamped in its place — on import, on template instantiation, and when web
normalization meets a resident tied store. Distinct or *partially* tied
orders are the author's numbers and survive verbatim, and day orders are
never touched (they are session identity — INV-DAY-ORDERS-PRESERVED).

> Stored verbatim, an all-tied day falls to the alphabetical display
> fallback and the alphabet does the lifter's programming: pull-ups drift to
> the end of the day because P sorts after D, and the hardest accessory
> meets the lifter at their most tired.

### INV-DELOAD-IS-THE-SLOTS-KNOB
*platforms: core*

A wave-family rest week lifts at the slot's own deload multiplier — default
0.775 of the rotation-1 base — and zero means *unset*, never an empty bar.
The volume cut (2×3) is not adjustable through this knob, the three working
rotations never listen to it, and other styles keep a recovery-specific shape
(secondary 1×5 at 0.75; 5/3/1 one ramp at 0.50 plus 1×5 at 0.60).

### INV-RECOVERY-IS-A-BRIDGE
*platforms: core, web*

Phase 4 of a recognizable upper/lower program is a **two-exposure recovery
bridge**, not a fourth pass through every A/B day. Cadence selects the first
authored day whose main lift is squat/hinge and the first whose main lift is
press/pull, preserves their authored order, and rolls over after the second.
For this cycle-based wave, day names and calendar weeks never participate.
Programs that cannot be classified safely retain every authored day rather
than silently losing work.

Completion is the set of selected recovery exposures banked in the current
cycle, not the current pointer's position. Either representative may be banked
first. A non-bridge day cannot complete recovery by itself, but banking **as
many recovery sessions as the bridge is long** is a hard cap; a legacy or
manual pointer therefore cannot prescribe an extra reduced workout. That cap is
the bridge's own length with a floor of two — never a constant two — so a
program keeping its full authored pass is not truncated by the guard meant to
protect it. An in-flight program upgraded from the old four-day phase 4
recognizes bridge exposures it already banked instead of prescribing them again.

A recovery bridge expires seven elapsed days after the final completed Peak (or
the preceding completed hard rotation when an early-recovery decision skipped
Peak). Recovery exposures never restart that clock. Today and Start reconcile
the state before showing or creating another recovery prescription, visibly
mark Recovery complete, apply the normal rollover, and begin the next cycle at
Volume day 1. The bridge can therefore contain zero, one, or two reduced
workouts, but it cannot prescribe one beyond the fixed seven-day boundary.

This duration is an expiry guard only. It never turns a cycle-based program
into a week-based program and never advances Volume, Load, or Peak because a
date changed. Reconciliation still never runs while a session is open, so an
in-progress workout cannot be made stale underneath the lifter.

Recovery prescriptions cut working volume, reduce every accessory to one set,
and freeze accessory, rep-window, and per-exposure progression as well as e1RM
observations. The next mesocycle always restarts at the first full authored day.

### INV-PHASE-NAME-IS-PER-SLOT
*platforms: core, web*

A Volume / Load / Peak / Recovery name may be rendered **only** against a slot
whose style actually prescribes those phases — the ones that come out of the
shared phase-shaped table (`usesCyclePhases`, i.e. everything except
`buildsOwnSessionShape`). `linearFives`, the three Texas days,
`doubleProgression`, `fiveThreeOne`, `maxEffort` and `dynamicEffort` never
carry one, and the program-level rotation indicator reports position only.

A slot's badge names the **resolved** style, so a slot left on `automatic`
advertises what the engine will actually run rather than the placeholder.

> The rotation counter is shared by slots whose prescriptions have nothing to
> do with each other. Printing one phase name across all of them asserted
> something about the engine that was false: a 5/3/1 slot prescribing an AMRAP
> single was labelled "Volume", and a novice linear slot that never grades at a
> peak was labelled "Peak". A wave glyph drawn above them claimed a weight wave
> that, for most styles, does not exist.

### INV-PREVIEW-RUNS-THE-REAL-ENGINE
*platforms: core, web*

A slot's forward preview is generated by the shipped engine — prescriptions
from `sessionPrescription`, steps between exposures from the same
`advanceAccessory` / `advanceLinearLift` / `advanceProgramLift` the banking
layer calls — never by a second implementation. It walks a clean success,
carries the slot's current stall state in, holds a graded style's new base
until the rollover so the recovery rotation still runs off the old one, and
persists nothing.

> A parallel implementation can disagree with the app, and a preview that
> disagrees with the session the lifter starts is worse than no preview. The
> defects this surface exists to expose — an increment taper that only ever
> returned zero or one plate step, a training-max ceiling that could never
> bind, a squat base whose +5 became +10 through rounding alone — were all
> found by sweeping parameter pairs, and were all visible at a glance here.

---

## Session lifecycle

### INV-OPEN-IS-NOT-START
*platforms: web*

Opening the logger does not start the workout. The clock runs only after an
explicit start, and an accidental start can be reset back to not-started with
the plan and logged sets intact.

> Starting from `onAppear` meant reading the plan logged elapsed time nobody
> trained, and there was no way to take it back.

### INV-UNSTARTED-HAS-NO-DURATION
*platforms: native · unverifiable*

A session that was never started reports no start time, so completion writes no
Health workout rather than inventing a duration.

### INV-BACK-KEEPS-WORKOUT-RUNNING
*platforms: native · unverifiable*

Back is navigation, not workout state. It saves the open session and returns
to Today without pausing or ending the workout clock or rest timer. Today
continues to show the active elapsed clock; pause and end are explicit controls.

> Calling this action Later, then replacing the clock with a play icon and
> "Resume session," made a running workout look paused even though the timer
> owner had not changed state.

### INV-SESSION-ALWAYS-ESCAPABLE
*platforms: web*

A session can always be discarded from inside itself, not only from Today, and
the confirmation names how many logged sets would be lost. Discarding never
touches banked history or the program schedule.

### INV-PROPAGATION-IS-OPT-IN
*platforms: native · unverifiable*

Applying reps or weight to the remaining planned sets are two independent
opt-ins, both off by default. Opening a set to add a body flag rewrites nothing.

---

### INV-PROGRESSION-RIDES-PERFORMED
*platforms: core*

A clean cycle advances the base from what was **performed**, not the stale
programmed number. The grade fires at the Peak, whose top set is
base-multiplied by design, so the performed weight feeds the base as its
overshoot **ratio** over its own plan — only above plan, only past the same
half-step tolerance the grade uses, and never downward. A performance with no
recorded plan keeps the old advance exactly.

> A lifter in a kg-plate gym lands a stack above every lb prescription. They
> pulled 221.4 for the programmed 215 all cycle, graded clean — and the next
> cycle prescribed 225: the +10 increment applied to a number they had not
> lifted in a month, handing back +3.6 real. The base now rides what the bar
> actually carried.

## Grading

### INV-BELOW-PLAN-IS-BELOW-PLAN
*platforms: core*

Propagating an edit changes the work about to be done, not the target the
session is graded against. A lighter session is saved as performed work and
still grades as below plan — otherwise the base weight could climb on work that
was never done.

---

## History charts

### INV-CHART-SPLITS-BY-ROLE
*platforms: web*

The progression chart separates main from complementary occurrences of a lift.
Main shows by default; complementary is opt-in and visually recessive.

> The same lift can hold a main slot on one day and a complementary slot on
> another at a lighter base. One line across both is a sawtooth between two
> unrelated progressions.

### INV-CHART-ROLE-EXCLUDES-EXTRA
*platforms: web*

Only a lift's **main** slots feed the main series. Unprogrammed work inside a
program session — and accessory work — is extra volume, not a main effort. An
entry with no role in a session with no program at all IS that lift's record
and stays main.

> A few light squats added to an upper day were charted as main and pulled the
> squat progression down to a weight never worked as a main lift.

### INV-VOLUME-KEEPS-ITS-OWN-SCALE
*platforms: web*

In the combined chart, tonnage never stretches the load axis that working
weight and estimated 1RM share.

### INV-CHART-ROTATION-FROM-SESSION
*platforms: core*

The rotation a charted point belongs to is a fact about the session. A slot's
own phase names it where the slot carries one; otherwise the session's program
tag does. Only a session logged outside a program is "Untracked". Every
rotation label the split view can produce has a chart colour.

> Only main and complementary slots ever carried a per-entry phase — accessory
> slots never have, and neither did entries logged before phase capture. Read
> from the entry alone, a session History's Rotations tab counted under
> "Cycle 2 · R3" collapsed into the untracked series on Charts, so most of a
> real training history looked like it belonged to no cycle at all.

### INV-PROJECTION-IS-THE-PERFORMED-RATE
*platforms: core*

A chart projection is the least-squares rate of the **performed** history,
extended forward. It is not a plan, not a target, and not what the program
engine will prescribe — programmed work has its own forward view
(`INV-PREVIEW-RUNS-THE-REAL-ENGINE`) and the two are allowed to disagree. A
downward trend projects downward; no projected value falls below zero. The
copy says "at this rate" every time.

> A forward line on a training chart is read as a promise. Every property here
> exists to keep it a description of what the lifter has already done: fitted
> from performed sets, honest about decline, and worded so it can never be
> mistaken for the program's intent.

### INV-PROJECTION-REFUSES-THIN-HISTORY
*platforms: core*

A projection needs at least four exposures spanning at least 21 days, on a
lift trained within the last 35 days. Otherwise there is no projection at all
— not a shorter or fainter one.

> Four sessions inside one week extrapolate to anything you like. A confident
> line through three points is the most misleading thing a chart can draw.

### INV-PROJECTION-DECLARES-ITS-FIT
*platforms: core*

Every projection reports how well its line describes the history it was fitted
from, and the UI shows it. A flat history is a perfect fit, not a division by
zero.

> A line drawn through noise still has a slope. Reporting R² is what stops that
> slope from reading as a finding.

---

## Delivery

### INV-WEB-APP-SCOPE
*platforms: web*

The PWA is served from its own `app/` directory, addresses its assets
relatively, and keeps its manifest `start_url`/`scope` directory-relative so the
whole app can be remounted without editing it. Its offline shell precaches every
module under `app/js/`, and every path it precaches still exists — `addAll`
rejects atomically, so one stale entry stops the worker installing at all and
costs the app every bit of its offline support. The worker at the app's previous
root scope keeps
existing solely to retire itself: it unregisters, deletes only the legacy shells
it owns, serves nothing, and redirects nobody. Moving a stranded install to
`app/` is the job of the `display-mode: standalone` check in `web/index.html`,
which is the only thing that can tell a real install from a browser tab.

### INV-WEB-CACHE-OWNERSHIP
*platforms: web*

Every service worker deletes only the caches it owns, matched by name prefix.
`web/app/sw.js` owns `cadence-app-`; `web/sw.js` retires the legacy
`cadence-<build>` shells and explicitly excludes the app's prefix. Neither may
sweep `caches.keys()` unfiltered.

> Cache Storage is keyed by ORIGIN, not by scope, so `caches.keys()` returns
> every cache on the whole github.io account — including other projects
> published under it. The self-inflicted case is worse: `/cadence/app/` sits
> inside the retirement worker's `/cadence/` scope, so the first visit to the
> relocated app is itself a navigation that can activate the retiree *after* the
> app worker has populated its precache. An unfiltered delete wipes the new
> offline shell, and the installed worker will not re-run `install` to rebuild
> it — leaving the app with no guaranteed offline shell until the assets happen
> to be re-fetched online.

> The app was served from the Pages root before the product site existed. A
> home-screen install keeps that registration and its cache-first handler
> forever, so deleting the old worker would strand those installs on a stale
> shell, and replacing it with the site's own worker would hand them the
> marketing page as their app. An unlisted module is worse: the app deploys
> green and then fails in a gym with no signal.
