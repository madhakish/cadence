# Rest timers

How Cadence decides how long the rest countdown runs after a set. The
logic is identical in both apps (`RestDefaults` in CadenceCore ≡
`restDefaultSeconds` in `web/app/js/core.js`).

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

All five appear under **Settings → Rest & training behavior**, from **0:00
to 60:00** (the existing native/web backup range). On iPhone, tap a value to
open the duration editor: the value shown big, presets for 1:00, 1:30, 2:00,
3:00, 4:00 and 5:00 (the current one is lit), **−15 s / +15 s** for quick
adjustments (hold to repeat; an off-grid value such as 1:37 steps to the next
quarter-minute mark), and **Off**. **Enter exact duration** opens hours,
minutes and seconds when you need a value such as 1:37, including after using
a preset or stepper. The fields stack at accessibility text sizes. Extra
seconds carry into minutes in the readout, and invalid entry cannot be saved.
The web editor takes hours, minutes and seconds directly and also accepts
pasted HH:MM:SS. Both editors retain exact seconds through export, restore,
and opening and saving without changes. They are *defaults*: turning one
changes every exercise that falls through to it, and never touches an
exercise that has a rest of its own. **Save** applies the draft; **Cancel**
or dismissal leaves the stored value untouched. Setting a timer to 0:00
(Off) disables the countdown for
that bucket. The per-exercise **Rest override** and the running timer's
**Remaining rest** use the same editor, with **Use default from Settings**
and **End rest** in place of Off.

A handful of seeded accessories deliberately carry their own rest instead
of using the buckets — heavy barbell accessories (hang variants, pulls,
RDLs: 3:00; good mornings 2:00) and light band/core work (1:00). They
show that value in the library, where it can be cleared back to `Default`.

## Controls while resting

- **Start**: automatic after a flagged set if *Auto-start rest after a
  set* is on; otherwise tap **Rest**.
- **−1:00 / +1:00** adjust a running countdown (floor 0:00); **Skip**
  ends it. Tap the countdown to edit its remaining hours/minutes/seconds.
  Saving preserves elapsed rest and, on iOS, pause state. Zero ends rest;
  saving after expiry cannot restart it. Editing a default or exercise
  override never adjusts a running countdown.
- The exercise override uses the same editor. **Use default from Settings**
  clears it to zero, with the effective duration shown separately. Zero here
  means fallback, not an instruction to disable a nonzero global default.
- On iOS the countdown lives on the Lock Screen / Dynamic Island, and the
  Action Button or Control Center toggles rest.
