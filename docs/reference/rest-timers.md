# Rest timers

How Cadence decides how long the rest countdown runs after a set. The
logic is identical in both apps (`RestDefaults` in CadenceCore ≡
`restDefaultSeconds` in `web/js/core.js`).

## Resolution order

For the exercise you're resting from, the first rule that applies wins:

1. **The exercise's own rest.** If the exercise has a rest of its own —
   set with the ⏱ control in the logger, or on the exercise in the
   library — that duration is used everywhere the exercise appears,
   whatever its role or movement. `Default` (0:00) means "no rest of its
   own; fall through".
2. **Conditioning never rests.** Conditioning work (walks, bike, rowing…)
   gets no timer — the work is the clock.
3. **Its role in today's program day.** A **complementary** lift uses the
   *Complementary lifts* timer; an **accessory** uses the *Accessories*
   timer. This is why a back-off squat rests 3:00 while a top squat rests
   5:00 — same movement, different role.
4. **Its movement type.** Everything else (main program lifts, standalone
   and blank-session work) is keyed on the exercise's movement group —
   the same data that powers [swaps](swap-rules.md):

   | Movement group | Timer | Stock value |
   |---|---|---|
   | squat, hinge (Main) | Squat & deadlift mains | 5:00 |
   | olympic (Main) | Olympic lifts | 4:00 |
   | any other Main | Other main lifts (presses…) | 3:00 |
   | everything else | Accessories | 1:30 |

## The five timers in Settings

All five are steppers under **Settings → Rest timer**, adjustable
0:00–10:00 in 15 s steps. They are *defaults*: turning one changes every
exercise that falls through to it, and never touches an exercise that has
a rest of its own. Setting a timer to 0:00 disables the countdown for
that bucket.

A handful of seeded accessories deliberately carry their own rest instead
of using the buckets — heavy barbell accessories (hang variants, pulls,
RDLs: 3:00; good mornings 2:00) and light band/core work (1:00). They
show that value in the library, where it can be cleared back to `Default`.

## Controls while resting

- **Start**: automatic after a flagged set if *Auto-start rest after a
  set* is on; otherwise tap **Rest**.
- **−1:00 / +1:00** adjust a running countdown (floor 0:00); **Skip**
  ends it.
- On iOS the countdown lives on the Lock Screen / Dynamic Island, and the
  Action Button or Control Center toggles rest.
