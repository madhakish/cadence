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

Two things the recovery rotation deliberately does **not** do:

- **It does not jump the program to its deload week.** Skipping the peak marks
  every wave-family slot as a missed peak, which starts them toward the
  two-stall 90% rebuild — punishing a lifter the engine has just judged to be
  under-recovered.
- **It does not lower main-lift load.** A cycle is graded on the peak work
  actually performed, and no session records "this was a planned deload", so
  deliberately lighter mains would read back as a failed peak. Cutting
  accessory *sets* has no such side effect: double progression grades reps at a
  held weight, so fewer sets is invisible to it.

Rule identifiers carry the engine's rule version, and coaching decisions store
the identifier they were made under, so a rule whose meaning changes gets a new
version rather than silently reinterpreting old audit rows.

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
