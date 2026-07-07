import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Countdown between sets. Manual by default — armed from the Rest buttons or
/// the bottom bar; only auto-armed after a set when the auto-start setting is
/// on. Schedules a local notification so the phone can sit face-down on the
/// chalk bucket, and buzzes on finish when haptics are enabled.
@Observable
final class RestTimer {
    private(set) var remaining: TimeInterval = 0
    private(set) var total: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var exerciseName = ""
    /// Mirrors the haptics setting; the session view keeps it in sync.
    var hapticsEnabled = true
    private var endDate: Date?
    private var timer: Timer?

    var progress: Double {
        total > 0 ? max(0, remaining / total) : 0
    }

    var display: String { mmss(Int(remaining.rounded())) }

    func start(seconds: Int, exerciseName: String) {
        // Guard BEFORE stop(): arming a zero-rest movement (conditioning) must
        // not kill a countdown already running (mirrors web armRest).
        guard seconds > 0 else { return }
        stop()
        self.exerciseName = exerciseName
        total = TimeInterval(seconds)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        isRunning = true
        NotificationService.scheduleRestDone(in: total, exerciseName: exerciseName)
        // 0.5s halves the observation churn vs 0.25s — nothing rendered needs
        // sub-second resolution, and endDate keeps the countdown accurate.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        remaining = 0
        endDate = nil
        NotificationService.cancelRestDone()
    }

    func add(seconds: Int) {
        guard isRunning, let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        endDate = newEnd
        total += TimeInterval(seconds)
        // Reschedule the local notification or it fires at the ORIGINAL end —
        // a minute early after +1:00, defeating the face-down-phone design.
        NotificationService.cancelRestDone()
        NotificationService.scheduleRestDone(in: max(0, newEnd.timeIntervalSinceNow), exerciseName: exerciseName)
        tick()
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            timer?.invalidate()
            timer = nil
            isRunning = false
            if hapticsEnabled {
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            }
        }
    }
}
