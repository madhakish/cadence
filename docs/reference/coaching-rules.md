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
2. the nearest load achievable with the active gym's bar, collars, plates, and
   loading policy; and
3. the final performed load entered during the session.

With the default Closest policy, equal-distance ties choose the heavier load on
a Volume exposure and the lighter load on Peak/other exposures. Explicit gym
policies (Never over, Never under, or Exact) take priority. When snapping
changes a target, the UI shows the nearest load below and above with a per-side
plate breakdown.
