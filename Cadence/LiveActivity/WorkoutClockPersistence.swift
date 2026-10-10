import Foundation
import CadenceCore

/// One durable authority shared by foreground controls and LiveActivityIntent
/// (which runs in the app process). Keep the unbounded pause history out of
/// ActivityKit's size-limited ContentState. Only synthetic fixtures are tested.
enum WorkoutClockPersistence {
    private static let key = "workoutClockState"
    private static let lock = NSLock()

    static func load() -> WorkoutClockRecord? {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    static func save(_ record: WorkoutClockRecord) {
        lock.lock()
        defer { lock.unlock() }
        write(record)
    }

    static func clear(for sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard read()?.sessionID == sessionID else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Read/modify/write under one lock so foreground and intent transitions
    /// cannot overwrite each other's measured pause history.
    static func update(for sessionID: String,
                       _ change: (inout WorkoutClockRecord) -> Void) -> WorkoutClockRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard var record = read(), record.sessionID == sessionID else { return nil }
        change(&record)
        write(record)
        return record
    }

    private static func read() -> WorkoutClockRecord? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let record = try? JSONDecoder().decode(WorkoutClockRecord.self, from: data),
              StopwatchRecovery.recordUsable(start: record.start, pausedAt: record.pausedAt, now: Date()) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return record
    }

    private static func write(_ record: WorkoutClockRecord) {
        // All fields are finite dates from the clock. Failure must not leave a
        // stale export history eligible to be written as the current workout.
        guard let data = try? JSONEncoder().encode(record) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
