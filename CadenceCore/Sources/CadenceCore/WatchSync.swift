import Foundation

// Watch ⇄ phone sync for one workout session: the operation vocabulary, a
// Lamport clock, per-field last-writer-wins merge and a deterministic set order.
// Design: docs/superpowers/specs/2026-10-18-apple-watch-design.md, sections 4–6.
//
// Swift-only by owner decision (the web app takes no part in watch sync), so
// this file is intentionally not mapped in docs/reference/parity-map.json.
// Deterministic: nothing here reads a clock or mints an ID; callers pass both.

public enum SyncDevice: String, Codable, CaseIterable, Sendable {
    case phone
    case watch
}

/// A Lamport version plus the device that wrote it. Orders every write
/// totally: version first, then the device as a fixed tie-break, so both
/// replicas pick the same winner whatever their wall clocks say.
public struct SyncStamp: Codable, Hashable, Comparable, Sendable {
    public var version: Int
    public var device: SyncDevice

    public init(version: Int, device: SyncDevice) {
        self.version = version
        self.device = device
    }

    public static func < (a: SyncStamp, b: SyncStamp) -> Bool {
        (a.version, a.device.rawValue) < (b.version, b.device.rawValue)
    }
}

/// One last-writer-wins register. Writing the same stamp twice is a no-op,
/// which is what makes a redelivered operation harmless.
public struct SyncStamped<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public private(set) var value: Value
    public private(set) var stamp: SyncStamp

    public init(_ value: Value, at stamp: SyncStamp) {
        self.value = value
        self.stamp = stamp
    }

    @discardableResult
    public mutating func write(_ newValue: Value, at newStamp: SyncStamp) -> Bool {
        guard newStamp > stamp else { return false }
        value = newValue
        stamp = newStamp
        return true
    }
}

/// Wraps a value that may itself be nil, so a patch can say "set this field to
/// nil" (clear a drop-load reason) as distinct from "leave it alone".
public struct SyncValue<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value

    public init(_ value: Value) { self.value = value }
}

// MARK: - Session shape

public struct SyncCatalogExercise: Codable, Hashable, Sendable {
    public var exerciseID: String
    public var name: String
    public var isPerSide: Bool
    public var loadBasis: LoadBasis
    public var implementCount: Int

    public init(exerciseID: String, name: String, isPerSide: Bool = false,
                loadBasis: LoadBasis = .totalBar, implementCount: Int = 0) {
        self.exerciseID = exerciseID
        self.name = name
        self.isPerSide = isPerSide
        self.loadBasis = loadBasis
        self.implementCount = implementCount
    }
}

/// A set as it is created: the planned prescription plus its starting values.
public struct SyncPlannedSet: Codable, Hashable, Sendable {
    public var id: String
    public var status: SetStatus
    public var reps: Int
    public var weightLb: Double
    public var durationSeconds: Int?
    public var isWarmup: Bool
    public var flags: [String]
    public var autoregReason: AutoregReason?
    public var plannedReps: Int?
    public var plannedWeightLb: Double?
    public var plannedDurationSeconds: Int?
    public var prescriptionBlock: PrescriptionBlockKind

    public init(id: String, status: SetStatus = .planned, reps: Int, weightLb: Double,
                durationSeconds: Int? = nil, isWarmup: Bool = false, flags: [String] = [],
                autoregReason: AutoregReason? = nil, plannedReps: Int? = nil,
                plannedWeightLb: Double? = nil, plannedDurationSeconds: Int? = nil,
                prescriptionBlock: PrescriptionBlockKind = .work) {
        self.id = id
        self.status = status
        self.reps = reps
        self.weightLb = weightLb
        self.durationSeconds = durationSeconds
        self.isWarmup = isWarmup
        self.flags = flags
        self.autoregReason = autoregReason
        self.plannedReps = plannedReps
        self.plannedWeightLb = plannedWeightLb
        self.plannedDurationSeconds = plannedDurationSeconds
        self.prescriptionBlock = prescriptionBlock
    }
}

public struct SyncPlannedExercise: Codable, Hashable, Sendable {
    /// The session entry's stable ID (`SessionExercise`), not the catalog ID.
    public var id: String
    public var catalog: SyncCatalogExercise
    public var programSlotID: String?
    public var programRole: String?
    public var sets: [SyncPlannedSet]

    public init(id: String, catalog: SyncCatalogExercise, programSlotID: String? = nil,
                programRole: String? = nil, sets: [SyncPlannedSet]) {
        self.id = id
        self.catalog = catalog
        self.programSlotID = programSlotID
        self.programRole = programRole
        self.sets = sets
    }
}

/// Where in a program a planned session sits. Duplicate starts are matched on
/// it (design section 4).
public struct SyncProgramPosition: Codable, Hashable, Sendable {
    public var programID: String
    public var cycle: Int
    public var week: Int
    public var dayIndex: Int
    public var tfhPolicyID: String?

    public init(programID: String, cycle: Int, week: Int, dayIndex: Int, tfhPolicyID: String? = nil) {
        self.programID = programID
        self.cycle = cycle
        self.week = week
        self.dayIndex = dayIndex
        self.tfhPolicyID = tfhPolicyID
    }
}

/// The planned session the phone builds ahead of time and the watch starts.
public struct SyncSessionSnapshot: Codable, Hashable, Sendable {
    public var title: String
    public var position: SyncProgramPosition?
    public var builtAt: Date
    public var exercises: [SyncPlannedExercise]

    public init(title: String, position: SyncProgramPosition?, builtAt: Date, exercises: [SyncPlannedExercise]) {
        self.title = title
        self.position = position
        self.builtAt = builtAt
        self.exercises = exercises
    }
}

// MARK: - Operations

/// Field edits to one set. A nil field is left alone.
public struct SyncSetPatch: Codable, Hashable, Sendable {
    public var status: SetStatus?
    public var reps: Int?
    public var weightLb: Double?
    public var durationSeconds: Int?
    public var isWarmup: Bool?
    public var autoregReason: SyncValue<AutoregReason?>?
    /// The catalog exercise the set was performed as. Sent with a completion so
    /// work done before a swap the device had not seen keeps its movement.
    public var performedAs: String?

    public init(status: SetStatus? = nil, reps: Int? = nil, weightLb: Double? = nil,
                durationSeconds: Int? = nil, isWarmup: Bool? = nil,
                autoregReason: SyncValue<AutoregReason?>? = nil, performedAs: String? = nil) {
        self.status = status
        self.reps = reps
        self.weightLb = weightLb
        self.durationSeconds = durationSeconds
        self.isWarmup = isWarmup
        self.autoregReason = autoregReason
        self.performedAs = performedAs
    }
}

/// Who owns the session's Health workout once the watch has ended it.
public enum SyncHealthOutcome: Codable, Hashable, Sendable {
    case saved(workoutID: String)
    /// Discarded (writing off or unconfirmed) or failed before finishing.
    case notWritten
    /// Finishing reported an error, so Health may hold the workout.
    case unknown
}

public struct SyncSessionEnd: Codable, Hashable, Sendable {
    public var endedAt: Date
    /// Every operation the ending device issued for the session: the phone
    /// banks only once it has processed all of them (design section 5).
    public var operationIDs: [String]
    public var health: SyncHealthOutcome

    public init(endedAt: Date, operationIDs: [String], health: SyncHealthOutcome) {
        self.endedAt = endedAt
        self.operationIDs = operationIDs
        self.health = health
    }
}

public enum SyncPayload: Codable, Hashable, Sendable {
    case sessionStarted(SyncSessionSnapshot)
    case setPerformed(setID: String, patch: SyncSetPatch)
    case setFlags(setID: String, flags: [String])
    case setAdded(exerciseID: String, after: String?, set: SyncPlannedSet)
    /// `sawStatus` is the status stamp the remover had seen. Newer performed
    /// work it had not seen beats the removal.
    case setRemoved(setID: String, sawStatus: SyncStamp)
    // Exercise structure is phone-only: the watch cannot add, reorder or swap.
    case exerciseAdded(after: String?, exercise: SyncPlannedExercise)
    case exerciseRemoved(exerciseID: String, sawStatus: SyncStamp)
    case exerciseMoved(exerciseID: String, after: String?)
    case exerciseReplaced(exerciseID: String, catalog: SyncCatalogExercise)
    case restChanged(RestClock.State?)
    case sessionPaused(at: Date)
    case sessionResumed(at: Date)
    case sessionEnded(SyncSessionEnd)

    var isPhoneOnly: Bool {
        switch self {
        case .exerciseAdded, .exerciseRemoved, .exerciseMoved, .exerciseReplaced: return true
        default: return false
        }
    }
}

public struct SyncOperation: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var device: SyncDevice
    /// 1-based and contiguous per device per session. Receivers apply each
    /// device's operations in this order, whatever order the transport
    /// delivers them in.
    public var seq: Int
    public var version: Int
    /// For display and session timing only; never for ordering.
    public var timestamp: Date
    public var payload: SyncPayload

    public init(id: String, sessionID: String, device: SyncDevice, seq: Int, version: Int,
                timestamp: Date, payload: SyncPayload) {
        self.id = id
        self.sessionID = sessionID
        self.device = device
        self.seq = seq
        self.version = version
        self.timestamp = timestamp
        self.payload = payload
    }

    public var stamp: SyncStamp { SyncStamp(version: version, device: device) }
}

/// "I have processed your operations through `throughSeq`": the sender may
/// drop them from its outbox.
public struct SyncAck: Codable, Hashable, Sendable {
    public var sessionID: String
    public var device: SyncDevice
    public var throughSeq: Int

    public init(sessionID: String, device: SyncDevice, throughSeq: Int) {
        self.sessionID = sessionID
        self.device = device
        self.throughSeq = throughSeq
    }
}

// MARK: - Session rules

public enum SyncSessionRules {
    /// A watch session whose program position already has a banked session,
    /// or that the program has advanced past, is a duplicate. Open sessions
    /// are matched separately with `ProgramSession.make`'s resume rules.
    public static func duplicatesBankedWork(_ position: SyncProgramPosition,
                                            bankedPositions: [SyncProgramPosition],
                                            programNow: SyncProgramPosition?) -> Bool {
        if bankedPositions.contains(position) { return true }
        guard let now = programNow, now.programID == position.programID,
              now.tfhPolicyID == position.tfhPolicyID else { return false }
        return (now.cycle, now.week, now.dayIndex) > (position.cycle, position.week, position.dayIndex)
    }

    /// A cached setting is not consent: the watch writes a Health workout only
    /// if the phone confirmed writing is on after this session began.
    public static func watchMaySaveWorkout(sessionStartedAt: Date, latestSetting: SyncHealthSetting?) -> Bool {
        guard let setting = latestSetting else { return false }
        return setting.enabled && setting.receivedAt >= sessionStartedAt
    }

    /// Bank-time export runs only when no watch workout exists or the watch
    /// reports it wrote none. `unknown` gets no automatic export, matching
    /// `HealthKitService.saveWorkout`'s no-retry rule for ambiguous finishes.
    public static func phoneMayExportAtBank(watchOutcome: SyncHealthOutcome?) -> Bool {
        switch watchOutcome {
        case nil, .notWritten: return true
        case .saved, .unknown: return false
        }
    }
}

/// The phone's Health-writing setting as the watch last received it.
public struct SyncHealthSetting: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var receivedAt: Date

    public init(enabled: Bool, receivedAt: Date) {
        self.enabled = enabled
        self.receivedAt = receivedAt
    }
}
