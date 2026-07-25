# History charts reference

The **Charts** tab plots one lift over time. Native and web draw the same
series from the same rules (`ProgressionChartsView` ≡ `renderCharts` +
`progressionChart` in `web/app/js/charts.js`).

## Role: why a lift can be two lines

A program day matrix routinely puts the same lift in two different slots —
`Lower A: Back Squat/main` and `Lower B: Back Squat/complementary` are
independent records with their own base weights, and the complementary one
is deliberately lighter ([program model](program-model.md)). Charting both
as a single line produced a sawtooth between two unrelated progressions,
which made main-lift progress unreadable.

So the chart splits by role:

| Series | What counts |
|---|---|
| **Main** (solid, shown by default) | Every occurrence whose program role is not complementary — main slots, standalone tracked lifts, and blank-session work |
| **Complementary** (dashed, opt-in) | Occurrences in a complementary program slot |

Anything unprogrammed stays in the main series, so standalone and
blank-session history charts exactly as it always did. **Show
complementary** adds the second line dashed rather than at equal weight, so
the main progression stays visually dominant.

## Metrics

| Metric | Value per session |
|---|---|
| Working weight | Heaviest completed working set |
| Est. 1RM | Best Epley estimate across completed working sets — see [progression rules](progression-rules.md) |
| Volume | Working tonnage (warm-ups excluded) |
| **All three** | Weight and est. 1RM as lines; volume as bars behind |

**All three** deliberately does *not* use a second y-axis for volume.
Working weight and est. 1RM share a unit, so they belong on one axis and the
**gap between them is the signal** — an est. 1RM climbing while the top set
stays flat means the reps are improving at a fixed load. Tonnage is a
different quantity two orders of magnitude larger, so it recedes to
translucent bars on their own zero-based right-hand scale. It can never
stretch the load axis.

## Split by rotation

Plots one line per rotation (R1 Volume → R4 Deload) so this cycle's R1 is
compared against last cycle's R1 instead of reading the wave as a sawtooth.

The two splits compose: **colour carries the rotation, dash carries the
role**, so turning both on stays legible instead of fighting over one
visual channel.

## Peak target

When the selected lift has an enabled peak single with a recorded last
value, its next target is drawn as a dashed rule
(`lastPeakSingleLb + peakSingleIncrementLb`). Volume-only views omit it —
a tonnage axis has no meaningful load target.

## Rep PRs

Below the chart: the heaviest completed set at each rep count from 1 to 12.
This is a lifetime best per rep, not a per-session series, so it never
moves down.
