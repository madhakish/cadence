# Cadence — Project Instructions

Repo and app are both named **Cadence**. Single-user, local-first workout-tracking
app (no backend, no accounts). Migrated here from its temporary home in the-greenhouse
repo (previously alpha-named Comeback).

It ships as **two apps that share one brain**: a **native iOS app** (SwiftUI +
SwiftData, iOS 17+) and a **web PWA** (`web/` — vanilla JS, IndexedDB, no build
step; the live daily driver at `madhakish.github.io/cadence/`). ALL computational
logic lives in `CadenceCore` (pure Swift, Foundation-only, Linux-testable) and
is **mirrored 1:1 in `web/js/core.js`** with identical tests (XCTest ≡ the node
suite). That parity is non-negotiable — it's why the two apps can't drift.

## Layout

| Path | Purpose |
|------|---------|
| `project.yml` | XcodeGen spec. `xcodegen generate` produces `Cadence.xcodeproj` (gitignored — never commit it) |
| `CadenceCore/` | Pure-Swift package: plate math, program engine, warmup ramp, PR detection, units. ALL testable logic lives here |
| `CadenceCore/Tests/` | Unit tests, including `CompileRegressionTests.swift` (see below) |
| `Cadence/` | Native app target: SwiftUI views, SwiftData `@Model` classes, services, seed data |
| `web/` | Web PWA: `js/core.js` (mirror of CadenceCore), `js/db.js` (IndexedDB), views, service worker. No build step |
| `web/tests/` | `core.test.mjs` (parity checks vs XCTest) + `smoke.test.mjs` (jsdom + fake-indexeddb) + `fixtures/synthetic-backup.json` (broad-coverage dataset; regenerate with `web/tools/generate-synthetic-backup.mjs`, restores into BOTH apps) |
| `fastlane/`, `docs/TESTFLIGHT.md` | Mac-free TestFlight pipeline (dormant until configured) |
| `.github/workflows/ci.yml`, `pages.yml` | CI + release pipeline; web tests + Pages deploy |
| `.releaserc.json` | semantic-release config |

## Conventional Commits — REQUIRED

Releases are fully automated by semantic-release; commit messages on `main`
ARE the version-bump and changelog mechanism. Use them correctly:

| Prefix | Effect on release |
|--------|-------------------|
| `fix:` | patch bump (x.y.Z) |
| `feat:` | minor bump (x.Y.0) |
| `feat!:` / `BREAKING CHANGE:` footer | major bump (X.0.0) |
| `docs:`, `ci:`, `chore:`, `refactor:`, `test:`, `style:` | no release |

- Never hand-create `v*` tags or GitHub Releases — semantic-release owns them.
- Never hand-bump versions. (`MARKETING_VERSION` in `project.yml` is only a
  fallback; the TestFlight `beta` lane stamps `CFBundleShortVersionString` from
  the released `v*` tag via `APP_VERSION`, so builds track the semantic version
  1:1, and the sideload release filenames carry it too. Build number is
  `latest_testflight_build_number + 1`.)
- Scopes are fine: `fix(ci):`, `feat(release):`, etc.
- Avoid `#word` tokens in commit messages (e.g. write "the Predicate macro",
  not "#Predicate") — the release-notes generator parses them as issue
  references and emits bogus "closes #…" links.

## Build & Test

- **Core logic (any OS, including Linux):** `cd CadenceCore && swift test`.
  CadenceCore must stay Foundation-only so it keeps building and testing on
  Linux — no SwiftUI/SwiftData/UIKit/HealthKit imports in the package.
  Darwin-only tests go behind `#if canImport(Darwin)`.
- **App (Mac with Xcode 15+ only):**
  `brew install xcodegen && xcodegen generate && open Cadence.xcodeproj`.
- This environment has no Apple toolchain; CI is the compiler. Expect to
  iterate via Actions logs when touching app-target code.

## CI & Releases (`.github/workflows/ci.yml`)

Four jobs on push to `main` (the first three also on PRs):

1. `core-tests` — `swift test` in the `swift:5.10` Linux container.
2. `web-tests` — the node parity + smoke suites (`web/tests/`); enforces the
   CadenceCore↔core.js mirror pre-merge.
3. `app-build` (macos-latest) — `swift test` on Darwin, XcodeGen, Release
   builds for iOS Simulator and unsigned device, uploads the
   `Cadence-installer` artifact (`Cadence-unsigned.ipa` +
   `Cadence-simulator.app.zip`).
4. `release` — only on green `main` pushes, gated on ALL of the above
   (including `web-tests` — a tag is never cut while the JS mirror fails):
   semantic-release tags the next version, creates the GitHub Release, and
   attaches the version-stamped installer files from the same run's artifact.
   These four job names are also the checks to require in any `main` ruleset.

The `.ipa` is unsigned (no signing certs in CI) — it must be re-signed to
sideload (AltStore/Sideloadly).

**TestFlight** distribution is scaffolded and fully Mac-free: the `testflight`
job runs `fastlane beta` (`fastlane/Fastfile`) on the macOS runner to sign and
upload. It's **dormant** until you set the repo variable `TESTFLIGHT_ENABLED=true`
and add the Apple secrets — see `docs/TESTFLIGHT.md`. Signing uses an App Store
Connect API key + `fastlane match` (certs in a private repo); never commit the
`.p8`, PAT, or `MATCH_PASSWORD`.

## Compile failures become tests

Every compile failure found in CI gets its root cause captured in
`CadenceCore/Tests/CadenceCoreTests/CompileRegressionTests.swift` as a
minimal fixture that stops compiling (or fails) if the pattern returns.
Existing entries — don't reintroduce these patterns:

- A computed property body whose first token is `set` parses as a setter
  declaration when the type has a property named `set`; qualify with `self.`.
- SwiftData/Foundation `#Predicate` cannot reference a property of a captured
  object (`track.exerciseName`); hoist the value into a local `let` first.
- `Weight.trim` must strip trailing zeros at any precision (runtime, not
  compile — caught by the Linux test job on the first ever run).
- A large SwiftUI `ViewBuilder` closure holding a `let` binding plus a
  many-argument view call can exceed the type-checker's budget ("unable to
  type-check this expression in reasonable time") — hoist the content into a
  computed property and do lookups via plain helper funcs. Not expressible as
  a CadenceCore fixture (no SwiftUI in the package); pattern hit in
  ActiveSessionView's List.

## App conventions

- **All weights stored canonically in pounds (`Double`).** kg exists only at
  entry/display boundaries via `Weight`/`UnitDisplay` in CadenceCore.
- New computational logic goes in CadenceCore with tests, not in views.
- SwiftData models live in `Cadence/Models/`; seed data in `Seed/Seeder.swift`
  encodes real training history — don't casually regenerate it.
- HealthKit is optional and write-only by design; the app reads nothing.
- **One workout Live Activity** (Lock Screen + Dynamic Island): a session
  stopwatch (elapsed + current lift) that swaps to the rest countdown +
  Pause/+0:30/End while resting. The contract, controller, and App Intents
  live in `Cadence/LiveActivity/` and are compiled into BOTH the app and the
  `CadenceWidgets` extension (one definition across processes); the rest
  state math is `RestClock` in CadenceCore, mirrored as `restClock*` in
  `web/js/core.js`. Quick rest control (start/skip) is `ToggleRestIntent` —
  exposed via App Shortcuts (Action Button, Siri) and an iOS 18 Control
  Center control. Deliberate: no volume/mute-button hijacking.

## Workout Program (adaptive progression)

A structured plan layered on top of the per-lift cycle engine. There are now two
progression systems: standalone `LiftTrack`s (independent per-lift cycles, the
"Next up"/Progression list) and a **Program** that bundles training days.

- **Model** (`Cadence/Models/ProgramModels.swift`, mirrored as the embedded
  `programs` IndexedDB store in `web/js/db.js`): `Program` (focus, cycleNumber,
  currentWeek 1–4, nextDayIndex, roundingLb, isActive) → `ProgramDay` (name, order)
  → `ProgramLift` (main/complementary, baseWeightLb, estimatedMaxLb, stallCount) +
  `ProgramAccessory` (sets, min/max/currentReps, weightLb, incrementLb). The
  program owns its lifts' state and drives ONE 4-week wave; program lifts are
  filtered out of the standalone "Next up" and are NOT advanced as `LiftTrack`s.
- **Adaptive engine** lives in `CadenceCore/Sources/CadenceCore/ProgramProgression.swift`,
  mirrored 1:1 in `web/js/core.js` with identical assertions in
  `ProgramProgressionTests.swift` and `web/tests/core.test.mjs`. It is pure and
  deterministic — it consumes a performance *summary*, never a session or a clock.
  - `gradeCycle`: SUCCESS only on a clean Peak (all sets at target reps, no
    stopped-early/dropped-load, ≤`QUALITY_FLAG_TOLERANCE` grindy/wobble); else HOLD/FAIL.
  - `taperedIncrement`: a fraction of base × headroom to a focus-dependent ceiling
    (`estimatedMax × tmFraction`), floored at plate granularity, 0 at/over the ceiling.
  - `advanceCycleLift`: clean → tapered bump; non-success → stall, and at
    `STALL_LIMIT` (2) auto-deload by `DELOAD_REBUILD_FRACTION` (−10%) with a note.
  - `advanceAccessory`: weighted → double progression (earn the rep range, add load,
    reset); bodyweight (`incrementLb <= 0`) → keep adding reps (maxReps advisory).
  - Training focus (strength/hypertrophy/maintain) sets the ceiling + increment;
    maintain never increments. Don't add nondeterminism to these functions.
- **Generation + rollover**: `ProgramSession.make` / web `createSessionFromProgramDay`
  build a tagged session (program/cycle/week/day + per-exercise role). Completion
  (`SessionCompletion.swift` / web `completeSession`) grades each lift at the
  **week-3 Peak** into a pending result and APPLIES it at the deload week's end
  (rollover: cycle++, week→1, deload/ceiling notes written as `programNote`
  milestones). Accessories double-progress every bank.

## Design principles

The app holds an opinion about training; these constraints keep it coherent.

- **Adherence dominates outcome.** A simple, consistent plan gets executed.
  Complexity lives *inside* the autoregulation, triggered by data — never exposed
  as knobs.
- **Guide, don't interrogate.** Minimize inputs; pre-fill everything predictable
  (a program day pre-fills weight/sets/reps for one-tap confirm); every required
  tap must earn itself.
- **Knows when it doesn't know.** Prefer logging silently when confident and
  asking one light question when not. Wrong auto-detection is worse than manual
  entry — it corrupts the log.
- **The program is the prior.** A known plan collapses "which of 470 exercises"
  into "which of today's five." Lean on it.
- **n=1.** Built for one user, ~30 movements, one gym. Refuse speculative
  generality; generalize later from a working app + real data.
- **Logic in CadenceCore, pure + tested + mirrored to JS.** Platform I/O
  (HealthKit, IndexedDB/SwiftData, sensors) stays at the edges so the reasoning
  is deterministic and unit-testable.

## Roadmap

Build order is deliberately easy-first — never build the hard sensor-fusion
thing before there's a working, distributed app.

- **Phase 0 — simple logger + clear the Apple pipeline.** ~Done: the logger is
  live (web) and the TestFlight pipeline is wired (dormant — see
  `docs/TESTFLIGHT.md`). Deliverable is the credential + template, not revenue.
- **Phase 1 — Program Engine + Readiness Engine.**
  - Program Engine: **built** (adaptive progression above). Today's autoregulation
    is *in-session only* (quality flags + dropped-load), not yet RPE/RIR shifting
    with *pre-session* readiness.
  - Readiness Engine: **not built.** Pivotal change — it needs **HealthKit READ**
    (HRV, resting HR, sleep, respiratory rate, wrist temp), reversing the current
    write-only stance; **native-only** (the web PWA can't read Apple Health).
    Encode the math as **pure CadenceCore functions** (Banister fitness-fatigue,
    acute:chronic workload ratio, MEV/MAV/MRV volume landmarks, RPE/RIR), with
    constants **refit to the user's own data** (population norms transfer poorly).
    Ship it as a **gentle nudge first** (RPE ±0.5, go/hold — never a dramatic
    override) and **watch before it prescribes**: show the score would have been
    right before it's allowed to move load.
- **Phase 1.5 — durability + reach (planned).** Auto-backup first (scheduled
  export of the bundle: iCloud/Files on iOS, download/File System Access on
  web) so nobody loses data; then an **online portal** — login, synced app
  data, and a bigger-screen UI for program/preference management. This
  deliberately reverses the "no backend, no accounts" stance; the backup
  bundle is already the cross-platform interchange and is the natural sync
  payload. An **Android app** is also planned — before the portal, decide how
  core logic ships to a third platform (Kotlin mirror vs a compiled shared
  core), because the 1:1-mirror discipline gets expensive at three copies.
- **Phase 2 — ambient capture.** Geofence → `HKWorkoutSession` → set/rest
  detection → wrist-IMU exercise classification *under the day's program as a
  strong prior* (5-way, not 470-from-scratch) → load **predicted** from program +
  last session (unobservable from the wrist; not passive). Far off; watchOS.

Open questions to resolve while building Phase 1: HRV/sleep/RHR/temp weighting +
the user's personal baselines; deload trigger (scheduled vs readiness vs hybrid)
and its hysteresis; confirming watchOS high-rate capture needs an active
`HKWorkoutSession`; the confidence threshold for silent-log vs ask.

## Housekeeping

- Never commit: `Cadence.xcodeproj` (generated), `.build/`, `DerivedData/`,
  secrets/API keys of any kind.
- Run `swift test` in `CadenceCore/` before pushing when Swift is available.
- Keep CI green on `main`; broken `main` blocks all releases.
- GitHub Actions runners deprecate Node versions periodically — bump
  `actions/*` versions when CI warns.
- Conventional Commits everywhere, including merge commits where practical.
