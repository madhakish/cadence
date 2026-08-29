# History charts reference

The **Charts** tab plots one lift over time. Native and web draw the same
series from the same rules (`ProgressionChartsView` ≡ `renderCharts` +
`progressionChart` in `web/app/js/charts.js`). Presentation differs by
platform: native offers **Progression / Volume / Rep PRs** as three plots of
one full-height chart surface (a segmented control switches between them, so
each chart gets a real viewport instead of collapsing beside its siblings),
while web stacks the same three views on one scrolling screen. Which series
exist, what counts into them, and which lifts earn which metrics are
identical on both.

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
| **Weight + e1RM** | Both lines on the shared load axis |
| Reps | Best completed working set's reps — offered *instead* of the load metrics for a bodyweight lift |

Working tonnage (warm-ups excluded, main slots only) is its own **Volume**
view — a bar chart on its own zero-based scale, never sharing the load axis.
It exists only for lifts whose load basis supports load PRs: a lift that
tracks reps rather than external load has no meaningful tonnage, and the
Volume view says so instead of charting snapshotted history under semantics
the lift no longer has.

Which metrics are offered depends on what the lift's load **means**. An
unloaded pull-up has no external resistance, so working weight, est. 1RM and
tonnage could only ever draw a flat zero — so a lift whose load basis earns no
load PR ([INV-NO-LOAD-WITHOUT-RESISTANCE](invariants.md)) is offered **Reps**
and nothing else. `Weighted Pull-up` hangs real plates from a belt, so it keeps
every load metric. Reps carry no weight unit and never convert between lb
and kg; a projected rep count is rounded, since a "12.4 rep" set does not exist.

Every metric — tonnage included — is converted to your display unit at the
chart boundary. Weights are stored in canonical pounds, so a kg lifter's
volume axis reads in kilograms like the rest of the chart.

**Weight + e1RM** deliberately shares one axis: the two metrics genuinely
share a unit, and the **gap between them is the signal** — an est. 1RM
climbing while the top set stays flat means the reps are improving at a
fixed load. Tonnage is a different quantity two orders of magnitude larger,
which is exactly why it lives on its own Volume view with its own zero-based
scale instead of stretching the load axis.

## Split by rotation

Plots one line per rotation (R1 Volume → R4 Recovery) so this cycle's R1 is
compared against last cycle's R1 instead of reading the wave as a sawtooth.

The two splits compose: **colour carries the rotation, dash carries the
role**, so turning both on stays legible instead of fighting over one
visual channel.

A point's rotation comes from the session it was performed in. Slots that
carry their own phase use it; everything else — accessory work, and anything
logged before per-entry phase capture — takes the rotation from the session's
program tag, the same tag the **Rotations** tab groups by. Only a session
logged outside a program reads as **Untracked**.

## Project forward

**Off · 1 month · 3 months.** With a horizon selected, the chart fits a
least-squares line through the performed history and extends it past today,
drawn thin and dashed behind a shaded future region and a *today* divider.
Below the chart it names the rate, the value it reaches, and how well the
line actually fits:

> **+4.2 lb/week · 245 lb in 1 month at this rate**
> steady trend · fitted from performed sessions — a continuation of the past,
> not a plan.

What it is and is not:

- It is **the rate you have already been adding**, extended. It is not a
  target, and not what the program will prescribe — programmed work has its
  own forward view, which runs the real progression engine and is allowed to
  disagree with the trend.
- It follows the **lift**, not a rotation. Splitting the history into four
  rotation lines does not fit four separate futures through a quarter of the
  evidence each.
- **A decline projects downward.** No projected value goes below zero.
- The fit quality is always shown — *steady trend*, *rough trend*, or *very
  noisy — treat as a guess*. A line through noise still has a slope, and the
  wording is what stops that slope reading as a finding.
- When the rate rounds to zero at one decimal **and** the fit quality is at
  least 0.4 (the same floor that earns *rough trend*), the fit-quality line
  adds **Plateaued**. A rate that rounds to zero because the fit can't find a
  direction in the noise (fit quality below 0.4) is not called plateaued —
  the wording only reads "flat" when the line is also trustworthy enough to
  believe it.

It **refuses** rather than drawing a confident line through thin history, and
says why: fewer than 4 exposures, a span under 21 days, or a lift untrained
for more than 35 days. Selecting a horizon always produces an answer — either
the trend or the reason there isn't one.

## Peak target

When the selected lift has an enabled peak single with a recorded last
value, its next target is drawn as a dashed rule
(`lastPeakSingleLb + peakSingleIncrementLb`). Volume-only views omit it —
a tonnage axis has no meaningful load target.

## Rep PRs

The heaviest completed set at each rep count from 1 to 12 — a chart plus a
card per rep count (its own plot on native, below the progression chart on
web). This is a lifetime best per rep, not a per-session series, so it never
moves down.

## Inspecting a point

Tap or drag across the plot to select an exposure. The selected date stays
marked on the chart and the detail line reports its performed weight, reps,
estimated 1RM, program role, and rotation. Web points use a larger invisible
touch target than the dot they draw, so making the chart finger-friendly does
not turn the data marks into blobs. Performed-series curves pass through every
recorded point and clamp each segment between its endpoints, so smoothing the
line cannot invent a higher or lower workout between two real sessions.

## Completed-session detail

Opening a session starts with the work-set count, performed volume, and honest
elapsed time when completion timestamps exist. Each exercise names its top set
and volume. Set rows lead with what was actually performed; the original plan
appears underneath only when load, reps, or duration changed. Skipped and
unperformed sets say so explicitly, and AMRAP rep floors retain the `+`.
