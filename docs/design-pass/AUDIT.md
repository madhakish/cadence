# Design-pass audit

Scope: issues #177–#187, implemented as one cohesive pass because the shared
plate renderer, live exercise hierarchy, and proof fixture have to agree in one
tree. iPhone is the primary surface; web follows the same information and data
contracts.

## Surface and ownership matrix

| Surface | Native | Web | Shared source of truth |
| --- | --- | --- | --- |
| Main session | `Cadence/Views/ActiveSessionView.swift` | `web/app/js/views/session.js` | persisted `WorkoutSession` / set load |
| Plate calculator | `Cadence/Views/PlateCalculatorView.swift` | `web/app/js/views/plates.js` | solver `PlateSolution` / entered-stack `PlateSolution` |
| Plate renderer and totals | `Cadence/Views/BarbellView.swift` | `web/app/js/barbell.js` | plate/bar metadata + solver result |
| Exercise information | `Cadence/Views/LibraryView.swift` | `web/app/js/views/settings.js` and session sheet | resolved prescription and program slot |
| Muscle figure | `Cadence/Views/AnatomyFigureView.swift` | `web/app/js/anatomy.js` | exercise primary/secondary muscle IDs |
| Settings | `Cadence/Views/SettingsView.swift` | `web/app/js/views/settings.js` | existing settings, gym, exercise, and program models |
| Ad-hoc work | `Cadence/Views/ActivityQuickLogView.swift` | `web/app/js/views/activity.js` | #167 `ActivityDetail` + canonical conditioning set |
| Ad-hoc history | `Cadence/Views/HistoryView.swift` | `web/app/js/views/history.js` | the normal all-time `WorkoutSession` timeline |

## Canonical data map

| Concern | Native | Web |
| --- | --- | --- |
| Plate denomination, unit, colour token, diameter, thickness | `CadenceCore/Sources/CadenceCore/Plates.swift` | `web/app/js/core.js` |
| Solver and `PlateSolution` / `Loadout` | `CadenceCore/Sources/CadenceCore/PlateMath.swift` | `web/app/js/core.js` |
| Weight conversion and exact trimming | `CadenceCore/Sources/CadenceCore/Units.swift` | `web/app/js/core.js` |
| Theme, radius, motion, semantic colours | `Cadence/Views/Theme.swift` | `web/app/styles.css` |
| Gorilla source assets | `Cadence/Assets.xcassets/VitruvianFront.imageset/vitruvian-front.jpeg`, `Cadence/Assets.xcassets/VitruvianBack.imageset/vitruvian-back.jpeg` | `web/app/assets/vitruvian-front.jpeg`, `web/app/assets/vitruvian-back.jpeg` |
| Deterministic proof state | `Cadence/Seed/VisualProofSeed.swift` | web smoke-test fixture setup |

Gorilla web asset SHA-256 before and after:

- front: `ec95ffe80e86263a441f31e01e7e5fcf6b9312d3b2d7a3e6fc3a9ae36bfd1006`
- back: `940bbc7bf72794778d3304d226cf5ca3d265e68985bc0ffa72cb198c743a51f5`

The source rasters were not edited. Native asset-catalog copies and web copies
remain byte-identical within each pose.

## Baseline renderer inventory

- Native plates were drawn by `BarbellView`; callers could ask it to solve again
  from a target, which allowed a view to disagree with a previously selected
  loadout.
- Web plates were drawn by `barbellSVG`; calculator and session callers did not
  consistently pass an already selected solution.
- Compact per-set and calculator presentations lived in those same modules but
  used different geometry and totals treatment.

The pass keeps one renderer module per surface and makes a complete
domain-owned `PlateSolution` its only input. The renderer cannot accept a
target or inventory, so it cannot sort, sum, substitute, or solve. Reverse mode
constructs one `PlateSolution` from the entered stack in the user's exact
collar-to-sleeve order and never invokes the target solver.

## Ranked baseline problems

1. The active session did not answer current exercise, current set, load, plates,
   and next action in one glance; progress and secondary controls competed with
   the work.
2. Plate graphics were too small and partial to verify a mixed-unit load. Totals
   did not consistently distinguish requested, achieved, bar, per-side stack,
   collars, and difference.
3. Callers could re-solve for display instead of drawing the solver's chosen
   stack, creating a path for the diagram and recorded load to diverge.
4. Warmup, completed, current, and upcoming sets lacked a sufficiently strong,
   stable visual hierarchy for between-set use.
5. Exercise information mixed immediate prescription, history, anatomy, and
   programming detail at the same weight. Complementary focus provenance was
   difficult to scan.
6. Settings were a long implementation-order list. Bar unit, plate denomination,
   defaults, and per-exercise overrides were not explained together.
7. The Vitruvian gorilla sat inside a hard rectangular image boundary and muscle
   labels were less useful for keyboard, focus, and tap exploration.
8. The web shell briefly painted the old Memento palette before loading the
   persisted Carbon default.
9. #167's typed wood-splitting record had no purpose-built iPhone entry/edit
   flow, so hard physical work could not be logged without pretending it was a
   program workout.

## Settings-key disposition

| Persisted setting | Section | Presentation |
| --- | --- | --- |
| `themeNameRaw` / `theme` | Appearance & accessibility | theme choice |
| `unitDisplayRaw` / `unitDisplay` | Units & loading | three-value display choice |
| `mainCompoundRestSeconds` / `rest.mainCompoundSeconds` | Training behavior | Rest guidance stepper |
| `olympicRestSeconds` / `rest.olympicSeconds` | Training behavior | Rest guidance stepper |
| `mainUpperRestSeconds` / `rest.mainUpperSeconds` | Training behavior | Rest guidance stepper |
| `secondaryRestSeconds` / `rest.secondarySeconds` | Training behavior | Rest guidance stepper |
| `accessoryRestSeconds` / `rest.accessorySeconds` | Training behavior | Rest guidance stepper |
| `autoStartRest` | Training behavior | switch |
| `haptics` | Training behavior | switch |
| `gymTagFirstLaunchOfDay` | Training behavior | switch |
| `birthYear` | Training behavior | bounded year choice with purpose stated |
| `healthKitEnabled` | Training behavior | native Health write permission switch |
| device-local Health read preference | Training behavior | native Health comparison switch; excluded from backups |
| `seededAt`, `restSeedStampsCleared`, `loadSemanticsMigrated`, `verticalPullMainsPromoted` | Internal migration state | deliberately not exposed as controls |

Gym bars, plates, collars, loading policy, barcode, programs, tracks, intervals,
exercise overrides, and backup checkpoints are their own existing persisted
models. Settings links to their editors in the matching task section instead of
copying them into new preference keys.

## Capture and verification

The `CadenceVisualProof` scheme launches an isolated in-memory store containing
a mixed kg-on-lb bar, warmup/current/upcoming set states, previous performance,
a complementary hypertrophy slot, and a long wood-splitting activity. The
`iPhone visual proof` workflow captures the home, ad-hoc form, active session,
exercise pane, anatomy, calculator, expanded bar, Settings, and History surfaces.
It cannot read or mutate a user's store.

The comparison baseline is not a reconstruction. A proof-only workflow checks
out pre-pass commit `1bdcc3d68ac5eb51b352ddddb0f98cf25e4dfa5c`, injects only
an in-memory fixture and UI-test target, and captures its unmodified production
views on the same iPhone simulator. That instrumentation is removed after the
baseline artifact is committed.

Web verification runs from `web` with `npm test`. Native core, migration, device
build, and visual proof run in GitHub Actions because the repository's local
Linux workspace has no Xcode runtime.
