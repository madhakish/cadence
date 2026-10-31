import CadenceCore
import Foundation
import WatchKit

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
    @Published private(set) var endpoint: SyncEndpoint?
    @Published private(set) var healthSetting: SyncHealthSetting?
    @Published private(set) var sessionStartedAt: Date?
    @Published var focusExerciseID: String?
    /// Shown after ending until the next session starts.
    @Published private(set) var summary: Summary?
    @Published private(set) var isEnding = false

    let recorder = WorkoutRecorder()
    /// Set by `WatchLink`: hands a message to WatchConnectivity.
    var send: (WatchWire) -> Void = { _ in }

    struct Summary: Equatable {
        var sets: Int
        var volumeLb: Double
        var duration: TimeInterval
    }

    private let fileURL: URL

    /// Debug builds only: `--watch-fixture` runs against a synthetic plan in a
    /// scratch directory with HealthKit off, for the watch UI smoke test.
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
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            plan = stored.plan
            endpoint = stored.endpoint
            healthSetting = stored.healthSetting
            sessionStartedAt = stored.sessionStartedAt
        }
        #if DEBUG
        if isFixture { plan = WatchSessionModel.fixturePlan() }
        #endif
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
        return WatchPlan(next: snapshot, settings: settings, sentAt: now)
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

    /// The set just finished, for the rest screen's tags and edit.
    @Published private(set) var lastLoggedSetID: String?

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
        summary = nil
        focusExerciseID = nil
        send(.operations([op]))
        save()
        guard !isFixture else { return }
        Task { await recorder.start() }
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

    func complete(_ set: SyncSessionView.Set, reps: Int, weightLb: Double, durationSeconds: Int? = nil) {
        guard let exercise = currentExercise else { return }
        issue(.setPerformed(setID: set.id, patch: SyncSetPatch(
            status: .completed, reps: reps, weightLb: weightLb,
            durationSeconds: durationSeconds ?? set.durationSeconds, performedAs: exercise.catalog.exerciseID)))
        lastLoggedSetID = set.id
        if settings?.haptics ?? true { WKInterfaceDevice.current().play(.success) }
        if settings?.autoStartRest ?? true {
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
        guard let exercise = currentExercise else { return }
        let plan = ProgramEngine.dropLoadPlan(
            sets: exercise.sets.map { (weightLb: $0.weightLb, isWarmup: $0.isWarmup, isFlagged: $0.status != .planned) },
            barLb: exercise.catalog.loadBasis == .totalBar ? 45 : 0)
        for step in plan {
            issue(.setPerformed(setID: exercise.sets[step.index].id, patch: SyncSetPatch(
                weightLb: step.weightLb, autoregReason: SyncValue(reason))))
        }
    }

    func skip(_ set: SyncSessionView.Set) {
        issue(.setPerformed(setID: set.id, patch: SyncSetPatch(status: .skipped)))
    }

    /// Undo a logged set back to planned (the rest screen's Edit).
    func reopen(_ setID: String) {
        issue(.setPerformed(setID: setID, patch: SyncSetPatch(status: .planned)))
        if lastLoggedSetID == setID { lastLoggedSetID = nil }
    }

    func addRest(_ seconds: Double) {
        guard let rest = view?.rest else { return }
        issue(.restChanged(RestClock.add(rest, seconds: seconds)))
    }

    func endRest() {
        issue(.restChanged(nil))
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

    private func save() {
        let stored = Stored(plan: plan, endpoint: endpoint, healthSetting: healthSetting, sessionStartedAt: sessionStartedAt)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
