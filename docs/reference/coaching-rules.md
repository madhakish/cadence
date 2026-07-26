# Deterministic coaching rules

Cadence evaluates a complete pass through the program's ordered days as one
**rotation**. A four-day Lower A → Upper A → Lower B → Upper B program can take
12 days or 16 days; the calendar week does not change the boundary. Calendar
weeks remain an optional history view, while coaching and capacity decisions
use rotations and rolling 14/28-day totals.

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

One red rotation is noise. **Two consecutive red rotations** mean the 25% cut
has already been tried and did not restore output, so Cadence escalates to a
**recovery rotation**: the accessory-set cut deepens to 50% for one rotation.
Every session still runs. This follows the survey picture of how lifters
actually deload — cut volume, keep frequency — rather than a fixed calendar
rule, and like the 25% cut it is a temporary override that expires at the next
boundary.

Alongside the accessory cut, two consecutive red rotations also **cut the cycle
short**: the program skips whatever is left of the wave and goes straight to its
deload rotation. This is automatic and needs no consent, because it removes work
rather than adding it.

- **Trigger:** persistent red, not a single red. One bad rotation is noise, and
  its answer (the reversible accessory cut) is already cheaper.
- **Rotations 1 and 2 only.** From rotation 3 the schedule advances into the
  deload by itself, so there is nothing to skip.
- **Floor:** at least two complete rotations must have been banked since the
  last deload rotation. Without it, a run of red rotations turns the recovery
  deload into the schedule, which is the opposite of what it is for. Counted in
  rotations rather than sessions so it means the same thing on every split — a
  session floor is a different number of rotations on a two-day program than on
  a six-day one, and can be unreachable inside a cycle on short ones.
- **No ceiling rule.** The survey picture is "deload every 5–6 weeks or when
  performance stalls". Cadence's fixed four-rotation wave already deloads well
  inside that ceiling, so a ceiling rule could never fire and none is written.

A cut-short cycle would otherwise reach the rollover with no peak grade on
record, which the wave family reads as a missed peak. It is not one — the peak
never ran. So at the moment the program jumps, every cycle-graded slot that
does not already carry a grade is given an explicit **hold**: the base stays,
no stall accrues, and the increment record stops advertising a bump that did not
happen. That hold travels through the same pending-grade mechanism a real peak
uses, so the rollover applies it on its existing path.

The recovery rotation deliberately does **not** do one further thing:

- **It does not lower main-lift load.** A cycle is graded on the peak work
  actually performed, and no session records "this was a planned deload", so
  deliberately lighter mains would read back as a failed peak. Cutting
  accessory *sets* has no such side effect: double progression grades reps at a
  held weight, so fewer sets is invisible to it.

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

An applied rotation keeps the slot's load and estimate — a compatible candidate
trains the same pattern at the same tier, so those remain the best prior — but
clears the stall counter, because inheriting the countdown would deload a lift
that has not yet missed anything.

## Capacity and movement gaps

After two consecutive Green rotations, Cadence may offer one bundled, audited
capacity plan capped by the program's `maximumAddedSetsPerRotation` (six by
default). Default minimums per rotation are three vertical-pull sets, three
hamstring-isolation sets, two rear-delt/cuff sets, two adductor sets, and four
core sets. Existing capacity-managed slots grow only to their configured
maximum; otherwise Cadence proposes an available exercise from the library.

Hamstring isolation and hip-extension additions are placed on the squat-led
day, preserving the posterior-chain budget of the deadlift-led day. Program
validation also warns about hamstring work immediately before deadlifts,
Olympic/power sets above three reps, missing vertical pulls, and interval work
sharing a day with power work.

Every proposal crosses an explicit Apply/Not now boundary and writes a coaching
decision record. Applying the same rotation twice is prevented by the decision
identity; a later rotation produces a new evidence key and can be considered
again.

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
