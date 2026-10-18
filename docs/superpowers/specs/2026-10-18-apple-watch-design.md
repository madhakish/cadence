# Apple Watch app — design

Date: 2026-10-18
Status: draft for owner approval (builder check done; owner answers folded in)
Baseline: main `57cb52f` (SwiftData schema V15, backup schema 16)
Task issue: #329 (owner decisions are recorded in its comments)

## Intent

The owner wants to run an entire lifting session from the wrist and never pick
up the phone: every set of every exercise. The phone stays in a pocket or bag.
On top of that, the watch should learn the wrist-motion "signature" of the
owner's own lifts so that sets complete themselves. It detects when a set ends
and counts the reps, so logging becomes confirming rather than typing.

Success looks like a full program day logged on the watch with the phone never
unlocked, ending as one session in the Cadence log (with PRs and program
progression applied exactly as if it had been logged on the phone) and one
workout in Apple Health carrying real heart rate.

## Owner decisions

These came from the owner and are not open to the builder:

1. **The watch runs the session itself.** It shows the planned work, logs each
   set (reps, load), runs the rest timer and advances to the next exercise. It
   keeps working when the phone is unreachable or the phone app is closed.
2. **Both apps work on their own and share data.** Either device can log a set;
   sets logged on one appear on the other. The session ends as one record and
   one Health workout.
3. **iPhone and watch only.** The web app takes no part in sync.
4. **The watch only runs sessions.** No program, exercise or settings editing
   on the watch beyond what running a session needs.
5. **Heart rate is a small, out-of-the-way reading**, not a feature screen.
6. **Motion-signature autocomplete.** Wrist motion recorded from the owner's own
   sets is used to detect set end and count reps.
7. **Detected sets log automatically and stay editable.** A watch setting
   switches to **tap to confirm** instead.
8. **Effort tags on the rest screen.** After a set logs, the rest screen offers
   two optional rows of large buttons: quality (Clean / Grindy / Wobble) and
   reps in reserve (1 / 2 / 3+). One tap each. Ignoring them leaves the set
   untagged and blocks nothing.
9. **Hardware:** Apple Watch SE (3rd generation), 40 mm. The owner should
   confirm the model and watchOS version.
10. **No server.** Cadence stays local-first: no account, no hosting.
11. **Set kinds in the first version:**
    - full logging for loaded reps, bodyweight reps and timed holds (with a
      hold timer);
    - carries and conditioning logged by duration only. Their distance,
      yards, incline and flights stay phone-side for now.
12. **Health permission on the watch.** The watch may ask for Health permission
    the first time a session starts on it, because that is what keeps it
    running for a full session. Whether anything is *saved* to Health is still
    the phone's existing setting, off by default.
13. **Apple Intelligence is out of scope.** If it is used later, it belongs to
    the iPhone app; nothing on the watch App ID depends on it.

## Goals

- A watchOS app embedded in the Cadence iOS app, bundle ID
  `com.madhakish.Cadence.watchkitapp` (registered, HealthKit capability).
- Manual session running on the watch, synced with the phone in both directions.
- A watch-side workout session that provides heart rate, keeps the app alive
  during the session, and writes the Health workout when Health writing is on.
- Motion recording of real sets, exportable for offline work.
- A rep and set-end detector developed and measured offline against those
  recordings, then run on the watch for exercises that pass the bar.

## Non-goals

- No web app changes and no web sync.
- No program editing, exercise library editing or history browsing on the
  watch.
- No backup format change. Motion recordings are not part of the backup.
- No CloudKit or other cloud sync in this design. If the owner later needs the
  watch to sync while the phone is off, that is a separate design.
- No Apple Intelligence features.

## Anti-goals (would make this a failure even if it works)

- A logged set lost or duplicated by sync. This includes sets logged on the
  watch while the phone was away.
- Two Health workouts for one session.
- An auto-logged set the owner cannot see and fix immediately.
- Auto-logging an exercise whose detector has not been shown accurate on that
  owner's recordings.
- PR detection, progression or milestones computed differently for
  watch-logged sessions than for phone-logged ones.
- Weakening any existing invariant, migration rule or CI gate to make room for
  the watch.

## Constraints from the codebase

- **SwiftData is the system of record on the phone** (`WorkoutSession`,
  `SessionExercise`, `SetEntry`, schema V15). Schema changes need a frozen
  snapshot, a new version, on-disk migration tests and a SemVer major marker
  (AGENTS.md).
- **Sets have no stable identity.**
  - `SetEntry` has no ID.
  - `SessionExercise` has only `exerciseID` and `programSlotID`.
  - Lock Screen commands identify a set by session ID, exercise and set
    position, plus a layout fingerprint, and refuse stale commands
    (`INV-LOCK-SCREEN-SET-IDENTITY`).
  - Positional identity is not safe for offline, two-device editing, because
    users add and remove sets and exercises.
- **Banking** (`SessionCompletion.finish`) does completion, PR detection,
  milestones, program advancement and the Health export in one atomic save. It
  runs only in the iPhone app.
- **Planned sessions** are built in the app (`ProgramSession.make`,
  `TFHSession.make`) against the SwiftData context, not in CadenceCore.
- **The Health workout is written at bank time** by `HealthKitService.saveWorkout`
  from `HealthWorkoutTiming` (`INV-HEALTH-WORKOUT-TIMING`). Writing is gated by
  `AppSettings.healthKitEnabled`, which is off by default. The duplicate filter
  only recognises the phone app's own bundle ID.
- **CadenceCore** is Foundation-only and Linux-testable. Its `Package.swift`
  lists iOS and macOS only. Domain logic is mirrored in `web/app/js/core.js`
  unless marked Swift-only in `docs/reference/parity-map.json`.
- **No App Group** exists. The widget extension does not share the app's store.
- **CI:**
  - `project.yml` targets and schemes, the `swiftc -parse` list in `ci.yml`,
    `classify-ci-paths.sh`, `verify-release-artifact.sh` and the Fastfile
    signing steps all enumerate targets explicitly.
  - The first signed build of a new App ID needs the temporary read-write
    `match` setup (`docs/TESTFLIGHT.md`, step 3), which the owner provides.
- **Hardware:** the SE 3 has an optical heart sensor, accelerometer and
  gyroscope (Apple spec page). It is a 40 mm screen. Whether it supports
  `CMBatchedSensorManager` (high-rate batched motion) is unknown; check
  `isAccelerometerSupported` / `isDeviceMotionSupported` at runtime.
- **Development loop:** run Xcode builds from a Mac straight to the paired
  watch. CI and TestFlight remain the release path.

## Design

### 1. Targets and shared code

- **New watchOS app target** `CadenceWatch` in `project.yml`, embedded in
  `Cadence` the same way `CadenceWidgets` is, with HealthKit entitlement.
- **Deployment target** watchOS 26.0 (the SE 3 shipped with it). *Assistant's
  call; raise it if the owner's watch runs a newer version and a needed API
  requires it.*
- **CadenceCore** adds watchOS 26 to its platforms and is linked by the watch
  target.
  - `Package.swift` is `swift-tools-version:5.9`, so use the string form
    `.watchOS("26.0")` rather than a tools bump. A bump would also have to
    move the local `swift:5.10` container.
  - Everything the two devices must agree on lives there, as Foundation-only
    Swift: the sync message types, the merge rules and later the detector. It
    is testable on Linux locally in the container; CI runs it on macOS.
- **These new CadenceCore modules are Swift-only:** the web app is out of scope
  by owner decision. Record each new public symbol as `swiftOnly` with that
  reason if the module is mapped in `parity-map.json`, or keep the modules
  unmapped and state the reason in their header comment.

### 2. Stable identity (schema V16)

- **Add stable UUID string IDs to `SetEntry` and `SessionExercise`**, assigned
  at creation and backfilled once by the V15→V16 migration.
  - Sync addresses sets and exercises by these IDs, never by position.
  - The same migration adds the session fields sync needs (below).
- **The backup format does not change.** IDs are device-local identity for
  sync. A restore creates fresh IDs, so sync must never span a restore:
  - a restore tells the watch that the IDs of any session the restore
    replaced are gone. The watch answers with a recovery bundle: its whole
    replica (exercises, order, planned values, load basis and every
    performed set) plus its outbox, because acknowledged operations are no
    longer in the outbox and the deltas alone cannot rebuild the session.
    The phone turns the bundle into a new unbanked session, flagged for
    review like a duplicate start (section 4), instead of guessing positions
    or dropping sets the watch logged (anti-goal 1). The watch keeps the
    replica until the phone confirms that session is saved;
  - the V16 session fields that guard banking and Health export (below) are
    not in the backup, and a restore cannot tell which unbanked session the
    watch started. A restored unbanked session is therefore never banked
    automatically, and its bank-time Health export asks first. Restoring must
    never produce a second Health workout or a second program advance.
  - *Assistant's call.* The alternative is a backup-schema change, which also
    requires web import/export updates under the portable backup contract.
- *Assistant's call.* The alternative was reusing the Lock Screen's positional
  identity with stale-command refusal. That rejects any queued watch edit after
  the layout changed on the phone, which loses sets: anti-goal 1.

### 3. What each device holds

- **The phone is the system of record** for everything: programs, history and
  banked sessions. Only the phone builds planned sessions and banks them.
- **The watch holds a small local store** (Codable files are enough; SwiftData
  is not required):
  - the **next planned session**, as a snapshot pushed by the phone;
  - the **active session** replica;
  - an **outbox** of operations not yet acknowledged by the phone;
  - **settings** it needs: rest durations, auto-start-rest, haptics, the
    Health-writing flag, units, and its own tap-to-confirm toggle.
- **The next planned session is built ahead of time.** Whenever program state
  or settings change, the phone builds the next planned session (as
  `startProgramDay` would, but without inserting it) and pushes it with
  `updateApplicationContext`.
  - The watch can then start that day with the phone unreachable.
  - If the program has no next day, the watch shows nothing to start. Ad-hoc
    sessions are not started on the watch.
- **The watch only knows what the phone last told it.** If the phone app has
  never run since the watch app was installed, the watch has nothing to start
  and says so.

### 4. Sync

- **Transport is WatchConnectivity:**
  - `updateApplicationContext` for the latest snapshot and settings;
  - `transferUserInfo` for operations, which is queued and delivered when the
    devices are next in contact;
  - `sendMessage` as a fast path when the counterpart is reachable;
  - `transferFile` for motion recordings.
  - HealthKit workout mirroring may be used for live state if it makes the
    builder's life easier; it is not required.
- **The unit of sync is an operation.** Each one has:
  - an operation UUID;
  - a session ID;
  - a target ID (set or exercise);
  - a payload;
  - a logical version: a per-device counter that each device raises past
    every version it has seen before it issues an operation (a Lamport
    clock), so an edit made after seeing another always orders after it,
    whatever the two devices' clocks say;
  - a wall-clock timestamp, for display and session timing only, never for
    ordering;
  - the originating device.
- **Operations are idempotent** (applying one twice is a no-op, keyed by
  operation UUID).
  - The phone stores the UUIDs it has applied, and a tombstone for every set
    or exercise removed, with the session (V16 fields) until the session is
    banked and the watch has acknowledged it. Without them a `setAdded`
    delivered again after a relaunch would bring back a removed set.
  - A `setAdded` whose anchor set was removed is placed where the anchor was;
    the tombstone keeps that position. It is never rejected, because that
    loses a set logged on the other device.
  - An edit to a removed set is recorded as rejected, not applied, and is
    visible in the session's review notice.
- **Starting a session.** `sessionStarted` carries the full session snapshot,
  with the session ID minted by the device that started it.
- **Set edits:**
  - `setPerformed` covers status, performed reps, performed load, performed
    duration (`durationSeconds`, for holds, carries and conditioning), flags
    and the warmup flag;
  - `setAdded` and `setRemoved`. `setAdded` carries the ID of the set it
    follows (none for first), so sets added on both devices while apart land
    in a deterministic order: inserts after the same set order by
    (version, device);
  - `exerciseAdded` and `exerciseRemoved` exist only for phone-originated
    changes, since the watch cannot add exercises;
  - `setFlags` covers the effort tags.
- **Session control.** `restStarted`/`restEnded` carry an absolute end time;
  `sessionPaused`/`sessionResumed` carry timing events; `sessionEnded` means
  the user finished on the watch.
- **Conflict rule.** Each field of a set is last-writer-wins by
  (version, device), applied per field so an edited weight never resets
  reps (training-data invariant). `setRemoved` wins over later edits to the
  same set.
  - A person edits one set on one device at a time, so true conflicts are rare.
    The rule exists to make the rare case deterministic, not clever.
- **This logic lives in CadenceCore** and is tested on Linux with scripted
  two-device interleavings, including a watch outbox delivered after the phone
  added and removed sets.
- **The phone applies operations** through the same service layer the logger
  uses (`WorkoutCommandService` or a sibling). Rest auto-start, haptics and the
  Live Activity behave as if the set were tapped on the phone.
- **Duplicate starts.** If both devices start the same program day while apart,
  the phone ends up with two sessions for one day.
  - On receiving `sessionStarted`, the phone applies the same open-session
    matching `ProgramSession.make` uses for resuming. A watch-minted session
    that matches an open session is a duplicate.
  - The phone flags the newer one, lets the user keep one and discard the
    other, and never merges them silently.
  - A flagged duplicate is never banked automatically, even when
    `sessionEnded` arrives. It waits for the user's choice, so the program
    cannot advance twice.
  - When the devices are in contact, starting on one device joins the
    other's active session instead of creating a new one.
  - *Assistant's call.*

### 5. Ending and banking

- **Ending on the watch** sends `sessionEnded` with the final timing, the
  UUIDs of every operation the watch issued for the session, and the outcome
  of the watch's Health workout (section 6): saved (with its UUID), not
  written (discarded because Health writing is off, or failed before the
  workout was finished), or unknown (finishing reported an error, so Health
  may hold it). The watch sends it only after that save has finished, so the
  phone always knows who owns the Health workout before it banks.
- **The phone banks the session** with `SessionCompletion.finish` once it has
  received `sessionEnded` and accounted for every operation it lists
  (applied, or recorded as rejected under the rules in section 4, so one
  rejected edit cannot hold the session unbanked forever), so PRs,
  milestones and progression are computed exactly once, in one place, over
  every set. WatchConnectivity does not order `sendMessage` against
  `transferUserInfo`, so `sessionEnded` can arrive before sets queued earlier.
  Until then the phone shows the session as ended on the watch and waiting to
  be saved. Banking then happens without asking.
- **The watch shows a local summary immediately:** sets, volume and duration
  from its replica. It does not show PRs, because only the phone detects them.
- **Ending on the phone** uses the same barrier as ending on the watch.
  - If the watch has the session open, the phone asks it to end: the watch
    ends its workout session and answers with `sessionEnded` exactly as
    above, listing its operation UUIDs and its Health outcome. The phone
    banks once it has accounted for those operations, and exports to Health
    only under the rules in section 6.
  - If the watch does not answer within a short wait, or cannot be reached,
    the phone says so and offers to wait. Banking without the watch is then
    the owner's choice and never silent: sets that arrive later take the
    late-operation path below, which does not replay program progression
    (anti-goal 5). While the watch owns the Health workout, the phone does
    not export one; the watch saves it when it ends.
- **Late operations.** Operations that arrive after the session was banked are
  never dropped.
  - Late value edits to an existing set (performed load, reps, duration,
    distance, status) go through the existing banked-session correction
    path, `SessionCorrectionService.applyAndRebuild`, with the same rules as
    a manual correction. It rebuilds the affected PR milestones; it does not
    replay the program grade or advancement (epic #155 Stage 6).
  - That service changes only those fields on a set that already exists. It
    cannot add or remove a set, or change the warmup flag, effort tags or
    `autoregReason`. Phase 2 therefore extends the correction boundary with
    those operations, under the same rebuild rules, with tests. Until an
    operation can be applied it is stored with the session and listed for
    the owner, never dropped.
  - This path is only for a session banked on the phone without the watch,
    never for a watch-ended session.
  - The phone shows a notice that sets from the watch were added to a saved
    session.
  - *Assistant's call.*
- **A stale plan.** The planned-session snapshot depends on the date
  (`startProgramDay` reconciles the recovery bridge as of today).
  - At Start, the watch asks the phone for a fresh snapshot when it is
    reachable.
  - If the phone is unreachable, a cached snapshot is offered only when it was
    built for today. An older one is offered with a "plan may be out of date"
    warning.
  - A session built from a stale plan is still accepted: performed sets are
    the truth. The phone flags it for review and does not advance the program
    until the user confirms which day it was.
  - *Assistant's call.*

### 6. Workout session, heart rate and Health

- **Starting a session on the watch** starts an `HKWorkoutSession` with an
  `HKLiveWorkoutBuilder`, activity type from the same `WorkoutClassification`
  the phone uses. This keeps the app running with the wrist down and provides
  heart rate.
- **Heart rate** is a small number in a corner of the set and rest screens. It
  is never a separate page.
- **Authorization.** The watch asks for its own HealthKit permission (share
  workouts; read heart rate and energy) the first time a session starts on the
  watch.
  - Asking for this permission is an owner decision (12).
  - **Fallback if declined:** run the session with `WKExtendedRuntimeSession`.
    That gives no heart rate and no motion recording. Per a secondary source,
    the background-capable type stops after about an hour, so the watch must
    warn the user before that happens.
  - *Builder to verify that limit against Apple's documentation.*
- **Writing to Health follows the existing setting.**
  - If `healthKitEnabled` is on, the watch ends its builder and saves the
    workout. It carries heart rate, Apple's energy estimate and the pause and
    resume events.
  - If the setting is off, the watch discards the builder
    (`discardWorkout`), so nothing is written. This keeps the existing rule
    that Health writes are off by default.
- **Workout type and distance.**
  - The watch's workout uses the `WorkoutClassification` of the planned day,
    because the type is fixed when the workout session starts.
  - Before saving, the watch adds distance samples for any conditioning sets
    logged on it, with the same rules the phone uses at bank time.
  - If the completed work would have classified differently, the Health
    workout keeps the start type. This is a known, accepted difference.
  - *Assistant's call.*
- **No duplicate workout.**
  - V16 adds a `healthWorkoutRecordedOnWatch` marker (or the saved workout's
    UUID) to `WorkoutSession`, set from `sessionEnded` before banking.
    Bank-time export skips any session the watch recorded.
  - The phone exports at bank time only when the watch reports *not
    written*. An *unknown* outcome gets no automatic export: like
    `HealthKitService.saveWorkout`, which never retries an ambiguous finish,
    the phone shows a notice and the owner checks Health.
  - `HealthComparison`'s own-sample filter learns the watch bundle ID, so
    Cadence never shows its own watch data as independent Health data.
  - Only samples Cadence derives from the log (the distance samples added
    before saving) are its own. Heart rate and energy measured by the
    watch's builder are sensor readings, a real second opinion. If they are
    attributed to the watch app's bundle, the filter must tell them apart
    by sample type or by metadata Cadence writes on its own samples, not by
    bundle alone. *Builder to verify the source attribution on device.*
  - This deliberately changes the assertion in `HealthComparisonTests.swift`
    that treats a watch bundle as a foreign source. Under
    `INV-HEALTH-IS-A-SECOND-OPINION` it then means *Cadence's own* watch
    bundle; other watch apps stay foreign.
- **Timing.**
  - A session started on the watch takes its start time and pause events from
    the watch workout session. The phone's `WorkoutClock` mirrors them through
    operations.
  - A session started on the phone and continued on the watch keeps the
    phone's timing.
  - The watch does not start its own Health workout for a session the phone
    started, unless the owner taps "Start on watch" there. In that case the
    phone's own export is skipped as above.
  - *Assistant's call.* This keeps `INV-HEALTH-WORKOUT-TIMING` true for
    whichever device owns the workout.

### 7. Watch screens (40 mm)

One thing per screen, large tap targets, Dynamic Type and VoiceOver. Use the
house look adapted for watchOS; the builder chooses the visual details.

- **Start.** Today's planned day (name and exercise count) and a Start button.
  If the phone has an active session, it shows "Continue" instead.
- **Set.**
  - Shows the exercise name, "set n of m" and the planned load × reps, with a
    large **Done** button.
  - The Digital Crown adjusts reps. Tapping the load opens a load adjuster.
  - The phone's mid-session **drop load** is offered too. It carries
    `autoregReason` in `setPerformed`, so banking treats a dropped set the
    same way as on the phone.
  - Skip, and warmup sets, are reachable without crowding the main button.
  - Heart rate sits in a corner.
- **Rest.**
  - A countdown with +30 s and skip, and a haptic when rest ends.
  - Below it are the two optional effort rows (Clean / Grindy / Wobble;
    1 / 2 / 3+) and a preview of the next set.
  - The last set can be edited from here.
- **Exercise list.** A swipe away. It shows progress and lets you jump to an
  exercise.
- **End.** End the workout and see the local summary.
- **Always-on display.** Shows a dimmed rest countdown or current set.

### 8. Motion recording (before any detection)

- **What is recorded.** While a watch session runs, the watch records device
  motion continuously: user acceleration, rotation rate, gravity and attitude.
  It also logs session events:
  - set completed, with set ID, exercise ID, performed reps, load and warmup;
  - set skipped and edited;
  - rest started and ended;
  - exercise focus changes.
- **Sampling rate.** Default 50 Hz, which is ample for reps of about
  0.2–1.5 Hz. Use `CMBatchedSensorManager` at higher rates only if the
  device supports it. *Assistant's call; the builder may change the rate
  with a measured reason.*
- **Labels.** Labels are the owner's ordinary manual logging. The Done tap marks
  set end; the previous rest's end or the exercise focus change bounds the
  start.
- **Device metadata.** Each recording records the watch model, wrist side and
  crown orientation (`WKInterfaceDevice`), because the sign of the signal
  depends on them.
- **Storage.** Recordings are compact binary files, one per session, plus a
  JSON sidecar of events and metadata. About 3 KB/s at 50 Hz is roughly 12 MB
  for a 70-minute session.
- **Transfer.** Recordings move to the phone with `transferFile` and are
  deleted from the watch once the phone acknowledges them.
- **Export.** The phone keeps recordings in its app container, outside SwiftData
  and outside the backup. Settings gets "Export motion recordings", which uses
  the share sheet to produce a zip. That is how the data reaches the
  development machine.
- **On/off.** Recording is on by default while sessions run on the watch, with
  an off switch, because the owner asked for it. Recordings stay on the
  owner's devices unless exported.

### 9. Detector (offline first)

- **Where it lives.** A pure-Swift module in CadenceCore. Its input is a motion
  stream plus the exercise ID and that exercise's stored signatures. Its output
  is a set-end event with a rep count and a confidence.
  - Repository tests use **synthetic** motion fixtures only. AGENTS.md
    forbids committing real workout or health data, and real recordings are
    both.
  - A local evaluation command, outside CI, runs the detector over a folder
    of exported recordings on the developer's machine and prints a
    per-exercise accuracy table.
  - Only that aggregate table may be posted to issues or PRs, never the
    recordings.
- **Approach is left to the builder.** Candidates:
  - band-pass filtering and peak counting on the dominant motion axis;
  - template matching (dynamic time warping) against the owner's recorded reps
    per exercise;
  - a small on-device classifier.
  - Prefer the simplest approach that meets the bar.
- **Signatures are per exercise**, derived from the owner's labelled sets,
  built on the phone and synced to the watch with the snapshot.
- **Accuracy bar (*assistant's call*).** An exercise is enabled for
  autocomplete only when evaluation on recordings held out from that
  exercise's signature build shows:
  - at least 10 sets in the evaluation;
  - an exact rep count on at least 90% of sets, and within ±1 on at least 98%;
  - set end detected within 5 s of the Done tap on at least 95%;
  - over the full held-out session streams, including rests, setup, walking
    between stations and other exercises, at most one detection with no
    matching Done tap per 100 real sets. A detector that finds every set but
    also logs sets that never happened corrupts the session.
- **Per-exercise reporting.** The evaluation runs offline and reports each
  exercise. Exercises below the bar stay manual, and the owner sees which
  exercises are enabled.
- **Expectation, unmeasured:** presses, rows, curls and pulldowns will pass
  sooner than squats and deadlifts.

### 10. Autocomplete on the watch

- **When the detector fires** for an enabled exercise (default mode):
  - the set logs as completed with the detected reps and the set's current
    load: the planned load unless it was adjusted or dropped on the watch;
  - the rest timer starts under the existing `restAfterCompleting` rule;
  - the watch gives a distinct haptic;
  - the rest screen shows "8 reps · Edit".
- **Editing.** Any auto-logged set can be edited from the rest screen or the
  exercise list. An edit is an ordinary `setPerformed` operation.
- **Tap-to-confirm mode** is a toggle in the watch app's own settings, stored
  on the watch.
  - Rest still starts at detection, because the bar is already racked.
  - The set is written only when the owner taps Confirm. Until then the set
    shows the proposed reps.
- **Marking.** Auto-logged sets carry a marker so their accuracy can be
  measured later from exports. *Builder's choice of mechanism:* an operation
  field kept in the motion sidecar is enough. No schema field is needed.

## Delivery

Each phase is one PR, and each merge to main cuts a release, so every phase
leaves the app shippable. Every phase has its own task issue linked to #329.

1. **Watch target, signing and CI.**
   - An empty watch app that launches and shows "Open Cadence on your iPhone".
   - CadenceCore built for watchOS, with Fastlane `match` and signing for the
     new ID.
   - A watch simulator build in CI, plus target enumeration in the CI scripts
     and the release-artifact check.
   - Needs the owner's one-time read-write `match` run.
2. **The watch runs a session.**
   - V16 identity and session fields.
   - The planned-session snapshot.
   - Manual set logging on the watch: loaded reps, bodyweight reps and timed
     holds in full; carries and conditioning by duration (owner decision 11).
   - Two-way sync in CadenceCore with interleaving tests.
   - Banking on the phone.
   - The workout session with heart rate and the Health workout without
     duplicates.
   - Effort tags on the rest screen.
   - Done when the owner logs a full program day on the watch with the phone
     never unlocked, and the result matches a phone-logged day: same PRs,
     progression and one Health workout.
3. **Motion recording and export.** Done when a session's recording reaches the
   phone, exports as a zip, and its events line up with the logged sets.
4. **Offline detector.**
   - The CadenceCore detector and its fixtures.
   - The per-exercise evaluation report, run against the owner's recordings.
   - No watch UI change.
5. **Autocomplete on the watch.**
   - Signatures synced.
   - Detection on the watch for enabled exercises.
   - Auto-log by default, the tap-to-confirm toggle, and editing.
   - Done when a real session auto-logs the enabled exercises within the
     accuracy bar.

Phases 3 and 4 can overlap: detector work can start as soon as the first
recordings exist.

## Verification

- **Linux-testable logic.** Sync merge, operation application and the detector
  are tested in CadenceCore on Linux, with scripted two-device histories and
  synthetic motion fixtures. The detector's real accuracy comes from the local
  evaluation in section 9.
- **Migration.** The V16 migration gets on-disk tests in
  `CadenceMigrationTests` per the existing rules.
- **Simulators.** CI builds the watch target and runs a watch-simulator smoke
  test of start → log a set → rest → end.
- **New journeys.** Each new critical journey gets a requirement, synthetic
  setup and evidence per `docs/CI-ACCEPTANCE.md`.
- **Device acceptance.** The owner signs off on the SE 3 at the end of phases 2,
  3 and 5. Simulators cannot provide heart rate or motion.

## Left to the builder

- The detector algorithm, within the accuracy bar.
- The watch-side storage format and recording file layout.
- Whether to use HealthKit workout mirroring alongside WatchConnectivity.
- Visual details of the watch screens within the house look.
- The exact operation encoding, as long as it is idempotent, versioned and
  tested.
