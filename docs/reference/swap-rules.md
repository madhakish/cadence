# Swap rules reference

## Candidate filter

An exercise is offered as a substitute only if **all** of these hold:

| Rule | Rationale |
|---|---|
| Same **movement group** (non-empty): squat, hinge, press, olympic, pull, shoulder, arms, core, conditioning | A swap trains the same pattern |
| Same **category** (Main / Accessory / Conditioning) | No accessory → competition-lift jumps; prescriptions stay tier-appropriate |
| Same **loadability** — `bodyweight`/`timed`/`conditioning` types never mix with loaded types | A weight prescription can't follow the swap (no DB Press → Dips) |
| Not **shelved** | Shelved means deliberately benched (injury, re-entry test pending) |
| Not the same exercise | — |

Exercises with no movement group offer no swaps. Groups are editable in
the exercise library.

## Scopes (program slots)

| Scope | Program slot | Reverts? | Progression state |
|---|---|---|---|
| **Just this session** (default) | Untouched | — | Slot ungraded that day; a skipped peak counts as a stall |
| **Rest of this cycle** | Renamed | Automatically at the next rollover, with a History note | Carries across; the week-3 grade banked under the substitute applies to the slot |
| **Whole program** | Renamed permanently | Never (clears any pending cycle revert) | Carries across |

Re-swapping mid-cycle keeps the **first** original as the revert target.
Off-program exercises have no slot; their swaps are inherently
session-only and skip the dialog.

## Session fix-ups on swap

- Per-side (unilateral) flags follow the new exercise.
- Equipment change to non-barbell: the warmup ramp is removed (sets
  renumbered). Equipment change to barbell: a ramp is generated from the
  planned weight.
- Logged working sets are never modified.

## Platform scope

The swap gesture is iOS-only. The resulting program state (including
pending cycle reverts) is honored identically on web — it travels in
backups — and web users can achieve permanent swaps via the program
editor (remove/re-add).
