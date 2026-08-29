import Foundation

/// A typed calendar span the lifter declares over their timeline. The kinds
/// are deliberately distinct — they differ in whether load was applied,
/// whether the body was recovering, and what the engine should do afterwards
/// (INV-INTERVAL-KINDS-STAY-DISTINCT). Nothing collapses them into a single
/// "break".
public enum TrainingIntervalKind: String, Codable, CaseIterable, Sendable {
    /// Planned reduced-load training inside a cycle — sessions still expected.
    case deload
    /// Planned no-training days. Not missed days.
    case rest
    /// Travel, gym closure, illness, layoff. Not missed days; return may
    /// deserve re-entry rather than straight continuation.
    case away
    /// Real work, deliberately off-program: it must not feed program
    /// progression or PR baselines (INV-RECOVERY-WORK-IS-OFF-PROGRAM).
    case activeRecovery

    public var name: String {
        switch self {
        case .deload: return "Deload"
        case .rest: return "Rest"
        case .away: return "Away"
        case .activeRecovery: return "Active recovery"
        }
    }
}

/// Pure calendar math over interval snapshots. Callers pass inclusive
/// day-bounded epoch milliseconds (start-of-day for `startMs`, end-of-day
/// for `endMs`) so both clients resolve time zones the same way at the edge
/// and the shared logic stays a pure number comparison.
/// Mirrors web `core.js` interval helpers.
public struct TrainingIntervalSnapshot: Hashable, Sendable {
    public let kind: TrainingIntervalKind
    public let startMs: Double
    public let endMs: Double

    public init(kind: TrainingIntervalKind, startMs: Double, endMs: Double) {
        self.kind = kind
        self.startMs = startMs
        // An inverted range collapses to its start rather than excusing time
        // it does not cover.
        self.endMs = Swift.max(startMs, endMs)
    }
}

public enum TrainingIntervals {
    /// The kinds that excuse an absence: a day inside one is never a missed
    /// day, never breaks a streak, and never reads as a lapse
    /// (INV-INTERVAL-IS-NOT-A-GAP). Deload deliberately does NOT excuse
    /// absence — deload days still expect sessions.
    public static let absenceExcusingKinds: Set<TrainingIntervalKind> = [.rest, .away, .activeRecovery]

    public static func contains(_ interval: TrainingIntervalSnapshot, _ timeMs: Double) -> Bool {
        timeMs >= interval.startMs && timeMs <= interval.endMs
    }

    /// Whether a moment falls inside any interval of the given kinds.
    public static func inside(
        _ timeMs: Double, intervals: [TrainingIntervalSnapshot],
        kinds: Set<TrainingIntervalKind>? = nil
    ) -> Bool {
        intervals.contains { interval in
            (kinds?.contains(interval.kind) ?? true) && contains(interval, timeMs)
        }
    }

    /// Whether the gap between two trained moments is excused: some
    /// absence-excusing interval overlaps the open time between them. The
    /// spacing advisory and the shorter-spacing trial must not read a
    /// declared break as a training-frequency signal.
    public static func gapExcused(
        fromMs: Double, toMs: Double, intervals: [TrainingIntervalSnapshot]
    ) -> Bool {
        guard toMs > fromMs else { return false }
        return intervals.contains { interval in
            absenceExcusingKinds.contains(interval.kind)
                && interval.startMs <= toMs && interval.endMs >= fromMs
        }
    }

    /// Work logged inside an active-recovery interval is real, banked
    /// history — and explicitly off-program (INV-RECOVERY-WORK-IS-OFF-PROGRAM).
    public static func isOffProgramTime(
        _ timeMs: Double, intervals: [TrainingIntervalSnapshot]
    ) -> Bool {
        inside(timeMs, intervals: intervals, kinds: [.activeRecovery])
    }

    /// The away interval most recently ended before `nowMs`, when it ended
    /// within `windowMs` and no session has been banked since it ended —
    /// the moment to suggest re-entry rather than straight continuation.
    public static func recentReturnFromAway(
        nowMs: Double, lastSessionMs: Double?, intervals: [TrainingIntervalSnapshot],
        windowMs: Double = 7 * 86_400_000
    ) -> TrainingIntervalSnapshot? {
        intervals
            .filter { $0.kind == .away && $0.endMs < nowMs && nowMs - $0.endMs <= windowMs }
            .filter { interval in
                guard let lastSessionMs else { return true }
                return lastSessionMs <= interval.endMs
            }
            .max { $0.endMs < $1.endMs }
    }

    /// Total calendar days per kind within `[sinceMs, untilMs]`, mirroring
    /// the merge-not-sum discipline `HealthComparison.asleepSeconds` uses
    /// for overlapping sleep stages: two same-kind intervals covering the
    /// same day count that day once, not twice. Different kinds never merge
    /// into each other (INV-INTERVAL-KINDS-STAY-DISTINCT) — a day inside
    /// both a deload span and an away span counts for both. Intervals
    /// extending outside the window are clamped to its edges first.
    public static func daysByKind(
        intervals: [TrainingIntervalSnapshot], sinceMs: Double, untilMs: Double
    ) -> [TrainingIntervalKind: Int] {
        var result = Dictionary(uniqueKeysWithValues: TrainingIntervalKind.allCases.map { ($0, 0) })
        guard untilMs > sinceMs else { return result }

        for kind in TrainingIntervalKind.allCases {
            let clamped = intervals
                .filter { $0.kind == kind }
                .compactMap { interval -> (start: Double, end: Double)? in
                    let start = Swift.max(interval.startMs, sinceMs)
                    let end = Swift.min(interval.endMs, untilMs)
                    return start <= end ? (start, end) : nil
                }
                .sorted { $0.start < $1.start }
            guard let first = clamped.first else { continue }

            var totalMs: Double = 0
            var runStart = first.start
            var runEnd = first.end
            for span in clamped.dropFirst() {
                if span.start > runEnd {
                    totalMs += runEnd - runStart + 1
                    runStart = span.start
                    runEnd = span.end
                } else if span.end > runEnd {
                    runEnd = span.end
                }
            }
            totalMs += runEnd - runStart + 1
            result[kind] = Int((totalMs / 86_400_000).rounded())
        }
        return result
    }
}
