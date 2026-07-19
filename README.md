# Cadence

A local-first logbook for structured strength training. Two apps sharing one
brain: native iOS (SwiftUI + SwiftData, iOS 17+) and a web PWA
([madhakish.github.io/cadence](https://madhakish.github.io/cadence/)).
Single user, local-first. No backend, no accounts, no streaks, no badges,
no quotes.

**User documentation** (tutorials, how-to guides, reference) lives in
[docs/](docs/README.md) — start with
[Build your first program](docs/tutorials/first-program.md) or
[pick a pre-programmed style](docs/how-to/start-from-a-style.md).

## What it does

- **Plate math calculator** — the killer feature, one tap from anywhere
  (floating button over every tab). Target in lb *or* kg → per-side loading
  from the gym's actual plate inventory, mixed kg/lb on the same side,
  achieved total shown in both units, warning when off target by > 2 lb.
  Reverse mode: tap in what's on the bar, get the total.
- **Program engine** — 4-week microcycle per lift (Volume 5×5 → Load 5×3 →
  Peak 3×3 → Deload 3×5), offset-based strength waves, double progression,
  optional primers/top singles, and rotation-first readiness. Each lift keys
  off completed performed work, never the calendar. Rack-aware targets keep
  the theoretical prescription, achieved load, and final performed load
  separate. Mid-session "Dropping load" uses a pre-computed fallback and logs
  why (bar speed / wobble / joint / heat / fatigue / not there).
- **Session logging** — pre-filled warmup ramps (barbell bar×10 +
  ~40/55/70/85%; main dumbbell ~40/60/80% per hand), add/remove individual
  sets, propagate weight/reps edits across the remaining planned work,
  explicit planned/completed/skipped sets, optional exclusive quality
  (clean/grindy/wobble), independent stopped-early notes, kg or lb entry
  stored canonically in lb, rest timer (5:00 main / 1:30 accessory,
  per-exercise override) with local notification, end-of-session summary
  with volume, top sets, and auto-detected PRs.
- **Body signals** — optional shoulder / hip / knee flags per set, per-site
  timeline, and an optional next-morning knee check-in after running.
- **Body** — private on-device bodyweight chart with optional annotations and
  protein quick-log against a configurable target.
- **Gym tag** — store a photo of the membership keychain barcode per gym;
  shows full-screen at max brightness so the phone is the second tag the
  gym's software can't issue.
- **Settings & export** — units display, multiple gyms with per-gym plate
  inventories, per-lift increments, rest defaults, optional write-only
  HealthKit, full JSON + CSV export.

Fresh installs contain a searchable, categorized library of 141 generic
strength, accessory, bodyweight, Olympic, and conditioning exercises plus a
default gym. Existing installs receive missing generic definitions without
overwriting their edits.
No workout history, body metrics, health signals, program state, or personal
starting weights ship in the repository. Program-style templates are optional
starting points and remain editable before the first session.

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
├── Cadence/                 # App target (SwiftUI + SwiftData)
│   ├── CadenceApp.swift
│   ├── Models/              # @Model classes (canonical lb everywhere)
│   ├── Seed/                # generic exercise seed + program style templates
│   ├── Services/            # notifications, rest timer, completion/PRs,
│   │                        # export, optional HealthKit (write-only)
│   └── Views/               # dark, big targets, terse copy
├── web/                     # Web PWA: core.js mirrors CadenceCore 1:1,
│                            # IndexedDB, no build step, deployed via Pages
└── docs/                    # User documentation (Diátaxis) + TestFlight guide
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

Web tests (the parity + smoke suites that keep `web/js/core.js` in
lockstep with CadenceCore):

```bash
cd web && npm ci && npm test
```

Notes:
- CI always runs portable core/web checks, runs parallel native builds only
  when needed, and reserves full shipped-store migration reconstruction for
  persistence changes. Semantic-release cuts versioned releases with
  installable artifacts; see `CLAUDE.md` for the safety contracts and
  `docs/TESTFLIGHT.md` for TestFlight distribution and recovery.
- HealthKit is optional: the capability is declared, the toggle lives in
  Settings, and the app only ever writes (workouts + bodyweight).
- All weights are stored in lb (`Double`). kg exists only at entry/display.
