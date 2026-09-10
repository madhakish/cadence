# Cadence quality review and next work — 7 September 2026

Reviewed main `495cb2706da0c8403974d34e672d1512d6dddbc4`, after merging
#202 → #204 → #205 → #201. No open PRs remained at the start of this review.
The follow-up patch fixes two reproduced reporting defects and adds regression
coverage. The larger changes below are recommendations, not implemented features.

## CI and release result

[Combined main CI 34153137173](https://github.com/madhakish/cadence/actions/runs/34153137173)
completed successfully. This is verification of the combined tree, not an
inference from its ingredient PRs.

| Gate | Observed result |
| --- | --- |
| Preflight and path classification | Passed |
| Linux CadenceCore and app Swift syntax | Passed; 423 core tests, zero failures |
| Web parity, runtime, migration, release tooling | Passed |
| Real shipped-store migrations | Passed |
| Signed production artifact and simulator build | Passed |
| Stable macOS aggregate | Passed; separate unsigned device job correctly skipped on this release run |
| Pages deployment | Passed |
| Semantic release and GitHub asset promotion | Passed; published v15.0.0 |
| TestFlight promotion | Passed; App Store Connect accepted the binary at 19:05 UTC |

[v15.0.0](https://github.com/madhakish/cadence/releases/tag/v15.0.0) contains
the signed IPA, its SHA-256 file, and the simulator app. Fastlane deliberately
does not wait for Apple processing; upload success does not prove tester
availability. No additional release was dispatched by this review.

The earlier #204 main run passed and built an artifact, but semantic-release
declined publication after remote main advanced. Its old reconciliation message
incorrectly inferred that the commit was not release-producing. The patch makes
the message state only the observed absence of an exact tag. Publishing rules,
release classification, signatures, promotion, and queue behavior are unchanged.

Keep the fast-test ladder, production SDK checks, migration gates, and immutable
artifact promotion. If release latency becomes a problem, measure time spent on
superseded candidates first. Make verified/built/published/uploaded state visible;
do not weaken checks or treat a green badge as proof of phone delivery.

## Reproduced defects and new tests

1. **Last-session recall disagreed with suggestion provenance.** A synthetic
   workout at 23:55 still said `today` at 00:05. Both native and web recall used
   elapsed-day calculations while provenance already used calendar dates.
   `historyAgeLabel` now owns the existing wording and both consumers reuse it.
   No timestamps, history calculations, prescriptions, or loads change.
2. **Successful untagged release outcome was mislabeled.** A shell fixture with
   an untagged `fix:` commit reproduced the misleading log assertion. The new
   test requires `published=false`, no invented version, and a truthful message.
   Existing tagged recovery and failed-untagged cases still pass.

The web regression opens the real logger with synthetic IndexedDB history in a
fresh America/Chicago process. It covers midnight, spring DST, fall DST, and a
same-day exposure, and verifies that rendering leaves the banked record intact.
Matching Swift/JS assertions cover the today/yesterday/day/week/month boundaries
and the existing future-date clamp. Both new defect tests failed before the fixes.

Local `npm test` passed: 54 invariants / 103 platform assertions, 1,727 core,
66 plate renderer, 51 migration, 129 program-file, 1,241 runtime smoke, six
anatomy groups, rest-duration/build-polish regressions, 233 site, and 64
accessibility contracts. Release reconciliation and whitespace checks also
passed. The new Swift tests require the follow-up PR's Linux/Darwin CI; this
workspace has no Swift/Xcode toolchain. Its exact results belong on the PR.

## Visual assessment

This is a current-source review informed by the repository's historical iPhone
captures. Those captures are explicitly from the older #188 candidate, not
v15.0.0. New app rendering was blocked by the browser's URL security policy,
which also prohibited alternate routes; no workaround was attempted. The approved
anatomy registration proof is not a full app screenshot. Current iPhone and web
visual acceptance therefore remains open in #187.

**Keep:** Foundry as default, Heritage Gold and Titanium options, the exact approved
gorilla and masks, quiet warmups, strong working-set emphasis, grouped Settings,
direct duration entry, and all-time/program-scoped history. The mascot needs no
further redraw. Additional skins are lower value than finishing the daily loop.

**Still weak:**

- **Plate fidelity and legibility (#55, #65, #180–182).** `BarbellView` still uses
  `diameterFactor`/`thicknessFactor`, a 124-point full bar, and rotated 9-point
  labels (5.6 in compact mode). It does consume the exact solver solution, which
  must remain authoritative. The approved realistic 38-degree inspection is
  absent. Exercise views infer bumper versus steel from the Olympic movement
  group; a gym's actual equipment should determine that choice. Add explicit
  physical profiles that distinguish a full-size 5 kg bumper from a 5 kg change
  plate. One plate identity must retain diameter, thickness, style, colour and
  denomination through front/expanded views. Never rebuild the stack in the view.
- **Load typography (#181, #185).** The native summary uses rounded 36/27-point
  numbers with a 0.65 shrink allowance. Use a disciplined type scale, readable
  baseline-aligned units and responsive reflow; avoid progressively shrinking
  load digits. Keep pounds first, kilograms second and bar included. Put the
  selected bar and per-side stack in one direct reading path.
- **Action hierarchy (#185, #196).** Make the current set's completion control a
  clear verb and the easiest thumb target. Rest controls and the next set belong
  beside it. `RootView` still places the global calculator with a fixed bottom
  offset; retain one-tap access but reserve layout space so it cannot cover
  Settings, chart controls or program rows. Prove this with large text and small
  phone captures rather than another padding guess.
- **Exercise selection (#63, #66).** The library has better grouping, but the
  program editor's embedded picker still presents expanded category sections
  with equipment filtering. Bring collapsible categories and movement filtering
  into the actual selection flows, preserve search and preview, and consider
  recent choices before adding a persisted favorites feature.
- **Material and density (#179, #186, #198).** Use subtle surface separation,
  restrained metal/chalk cues and lightly rounded geometry in the working area.
  Reduce stacked containers and competing captions. Prefer useful lifting imagery
  in exercise/equipment context; keep Today focused on the session and arrival
  tag. Preserve native pickers where they work. Avoid a custom-control rewrite.

## Recommended delivery order

### 1. Finish workout progression from the Lock Screen (#200, #197)

This is the highest-value functional change. `WorkoutActivityAttributes.ContentState`
currently carries the lift name and clocks, but no current set identity, ordinal,
load or reps. Intents operate on the activity, not the banked set record.
`EndWorkoutIntent` calls an activity dismissal path; it does not complete the
workout. Adding more buttons over that boundary would leave two meanings of done.

Build one small command path used by app controls and Live Activity intents.
Give commands stable session/set identity and a stale-state guard; persist the
result before projecting it into ActivityKit. Start with complete set → rest,
skip rest → next set, explicit skip set, undo, pause/resume and rest adjustment.
Add bounded load/repetition adjustments only once those transitions are reliable.
Finishing a workout must use the existing banking path. Dismissing its activity
must remain distinct from recording completion.

Decide the warmup policy explicitly: the current hero intentionally previews
working sets while unresolved warmups can keep an exercise active. A Lock Screen
action must say which set it changes. Never auto-credit an unlogged warmup or let
a stale completion button complete the following set.

[Apple's AppIntent authentication policy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)
supports intents running while locked via `alwaysAllowed`.
[Apple's Live Activity interaction guidance](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
requires awaited work and a UI that reflects the result. Validate the actual
Lock Screen presentation, authentication behavior, app relaunch and protected
store access on a physical iPhone; a successful intent unit test is insufficient.

The headphone cue should belong to a rest-completion identity. Native currently
uses the default local notification and foreground haptics; web has an oscillator.
Define one audible completion, correct routing while music plays, and no alert
after skip/cancel. Test Bluetooth headphones, speaker fallback, route changes,
pause/extend, background expiry and foreground return. Do not depend on a
JavaScript or foreground timer continuing to execute while the phone sleeps.

### 2. Land the approved plate experience and finish phone layout

Implement physical profiles before the renderer's geometry. Preserve solver
ordering in reverse entry; any assisted-loading ordering policy belongs upstream,
not in a visual sort. Then finish front-to-inspection motion, readable individual
denominations, the achieved-load baseline, action placement and catalog selection.
Keep geometry invariant when changing view angle or denomination display.

Capture the current build on small and normal iPhones, large Dynamic Type,
Foundry/Gold/Titanium, normal/reduced motion, and representative desktop web.
Include mixed plates on a pound bar, long stacks, change plates, empty bar,
unavailable target, warmups/current/completed/skipped sets and keyboard entry.
Do not close visual issues with source regex tests or old screenshots.

### 3. Make programming inspectable; tighten existing boundaries (#104, #58)

Cadence already has `cadence.program` version 2, independent of backup v13,
with plan/state/identity choices, validation and cross-platform fixtures. It also
has `ProgramEngine.exposurePreview` and a web mirror that run the shipped engine.
Keep those. A second DSL or parallel preview engine would create disagreement.

Add a machine-readable JSON Schema for the existing file contract if external
authoring/editor completion is the next use case. Keep semantic validation for
slot identity, valid schedule pointers, rep windows, partial runtime state and
equipment constraints. A schema cannot replace those checks. Validate schema and
both importers against the same accepted/rejected corpus.

Improve the existing preview into an explanation of authored plan → resolved
prescription → performed record → progression decision. Show the source base or
training max, rounding, equipment limit, resolved effort/focus, upcoming rotation
and the consequence of a clean completion or a miss. Run every scenario through
the real engine. Preserve complementary hypertrophy provenance and cycle semantics.

The concrete abstraction payoff is separating workout mutation from SwiftUI and
ActivityKit, and exposing the existing prescription decisions. Splitting files
solely for line count, generic repositories, strategy factories or an event bus
would be extra machinery without a demonstrated benefit.

### 4. Explain coaching before adding more coaching rules

The deterministic coach already evaluates rotations, distinguishes incomplete
evidence, enforces equipment constraints, records versioned decisions and uses
Apply/Not now. Home's coach sheet shows a recommendation explanation and one
readiness reason, but it could make the full evidence and proposed change easier
to inspect.

Add a compact rotation recap: what was completed, what improved or stalled,
which evidence produced the recommendation, exactly what Apply changes, and why
a decision is provisional or unavailable. Link evidence to performed sessions.
Revalidate proposals against edited program/history state before applying them.
Display evidence coverage instead of inventing a confidence percentage. Evaluate
new programming thresholds against explicit scenarios before changing them.

### 5. Improve analytical questions, not chart count (#155)

History already separates roles and like rotations, offers rep PRs and tonnage,
and has an optional performed-history trend with evidence/staleness refusals.
Program preview is separate from that trend. Retain these distinctions.

Next, make it easy to answer: am I adding load or reps at comparable effort;
where does performed work diverge from the plan; and which lifts stall across
rotations? Annotate program switches, declared breaks, deloads and manual edits.
Compare blocks descriptively with exposure counts and like-for-like load semantics;
do not imply one program caused an improvement from a small personal history.
Keep all-time history and filters, preserve horizontal chart navigation, and keep
conditioning/manual labor in its own measures rather than invented barbell tonnage.

## Next regression gates

| Work | Required behavioral proof |
| --- | --- |
| Workout commands | Duplicate/stale taps, undo, explicit skip, failed save, app relaunch, activity dismissal, no double banking; same result from app and intent |
| Rest cue | Exactly one completion, changed deadline replaces old cue, skip cancels, pause survives relaunch, device audio-route evidence |
| Plate profiles | Full-size 5 kg bumper versus change plate; same identity/diameter through view changes; exact 1.25; mixed inventory; solver/recorded-load parity |
| Program authoring | Shared valid/invalid corpus, legacy versions, unknown enums, partial state, identity collision, transactional rejection; preview uses actual resolution |
| Coaching and history | Stale recommendation after edits, duplicate Apply, evidence lineage, program rename/switch/deletion, performed-versus-plan distinction |
| Visual acceptance | Actual current native/web captures, normal/large text, keyboard and VoiceOver, no covered controls, reduced motion, readable stacks |

Use the existing issues above as the queue. The original design epic #177 remains
open: merged code and a shipped build are progress, not completion of the remaining
plate, Lock Screen and visual acceptance work.
