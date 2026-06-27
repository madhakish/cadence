# Cadence — Project Instructions

Repo for **Comeback**, a native iOS workout-tracking app (SwiftUI + SwiftData,
iOS 17+, single user, local-first — no backend, no accounts). The repo is named
Cadence; the app target, module, and bundle are named Comeback. Migrated here
from its temporary home in the-greenhouse repo.

## Layout

| Path | Purpose |
|------|---------|
| `project.yml` | XcodeGen spec. `xcodegen generate` produces `Comeback.xcodeproj` (gitignored — never commit it) |
| `ComebackCore/` | Pure-Swift package: plate math, program engine, warmup ramp, PR detection, units. ALL testable logic lives here |
| `ComebackCore/Tests/` | Unit tests, including `CompileRegressionTests.swift` (see below) |
| `Comeback/` | App target: SwiftUI views, SwiftData `@Model` classes, services, seed data |
| `.github/workflows/ci.yml` | CI + release pipeline |
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
- Never hand-bump versions. (`MARKETING_VERSION` in `project.yml` is currently
  static; the released tag/filenames carry the real version.)
- Scopes are fine: `fix(ci):`, `feat(release):`, etc.
- Avoid `#word` tokens in commit messages (e.g. write "the Predicate macro",
  not "#Predicate") — the release-notes generator parses them as issue
  references and emits bogus "closes #…" links.

## Build & Test

- **Core logic (any OS, including Linux):** `cd ComebackCore && swift test`.
  ComebackCore must stay Foundation-only so it keeps building and testing on
  Linux — no SwiftUI/SwiftData/UIKit/HealthKit imports in the package.
  Darwin-only tests go behind `#if canImport(Darwin)`.
- **App (Mac with Xcode 15+ only):**
  `brew install xcodegen && xcodegen generate && open Comeback.xcodeproj`.
- This environment has no Apple toolchain; CI is the compiler. Expect to
  iterate via Actions logs when touching app-target code.

## CI & Releases (`.github/workflows/ci.yml`)

Three jobs on push to `main` (first two also on PRs):

1. `core-tests` — `swift test` in the `swift:5.10` Linux container.
2. `app-build` (macos-latest) — `swift test` on Darwin, XcodeGen, Release
   builds for iOS Simulator and unsigned device, uploads the
   `Comeback-installer` artifact (`Comeback-unsigned.ipa` +
   `Comeback-simulator.app.zip`).
3. `release` — only on green `main` pushes: semantic-release tags the next
   version, creates the GitHub Release, and attaches the version-stamped
   installer files from the same run's artifact.

The `.ipa` is unsigned (no signing certs in CI) — it must be re-signed to
sideload (AltStore/Sideloadly). TestFlight distribution would need an Apple
Developer account + fastlane and is not set up.

## Compile failures become tests

Every compile failure found in CI gets its root cause captured in
`ComebackCore/Tests/ComebackCoreTests/CompileRegressionTests.swift` as a
minimal fixture that stops compiling (or fails) if the pattern returns.
Existing entries — don't reintroduce these patterns:

- A computed property body whose first token is `set` parses as a setter
  declaration when the type has a property named `set`; qualify with `self.`.
- SwiftData/Foundation `#Predicate` cannot reference a property of a captured
  object (`track.exerciseName`); hoist the value into a local `let` first.
- `Weight.trim` must strip trailing zeros at any precision (runtime, not
  compile — caught by the Linux test job on the first ever run).

## App conventions

- **All weights stored canonically in pounds (`Double`).** kg exists only at
  entry/display boundaries via `Weight`/`UnitDisplay` in ComebackCore.
- New computational logic goes in ComebackCore with tests, not in views.
- SwiftData models live in `Comeback/Models/`; seed data in `Seed/Seeder.swift`
  encodes real training history — don't casually regenerate it.
- HealthKit is optional and write-only by design; the app reads nothing.

## Workout Program (adaptive progression)

A structured plan layered on top of the per-lift cycle engine. There are now two
progression systems: standalone `LiftTrack`s (independent per-lift cycles, the
"Next up"/Progression list) and a **Program** that bundles training days.

- **Model** (`Comeback/Models/ProgramModels.swift`, mirrored as the embedded
  `programs` IndexedDB store in `web/js/db.js`): `Program` (focus, cycleNumber,
  currentWeek 1–4, nextDayIndex, roundingLb, isActive) → `ProgramDay` (name, order)
  → `ProgramLift` (main/complementary, baseWeightLb, estimatedMaxLb, stallCount) +
  `ProgramAccessory` (sets, min/max/currentReps, weightLb, incrementLb). The
  program owns its lifts' state and drives ONE 4-week wave; program lifts are
  filtered out of the standalone "Next up" and are NOT advanced as `LiftTrack`s.
- **Adaptive engine** lives in `ComebackCore/Sources/ComebackCore/ProgramProgression.swift`,
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

## Housekeeping

- Never commit: `Comeback.xcodeproj` (generated), `.build/`, `DerivedData/`,
  secrets/API keys of any kind.
- Run `swift test` in `ComebackCore/` before pushing when Swift is available.
- Keep CI green on `main`; broken `main` blocks all releases.
- GitHub Actions runners deprecate Node versions periodically — bump
  `actions/*` versions when CI warns.
- Conventional Commits everywhere, including merge commits where practical.
