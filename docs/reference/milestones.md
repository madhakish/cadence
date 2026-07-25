# Milestones reference

Automatic, terse achievement detection. Milestones are derived at bank time
from performed work only, never from the plan
(`PRDetection` ≡ `prEvaluate` in `web/js/core.js`), and are stored so the
History tab can list them.

## The three kinds

| Kind | Fires when |
|---|---|
| **Heaviest set** | The session's top working weight beats every prior working set of the same lift |
| **First scheme** | The session's top scheme has never been completed before for that lift |
| **Volume PR** | The session's working tonnage beats every prior session of that lift |

A fourth kind, **program note**, shares the same list but is an explanation
(a deload, a ceiling hold, a stale-session note), not an achievement — see
[progression rules](progression-rules.md).

## What counts

Only **completed working sets** count; warm-ups and planned-but-unlogged
sets never do. Comparisons are scoped to one exercise and one
[load basis](program-model.md) — an assisted pull-up is never compared with
a weighted one.

Load and tonnage milestones are suppressed where more weight does not mean
more work: **bodyweight** and **assisted** sets earn scheme milestones but
never a heaviest-set or volume PR, and their scheme milestone names reps
only rather than quoting a meaningless `0 lb`.

The very first session of a lift can earn a heaviest set and a first scheme
but never a volume PR — "more than nothing" is not an achievement.

## The top scheme

A session's scheme is the largest group of top-weight sets that share one
rep count, breaking a tie toward the higher rep count.

This matters because the scheme is also banked as the baseline every later
session is measured against. Reporting the *minimum* reps across all
top-weight sets — the old rule — described work nobody performed: a `225×5`
followed by a fatigue set of `225×2` read as `2×2`, and four clean fives
plus a dropped triple read as `5×3`. Those fabricated strings then became
the standard for every future comparison.

| Session at the top weight | Scheme |
|---|---|
| 5 × `225×5` | `5×5` |
| 4 × `225×5`, then `225×3` | `4×5` |
| `225×5`, then `225×2` | `1×5` |
| `185×8`, `185×6` | `1×8` (tie → harder group) |
| `225×3`, `225×3`, `225×5` | `2×3` (majority, not a tie) |

Back-off sets below the top weight never shape the scheme.

## A note on frequency

Set count is part of the scheme key, so adding or dropping a set at your
working weight mints a new "First N×R". This is expected rather than a
defect, but it does mean scheme milestones fire more often than load or
volume PRs.
