import CadenceCore
import Foundation
import SwiftData
import WatchConnectivity

/// WatchConnectivity on the phone (design #339, sections 3–5). Pushes the plan
/// as application context, applies the watch's operations to SwiftData through
/// `WatchSessionSync`, sends the phone's own edits to the watch as operations,
/// and banks a watch-ended session once the end barrier holds.
@MainActor
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()

    private var container: ModelContainer?
    /// Endpoints for watch sessions whose start has not arrived yet.
    private var waiting: [String: SyncEndpoint] = [:]
    private var saveObserver: NSObjectProtocol?
    private var restObserver: NSObjectProtocol?
    private var capturing = false

    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        if restObserver == nil {
            restObserver = NotificationCenter.default.addObserver(forName: .phoneRestChanged, object: nil,
                                                                  queue: .main) { [weak self] note in
                let change = note.object as? RestTimer.Change
                Task { @MainActor in self?.sendRest(change?.state) }
            }
        }
        if saveObserver == nil {
            // The logger saves directly; every save is a chance to send its
            // edits of a shared session to the watch.
            saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil,
                                                                  queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sendLocalEdits() }
            }
        }
        WCSession.default.delegate = self
        if WCSession.default.activationState == .activated { pushPlan() } else { WCSession.default.activate() }
    }

    // MARK: Plan

    /// Latest plan for the watch: application context keeps only the newest.
    func pushPlan() {
        guard let container, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let plan = try? makePlan(context: container.mainContext, container: container),
              let message = try? WatchWire.plan(plan).dictionary() else { return }
        try? session.updateApplicationContext(message)
        if session.isReachable { session.sendMessage(message, replyHandler: nil) { _ in } }
    }

    func makePlan(context: ModelContext, container: ModelContainer, now: Date = .now) throws -> WatchPlan {
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        let watchSettings = WatchSettings(
            accessoryRestSeconds: settings?.accessoryRestSeconds ?? 90,
            secondaryRestSeconds: settings?.secondaryRestSeconds ?? 180,
            mainUpperRestSeconds: settings?.mainUpperRestSeconds ?? 180,
            mainCompoundRestSeconds: settings?.mainCompoundRestSeconds ?? 300,
            autoStartRest: settings?.autoStartRest ?? false,
            haptics: settings?.haptics ?? true,
            unit: settings?.unitDisplay == .kgPrimary ? "kg" : "lb",
            healthKitEnabled: settings?.healthKitEnabled ?? false)
        var next: SyncSessionSnapshot?
        if let program = try context.fetch(FetchDescriptor<Program>()).first(where: \.isActive),
           let day = program.nextDay {
            next = try? WatchSessionSync.plannedSnapshot(program: program, day: day, container: container, builtAt: now)
        }
        let open = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { !$0.isCompleted }, sortBy: [SortDescriptor(\.date, order: .reverse)])).first
        var modality: WorkoutModality?
        if let next {
            let library = try context.fetch(FetchDescriptor<Exercise>())
            let kinds = next.exercises.compactMap { planned -> CompletedExerciseKind? in
                guard let exercise = library.first(where: { $0.id == planned.catalog.exerciseID }) else { return nil }
                return CompletedExerciseKind(name: exercise.name, type: exercise.typeRaw, category: exercise.categoryRaw)
            }
            modality = WorkoutClassification.classify(kinds)
        }
        return WatchPlan(next: next, activeSessionID: open?.id, settings: watchSettings, sentAt: now,
                         nextModality: modality)
    }

    // MARK: Messages from the watch

    func handle(_ wire: WatchWire) {
        guard let context = container?.mainContext else { return }
        switch wire {
        case .operations(let ops): apply(ops, context: context)
        case .requestPlan: pushPlan()
        case .join(let id): join(sessionID: id, context: context)
        case .ack(let ack):
            guard let session = try? find(ack.sessionID, context: context),
                  var endpoint = try? WatchSessionSync.endpoint(of: session) else { return }
            endpoint.acknowledge(ack)
            try? WatchSessionSync.store(endpoint, in: session)
            _ = PersistenceErrorCenter.shared.save(context, operation: "Recording what the watch received")
        case .plan, .recordingStored:
            break
        }
    }

    private func apply(_ ops: [SyncOperation], context: ModelContext) {
        for (sessionID, group) in Dictionary(grouping: ops, by: \.sessionID) {
            do {
                var session = try find(sessionID, context: context)
                var endpoint = try session.flatMap { try WatchSessionSync.endpoint(of: $0) }
                    ?? waiting[sessionID] ?? SyncEndpoint(device: .phone)
                var outgoing: [SyncOperation] = []
                if let session, !session.isCompleted {
                    outgoing += WatchSessionSync.captureLocalEdits(of: session, into: &endpoint, now: .now)
                }
                for op in group.sorted(by: { ($0.device.rawValue, $0.seq) < ($1.device.rawValue, $1.seq) }) {
                    endpoint.receive(op)
                }
                guard let replica = endpoint.replica else { waiting[sessionID] = endpoint; continue }
                waiting[sessionID] = nil
                if session == nil {
                    let startedAt = group.first { if case .sessionStarted = $0.payload { return true } else { return false } }?
                        .timestamp ?? .now
                    let created = try WatchSessionSync.materialize(replica, startedAt: startedAt, context: context)
                    created.syncReviewReasonRaw = try reviewReason(for: replica.snapshot, startedAt: startedAt,
                                                                    excluding: created, context: context)
                    session = created
                } else if let session, !session.isCompleted {
                    try WatchSessionSync.project(replica.view(), onto: session,
                                                 phone: try WatchSessionSync.phoneContext(of: replica), context: context)
                }
                if group.contains(where: { if case .restChanged = $0.payload { return true } else { return false } }) {
                    let view = replica.view()
                    let next = view.exercises.first { $0.sets.contains { $0.status == .planned } }?.catalog.name ?? ""
                    NotificationCenter.default.post(name: .watchRestChanged,
                                                    object: RestTimer.Change(state: view.rest, exerciseName: next))
                }
                guard let session else { continue }
                if session.isCompleted {
                    // Late operations after banking without the watch go through the
                    // correction path: values first, then structure; milestones
                    // rebuild and program state is not replayed (design section 5).
                    let late = WatchSessionSync.lateCorrections(view: replica.view(), session: session)
                    if !late.corrections.isEmpty {
                        try SessionCorrectionService.applyAndRebuild(late.corrections, in: session, context: context)
                    }
                    if !late.pending.isEmpty {
                        try SessionCorrectionService.applyWatchStructure(
                            replica.view(), pendingSetIDs: late.pending,
                            phone: try WatchSessionSync.phoneContext(of: replica), to: session, context: context)
                    }
                    if !late.corrections.isEmpty || !late.pending.isEmpty {
                        PersistenceErrorCenter.shared.message = "Sets from your watch were added to a saved session."
                    }
                }
                try WatchSessionSync.store(endpoint, in: session)
                _ = PersistenceErrorCenter.shared.save(context, operation: "Saving sets from your watch")
                send(.ack(replica.acknowledgement(for: .watch)))
                if !outgoing.isEmpty { send(.operations(outgoing)) }
                if try WatchSessionBanking.bankIfReady(session, context: context) != nil { pushPlan() }
            } catch {
                PersistenceErrorCenter.shared.message = "Cadence couldn't apply changes from your watch: "
                    + error.localizedDescription
            }
        }
    }

    /// The watch's Continue: share the phone's open session. The phone becomes
    /// its starter, so the watch receives a `sessionStarted` it can build from.
    private func join(sessionID: String, context: ModelContext) {
        guard let session = try? find(sessionID, context: context), !session.isCompleted else { return }
        do {
            var endpoint: SyncEndpoint
            if let existing = try WatchSessionSync.endpoint(of: session) {
                endpoint = existing
            } else {
                endpoint = SyncEndpoint(device: .phone)
                let title = session.programName ?? "Workout"
                _ = endpoint.start(sessionID: session.id,
                                   snapshot: try WatchSessionSync.snapshot(of: session, title: title, builtAt: .now),
                                   operationID: UUID().uuidString, now: session.date)
            }
            _ = WatchSessionSync.captureLocalEdits(of: session, into: &endpoint, now: .now)
            try WatchSessionSync.store(endpoint, in: session)
            _ = PersistenceErrorCenter.shared.save(context, operation: "Sharing your session with the watch")
            send(.operations(endpoint.outbox))
        } catch {
            PersistenceErrorCenter.shared.message = "Cadence couldn't share this session with your watch: "
                + error.localizedDescription
        }
    }

    /// After any save: send edits the phone made to a shared, open session.
    private func sendLocalEdits() {
        guard !capturing, let context = container?.mainContext else { return }
        capturing = true
        defer { capturing = false }
        guard let open = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { !$0.isCompleted })) else { return }
        for session in open where session.syncStateData != nil {
            guard var endpoint = try? WatchSessionSync.endpoint(of: session) else { continue }
            let ops = WatchSessionSync.captureLocalEdits(of: session, into: &endpoint, now: .now)
            guard !ops.isEmpty else { continue }
            try? WatchSessionSync.store(endpoint, in: session)
            _ = PersistenceErrorCenter.shared.save(context, operation: "Sending your edits to the watch")
            send(.operations(ops))
        }
    }

    /// The phone's rest changed by a phone action: share it with the watch for
    /// every open shared session whose rest differs.
    private func sendRest(_ state: RestClock.State?) {
        guard let context = container?.mainContext,
              let open = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { !$0.isCompleted }))
        else { return }
        for session in open where session.syncStateData != nil {
            guard var endpoint = try? WatchSessionSync.endpoint(of: session),
                  endpoint.replica.map({ $0.view().rest != state }) == true,
                  let op = endpoint.issue(.restChanged(state), operationID: UUID().uuidString, now: .now) else { continue }
            try? WatchSessionSync.store(endpoint, in: session)
            _ = PersistenceErrorCenter.shared.save(context, operation: "Sharing the rest timer with the watch")
            send(.operations([op]))
        }
    }

    /// Duplicate starts and stale plans wait for the owner (design sections 4–5).
    private func reviewReason(for snapshot: SyncSessionSnapshot, startedAt: Date, excluding created: WorkoutSession,
                              context: ModelContext) throws -> String? {
        if !Calendar.current.isDate(snapshot.builtAt, inSameDayAs: startedAt) { return "stalePlan" }
        guard let position = snapshot.position else { return nil }
        func positionOf(_ s: WorkoutSession) -> SyncProgramPosition? {
            guard let id = s.programID, let cycle = s.programCycleNumber, let week = s.programWeek,
                  let day = s.programDayIndex else { return nil }
            return SyncProgramPosition(programID: id, cycle: cycle, week: week, dayIndex: day, tfhPolicyID: s.tfhPolicyID)
        }
        let others = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.persistentModelID != created.persistentModelID }
        if others.contains(where: { !$0.isCompleted && positionOf($0) == position }) { return "duplicate" }
        let program = try context.fetch(FetchDescriptor<Program>()).first { $0.id == position.programID }
        let programNow = program.map {
            SyncProgramPosition(programID: $0.id, cycle: $0.cycleNumber, week: $0.currentWeek,
                                dayIndex: $0.nextDayIndex, tfhPolicyID: position.tfhPolicyID)
        }
        return SyncSessionRules.duplicatesBankedWork(position, bankedPositions: others.filter(\.isCompleted).compactMap(positionOf),
                                                     programNow: programNow) ? "duplicate" : nil
    }

    private func find(_ id: String, context: ModelContext) throws -> WorkoutSession? {
        try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })).first
    }

    private func send(_ wire: WatchWire) {
        guard WCSession.isSupported(), let message = try? wire.dictionary() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        if session.isReachable { session.sendMessage(message, replyHandler: nil) { _ in } }
        if case .operations = wire { session.transferUserInfo(message) }
        else if !session.isReachable { session.transferUserInfo(message) }
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.pushPlan() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushPlan() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let wire = WatchWire.decode(userInfo) else { return }
        Task { @MainActor in self.handle(wire) }
    }

    /// A motion recording from the watch. Stored before returning (the system
    /// deletes the incoming file afterwards), then acknowledged so the watch
    /// can delete its copy.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let sidecar = file.metadata?[WatchWire.motionMetadataKey] as? Data,
              let id = try? MotionRecordingStore.store(samplesAt: file.fileURL, sidecar: sidecar) else { return }
        Task { @MainActor in self.send(.recordingStored(recordingID: id)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let wire = WatchWire.decode(message) else { return }
        Task { @MainActor in self.handle(wire) }
    }
}
