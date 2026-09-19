# Run a training day

Rest alerts identify the next unfinished exercise, including its warmups. After
the last set of a lift, the alert advances to the next lift; it does not repeat
the completed lift. A running countdown keeps its remaining time when that
context changes. After all sets are resolved, the alert only reports that rest
is over.

## Preview, then start (or resume)

The **Today** screen shows the active program's next day with every
prescription pre-filled. **Tap the day's name to preview the whole
workout** — every lift with its full prescription and bar loadout, every
accessory — without starting anything; the pinned **Start** button up
top is what commits. Tap **Start** (on the card or the preview) to
begin. If a session for the program is already open, Start **resumes
it** — you can't accidentally create a duplicate, and a duplicate
smuggled in some other way banks as history without advancing the
program twice.

Off-program work: **Blank session** logs anything; standalone tracked
lifts appear under "Next up" with their own suggestions.

## During the session

- **Time planks and other holds.** Tap **Start** beside a planned timed set.
  The hold countdown is separate from rest and gives a finish cue. **Stop hold**
  ends an attempt early; **Log** saves whole seconds held and completes that
  set, keeping its original prescribed duration for progression. Reaching zero
  alone never logs work. **Try again** starts a fresh continuous attempt; closing
  discards the unsaved attempt. Adjust the target by tapping the set's hold time
  before starting. On iOS, allow notifications for a background finish alert;
  on web, keep Cadence visible for a timely sound. Both clocks catch up after
  backgrounding without counting time beyond the target. An app restart or
  page reload discards the unsaved attempt, leaving the set unchanged.
- **Confirm sets as you do them.** Everything predictable is pre-filled
  — weight, sets, reps, and a warmup ramp for barbell lifts and main dumbbell
  lifts — but remains *planned* until you mark it completed. Mark intentionally
  omitted work as *skipped*. Only completed work counts in history and
  progression.
- **Follow “Now” through the warmups.** The highlighted row and large load
  display follow the first unfinished set in the authored plan. Complete or
  skip each warmup to advance through the ramp; working sets become current
  after the preceding warmups are resolved. A barbell lift whose warmups are
  all still planned drops the steps at or below a working load you have
  already completed this session on the same movement with a bar — keeping
  at least the last two — whenever its ramp refreshes after a bar, gym, or
  working-weight change.
- **Check the equipment context.** “Training at” follows the gym captured by
  the session. Changing it updates default bars and warmups; a bar selected on
  one exercise is saved with that session and survives reopening it.
- **Rest timer** starts per your settings: an exercise's own rest (⏱)
  wins, then its role today (complementary lifts and accessories rest
  less than a top main), then its movement type — see
  [Rest timers](../reference/rest-timers.md). On iOS the Live Activity
  puts the countdown on the Lock Screen/Dynamic Island, and the Action
  Button or Control Center can start/skip rest.
- **Opening a session is not starting it.** The logger opens showing
  **not started** so you can read the plan, check loadouts, or reopen a
  session without logging time you didn't train. **Start workout** — in
  the bottom bar or the session menu — begins the clock. If you start one
  by accident, **Reset to not started** puts it back; the plan and any
  logged sets are untouched. A session that was never started banks
  without writing a Health workout, since it has no honest duration.
- **Workout clock controls** (iOS): once started, the session menu
  pauses, resumes, or restarts the elapsed clock at 0:00. The same
  pause/resume controls appear on the Live Activity's workout face, so an
  abandoned session's stopwatch can always be stopped from the Lock
  Screen.
- **Log sets from the Lock Screen** (iOS): the Live Activity's workout
  face names the set you're on — lift, set position, reps and load — with
  **Complete set** and **Skip**. Completing it logs exactly that set,
  arms your rest when auto-start is on, and moves the face to the next
  set; the rest face then says what's next. If the workout has moved on
  since the face was drawn (you logged in the app meanwhile), the button
  says so instead of logging a different set. Ending the activity never
  banks the workout — **Bank it** stays in the app.
- **Done with a session you never wanted?** **Discard session** removes
  it outright, from inside the session or from the Today card. The
  confirmation says exactly how many logged sets would be lost; your
  banked history and the program schedule are unchanged.
- **Grade honest quality.** Clean, grindy, and wobble are one optional,
  mutually exclusive assessment. *Stopped early* is independent and can
  accompany the appropriate completed or skipped status. These aren't
  judgments; they're the data autoregulation runs on.
- **Dropping load mid-session?** Use the drop-load control rather than
  silently editing the weight, so the reason is recorded. (Either way,
  working below prescription can't grade as a clean success.)
- **Conditioning work** (walks, bike, ruck — anything of the conditioning
  type) logs **distance, time, and incline** instead of weight×reps: tap
  the set to enter them; speed falls out of distance ÷ time. Rep-based
  conditioning like burpees keeps normal sets×reps, and cardio sets carry
  a completion status without a lifting-quality grade.
- **Add or remove individual sets** with the + Set / − Set controls, row swipe
  (iOS), or Delete set action. Extra back-off volume beyond the prescription
  never hurts your grade.
- **Adjust a work set without retyping the others.** The set sheet offers
  *Apply reps to remaining planned sets* and *Apply weight to remaining planned
  sets* as two independent opt-ins, both **off** by default — so editing reps
  can't reset a weight you deliberately chose, and opening a set just to add a
  body flag changes nothing else. Completed or skipped sets are never rewritten.
  Note that propagating an edit changes the work you're about to do, not the
  target you're graded against: a lighter session is saved as performed work
  but still grades as below plan.
- **Subtract** as well as add rest time with the −1:00 / +1:00 controls while a
  rest runs.
- **Wrong exercise available?** [Swap it](swap-an-exercise.md), or
  **remove it** from the session entirely via the exercise's ⋯ menu
  (iOS) / Remove button (web) — the program slot is untouched, the lift
  just isn't performed today.

Editing your program takes effect the next time you **Start** that day:
Start always reflects the current plan, so a lift you swapped in the
program editor shows up immediately (a session you already had open from
before the edit stays as it was — resume it from the Today card only if
you want the old snapshot).

## Bank it

Tap **Bank it.** when you're done. Banking is atomic: your history, PR
milestones, accessory progression, and program state all commit together
— or, if saving fails, nothing does and you can simply tap Bank again.
The summary shows top sets, volume, and any PRs or program notes.
If planned sets remain, Cadence confirms the incomplete bank and explains that
only completed work will count.

What banking advances:

| Every bank | At week-3 peak | At week-4's end |
|---|---|---|
| Day pointer, accessory double progression | Each lift graded; result stashed | Stashed results applied: increments, stalls, deloads; cycle rolls to week 1 |

### Barbell targets and actual weight

Cadence keeps the program target separate from the load your rack can build.
Sets and history record the actual bar, plate and collar mass. Kilogram plates
are converted by mass, never renamed as pound plates: a 45 lb bar plus 50 kg
on each side totals **265.46 lb (120.41 kg)**, not 275 lb. The plate summary
shows both units and the difference from the requested target.

Completing the suggested achievable load counts against that prescription.
The original target remains available for comparison. This change does not
rewrite old workouts: older logs may contain nominal weights, and today's gym
inventory cannot establish which plates were actually used. Correct a past set
only from your record of what was on the bar.
