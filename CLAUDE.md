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

## Housekeeping

- Never commit: `Comeback.xcodeproj` (generated), `.build/`, `DerivedData/`,
  secrets/API keys of any kind.
- Run `swift test` in `ComebackCore/` before pushing when Swift is available.
- Keep CI green on `main`; broken `main` blocks all releases.
- GitHub Actions runners deprecate Node versions periodically — bump
  `actions/*` versions when CI warns.
- Conventional Commits everywhere, including merge commits where practical.
