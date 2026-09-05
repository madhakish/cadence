# Log ad-hoc work

Some hard physical work belongs on your timeline but not in your program.
Wood splitting is the first kind Cadence records this way. It banks straight
into History as one completed session, and it never advances a training
cycle, sets a lifting PR, or counts as barbell tonnage.

## Bank a session

1. On **Today**, find the **Ad-hoc work** section and tap **Wood Splitting**.
2. Set when you started and how long you worked. Duration is the only
   required field.
3. Optionally record:
   - **Session effort** — RPE from 1 to 10 in half steps. With a duration
     it produces a session workload (minutes × RPE) in arbitrary units.
   - **Maul weight** — in lb or kg. This is an implement fact; it is never
     multiplied into volume.
   - **Rounds**, **split pieces**, **estimated strikes**, and **cords
     split** — leave anything you did not count blank. Cadence never infers
     one of these from another.
4. Add a note if you want (species, weather, tool) and tap **Bank work**.

The session is banked immediately as complete. Nothing opens the set-by-set
logger, and no program cursor moves.

## Review, edit, or delete

- **History → Log** lists the session alongside your workouts on its date.
  The row shows duration, effort, maul weight, and cords when recorded.
- At the top of the log, an **Ad-hoc work** summary for the current year
  totals sessions, logged time, cords, and effort. It is reported separately
  from lifting volume and training cycles.
- Open the row to see every recorded fact. **Edit** reopens the same form
  with your values; saving updates the existing record rather than creating a
  new one. **Delete** removes the session after confirmation and changes
  nothing about your program or workouts.

## What it is, underneath

An ad-hoc session is an ordinary completed session holding one conditioning
set for the canonical **Wood Splitting** exercise. Duration and maul weight
live on that set; the wood-specific facts live in a typed record attached to
the session. Because the exercise is conditioning, it is excluded from
tonnage, estimated-max, and PR detection on both platforms.

Ad-hoc sessions travel in your JSON backup (schema version 12), so a restore
on either platform keeps every recorded fact.
