# Edit a program mid-cycle

Programs are editable at any time from **Settings → Programs → (your
program)** — mid-cycle included. The engine grades whatever the program
says at the moment you bank, so edits simply take effect from the next
session.

## Days

- **Add a day**: **+ Add day**, then fill it with lifts/accessories. It
  joins the rotation at the end.
- **Rename**: open the day, edit the name field.
- **Delete a day**: the Delete button on the day row (web) or
  swipe/Edit mode (iOS).

## Lifts and accessories

Open the day. Every lift and accessory row is editable in place — role,
rotation-1 base, est. 1RM, accessory sets/rep range/load step — and every
row has an explicit **Remove** control (trash icon on iOS, Remove button
on web). On iOS the toolbar **Edit** button also enables delete mode.

To change the exercise in a slot: remove the row and re-add with the new
exercise — or, during a session, use a
[cycle- or program-scoped swap](swap-an-exercise.md), which preserves
the slot's progression state instead of resetting it.

## Position (Rotation)

The **Rotation** control sets cycle week and next day directly. Use it
to skip ahead, repeat a week, or align Cadence with training you did on
paper. Two things to know:

- Manual repositioning never *penalizes* you: lifts whose peak hasn't
  been graded aren't treated as missed when you move the pointer.
- Only sessions started from the program's **current** position advance
  it when banked. A session left over from before you repositioned still
  banks into history, but it won't drag the schedule around
  ([why](../reference/progression-rules.md#stale-sessions)).

## What edits do to progression

- Changing **rotation-1 base / est. 1RM** takes effect at the next
  session generated; pending peak grades still apply at rollover on top
  of whatever base is current then.
- Removing a lift discards its progression state (and any pending
  grade). Re-adding the same exercise later starts fresh at whatever
  base you enter.
- Changing **Focus** changes ceiling and increment rules from the next
  rollover on.
