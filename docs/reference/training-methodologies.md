# Training methodologies

Cadence ships four published barbell methodologies as program styles. Each is
implemented deterministically in the shared core (CadenceCore ↔ `web/js/core.js`)
and initializes itself from your recorded history: when a slot's exercise has
logged working sets, the program derives its starting weights from your best
estimated 1RM (Epley: `weight × (1 + reps/30)`), rounding **down** to the plate
step. With no history, the template's deliberately light hand-set base stands.
That is what makes program switching cheap — the app already knows your lifts.

| Style | Start (× e1RM) | Session shape | Progression |
| --- | --- | --- | --- |
| Linear fives (novice) | 0.74 | sets-across of 5 | +10 lb lower / +5 upper per session |
| Texas — volume day | 0.77 | 5×5 across | +5 per completion, twin slots synced |
| Texas — light day | 0.62 | 2×5 (squat) · 3×5 (press) | same, synced with its twin |
| Texas — intensity day | 0.86 | 1×5 PR set | same (= +5 lb/week per lift) |
| 5/3/1 wave | 0.90 (= training max) | 2 ramp sets + top "+" set | +10 lower / +5 upper TM per cycle |
| Max effort | 0.90 | top single + 3×3 back-off @80% | +10 / +5 after a made single |
| Dynamic effort | 0.50 (0.60 speed pulls) | speed sets, 3-week wave | holds; wave supplies progression |

## Novice linear progression — 3×5 and 5×5

Two templates: **Novice Linear — 3×5** follows Rippetoe's Starting Strength
prescription (3×5 across, squat every session, presses alternating by day,
deadlift 1×5). **Novice Linear — 5×5** is the Bill Starr / StrongLifts-lineage
variant — offered separately because 5×5 across is *not* the Starting Strength
prescription. Both add weight every banked session that completes as
prescribed; three consecutive misses deload that lift 10% and restart the
count, which is the published reset. Slots that repeat a lift across the A/B
days (the squat in both templates, the 3×5 deadlift) share one synchronized
progression, so the weight genuinely moves every session, not every other
exposure.

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
back"). Boring But Big supplies 5×10 volume at ~50% of the TM.

## Conjugate — Westside-style

Max-effort days work up to a top single at the slot's current target with 3×3
back-off at 80%; the deload rotation trades the single for 70% triples. A made
single moves the target +5/+10; a miss holds it — in this methodology you
**rotate the variation** (use the swap gesture; the swap pools are the
rotation pools) rather than grind the same bar. Dynamic-effort days wave
the slot base ×1.0 → ×1.10 → ×1.20 across the three loading rotations: with
bases at 50% of the max (squat, bench) and 60% (speed pulls), that is
50→55→60% for the squat and bench patterns and 60→66→72% for pulls — 10×2
for the squat pattern, 6×1 speed pulls, 9×3 for the bench. Speed sets never update the e1RM estimate —
a fast double at 55% says nothing about your max. Prescriptions are straight
bar weight; bands and chains are a coach's call the app does not fake.

## What is deliberately non-canonical

- Starting weights derive from e1RM fractions instead of the books' empirical
  ramp-up sessions; the fractions err light, matching the "start too light"
  doctrine everywhere.
- Phase-based methodologies ride Cadence's existing four-rotation calendar, so
  a program's rotation label (R1–R4) is the 5/3/1 week or the DE wave step.
- Texas Method volume/light/intensity slots move in parallel at the same
  weekly rate rather than recomputing from one shared 5RM; twin A/B slots of
  the same lift are synchronized, so the absolute gaps between day types stay
  fixed while every slot climbs +5 lb/week.
- AMRAP sets are recorded as ordinary sets whose target is the minimum;
  Cadence never asks you to grind past technical failure.
