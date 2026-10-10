import Foundation

/// Measured wall-clock history for the iOS Health export, independent of the
/// resettable stopwatch's display origin. No HealthKit dependency or web write
/// counterpart: the web client cannot export to Apple Health.
public struct HealthWorkoutTiming: Codable, Equatable {
    public struct Pause: Codable, Equatable {
        public let start: Date
        public var end: Date?
    }

    public let start: Date
    public private(set) var pauses: [Pause] = []

    public init(start: Date) { self.start = start }

    public mutating func pause(at date: Date) {
        guard pauses.last?.end != nil || pauses.isEmpty else { return }
        pauses.append(Pause(start: date, end: nil))
    }

    public mutating func resume(at date: Date) {
        guard let last = pauses.indices.last, pauses[last].end == nil else { return }
        pauses[last].end = date
    }

    public struct Export: Equatable {
        public let start: Date
        public let end: Date
        /// Complete interior pauses, represented as Health pause/resume events.
        public let pauses: [Pause]
        public let activeDuration: TimeInterval
    }

    /// Freeze at bank time, excluding an ongoing trailing pause altogether.
    /// Reject inconsistent/future timing rather than inventing a workout.
    public func export(endingAt date: Date) -> Export? {
        guard start <= date else { return nil }
        var cursor = start
        var pausedDuration: TimeInterval = 0
        var completed: [Pause] = []
        var end = date
        for (index, pause) in pauses.enumerated() {
            guard pause.start >= cursor, pause.start <= date else { return nil }
            if let resumed = pause.end {
                guard resumed >= pause.start, resumed <= date else { return nil }
                pausedDuration += resumed.timeIntervalSince(pause.start)
                if resumed > pause.start { completed.append(pause) }
                cursor = resumed
            } else {
                guard index == pauses.count - 1 else { return nil }
                end = pause.start
            }
        }
        let activeDuration = end.timeIntervalSince(start) - pausedDuration
        guard activeDuration.isFinite, activeDuration > 0 else { return nil }
        return Export(start: start, end: end, pauses: completed, activeDuration: activeDuration)
    }
}

/// The shipped stopwatch record's three fields keep their names and meaning.
/// The optional export history is additive: old binaries ignore it; old records
/// decode with nil and retain their stopwatch without inventing a real start.
/// This device-local record is neither a SwiftData model nor a portable backup.
public struct WorkoutClockRecord: Codable, Equatable {
    private let version = 2
    public let sessionID: String
    public var start: Date
    public var pausedAt: Date?
    public var healthTiming: HealthWorkoutTiming?

    public init(sessionID: String, start: Date, pausedAt: Date? = nil,
                healthTiming: HealthWorkoutTiming? = nil) {
        self.sessionID = sessionID
        self.start = start
        self.pausedAt = pausedAt
        self.healthTiming = healthTiming
    }

    private enum CodingKeys: String, CodingKey {
        case version, sessionID, start, pausedAt, healthTiming
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try LegacyClockRecordV1(from: decoder)
        sessionID = legacy.sessionID
        start = legacy.start
        pausedAt = legacy.pausedAt
        let storedVersion = (try? values.decode(Int.self, forKey: .version)) ?? 1
        // V1 upgrades without inventing history. Corrupt/unknown optional
        // history must not destroy a usable stopwatch's frozen V1 fields.
        if storedVersion == 2 {
            healthTiming = try? values.decodeIfPresent(HealthWorkoutTiming.self, forKey: .healthTiming)
        } else {
            healthTiming = nil
        }
    }

    public mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
        healthTiming?.pause(at: now)
    }

    public mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        start = start.addingTimeInterval(now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        healthTiming?.resume(at: now)
    }

    /// Reset only the visible stopwatch. If paused, this also resumes timing.
    /// The actual workout's start and completed pauses remain intact.
    public mutating func reset(at now: Date) {
        healthTiming?.resume(at: now)
        start = now
        pausedAt = nil
    }
}

/// Frozen shipped UserDefaults shape. Both V1 and V2 retain these exact fields;
/// upgrading adds optional history, and a V1 reader can still open V2 bytes.
private struct LegacyClockRecordV1: Codable {
    let sessionID: String
    let start: Date
    let pausedAt: Date?
}
