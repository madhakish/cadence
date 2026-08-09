# Olympic weightlifting foundation

Cadence's built-in Olympic template is a three-day **foundation block**, not a
competition peak and not a claim that every lifter needs the same variation.
It composes the existing slot prescriptions so the program stays editable,
portable, and swappable like every other Cadence program.

## Controlling sources

- Greg Everett's [simplest three-day Olympic weightlifting program](https://www.catalystathletics.com/article/1686/The-Simplest-Olympic-Weightlifting-Program-in-the-World/)
  supplies the day structure: snatch + pull + front squat, jerk + overhead
  work, and clean & jerk + pull + back squat. It also gives the three-step
  triples → doubles → singles build and the 5–10% load increase between steps.
- Catalyst Athletics' [starter program](https://www.catalystathletics.com/article/131/Starter-Program-for-Catalyst-Athletics-Online-Workouts/)
  supplies the five-set practice volume, fixed triples for pulls, light
  technique primers, and an easy bridge before the next block.

These are primary coaching-program sources from Greg Everett/Catalyst, not a
governing-body rule. Olympic programming varies with the athlete, technical
limiter, and distance from competition. The built-in block is intentionally a
conservative starting composition.

## Cadence composition

| Day | Lift slots | Assistance |
|---|---|---|
| Snatch + Front Squat | Snatch · Front Squat | Snatch Pull 3×3 · trunk work |
| Jerk + Overhead | Split Jerk · Push Press · Overhead Squat | vertical pull · trunk work |
| Clean & Jerk + Back Squat | Clean & Jerk · Back Squat | Clean Pull 3×3 · trunk work |

Classic/technical slots use five sets of triples, doubles, then crisp singles.
When usable exercise history exists, a new block starts at roughly 70% of the
best recorded e1RM and adds 7.5% of that opening load per step — approximately
70/75/80%. The recovery bridge uses three easy doubles at 90% of the opening
load. The bar still rounds to the configured plate step.

Push press and back squat use three sets of linear progression. Pulls use fixed
triples. Split jerk may seed from clean-and-jerk history, and overhead squat
may seed from snatch history, so a new block does not start blank merely
because the variation lacks its own history.

## Runtime boundaries

- Creating a new copy reads global completed history. Reactivating an existing
  copy resumes its saved loads, day position, and progression state.
- The template never overwrites an existing exercise or an existing program.
- Every day, slot, style, load, rep target, and exercise remains editable.
- Compatible swaps can replace the classic lifts with power, hang, block, or
  other technical variations. Cadence does not guess the athlete's limiter.
- A `Clean & Jerk` rep represents one complete clean-and-jerk repetition.
  Cadence does not yet encode complex notation such as `2 cleans + 1 jerk` in
  a single set. Use separate Clean and Split Jerk slots when that distinction
  matters.

## Deliberate limits

This block does not claim to be a competition taper, Bulgarian daily-max
system, national-team plan, or individualized technical diagnosis. Those are
different compositions over the same engine, not conditionals to spray into
this template.
