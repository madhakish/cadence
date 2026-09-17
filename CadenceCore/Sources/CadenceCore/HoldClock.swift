import Foundation

/// A continuous timed hold, independent of rest. Epoch time keeps the result
/// accurate when display ticks are delayed or the app is backgrounded.
/// Stopping ends the attempt; resuming would incorrectly count rest as work.
public enum HoldClock {
    public struct State: Equatable, Sendable {
        public let startEpoch: Double
        public let targetSeconds: Int
        public var stoppedEpoch: Double?
    }

    public static func start(seconds: Int, now: Double) -> State? {
        guard (1...1800).contains(seconds), now.isFinite else { return nil }
        return State(startEpoch: now, targetSeconds: seconds)
    }

    public static func elapsed(_ state: State, now: Double) -> Double {
        let end = state.stoppedEpoch ?? now
        guard end.isFinite else { return 0 }
        return min(Double(state.targetSeconds), max(0, end - state.startEpoch))
    }

    public static func remaining(_ state: State, now: Double) -> Int {
        Int(ceil(Double(state.targetSeconds) - elapsed(state, now: now)))
    }

    /// Whole seconds actually held, capped at the target. Delayed callbacks
    /// never award extra work, and a partial second is never rounded up.
    public static func loggedSeconds(_ state: State, now: Double) -> Int {
        Int(floor(elapsed(state, now: now)))
    }

    public static func stop(_ state: State, now: Double) -> State {
        guard state.stoppedEpoch == nil, now.isFinite else { return state }
        var stopped = state
        stopped.stoppedEpoch = state.startEpoch + elapsed(state, now: now)
        return stopped
    }
}
