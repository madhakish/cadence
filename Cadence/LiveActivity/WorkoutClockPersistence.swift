import Foundation
import CadenceCore

/// One durable authority shared by foreground controls and LiveActivityIntent
/// (which runs in the app process). Keep the unbounded pause history out of
/// ActivityKit's size-limited ContentState. Only synthetic fixtures are tested.
enum WorkoutClockPersistence {
    private static let key = "workoutClockState"
    private static let lock = NSLock()

    static func load(defaults: UserDefaults = .standard) -> WorkoutClockRecord? {
        lock.lock()
        defer { lock.unlock() }
        return read(defaults: defaults)
    }

    /// Adopt a recovered activity (or explicitly start a new clock) only if
    /// no intent changed/cleared the durable state during the recovery read.
    /// A newer matching record wins; a newer owner or teardown cancels adoption.
    static func adopt(_ proposed: WorkoutClockRecord,
                      replacing observed: WorkoutClockRecord?,
                      defaults: UserDefaults = .standard) -> WorkoutClockRecord? {
        lock.lock()
        defer { lock.unlock() }
        let current = read(defaults: defaults)
        if current != observed {
            return current?.sessionID == proposed.sessionID ? current : nil
        }
        write(proposed, defaults: defaults)
        return proposed
    }

    static func clear(for sessionID: String, defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        guard read(defaults: defaults)?.sessionID == sessionID else { return }
        defaults.removeObject(forKey: key)
    }

    /// Read/modify/write under one lock so foreground and intent transitions
    /// cannot overwrite each other's measured pause history.
    static func update(for sessionID: String, recovering fallback: WorkoutClockRecord? = nil,
                       defaults: UserDefaults = .standard,
                       _ change: (inout WorkoutClockRecord) -> Void) -> WorkoutClockRecord? {
        lock.lock()
        defer { lock.unlock() }
        let persisted = read(defaults: defaults)
        guard persisted == nil || persisted?.sessionID == sessionID else { return nil }
        // Shipped V1 intents changed only ActivityKit. Import that snapshot
        // once; every V2 record is authoritative even without export history.
        let candidate = persisted?.isLegacy == true ? (fallback ?? persisted) : (persisted ?? fallback)
        guard var record = candidate, record.sessionID == sessionID else { return nil }
        change(&record)
        // A legacy activity without a record may still update its face, but
        // must not resurrect durable state while a bank/discard teardown is
        // queued. Foreground adoption explicitly saves recovered records.
        if persisted != nil { write(record, defaults: defaults) }
        return record
    }

    private static func read(defaults: UserDefaults) -> WorkoutClockRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let record = try? JSONDecoder().decode(WorkoutClockRecord.self, from: data),
              StopwatchRecovery.recordUsable(start: record.start, pausedAt: record.pausedAt, now: Date()) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return record
    }

    private static func write(_ record: WorkoutClockRecord, defaults: UserDefaults) {
        // All fields are finite dates from the clock. Failure must not leave a
        // stale export history eligible to be written as the current workout.
        guard let data = try? JSONEncoder().encode(record) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
