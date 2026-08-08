# Programming defaults

Program setup is history-first and incremental. You do not have to enter every
training max and accessory load before trying a new program, and a loaded slot
does not silently arrive blank.

## Resolution order

| Slot | First choice | Second choice | No-history fallback |
|---|---|---|---|
| Main lift | Best completed working-set e1RM for the named history exercise | — | Conservative exercise/type load and e1RM |
| Accessory with a methodology fraction | That fraction of its completed-set e1RM | — | Conservative exercise/type load |
| Other loaded accessory | Most recent completed working weight | — | Conservative exercise/type load |
| Bodyweight, band, timed, conditioning | Its native reps/time/effort progression | — | 0 lb |

Derived percentage loads round **down** to the program's plate step and never
below the safe fallback. A conjugate special exercise can point at the matching
competition lift for its initial e1RM without changing the saved exercise name.

The defaults catalog is application reference data. It is not a body
measurement, estimated athlete capability, workout record, or exported profile
field. Once you perform and bank the movement, that actual history takes
priority the next time a template is created.

## Conservative equipment fallbacks

| Slot/equipment | Load | Placeholder e1RM | Default step |
|---|---:|---:|---:|
| Main barbell | 45 | 65 | 5 |
| Main dumbbell (per implement) | 10 | 20 | 5 |
| Main kettlebell | 15 | 25 | 5 |
| Main machine | 20 | 35 | 5 |
| Accessory barbell | 20 | 30 | 5 |
| Accessory dumbbell (per implement) | 5 | 10 | 2.5 |
| Accessory kettlebell | 10 | 20 | 5 |
| Accessory machine | 10 | 20 | 5 |
| Bodyweight / band / timed / conditioning | 0 | 0 | 0 |

Exercise-specific overrides make the generic numbers more useful. The bundled
catalog currently includes:

| Movement | No-history load | Step |
|---|---:|---:|
| Y-T-W Raises / Rear Delt Fly | 5 per dumbbell | 2.5 |
| DB Overhead Triceps Extension | 5 per dumbbell | 2.5 |
| KB Swing / Goblet Squat | 15 | 5 |
| Snatch / Overhead Squat | 35 | 5 |
| Deadlift | 65 | 5 |
| Barbell Row / Snatch Pull / Clean Pull | 45 | 5 |
| Face Pulls / Triceps Pushdown | 10 | 5 |
| Lat Pulldown / Lying Leg Curl | 20 | 5 |

These are intentionally suggestions, not claims about what a lifter *should*
use. Correct the first workout to match the implement, machine stack, range of
motion, and current ability. Later template creation will reuse the record.

Standalone program files remain explicit, portable plans: import preserves the
author's supplied weights and touches only program data. In the interactive
editor, newly added slots use the same history-first resolution and defaults
catalog as bundled templates.
