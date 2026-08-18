# Deterministic coaching rules

For a cycle-based program, Cadence evaluates a complete pass through the
program's ordered days as one **rotation**. A four-day Lower A → Upper A →
Lower B → Upper B program can take 12 days or 16 days; the calendar week does
not change that program's boundary. A week-bound design can use calendar weeks
instead; this recovery-bridge change neither defines nor alters that behavior.
The choice is a program concern, not something coaching should infer from its
lifts. Capacity still uses rolling 14/28-day totals.

The first complete rotation after the program's optional reliable-history date
establishes a baseline. Before that baseline, incomplete rotations remain
**Unknown**. After it exists, an incomplete rotation shows provisional readiness
from only the programmed slots already banked, matched by day and main,
complementary, or accessory role. It never adds work until the rotation is
complete. Later rotations use performed weights, reps, set status, warm-up quality,
and body signals. They do not reconstruct history from today's program.

## Readiness lights

- **Green:** at least 90% of prescribed lifting sets were completed at the
  planned load/reps, without a body stop, and repeated-lift output held steady.
- **Yellow:** work was below plan, warm-up or working-set quality was flagged,
  a body signal was logged, or repeated output softened. Loading and volume
  hold for another exposure.
- **Red:** fewer than 80% of lifting sets were completed, a body signal stopped
  work, a post-session check-in reported a hard-stop response, or output fell
  at least 5% across two repeated lifts. Cadence proposes a
  25% accessory-set reduction for the next rotation only. The saved program is
  not permanently cut, and the override expires at the following boundary.

Conditioning is counted in minutes in its own ledger. It never inflates lifting
set completion or e1RM deltas.

### When a red rotation does not resolve

One red rotation is noise. **Two consecutive red rotations** mean the temporary
25% accessory cut did not restore output, so Cadence **cuts the cycle short**
and goes straight to the recovery bridge. This is automatic because it only
removes work: one representative lower exposure, one representative upper
exposure, then rollover. Recovery's one-set accessory cap supersedes any
ordinary percentage override while the bridge is active.

- **Trigger:** persistent red, not a single red. One bad rotation is noise, and
  its answer (the reversible accessory cut) is already cheaper.
- **Rotations 1 and 2 only.** From rotation 3 the schedule advances into
  recovery by itself, so there is nothing to skip.
- **Floor:** at least two complete rotations must have been banked since the
  last recovery phase. Without it, a run of red rotations turns recovery into
  the schedule, which is the opposite of what it is for. Counted in
  rotations rather than sessions so it means the same thing on every split — a
  session floor is a different number of rotations on a two-day program than on
  a six-day one, and can be unreachable inside a cycle on short ones.
- **No calendar ceiling.** Cadence has no week counter. The three progression
  rotations already establish the block length, and readiness can shorten it.

A cut-short cycle would otherwise reach the rollover with no peak grade on
record, which the wave family reads as a missed peak. It is not one — the peak
never ran. So at the moment the program jumps, every cycle-graded slot that
does not already carry a grade is given an explicit **hold**: the base stays,
no stall accrues, and the increment record stops advertising a bump that did not
happen. That hold travels through the same pending-grade mechanism a real peak
uses, so the rollover applies it on its existing path.

The bridge is deliberately inert: main work uses its reduced recovery
prescription, accessories fall to one set, and banking cannot change accessory
targets, per-exposure bases, stall counts, peak-single anchors, or e1RM. The
peak was already graded (or explicitly held during the early jump); recovery
does not grade it again.

Rule identifiers carry the engine's rule version, and coaching decisions store
the identifier they were made under, so a rule whose meaning changes gets a new
version rather than silently reinterpreting old audit rows.

## Rotation suggestions

Two things make a slot wrong as it stands, independently of how the last
rotation went:

- **Its exercise is shelved.** The program keeps prescribing a movement the
  lifter has taken out of rotation, every rotation, silently.
- **It is stuck.** A lift slot's stall counter resets the moment its base is
  rebuilt, so any non-zero value means the weight is being retried rather than
  added to — the moment to rotate the variation is before the weight gets cut,
  which is what the max-effort styles already say in their progression notes.
  Accessory counters are unbounded and nothing ever resolves them, so an
  accessory needs three stuck exposures before it counts as a plateau. A lift
  whose peak grade is still pending is read from that pending grade, not the
  settled one, so a stall does not stay hidden for the cycle worth leaving.

Because both are program hygiene rather than added capacity, they are offered
at every readiness level instead of waiting for a green streak — but they sort
below every readiness rule, so the light stays the headline. Conditioning slots
are never rotated by this rule.

The engine names the slot only. Resolving an actual replacement needs the
exercise library, which lives on the clients, so the swap happens at Apply time
through the same `SwapRules` compatibility used by the manual swap gesture:
same movement group, same programming tier, same loadability, not shelved. If
nothing compatible is available the proposal refuses with that reason rather
than substituting something that does not fit.

Candidates are ranked deterministically, and a `freeWeightsOnly` program
filters them to barbell, dumbbell, kettlebell, bodyweight, and timed-hold work. Apply also
checks that the named slot still contains the named exercise; a stale proposal
cannot overwrite a manual edit made after the coach evaluated it.

An ordinary applied rotation keeps the slot's load and estimate — a compatible
candidate trains the same pattern at the same tier, so those remain the best
prior — but clears the stall counter. Max-effort variations are different: a
returning variation uses its own clean completed single plus the normal
increment, while an unseen one gets the documented calibration ceiling. The
slot's stable reference estimate is not overwritten by the outgoing special
exercise.

A weekly max-effort rotation is offered only after the session contains a
completed, prescribed work single for that slot. Opening the session, skipping
the lift, or completing only volume work is not an exposure.

## Vertical-pull tier promotion

Current templates train the vertical pull as **programmed lift work** —
pull-ups on a double-progression rep window that earns load at the top,
growing into weighted pull-ups — never as an accessory buried under the
press, and never only as a machine stack. A program instantiated before that
change still carries the old shape, and no migration rewrites an authored
program, so the coach offers the upgrade instead: one recommendation per day
whose **only** vertical pull is accessory work (a machine pulldown, or a
pull-up accessory). Days already pulling at the lift tier, days with no lift
work at all, and shelved pull accessories are left alone.

Applying it retires those accessories and adds the template's own slot — a
complementary `doubleProgression` pull-up lift, three sets, born at
bodyweight. If pull-ups are not in the library (or are shelved), the
proposal refuses with that reason, the same posture a rotation takes with no
compatible variation. Unlike the per-rotation hygiene rules, its identity is
rotation-independent: dismissing it once silences it for good, and applying
it removes the condition that raised it.

## Capacity and movement gaps

After two consecutive Green rotations, Cadence may offer one bundled, audited
capacity plan capped by the program's `maximumAddedSetsPerRotation` (six by
default). Default minimums per rotation are three vertical-pull sets, three
hamstring-isolation sets, two rear-delt/cuff sets, two adductor sets, and four
core sets. Existing capacity-managed slots grow only to their configured
maximum; otherwise Cadence proposes an available exercise from the library.
Automatic capacity never grows a day explicitly authored as `technique` or
`explosive`; those days own execution quality rather than fatigue accumulation.
Programs with the legacy `general` intent behave exactly as before. The
program's equipment policy also filters any new exercise proposed for a gap —
and it filters at **evaluation** time, not only on Apply: the snapshot carries
the set of patterns the library can actually fill under the policy, so the
coach never proposes an addition that is guaranteed to fail (a
`freeWeightsOnly` program whose only adductor candidates are machines).

A floor that cannot be raised automatically — every candidate day is
`technique`/`explosive`, or no policy-compatible exercise exists — is not
silently dropped. A separate informational recommendation
(`capacity.rotation-plan.blocked`, a `hold` change) names each blocked
pattern and why, so an unmet minimum is always visible to the athlete.

Hamstring isolation and hip-extension additions are placed on the squat-led
day, preserving the posterior-chain budget of the deadlift-led day. Program
validation also warns about hamstring work immediately before deadlifts,
Olympic/power sets above three reps, missing vertical pulls, and interval work
sharing a day with power work.

Every proposal crosses an explicit Apply/Not now boundary and writes a coaching
decision record. Applying the same rotation twice is prevented by the decision
identity; a later rotation produces a new evidence key and can be considered
again.

## Training breaks (declared intervals)

The lifter can declare typed calendar spans in Settings — **deload**, **rest**,
**away**, and **active recovery** — entered either as a day count or an
explicit date range. The kinds stay distinct
([INV-INTERVAL-KINDS-STAY-DISTINCT]): they differ in whether load was applied,
whether the body was recovering, and what the engine should do afterwards.

Declaring an interval never mutates program state
([INV-INTERVAL-PRESERVES-SCHEDULE]); it changes how the calendar is read:

- A day inside a rest, away, or active-recovery span is never a missed day
  ([INV-INTERVAL-IS-NOT-A-GAP]). The Today spacing advisory stays quiet
  through an excused gap, and the shorter-spacing trial drops any
  session-to-session gap such a span overlaps — a vacation is not a frequency
  observation. Deload deliberately does **not** excuse absence: deload days
  still expect sessions.
- A session banked inside an **active-recovery** span is real, saved history —
  and explicitly off-program ([INV-RECOVERY-WORK-IS-OFF-PROGRAM]): it sets no
  PR milestones, advances no standalone track, and never moves the program
  schedule. The bank summary says so. Sessions inside rest or away spans are
  deliberate, ordinary training and grade normally.
- For a week after an **away** span ends with nothing banked since, Today
  offers a re-entry note instead of resuming as if nothing happened.

Intervals appear as rows in the History log, as shaded bands behind the
progression chart's lines (so a plateau or a drop carries its visible cause),
and travel in backups (schema version 10, `intervals` collection).

## Equipment-aware prescriptions

The engine keeps three separate values:

1. the theoretical strategy target;
2. the load the session prescribes after resolving that target against the
   active gym's bar, collars, plates, and loading policy; and
3. the final performed load entered during the session.

Resolving is **loading guidance, not a new prescription**. When the closest
clean stack lands within 2 lb of the target — routine when kg plates serve a
lb prescription — the session keeps the neat programmed number and the bar
graphic explains the actual plates, so a 220 lb prescription never becomes a
221.4 lb one that then compounds through the stepper and progression. Only a
genuinely unreachable target stores the achieved load.

With the default Closest policy, equal-distance ties choose the heavier load on
a Volume exposure and the lighter load on Peak/other exposures. Explicit gym
policies (Never over, Never under, or Exact) take priority. When snapping
changes a target, the UI shows the nearest load below and above with a per-side
plate breakdown.
