import Foundation

/// Pure state math for the between-sets rest countdown. One implementation of
/// pause/resume/extend shared by the in-app `RestTimer`, the Live Activity
/// controller (both processes render from the same `State`), and — mirrored
/// 1:1 — the web logger (`restClock*` in web/js/core.js). Deterministic: every
/// transition takes `now` explicitly; nothing here reads a clock.
///
/// Epoch seconds, not `Date`: the same numbers flow through the JS mirror and
/// the tests assert identical values on both sides.
public enum RestClock {
    public struct State: Codable, Hashable, Sendable {
        /// When the rest ends (epoch seconds). Meaningful only while running;
        /// frozen (stale) while paused — `resume` recomputes it.
        public var endEpoch: Double
        public var paused: Bool
        /// Seconds left at the moment of pause (the frozen display source).
        public var pausedRemaining: Double
        /// Full rest length including extensions, for the progress ring.
        public var total: Double

        public init(endEpoch: Double, paused: Bool = false, pausedRemaining: Double = 0, total: Double) {
            self.endEpoch = endEpoch
            self.paused = paused
            self.pausedRemaining = pausedRemaining
            self.total = total
        }
    }

    public static func start(total: Double, now: Double) -> State {
        let t = max(0, total)
        return State(endEpoch: now + t, paused: false, pausedRemaining: 0, total: t)
    }

    /// Idempotent: pausing a paused clock changes nothing (a second Lock
    /// Screen tap must not re-freeze a stale remaining).
    public static func pause(_ s: State, now: Double) -> State {
        guard !s.paused else { return s }
        var out = s
        out.paused = true
        out.pausedRemaining = max(0, s.endEpoch - now)
        return out
    }

    /// Idempotent: resuming a running clock changes nothing.
    public static func resume(_ s: State, now: Double) -> State {
        guard s.paused else { return s }
        var out = s
        out.paused = false
        out.endEpoch = now + max(0, s.pausedRemaining)
        return out
    }

    /// Extend (or shrink, negative) the rest. While paused the frozen
    /// remaining moves; while running the end moves. Both floor at 0.
    public static func add(_ s: State, seconds: Double) -> State {
        var out = s
        out.total = max(0, s.total + seconds)
        if s.paused {
            out.pausedRemaining = max(0, s.pausedRemaining + seconds)
        } else {
            out.endEpoch = s.endEpoch + seconds
        }
        return out
    }

    public static func remaining(_ s: State, now: Double) -> Double {
        s.paused ? s.pausedRemaining : max(0, s.endEpoch - now)
    }

    /// 1 at the start of the rest, 0 when it's over (the progress-ring source).
    public static func fractionRemaining(_ s: State, now: Double) -> Double {
        s.total > 0 ? min(1, max(0, remaining(s, now: now) / s.total)) : 0
    }
}
