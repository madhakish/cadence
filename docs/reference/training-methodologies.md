# Training methodologies

Cadence ships several published barbell methodologies as composable program
prescriptions. Each is
implemented deterministically in the shared core (CadenceCore ↔ `web/app/js/core.js`)
and initializes itself from your recorded history: when a slot's exercise has
logged working sets, the program derives its starting weights from your best
estimated 1RM (Epley: `weight × (1 + reps/30)`), rounding **down** to the plate
step. Accessories without a prescribed percentage reuse their most recent
completed working load. With no history, the shared conservative
[programming defaults](programming-defaults.md) catalog stands in. That is what
makes program switching cheap — the app already knows your lifts, and an
unfamiliar movement still does not become a setup form full of blanks.

| Style | Start (× e1RM) | Session shape | Progression |
| --- | --- | --- | --- |
| Linear progression | 0.74 | sets-across of 5; upper 3×5 may adapt to 5×3 | +10 lb lower / +5 upper per session |
| Texas — volume day | 0.77 | 5×5 across | +5 per completion, twin slots synced |
| Texas — light day | 0.62 | 2×5 (squat) · 3×5 (press) | same, synced with its twin |
| Texas — intensity day | 0.86 | 1×5 PR set | same (= +5 lb/week per lift) |
| 5/3/1 wave | 0.90 (= training max) | 2 ramp sets + top "+" set | +10 lower / +5 upper TM per cycle |
| Olympic technique | 0.70 | 5×3 → 5×2 → 5×1 · 3×2 recovery | ~70/75/80% quality build |
| Max effort | 0.90 from competition-lift history | ~90% single · near-max single · daily target | +10 / +5 after each made exposure |
| Dynamic effort | 0.50 squat/pull · 0.40 bench | speed sets, independent 3-step loop | holds; its loop supplies progression |

Classic wave, secondary, hypertrophy, and lift-level double
progression slots also reuse e1RM history when a template is created, at
conservative fractions of 0.65, 0.55, 0.50, and 0.50 respectively.

## Olympic weightlifting foundation

The built-in three-day block separates snatch, jerk, and clean & jerk practice;
pairs them with their pulls and squats; and builds classic-lift practice from
triples to doubles to singles. It is a source-shaped editable foundation, not
an individualized competition peak. The exact source map, history aliases,
and boundaries are documented in
[Olympic weightlifting foundation](olympic-weightlifting.md).

## Novice linear progression — 3×5 and 5×5

Two templates: **Novice Linear — 3×5** follows Rippetoe's Starting Strength
prescription (3×5 across, squat every session, presses alternating by day,
deadlift 1×5). **Novice Linear — 5×5** is the Bill Starr / StrongLifts-lineage
variant — offered separately because 5×5 across is *not* the Starting Strength
prescription. Both add weight every banked session that completes cleanly;
a grindy-but-complete session holds the weight (and breaks the miss chain),
and three consecutive misses deload that lift 10% and restart the count,
which is the published reset. Slots that repeat a lift across the A/B days
(the squat in both templates, the 3×5 deadlift) share one synchronized
progression while they remain in lockstep, so the weight genuinely moves
every session; a manually diverged slot keeps its own base.

### Adaptive upper-body stage

The 3×5 template can evolve one upper press at a time. After that slot misses
three consecutive prescriptions at the same load, its normal 10% rebuild remains the first
answer. Once Cadence can see both the failed stamped exposure and the rebuilt
base, coaching may recommend **5×3** for that slot. Accepting keeps its current
base and session-to-session loading; it changes only the rep structure while
preserving 15 work reps. **Not now** records the decision and changes nothing.
The proposal appears only when the latest three stamped exposures are the
failed run and the slot both allows coached set changes and permits five sets.

This follows the smallest-change sequence in Steve Ross's Starting Strength
article [Don't Jump Ship: Earning the Transition from Novice to Intermediate
Training](https://startingstrength.com/article/dont-jump-ship-earning-the-transition-from-novice-to-intermediate-training):
individual lifts change at different times, and upper presses move from 3×5 to
5×3 before a wholesale intermediate-program switch. Cadence's exact trigger is
deliberately conservative and deterministic: the current base must be at least
7.5% below the most recent failed linear prescription, which recognizes the
engine's rounded 10% rebuild without firing on an ordinary held weight.

Squat and pull transitions are not inferred by this rule. Their next coaching
steps change light-day or frequency structure, which needs authored schedule
semantics rather than a bogus one-slot approximation. The separate 5×5
template also stays 5×5 unless the user edits it; this rule claims only the
source-backed 3×5 → 5×3 transition.

## Texas Method

One template pass covers two calendar weeks (Volume/Light/Intensity **A**, then
**B**) so bench and press alternate weekly, per the book. Volume day squats
5×5 at ~90% of the intensity 5RM; light day squats 2×5 at ~80% of volume;
intensity day is a single 5RM PR set. The deadlift takes its 1×5 PR on
intensity day — *Practical Programming*'s base template pulls on volume day,
but the intensity-day PR is the dominant published practice and needs no
coached Olympic lifts. Twin A/B slots of the same lift and day type share one
synchronized progression at +5 lb per completion — the canonical +5 lb per
lift per week, and +5 per appearance for the weekly-alternating presses; two
misses reset that slot 5%.

## 5/3/1 — Wendler

The slot base is the **training max** (90% of 1RM — the original book's value),
never a working weight. Weeks map onto Cadence's four rotations: 65/75/85%
×5/5/5⁺, 70/80/90% ×3/3/3⁺, 75/85/95% ×5/3/1⁺, then a 40/50/60% ×5 deload.
The final set each week is an AMRAP: the shown reps are the *minimum*, extra
quality reps are welcome and feed the e1RM estimate. Only the top set gates
progression — hit the minimum across the cycle and the TM moves +5 lb (press,
bench) or +10 lb (squat, deadlift) at rollover; miss it and the TM resets
three cycles back (−15/−30 lb, Wendler's "five steps forward, three steps
back"); two consecutive compromised cycles — reps made only after an
autoregulated or manual load reduction — apply the same correction, since a
TM you can only hit at reduced load is set too high. Boring But Big supplies
5×10 volume at ~50% of the TM.

## Conjugate — Westside

Max effort advances after each weekly exposure and changes to a special
exercise; it does not wait for or borrow the dynamic wave's third step.
Dynamic effort owns a 50→55→60% squat/pull loop and a 40→45→50% bench loop.
The full four-day plan, assistance work, recovery behavior, implementation
boundaries, and source map are in the
[Conjugate method implementation](conjugate-method.md).

## Composition is the engine

These are prescriptions, not mutually exclusive program modes. Each lift slot
stores its own style and configuration, while the program stores the ordered
days. The editor and standalone program-file format preserve that combination,
so a custom/imported program may place max effort on one day, dynamic effort on
another, double progression on assistance, and a classic Cadence wave or 5/3/1
elsewhere. A pre-baked template is simply a reviewed starting composition.

## What is deliberately non-canonical

- Starting weights derive from e1RM fractions instead of the books' empirical
  ramp-up sessions; the fractions err light, matching the "start too light"
  doctrine everywhere.
- Built-in multi-step prescriptions read the program's style-neutral rotation
  pointer as their own step. They do not inherit the classic wave's
  Volume/Load/Peak labels or progression rule.
- Texas Method volume/light/intensity slots move in parallel at the same
  weekly rate rather than recomputing from one shared 5RM; twin A/B slots of
  the same lift are synchronized, so the absolute gaps between day types stay
  fixed while every slot climbs +5 lb/week.
- AMRAP sets are recorded as ordinary sets whose target is the minimum;
  Cadence never asks you to grind past technical failure.
- A session completed with 2+ quality-flagged (grindy/wobble) sets holds the
  weight instead of adding it — stricter than the books' grind-and-add, in
  line with the app's quality-gated progression everywhere else.
