# Cadence

A local-first logbook for structured strength training. Two apps sharing one
brain: native iOS (SwiftUI + SwiftData, iOS 17+) and a web PWA.
Single user, local-first. No backend, no accounts, no streaks, no badges,
no quotes.

- **Product site** — [madhakish.github.io/cadence](https://madhakish.github.io/cadence/)
- **Web app** — [madhakish.github.io/cadence/app/](https://madhakish.github.io/cadence/app/)
- **iOS** — TestFlight beta or build it yourself; see
  [the iOS page](https://madhakish.github.io/cadence/ios.html) and
  [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)

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
- **Program engine** — three completed progression rotations per mesocycle
  (Volume 5×5 → Load 5×3 → Peak 3×3), followed by a two-exposure Recovery
  bridge (one lower, one upper; main work 2×3), offset-based strength waves,
  double progression,
  optional primers/top singles, and rotation-first readiness. Each lift keys
  off completed performed work, never the calendar. Rack-aware targets keep
  the theoretical prescription, achieved load, and final performed load
  separate. Mid-session "Dropping load" uses a pre-computed fallback and logs
  why (bar speed / wobble / joint / heat / fatigue / not there).
- **Session logging** — pre-filled warmup ramps (loaded steps for back squats/deadlifts; bar×10 +
  ~40/55/70/85%; two bridging steps for complementary lifts after the day's
  main; main dumbbell ~40/60/80% per hand), add/remove individual
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
  inventories, per-lift increments, rest defaults, optional HealthKit (write
  workouts/bodyweight, and separately compare conditioning distance against
  Health), full JSON + CSV export.

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
│   │                        # export, optional HealthKit (write + compare)
│   └── Views/               # dark, big targets, terse copy
├── web/                     # Everything GitHub Pages serves (no build step)
│   ├── index.html           # Product site: overview, guide, iOS/beta, privacy
│   ├── site/site.css        # Site styling (the app's Memento tokens)
│   ├── sw.js                # Retirement worker for the app's former root scope
│   ├── app/                 # The PWA itself, served at /cadence/app/
│   │   ├── js/core.js       # Mirrors CadenceCore 1:1
│   │   ├── js/db.js         # IndexedDB + backup contract
│   │   └── sw.js            # Offline app shell
│   ├── tests/               # Parity, migration, smoke, and site-structure suites
│   └── tools/               # Fixture generators
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

Web tests (the parity + smoke suites that keep `web/app/js/core.js` in
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
- HealthKit is optional and in two separately granted halves, both off by
  default: writing (workouts + bodyweight), and reading walking/running/cycling
  distance to show beside a logged session. Reading never overwrites a log —
  it shows both numbers and you choose.
- All weights are stored in lb (`Double`). kg exists only at entry/display.

## Contributing

Bug reports and feature ideas are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for what makes a useful one, and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Security issues go through
[private reporting](https://github.com/madhakish/cadence/security/advisories/new),
not the public tracker.

Outside pull requests are not accepted; the license grants no right to publish
derivative works. A good report is worth more here than a patch.

Anyone working inside the repository — including coding agents — should start
with [AGENTS.md](AGENTS.md), the canonical guide to the migration protocol, the
native/web parity contract, and the definition of done.

## License

Copyright (c) 2026 madhakish. All rights reserved — see [LICENSE](LICENSE).
The source is published for reference and review; it is **not** open source.
You may read it and build it for your own personal use. You may not
redistribute it or publish a derivative work.

Cadence is a training logbook, not a medical device and not a coach.
