import Foundation

// One device's copy of a synced session, and the endpoint that issues and
// receives operations for it. Design: docs/superpowers/specs/
// 2026-10-18-apple-watch-design.md, sections 4–5. Swift-only (see WatchSync.swift).
//
// Convergence: both devices apply the same operations in per-device sequence
// order, every field write is last-writer-wins by stamp, and the two
// performed-work rules (a removed set with unseen performed work comes back; a
// set performed as a since-swapped exercise keeps its movement) are derived in
// `view()` rather than stored, so arrival order cannot change the result.

public enum SyncApplyOutcome: Equatable, Sendable {
    case applied
    /// Already processed: redelivery is a no-op.
    case duplicate
    /// Arrived ahead of an earlier operation from the same device; held until
    /// the gap fills.
    case buffered
    /// Processed but not applied, with the reason shown in the review notice.
    case rejected(String)
}

public struct SyncRejection: Codable, Hashable, Sendable {
    public var operationID: String
    public var reason: String
}

public struct SyncRemoval: Codable, Hashable, Sendable {
    public var stamp: SyncStamp
    /// The newest status stamp the remover had seen. Completed work stamped
    /// later than this was not seen, so it beats the removal.
    public var sawStatus: SyncStamp
}

public struct SyncReplica: Codable, Hashable, Sendable {
    public struct SetState: Codable, Hashable, Sendable {
        public let id: String
        public let exerciseID: String
        public let after: String?
        public let inserted: SyncStamp
        /// The set as created; planned fields are read from here.
        public let created: SyncPlannedSet
        public var status: SyncStamped<SetStatus>
        public var reps: SyncStamped<Int>
        public var weightLb: SyncStamped<Double>
        public var durationSeconds: SyncStamped<Int?>
        public var isWarmup: SyncStamped<Bool>
        public var flags: SyncStamped<[String]>
        public var autoregReason: SyncStamped<AutoregReason?>
        public var performedAs: SyncStamped<String?>
        public var removal: SyncRemoval?

        init(_ set: SyncPlannedSet, exerciseID: String, after: String?, at stamp: SyncStamp) {
            id = set.id
            self.exerciseID = exerciseID
            self.after = after
            inserted = stamp
            created = set
            status = SyncStamped(set.status, at: stamp)
            reps = SyncStamped(set.reps, at: stamp)
            weightLb = SyncStamped(set.weightLb, at: stamp)
            durationSeconds = SyncStamped(set.durationSeconds, at: stamp)
            isWarmup = SyncStamped(set.isWarmup, at: stamp)
            flags = SyncStamped(set.flags, at: stamp)
            autoregReason = SyncStamped(set.autoregReason, at: stamp)
            performedAs = SyncStamped(nil, at: stamp)
        }

        /// Performed work never disappears through sync: a removal hides a set
        /// only if the remover had seen its latest status.
        var hasUnseenWork: Bool {
            guard let removal else { return false }
            return status.value == .completed && status.stamp > removal.sawStatus
        }

        public var isVisible: Bool { removal == nil || hasUnseenWork }
    }

    public struct ExerciseState: Codable, Hashable, Sendable {
        public let id: String
        public var catalog: SyncStamped<SyncCatalogExercise>
        /// Catalog entries this exercise was swapped away from, oldest first.
        public var formerCatalogs: [SyncCatalogExercise]
        public let programSlotID: String?
        public let programRole: String?
        public var removal: SyncRemoval?
    }

    public struct TimingEvent: Codable, Hashable, Sendable {
        public var operationID: String
        public var at: Date
        public var paused: Bool
    }

    public let sessionID: String
    public let startedBy: SyncDevice
    public let snapshot: SyncSessionSnapshot
    /// Exercise entry order, removed entries included so anchors still resolve.
    public private(set) var exerciseOrder: [String]
    public private(set) var exercises: [String: ExerciseState]
    public private(set) var sets: [String: SetState]
    public private(set) var rest: SyncStamped<RestClock.State?>
    public private(set) var timing: [TimingEvent]
    public private(set) var ended: SyncStamped<SyncSessionEnd?>
    public private(set) var processedOperationIDs: Set<String>
    public private(set) var rejections: [SyncRejection]
    /// Next expected sequence number per device, keyed by `SyncDevice.rawValue`.
    public private(set) var nextSeq: [String: Int]
    public private(set) var pending: [SyncOperation]

    /// A replica exists from its session's `sessionStarted`, which must be the
    /// starting device's first operation.
    public init?(starting op: SyncOperation) {
        guard case .sessionStarted(let snapshot) = op.payload, op.seq == 1 else { return nil }
        sessionID = op.sessionID
        startedBy = op.device
        self.snapshot = snapshot
        exerciseOrder = []
        exercises = [:]
        sets = [:]
        rest = SyncStamped(nil, at: op.stamp)
        timing = []
        ended = SyncStamped(nil, at: op.stamp)
        processedOperationIDs = [op.id]
        rejections = []
        nextSeq = [op.device.rawValue: 2]
        pending = []
        for exercise in snapshot.exercises {
            insertExercise(exercise, after: exerciseOrder.last, at: op.stamp)
        }
    }

    @discardableResult
    public mutating func receive(_ op: SyncOperation) -> SyncApplyOutcome {
        guard op.sessionID == sessionID else { return .rejected("operation belongs to another session") }
        let expected = nextSeq[op.device.rawValue, default: 1]
        if op.seq < expected || processedOperationIDs.contains(op.id) { return .duplicate }
        if op.seq > expected {
            if !pending.contains(where: { $0.device == op.device && $0.seq == op.seq }) { pending.append(op) }
            return .buffered
        }
        let outcome = process(op)
        drainPending()
        return outcome
    }

    /// The highest contiguous sequence processed from `device`, for its outbox.
    public func acknowledgement(for device: SyncDevice) -> SyncAck {
        SyncAck(sessionID: sessionID, device: device, throughSeq: nextSeq[device.rawValue, default: 1] - 1)
    }

    /// The phone banks only after the ending device's every listed operation
    /// has been processed (applied, reinstated or rejected).
    public var isReadyToBank: Bool {
        guard let end = ended.value else { return false }
        return end.operationIDs.allSatisfy(processedOperationIDs.contains)
    }

    public func statusStamp(ofSet id: String) -> SyncStamp? { sets[id]?.status.stamp }

    public func newestStatusStamp(inExercise id: String) -> SyncStamp? {
        sets.values.filter { $0.exerciseID == id }.map(\.status.stamp).max()
    }

    // MARK: Applying

    private mutating func drainPending() {
        while let index = pending.firstIndex(where: { $0.seq == nextSeq[$0.device.rawValue, default: 1] }) {
            process(pending.remove(at: index))
        }
    }

    @discardableResult
    private mutating func process(_ op: SyncOperation) -> SyncApplyOutcome {
        nextSeq[op.device.rawValue, default: 1] += 1
        processedOperationIDs.insert(op.id)
        let outcome = apply(op)
        if case .rejected(let reason) = outcome {
            rejections.append(SyncRejection(operationID: op.id, reason: reason))
        }
        return outcome
    }

    private mutating func apply(_ op: SyncOperation) -> SyncApplyOutcome {
        let stamp = op.stamp
        if op.payload.isPhoneOnly && op.device != .phone {
            return .rejected("only the phone changes the exercise list")
        }
        switch op.payload {
        case .sessionStarted:
            return .rejected("session already started")

        case let .setPerformed(setID, patch):
            guard var set = sets[setID] else { return .rejected("unknown set") }
            if let v = patch.status { set.status.write(v, at: stamp) }
            if let v = patch.reps { set.reps.write(v, at: stamp) }
            if let v = patch.weightLb { set.weightLb.write(v, at: stamp) }
            if let v = patch.durationSeconds { set.durationSeconds.write(v, at: stamp) }
            if let v = patch.isWarmup { set.isWarmup.write(v, at: stamp) }
            if let v = patch.autoregReason { set.autoregReason.write(v.value, at: stamp) }
            if let v = patch.performedAs { set.performedAs.write(v, at: stamp) }
            sets[setID] = set
            // Applied either way so both replicas hold the same fields; a hidden
            // set only reports the edit as rejected.
            return set.isVisible ? .applied : .rejected("set was removed")

        case let .setFlags(setID, flags):
            guard var set = sets[setID] else { return .rejected("unknown set") }
            let normalized = SetLifecycle.normalizedFlags(quality: SetLifecycle.quality(in: flags),
                                                          stoppedEarly: flags.contains("stopped early"),
                                                          rir: SetLifecycle.rir(in: flags))
            set.flags.write(normalized, at: stamp)
            sets[setID] = set
            return set.isVisible ? .applied : .rejected("set was removed")

        case let .setAdded(exerciseID, after, set):
            guard exercises[exerciseID] != nil else { return .rejected("unknown exercise") }
            guard sets[set.id] == nil else { return .rejected("set already exists") }
            if let after, sets[after]?.exerciseID != exerciseID { return .rejected("anchor set is not in that exercise") }
            sets[set.id] = SetState(set, exerciseID: exerciseID, after: after, at: stamp)
            return .applied

        case let .setRemoved(setID, sawStatus):
            guard var set = sets[setID] else { return .rejected("unknown set") }
            let removal = SyncRemoval(stamp: stamp, sawStatus: sawStatus)
            if set.removal.map({ $0.stamp < stamp }) ?? true { set.removal = removal }
            sets[setID] = set
            return .applied

        case let .exerciseAdded(after, exercise):
            guard exercises[exercise.id] == nil else { return .rejected("exercise already exists") }
            if let after, exercises[after] == nil { return .rejected("unknown anchor exercise") }
            insertExercise(exercise, after: after, at: stamp)
            return .applied

        case let .exerciseRemoved(exerciseID, sawStatus):
            guard var exercise = exercises[exerciseID] else { return .rejected("unknown exercise") }
            let removal = SyncRemoval(stamp: stamp, sawStatus: sawStatus)
            if exercise.removal.map({ $0.stamp < stamp }) ?? true { exercise.removal = removal }
            exercises[exerciseID] = exercise
            return .applied

        case let .exerciseMoved(exerciseID, after):
            guard exercises[exerciseID] != nil, after != exerciseID else { return .rejected("unknown exercise") }
            if let after, exercises[after] == nil { return .rejected("unknown anchor exercise") }
            exerciseOrder.removeAll { $0 == exerciseID }
            exerciseOrder.insert(exerciseID, at: after.flatMap { exerciseOrder.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
            return .applied

        case let .exerciseReplaced(exerciseID, catalog):
            guard var exercise = exercises[exerciseID] else { return .rejected("unknown exercise") }
            let previous = exercise.catalog.value
            if exercise.catalog.write(catalog, at: stamp) { exercise.formerCatalogs.append(previous) }
            exercises[exerciseID] = exercise
            return .applied

        case let .restChanged(state):
            rest.write(state, at: stamp)
            return .applied

        case let .sessionPaused(at):
            timing.append(TimingEvent(operationID: op.id, at: at, paused: true))
            return .applied

        case let .sessionResumed(at):
            timing.append(TimingEvent(operationID: op.id, at: at, paused: false))
            return .applied

        case let .sessionEnded(end):
            ended.write(end, at: stamp)
            return .applied
        }
    }

    private mutating func insertExercise(_ exercise: SyncPlannedExercise, after: String?, at stamp: SyncStamp) {
        exercises[exercise.id] = ExerciseState(
            id: exercise.id, catalog: SyncStamped(exercise.catalog, at: stamp), formerCatalogs: [],
            programSlotID: exercise.programSlotID, programRole: exercise.programRole, removal: nil)
        let index = after.flatMap { exerciseOrder.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        exerciseOrder.insert(exercise.id, at: index)
        var previous: String?
        for set in exercise.sets where sets[set.id] == nil {
            sets[set.id] = SetState(set, exerciseID: exercise.id, after: previous, at: stamp)
            previous = set.id
        }
    }

    // MARK: Reading

    /// Set IDs of one exercise in sync order, hidden sets included. Sets
    /// inserted after the same anchor order newest stamp first, so concurrent
    /// inserts land identically on both devices.
    public func orderedSetIDs(inExercise exerciseID: String) -> [String] {
        var children: [String?: [SetState]] = [:]
        for set in sets.values where set.exerciseID == exerciseID {
            children[set.after, default: []].append(set)
        }
        for key in children.keys {
            children[key]?.sort { ($0.inserted, $0.id) > ($1.inserted, $1.id) }
        }
        var ordered: [String] = []
        var stack: [String?] = [nil]
        var visited: Set<String> = []
        while let anchor = stack.popLast() {
            if let anchor {
                guard visited.insert(anchor).inserted else { continue }
                ordered.append(anchor)
            }
            for child in (children[anchor] ?? []).reversed() { stack.append(child.id) }
        }
        return ordered
    }

    public func view() -> SyncSessionView {
        var out: [SyncSessionView.Exercise] = []
        var notice = SyncReviewNotice()
        for exerciseID in exerciseOrder {
            guard let exercise = exercises[exerciseID] else { continue }
            let visible = orderedSetIDs(inExercise: exerciseID).compactMap { sets[$0] }.filter(\.isVisible)
            if let removal = exercise.removal,
               !visible.contains(where: { $0.status.value == .completed && $0.status.stamp > removal.sawStatus }) {
                continue
            }
            if exercise.removal != nil { notice.reinstatedExerciseIDs.append(exerciseID) }
            notice.reinstatedSetIDs += visible.filter { $0.removal != nil }.map(\.id)

            // Work performed as another movement keeps that movement, in its own
            // entry directly before the swapped one.
            let current = exercise.catalog.value.exerciseID
            func performedElsewhere(_ set: SetState) -> String? {
                guard set.status.value == .completed, let id = set.performedAs.value, id != current else { return nil }
                return id
            }
            var movedOrder: [String] = []
            var moved: [String: [SetState]] = [:]
            for set in visible {
                guard let id = performedElsewhere(set) else { continue }
                if moved[id] == nil { movedOrder.append(id) }
                moved[id, default: []].append(set)
            }
            for catalogID in movedOrder {
                let catalog = exercise.formerCatalogs.last { $0.exerciseID == catalogID }
                    ?? SyncCatalogExercise(exerciseID: catalogID, name: catalogID)
                let entryID = "\(exerciseID)~\(catalogID)"
                notice.reinstatedExerciseIDs.append(entryID)
                out.append(SyncSessionView.Exercise(id: entryID, catalog: catalog, programSlotID: nil,
                                                    programRole: nil, isReinstated: true,
                                                    sets: moved[catalogID, default: []].map(SyncSessionView.Set.init)))
            }
            out.append(SyncSessionView.Exercise(id: exerciseID, catalog: exercise.catalog.value,
                                                programSlotID: exercise.programSlotID,
                                                programRole: exercise.programRole,
                                                isReinstated: exercise.removal != nil,
                                                sets: visible.filter { performedElsewhere($0) == nil }
                                                    .map(SyncSessionView.Set.init)))
        }
        notice.rejected = rejections
        return SyncSessionView(exercises: out, rest: rest.value,
                               timing: timing.sorted { ($0.at, $0.operationID) < ($1.at, $1.operationID) },
                               ended: ended.value, notice: notice)
    }
}

/// What the session looks like after merging: what the phone writes to
/// SwiftData and the watch draws.
public struct SyncSessionView: Equatable, Sendable {
    public struct Set: Equatable, Sendable {
        public var id: String
        public var status: SetStatus
        public var reps: Int
        public var weightLb: Double
        public var durationSeconds: Int?
        public var isWarmup: Bool
        public var flags: [String]
        public var autoregReason: AutoregReason?
        public var created: SyncPlannedSet
        public var isReinstated: Bool

        init(_ state: SyncReplica.SetState) {
            id = state.id
            status = state.status.value
            reps = state.reps.value
            weightLb = state.weightLb.value
            durationSeconds = state.durationSeconds.value
            isWarmup = state.isWarmup.value
            flags = state.flags.value
            autoregReason = state.autoregReason.value
            created = state.created
            isReinstated = state.removal != nil
        }
    }

    public struct Exercise: Equatable, Sendable {
        public var id: String
        public var catalog: SyncCatalogExercise
        public var programSlotID: String?
        public var programRole: String?
        public var isReinstated: Bool
        public var sets: [Set]
    }

    public var exercises: [Exercise]
    public var rest: RestClock.State?
    public var timing: [SyncReplica.TimingEvent]
    public var ended: SyncSessionEnd?
    public var notice: SyncReviewNotice
}

/// What the owner is told after a merge: work sync brought back and edits it
/// could not apply. Empty in the ordinary case.
public struct SyncReviewNotice: Equatable, Sendable {
    public var reinstatedSetIDs: [String] = []
    public var reinstatedExerciseIDs: [String] = []
    public var rejected: [SyncRejection] = []

    public var isEmpty: Bool { reinstatedSetIDs.isEmpty && reinstatedExerciseIDs.isEmpty && rejected.isEmpty }
}

/// One device's side of a session: its Lamport clock, sequence counter,
/// replica and unacknowledged outbox. Persist it as Codable.
public struct SyncEndpoint: Codable, Hashable, Sendable {
    public let device: SyncDevice
    public private(set) var clock: Int
    public private(set) var nextSeq: Int
    public private(set) var replica: SyncReplica?
    public private(set) var outbox: [SyncOperation]
    /// Operations that arrived before this device saw the session start.
    public private(set) var early: [SyncOperation]

    public init(device: SyncDevice) {
        self.device = device
        clock = 0
        nextSeq = 1
        replica = nil
        outbox = []
        early = []
    }

    /// Start a session on this device. Returns nil if one is already running.
    public mutating func start(sessionID: String, snapshot: SyncSessionSnapshot,
                               operationID: String, now: Date) -> SyncOperation? {
        guard replica == nil else { return nil }
        let op = make(sessionID: sessionID, payload: .sessionStarted(snapshot), operationID: operationID, now: now)
        replica = SyncReplica(starting: op)
        outbox.append(op)
        replayEarly()
        return op
    }

    /// Issue a local edit: applied here first, then queued for the other device.
    public mutating func issue(_ payload: SyncPayload, operationID: String, now: Date) -> SyncOperation? {
        guard let sessionID = replica?.sessionID else { return nil }
        let op = make(sessionID: sessionID, payload: payload, operationID: operationID, now: now)
        replica?.receive(op)
        outbox.append(op)
        return op
    }

    @discardableResult
    public mutating func receive(_ op: SyncOperation) -> SyncApplyOutcome {
        clock = max(clock, op.version)
        guard replica != nil else {
            if op.seq == 1, case .sessionStarted = op.payload {
                replica = SyncReplica(starting: op)
                replayEarly()
                return .applied
            }
            if !early.contains(op) { early.append(op) }
            return .buffered
        }
        return replica!.receive(op)
    }

    public mutating func acknowledge(_ ack: SyncAck) {
        guard ack.device == device, ack.sessionID == replica?.sessionID else { return }
        outbox.removeAll { $0.seq <= ack.throughSeq }
    }

    /// The operations `sessionEnded` must list: everything not yet
    /// acknowledged. An acknowledged operation has already been processed by
    /// the other device, so the end barrier does not need it.
    public var unacknowledgedOperationIDs: [String] { outbox.map(\.id) }

    private mutating func make(sessionID: String, payload: SyncPayload, operationID: String, now: Date) -> SyncOperation {
        clock += 1
        defer { nextSeq += 1 }
        return SyncOperation(id: operationID, sessionID: sessionID, device: device, seq: nextSeq,
                             version: clock, timestamp: now, payload: payload)
    }

    private mutating func replayEarly() {
        let held = early
        early = []
        for op in held { receive(op) }
    }
}
