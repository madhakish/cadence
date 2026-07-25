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

`platforms` values are `core` (CadenceCore + `web/js/core.js` parity),
`web` (JS runtime/UI), and `native` (SwiftUI). Native UI rules cannot be
asserted in this workspace and are marked `unverifiable` — they are documented
here so a reviewer can check them by hand, and are excluded from the coverage
gate rather than being silently absent.

---

## Prescription and loading

### INV-LOAD-STORED-NEAT
*platforms: core*

When the closest achievable rack load lands within `PlateMath.toleranceLb` of
the programmed target, the session stores the **programmed** number, not the
achieved one. Only a genuinely unreachable target stores what the rack can do.

> Rack near-misses used to overwrite the prescription, so a kg clean stack
> turned 220 lb into 221.4 lb, and the fraction then compounded through the
> stepper and into progression.

### INV-COMP-IS-VOLUME
*platforms: core*

A complementary lift on the automatic style is volume work: every rotation
prescribes **5 or more reps at or below the slot's base weight**. It never
mirrors the main lift's 5×5 → 5×3 → 3×3 wave.

### INV-COMP-WARMUP-BRIDGE
*platforms: core, web*

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

### INV-DAY-ORDERS-PRESERVED
*platforms: web*

Day orders are never renumbered on the user's behalf, including on import. A
day's order is the identity every banked session's `programTag.dayIndex` refers
to; renumbering would strand those sessions and misattribute their work.

### INV-NEXTDAY-IS-AN-ORDER
*platforms: web*

`nextDayIndex` names a day's **order**, so it is validated as a member of the
day orders — never range-checked against the day count.

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

### INV-VOLUME-KEEPS-ITS-OWN-SCALE
*platforms: web*

In the combined chart, tonnage never stretches the load axis that working
weight and estimated 1RM share.
