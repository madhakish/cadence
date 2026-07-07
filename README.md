# Cadence

A coach's logbook for a structured barbell comeback. Native iOS (SwiftUI +
SwiftData), iOS 17+, single user, local-first. No backend, no accounts, no
streaks, no badges, no quotes.

## What it does

- **Plate math calculator** — the killer feature, one tap from anywhere
  (floating button over every tab). Target in lb *or* kg → per-side loading
  from the gym's actual plate inventory, mixed kg/lb on the same side,
  achieved total shown in both units, warning when off target by > 2 lb.
  Reverse mode: tap in what's on the bar, get the total.
- **Program engine** — 4-week microcycle per lift (Volume 5×5 → Load 5×3 →
  Peak 3×3 → Deload 3×5), each lift on its own track keyed to its last
  completed session, never the calendar. +10 lb/cycle lower, +5 upper.
  Suggestions are editable in two taps; mid-session "Dropping load" recalcs
  remaining sets and logs why (bar speed / wobble / joint / heat / fatigue).
- **Session logging** — pre-filled warmup ramp (bar×10, ~40/55/70/85%),
  per-set quality flags (clean/grindy/wobble/stopped early), kg or lb entry
  stored canonically in lb, rest timer (5:00 main / 1:30 accessory,
  per-exercise override) with local notification, end-of-session summary
  with volume, top sets, and auto-detected PRs.
- **Injury signals** — body flags on left shoulder / left hip / right knee
  per set, per-site timeline, next-morning knee check-in notification after
  running, swelling = hard-stop banner. Barbell bench ships shelved with its
  re-entry test written down.
- **Body** — bodyweight chart with milestone annotations (168 discharge →
  194 current), protein quick-log vs 175 g target.
- **Gym tag** — store a photo of the membership keychain barcode per gym;
  shows full-screen at max brightness so the phone is the second tag the
  gym's software can't issue.
- **Settings & export** — units display, multiple gyms with per-gym plate
  inventories, per-lift increments, rest defaults, optional write-only
  HealthKit, full JSON + CSV export.

Seeded with the real training history (May 9 – Jun 7, 2026) so charts, PRs,
and next-session suggestions work on first launch: Deadlift → Wk3 Peak 3×3
@ 245, Squat → Wk2 Load 5×3 @ 195, Incline DB linear at 45s.

## Layout

```
.
├── project.yml              # XcodeGen spec → Cadence.xcodeproj
├── CadenceCore/             # Pure-Swift package: all testable logic
│   ├── Sources/CadenceCore/
│   │   ├── Units.swift          # lb↔kg, canonical-lb storage, formatting
│   │   ├── Plates.swift         # plate/bar/loadout types, standard sets
│   │   ├── PlateMath.swift      # mixed-unit solver + reverse mode
│   │   ├── ProgramEngine.swift  # cycle phases, suggestions, autoreg drop
│   │   ├── WarmupRamp.swift     # bar×10 + 40/55/70/85% ramp
│   │   └── PRDetection.swift    # heaviest set / volume PR / first scheme
│   └── Tests/CadenceCoreTests/  # 40+ unit tests
└── Cadence/                 # App target (SwiftUI + SwiftData)
    ├── CadenceApp.swift
    ├── Models/              # @Model classes (canonical lb everywhere)
    ├── Seed/Seeder.swift    # exact training history + program state
    ├── Services/            # notifications, rest timer, completion/PRs,
    │                        # export, optional HealthKit (write-only)
    └── Views/               # dark, big targets, terse copy
```

## Build

Requires a Mac with Xcode 15+.

```bash
brew install xcodegen
xcodegen generate
open Cadence.xcodeproj
```

Run tests (plate math, progression, PR detection, warmup ramp, units):

```bash
cd CadenceCore && swift test
# or run the CadenceCore test plan inside Xcode (⌘U)
```

Notes:
- This was authored in a Linux environment without an Apple toolchain, so it
  has not been compiled yet — expect to fix a handful of compiler nits on
  first build. The core logic is written to be verified by the test suite
  first (`swift test` runs on any Mac, no simulator needed).
- HealthKit is optional: the capability is declared, the toggle lives in
  Settings, and the app only ever writes (workouts + bodyweight).
- All weights are stored in lb (`Double`). kg exists only at entry/display.
