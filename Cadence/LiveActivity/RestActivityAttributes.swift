import ActivityKit
import Foundation

/// The contract shared between the app and the widget extension for the
/// between-sets rest Live Activity (Lock Screen + Dynamic Island).
///
/// The countdown is derived entirely from `endDate`, so `Text(timerInterval:)`
/// on the Lock Screen ticks with the phone asleep and the app suspended — no
/// background execution, no push. When paused we freeze the display on
/// `pausedRemaining` instead.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the rest ends. Ignored for display while `isPaused`.
        var endDate: Date
        var isPaused: Bool
        /// Seconds left at the moment of pause (frozen display source).
        var pausedRemaining: TimeInterval
        /// Original rest length, for the progress ring.
        var total: TimeInterval
    }

    /// The lift being rested (shown on the activity). Static for the activity's life.
    var exerciseName: String
}
