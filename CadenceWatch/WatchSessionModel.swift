import CadenceCore
import Foundation
import WatchKit
#if DEBUG
import notify
#endif

/// The watch's side of a session (design #339, sections 3–7): the phone's last
/// plan, this device's sync endpoint and the rest clock. Every tap becomes a
/// sync operation applied here first and queued for the phone, so the watch
/// keeps working with the phone out of reach. Persisted after every change, so
/// a relaunch mid-workout loses nothing.
@MainActor
final class WatchSessionModel: ObservableObject {
    struct Stored: Codable {
        var plan: WatchPlan?
        var endpoint: SyncEndpoint?
        var healthSetting: SyncHealthSetting?
        var sessionStartedAt: Date?
    }

    @Published private(set) var plan: WatchPlan?
    @Published private(set) var endpoint: SyncEndpoint? {
        // What the watch holds about a planned set lapses once that set stops
        // being planned, whoever changed it: a Done, a Skip or the phone.
        didSet { dropStateOfUnplannedSets() }
    }
    @Published private(set) var healthSetting: SyncHealthSetting?
    @Published private(set) var sessionStartedAt: Date?
    @Published var focusExerciseID: String? {
        didSet {
            if let id = focusExerciseID, id != oldValue {
                motion.note(.focusChanged, exerciseID: view?.exercises.first { $0.id == id }?.catalog.exerciseID)
            }
        }
    }
    /// Shown after ending until the next session starts.
    @Published private(set) var summary: Summary?
    @Published private(set) var isEnding = false

    let recorder = WorkoutRecorder()
    let motion = MotionRecorder()

    // MARK: Autocomplete state (design section 10)

    static let confirmKey = "autocompleteConfirm"
    /// Tap-to-confirm: rest starts at detection, the set is written on Confirm.
    @Published var confirmBeforeLogging: Bool {
        didSet { UserDefaults.standard.set(confirmBeforeLogging, forKey: Self.confirmKey) }
    }
    struct Proposal: Equatable {
        var setID: String
        var reps: Int
    }
    /// A detected set waiting for Confirm (tap-to-confirm mode).
    @Published private(set) var proposal: Proposal?
    /// Reps of the set just completed by detection, for "N reps · Edit".
    @Published private(set) var autoLoggedReps: Int?
    /// Loads changed on the watch for sets not logged yet, by set ID: what the
    /// set screen shows and what any completion of the set logs.
    @Published private(set) var adjustedLoads: [String: Double] = [:]
    private var detector: StreamingSetDetector?
    private var detectorExerciseID: String?
    /// Set by `WatchLink`: hands a message to WatchConnectivity.
    var send: (WatchWire) -> Void = { _ in }
    /// Set by `WatchLink`: queues a finished motion recording for the phone.
    var transferRecording: (URL) -> Void = { _ in }

    struct Summary: Equatable {
        var sets: Int
        var volumeLb: Double
        var duration: TimeInterval
    }

    private let fileURL: URL

    /// Debug builds only: `--watch-fixture` runs against a synthetic plan in a
    /// scratch directory with HealthKit off, for the watch UI smoke test;
    /// `--watch-fixture-motion` plays a synthetic bench set after Start, and
    /// `--watch-fixture-motion-on-signal` holds it until the test posts
    /// `fixtureMotionSignal`; `--watch-confirm-detected` adds tap-to-confirm,
    /// and `--watch-fixture-phone-logs-proposal` has the phone log a proposed set.
    let isFixture: Bool

    init(directory: URL? = nil) {
        #if DEBUG
        isFixture = ProcessInfo.processInfo.arguments.contains("--watch-fixture")
        #else
        isFixture = false
        #endif
        let scratch = isFixture ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) : nil
        let base = scratch ?? directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("watch-session.json")
        // A fixture run takes the setting from `--watch-confirm-detected` alone,
        // never from the defaults; assigned once so `didSet` doesn't persist it.
        confirmBeforeLogging = isFixture ? ProcessInfo.processInfo.arguments.contains("--watch-confirm-detected")
                                         : UserDefaults.standard.bool(forKey: Self.confirmKey)
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            plan = stored.plan
            endpoint = stored.endpoint
            healthSetting = stored.healthSetting
            sessionStartedAt = stored.sessionStartedAt
        }
        #if DEBUG
        if isFixture { plan = WatchSessionModel.fixturePlan() }
        #endif
        motion.onSamples = { [weak self] samples in self?.feed(samples) }
    }

    #if DEBUG
    static func fixturePlan(now: Date = Date()) -> WatchPlan {
        let bench = SyncCatalogExercise(exerciseID: "fixture-bench", name: "Bench Press")
        let row = SyncCatalogExercise(exerciseID: "fixture-row", name: "Barbell Row")
        func sets(_ weight: Double, _ reps: Int) -> [SyncPlannedSet] {
            (0..<2).map { _ in SyncPlannedSet(id: UUID().uuidString, reps: reps, weightLb: weight, plannedReps: reps,
                                         plannedWeightLb: weight) }
        }
        let snapshot = SyncSessionSnapshot(title: "Day A", position: nil, builtAt: now, exercises: [
            SyncPlannedExercise(id: UUID().uuidString, catalog: bench, programRole: "main", sets: sets(185, 5)),
            SyncPlannedExercise(id: UUID().uuidString, catalog: row, sets: sets(135, 8)),
            SyncPlannedExercise(id: UUID().uuidString, catalog: SyncCatalogExercise(exerciseID: "fixture-plank", name: "Plank"),
                                sets: [SyncPlannedSet(id: UUID().uuidString, reps: 0, weightLb: 0, durationSeconds: 30,
                                                      plannedDurationSeconds: 30)]),
        ])
        let settings = WatchSettings(accessoryRestSeconds: 90, secondaryRestSeconds: 180, mainUpperRestSeconds: 180,
                                     mainCompoundRestSeconds: 180, autoStartRest: true, haptics: false, unit: "lb",
                                     healthKitEnabled: false)
        var plan = WatchPlan(next: snapshot, settings: settings, sentAt: now)
        if ProcessInfo.processInfo.arguments.contains("--watch-fixture-motion") {
            // A signature learned from synthetic bench sets, so the UI test drives
            // the real detection path end to end.
            let training = (0..<3).map { _ in
                LabelledMotionSet(samples: fixtureMotion(reps: 5, start: 0), reps: 5, end: fixtureMotion(reps: 5, start: 0).last.map { Double($0.t) } ?? 0)
            }
            plan.signatures = RepDetector.signature(exerciseID: "fixture-bench", from: training).map { [$0] }
        }
        return plan
    }

    /// Synthetic bench motion: settle, `reps` along the watch's y axis, rack.
    static func fixtureMotion(reps: Int, start: Double) -> [MotionSample] {
        var samples: [MotionSample] = []
        let rate = MotionRecording.defaultSampleRate, period = 2.0
        let total = 3 + Double(reps) * period + 3
        var t = 0.0
        while t < total {
            let inReps = t >= 3 && t < 3 + Double(reps) * period
            let y = inReps ? Float(0.35 * sin(2 * .pi * (t - 3) / period)) : 0
            samples.append(MotionSample(t: Float(start + t), userAcceleration: SIMD3(0, y, 0), rotationRate: .zero,
                                        gravity: SIMD3(0, -1, 0), attitude: SIMD4(0, 0, 0, 1)))
            t += 1 / rate
        }
        return samples
    }

    /// The Darwin notification a UI test posts to play the fixture's set under
    /// `--watch-fixture-motion-on-signal`. The test runner is another process,
    /// so it has no other way in; CadenceWatchUITests posts the same name.
    static let fixtureMotionSignal = "com.madhakish.Cadence.watch-fixture.play-motion"

    /// Play the fixture's set ten seconds after Start, or, under
    /// `--watch-fixture-motion-on-signal`, the moment the test posts
    /// `fixtureMotionSignal`: a test that works on the set before it is
    /// detected must finish first, however slow the simulator (#368).
    private func startFixtureMotion() {
        guard ProcessInfo.processInfo.arguments.contains("--watch-fixture-motion-on-signal") else {
            return playFixtureMotion(after: 10)
        }
        var token: Int32 = 0
        notify_register_dispatch(Self.fixtureMotionSignal, &token, .main) { [weak self] token in
            notify_cancel(token)  // one set per signal, one signal per run
            MainActor.assumeIsolated { self?.playFixtureMotion(after: 0) }
        }
    }

    /// Feed one synthetic set (plus a quiet tail) through `feed`, ten times
    /// faster than real time, after a lead-in of `seconds`.
    private func playFixtureMotion(after seconds: UInt64) {
        var stream = Self.fixtureMotion(reps: 5, start: 0)
        let tail = (1...400).map { i in
            MotionSample(t: (stream.last?.t ?? 0) + Float(i) / 50, userAcceleration: .zero, rotationRate: .zero,
                         gravity: SIMD3(0, -1, 0), attitude: SIMD4(0, 0, 0, 1))
        }
        stream += tail
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            var index = 0
            while index < stream.count {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let batch = Array(stream[index..<min(index + 50, stream.count)])
                index += 50
                self?.feed(batch)
            }
        }
    }

    /// Five seconds after detection, the phone logs the proposed set (6 reps)
    /// through the sync path a real completion on the phone takes.
    private func fixturePhoneLogs(_ setID: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, let started = endpoint?.outbox.first(where: { $0.seq == 1 }) else { return }
            var phone = SyncEndpoint(device: .phone)
            phone.receive(started)
            guard let op = phone.issue(.setPerformed(setID: setID, patch: SyncSetPatch(status: .completed, reps: 6, weightLb: 185)),
                                       operationID: UUID().uuidString, now: Date()) else { return }
            receive(.operations([op]))
        }
    }
    #endif

    // MARK: Reading

    var view: SyncSessionView? { endpoint?.replica?.view() }
    var isRunning: Bool { view != nil && view?.ended == nil }
    var settings: WatchSettings? { plan?.settings }

    /// The exercise in focus: the one picked from the list, else the first
    /// with planned work left.
    var currentExercise: SyncSessionView.Exercise? {
        guard let view else { return nil }
        if let id = focusExerciseID, let picked = view.exercises.first(where: { $0.id == id }) { return picked }
        return view.exercises.first { $0.sets.contains { $0.status == .planned } } ?? view.exercises.last
    }

    var currentSet: SyncSessionView.Set? {
        currentExercise?.sets.first { $0.status == .planned }
    }

    /// The set a pending proposal is for, with its exercise: what the set screen
    /// shows while the proposal waits, wherever the focus has moved since.
    var proposedSet: (exercise: SyncSessionView.Exercise, set: SyncSessionView.Set)? {
        guard let proposal, let view else { return nil }
        for exercise in view.exercises {
            if let set = exercise.sets.first(where: { $0.id == proposal.setID }) { return (exercise, set) }
        }
        return nil
    }

    /// The set just finished, for the rest screen's tags and edit.
    @Published private(set) var lastLoggedSetID: String?

    /// The load the watch shows for a set: the owner's adjustment, else the plan's.
    func load(for set: SyncSessionView.Set) -> Double {
        adjustedLoads[set.id] ?? set.weightLb
    }

    func adjustLoad(_ setID: String, to weightLb: Double) {
        adjustedLoads[setID] = weightLb
    }

    func display(_ weightLb: Double) -> String {
        if settings?.unit == "kg" { return Weight.trim(Weight.kg(fromLb: weightLb)) + " kg" }
        return Weight.trim(weightLb) + " lb"
    }

    // MARK: Messages from the phone

    func receive(_ wire: WatchWire) {
        switch wire {
        case .plan(let plan):
            self.plan = plan
            healthSetting = SyncHealthSetting(enabled: plan.settings.healthKitEnabled, receivedAt: Date())
        case .operations(let ops):
            guard var endpoint = endpoint ?? joiningEndpoint(for: ops) else { return }
            for op in ops { endpoint.receive(op) }
            self.endpoint = endpoint
            if let replica = endpoint.replica { send(.ack(replica.acknowledgement(for: .phone))) }
        case .ack(let ack):
            endpoint?.acknowledge(ack)
            finishIfDelivered()
        case .recordingStored(let id):
            MotionRecorder.discard(recordingID: id)
        case .requestPlan, .join:
            break
        }
        save()
    }

    /// Operations for a session this watch has not started arrive after a
    /// Continue: the phone's session begins with its own `sessionStarted`.
    private func joiningEndpoint(for ops: [SyncOperation]) -> SyncEndpoint? {
        guard let first = ops.first, case .sessionStarted = first.payload, first.device == .phone else { return nil }
        sessionStartedAt = first.timestamp
        motion.start(sessionID: first.sessionID)
        return SyncEndpoint(device: .watch)
    }

    // MARK: Actions

    func start() {
        guard endpoint == nil, let snapshot = plan?.next else { return }
        send(.requestPlan)
        var endpoint = SyncEndpoint(device: .watch)
        guard let op = endpoint.start(sessionID: UUID().uuidString, snapshot: snapshot,
                                      operationID: UUID().uuidString, now: Date()) else { return }
        self.endpoint = endpoint
        sessionStartedAt = op.timestamp
        motion.start(sessionID: op.sessionID)
        summary = nil
        focusExerciseID = nil
        send(.operations([op]))
        save()
        #if DEBUG
        if isFixture, ProcessInfo.processInfo.arguments.contains("--watch-fixture-motion") { startFixtureMotion() }
        #endif
        guard !isFixture else { return }
        let modality = plan?.nextModality
        Task { await recorder.start(modality: modality) }
    }

    /// Continue the session the phone has open.
    func join() {
        guard endpoint == nil, let id = plan?.activeSessionID else { return }
        summary = nil
        send(.join(sessionID: id))
    }

    /// Holds, carries and conditioning are logged by time (owner decision 11).
    static func isTimed(_ set: SyncSessionView.Set) -> Bool {
        set.created.plannedDurationSeconds != nil || set.durationSeconds != nil
    }

    func complete(_ set: SyncSessionView.Set, reps: Int, weightLb: Double, durationSeconds: Int? = nil,
                  startRest: Bool = true, detected: Bool = false) {
        // The set's own exercise, not the one in focus: a detected set confirmed
        // after the owner moved on must still be performed as what it was.
        guard let exercise = view?.exercises.first(where: { $0.sets.contains { $0.id == set.id } }) ?? currentExercise
        else { return }
        if !detected {
            // A manual Done consumes this set's motion: the detector must not
            // later log the same physical set onto the next planned one, and a
            // pending proposal for it must not log it a second time.
            detector?.reset()
            autoLoggedReps = nil
            proposal = nil
        }
        issue(.setPerformed(setID: set.id, patch: SyncSetPatch(
            status: .completed, reps: reps, weightLb: weightLb,
            durationSeconds: durationSeconds ?? set.durationSeconds, performedAs: exercise.catalog.exerciseID)))
        lastLoggedSetID = set.id
        motion.note(.setCompleted, setID: set.id, exerciseID: exercise.catalog.exerciseID,
                    exerciseName: exercise.catalog.name, reps: reps, weightLb: weightLb, isWarmup: set.isWarmup)
        if settings?.haptics ?? true { WKInterfaceDevice.current().play(.success) }
        if startRest, settings?.autoStartRest ?? true {
            motion.note(.restStarted)
            let seconds = Double(settings?.restSeconds(forRole: exercise.programRole) ?? 120)
            issue(.restChanged(RestClock.start(total: seconds, now: Date().timeIntervalSince1970)))
        }
        if exercise.id == focusExerciseID, !(currentExercise?.sets.contains { $0.status == .planned } ?? false) {
            focusExerciseID = nil
        }
    }

    /// The phone's mid-session drop load (design section 7): the remaining
    /// planned work sets of the current exercise get the engine's dropped load
    /// and carry the reason, so banking treats them as on the phone. The
    /// configured fixed drop lives in the phone's planning context, so the
    /// watch uses the engine's standard drop.
    func dropLoad(reason: AutoregReason) {
        // The exercise the set screen shows: a proposed set's, while one waits.
        guard let exercise = proposedSet?.exercise ?? currentExercise else { return }
        let plan = ProgramEngine.dropLoadPlan(
            sets: exercise.sets.map { (weightLb: $0.weightLb, isWarmup: $0.isWarmup, isFlagged: $0.status != .planned) },
            barLb: exercise.catalog.loadBasis == .totalBar ? 45 : 0)
        for step in plan {
            adjustedLoads[exercise.sets[step.index].id] = nil  // the drop is the newer decision
            issue(.setPerformed(setID: exercise.sets[step.index].id, patch: SyncSetPatch(
                weightLb: step.weightLb, autoregReason: SyncValue(reason))))
        }
    }

    /// Live motion from the recorder: run the detector for the exercise in
    /// focus, if it is one the phone enabled.
    func feed(_ samples: [MotionSample]) {
        guard isRunning, proposal == nil, let exercise = currentExercise, let set = currentSet,
              let signature = plan?.signatures?.first(where: { $0.exerciseID == exercise.catalog.exerciseID })
        else { return }
        if detectorExerciseID != exercise.id || detector?.signature != signature {
            detector = StreamingSetDetector(signature: signature)
            detectorExerciseID = exercise.id
        }
        guard let found = detector?.append(samples) else { return }
        detected(found, set: set)
    }

    private func detected(_ found: DetectedSet, set: SyncSessionView.Set) {
        WKInterfaceDevice.current().play(.notification)  // distinct from a tapped Done
        if confirmBeforeLogging {
            // The bar is racked: rest starts now; the set waits for Confirm.
            proposal = Proposal(setID: set.id, reps: found.reps)
            #if DEBUG
            if isFixture, ProcessInfo.processInfo.arguments.contains("--watch-fixture-phone-logs-proposal") {
                fixturePhoneLogs(set.id)
            }
            #endif
            if settings?.autoStartRest ?? true, let exercise = currentExercise {
                let seconds = Double(settings?.restSeconds(forRole: exercise.programRole) ?? 120)
                issue(.restChanged(RestClock.start(total: seconds, now: Date().timeIntervalSince1970)))
                motion.note(.restStarted)
            }
        } else {
            complete(set, reps: found.reps, weightLb: load(for: set), detected: true)
            motion.note(.autoLogged, setID: set.id, exerciseID: currentExercise?.catalog.exerciseID, reps: found.reps)
            autoLoggedReps = found.reps
        }
    }

    func confirmProposal() {
        guard let proposal else { return }
        // Only a set still waiting: Confirm must not undo a Skip or overwrite a
        // completion that came from the phone.
        guard let set = view?.exercises.flatMap(\.sets).first(where: { $0.id == proposal.setID }), set.status == .planned
        else {
            self.proposal = nil
            return
        }
        complete(set, reps: proposal.reps, weightLb: load(for: set), startRest: false, detected: true)
        motion.note(.autoLogged, setID: set.id, reps: proposal.reps)
        self.proposal = nil
    }

    /// The owner's correction of the detected reps (the crown), logged on Confirm.
    func adjustProposal(reps: Int) {
        proposal?.reps = reps
    }

    func dismissProposal() {
        proposal = nil
    }

    func skip(_ set: SyncSessionView.Set) {
        // The set's own exercise, as in `complete`: a proposed set can be
        // skipped after the owner moved the focus to another exercise.
        let exercise = view?.exercises.first { $0.sets.contains { $0.id == set.id } } ?? currentExercise
        issue(.setPerformed(setID: set.id, patch: SyncSetPatch(status: .skipped)))
        motion.note(.setSkipped, setID: set.id, exerciseID: exercise?.catalog.exerciseID)
    }

    /// Undo a logged set back to planned (the rest screen's Edit).
    func reopen(_ setID: String) {
        autoLoggedReps = nil
        issue(.setPerformed(setID: setID, patch: SyncSetPatch(status: .planned)))
        motion.note(.setEdited, setID: setID)
        if lastLoggedSetID == setID { lastLoggedSetID = nil }
    }

    func addRest(_ seconds: Double) {
        guard let rest = view?.rest else { return }
        issue(.restChanged(RestClock.add(rest, seconds: seconds)))
    }

    func endRest() {
        issue(.restChanged(nil))
        motion.note(.restEnded)
    }

    /// Optional effort tags (owner decision 8): one quality and one reps-in-reserve.
    func tag(_ setID: String, quality: String?, rir: String?) {
        guard let set = view?.exercises.flatMap(\.sets).first(where: { $0.id == setID }) else { return }
        let stoppedEarly = set.flags.contains("stopped early")
        let flags = SetLifecycle.normalizedFlags(quality: quality ?? SetLifecycle.quality(in: set.flags),
                                                 stoppedEarly: stoppedEarly,
                                                 rir: rir ?? SetLifecycle.rir(in: set.flags))
        issue(.setFlags(setID: setID, flags: flags))
    }

    func end() async {
        guard isRunning, !isEnding, let started = sessionStartedAt else { return }
        isEnding = true
        defer { isEnding = false }
        if view?.rest != nil { issue(.restChanged(nil)) }
        let mayWrite = SyncSessionRules.watchMaySaveWorkout(sessionStartedAt: started, latestSetting: healthSetting)
        let health = await recorder.finish(save: mayWrite)
        let ended = Date()
        let completed = view?.exercises.flatMap(\.sets).filter { $0.status == .completed && !$0.isWarmup } ?? []
        summary = Summary(sets: completed.count,
                          volumeLb: completed.reduce(0) { $0 + $1.weightLb * Double($1.reps) },
                          duration: ended.timeIntervalSince(started))
        let ids = endpoint?.unacknowledgedOperationIDs ?? []
        issue(.sessionEnded(SyncSessionEnd(endedAt: ended, operationIDs: ids, health: health)))
        if let recording = motion.stop() { transferRecording(recording) }
    }

    // MARK: Plumbing

    private func issue(_ payload: SyncPayload) {
        guard var endpoint, let op = endpoint.issue(payload, operationID: UUID().uuidString, now: Date()) else { return }
        self.endpoint = endpoint
        send(.operations([op]))
        save()
    }

    /// Once the phone holds every operation of an ended session, the watch's
    /// copy is no longer needed.
    private func finishIfDelivered() {
        guard let endpoint, endpoint.replica?.view().ended != nil, endpoint.outbox.isEmpty else { return }
        self.endpoint = nil
        sessionStartedAt = nil
        lastLoggedSetID = nil
    }

    private func dropStateOfUnplannedSets() {
        let planned = Set(view?.exercises.flatMap(\.sets).filter { $0.status == .planned }.map(\.id) ?? [])
        if let proposal, !planned.contains(proposal.setID) { self.proposal = nil }
        if adjustedLoads.keys.contains(where: { !planned.contains($0) }) {
            adjustedLoads = adjustedLoads.filter { planned.contains($0.key) }
        }
    }

    private func save() {
        let stored = Stored(plan: plan, endpoint: endpoint, healthSetting: healthSetting, sessionStartedAt: sessionStartedAt)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
