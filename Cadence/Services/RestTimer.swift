import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Countdown between sets. Manual by default — armed from the Rest buttons or
/// the bottom bar; only auto-armed after a set when the auto-start setting is
/// on. Delegates the "Rest over." notification and the Lock Screen / Dynamic
/// Island Live Activity to `RestActivityController` so the phone can sit
/// face-down on the chalk bucket and still be driven from the Lock Screen;
/// buzzes on finish when haptics are enabled.
@Observable
final class RestTimer {
    private(set) var remaining: TimeInterval = 0
    private(set) var total: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var exerciseName = ""
    /// Mirrors the haptics setting; the session view keeps it in sync.
    var hapticsEnabled = true
    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 0
    private var timer: Timer?

    var progress: Double {
        total > 0 ? max(0, remaining / total) : 0
    }

    var display: String { mmss(Int(remaining.rounded())) }

    func start(seconds: Int, exerciseName: String) {
        // Guard BEFORE clearing: arming a zero-rest movement (conditioning) must
        // not kill a countdown already running (mirrors web armRest).
        guard seconds > 0 else { return }
        // Clear only LOCAL state — do NOT fire the controller's finish here. It
        // runs in its own task and could land after begin()'s task, tearing down
        // the rest we're about to start. begin() ends any prior activity and
        // reschedules the notification in-order, so it owns the teardown.
        stopLocalOnly()
        self.exerciseName = exerciseName
        total = TimeInterval(seconds)
        remaining = total
        isPaused = false
        let end = Date().addingTimeInterval(total)
        endDate = end
        isRunning = true
        RestActivityController.beginDetached(exerciseName: exerciseName, total: total, endDate: end)
        startTicking()
    }

    func stop() {
        invalidate()
        isRunning = false
        isPaused = false
        remaining = 0
        endDate = nil
        RestActivityController.finishDetached()
    }

    func add(seconds: Int) {
        guard isRunning else { return }
        total += TimeInterval(seconds)
        if isPaused {
            pausedRemaining = max(0, pausedRemaining + TimeInterval(seconds))
            remaining = pausedRemaining
        } else if let end = endDate {
            endDate = end.addingTimeInterval(TimeInterval(seconds))
            tick()
        }
        pushState()
    }

    func pause() {
        guard isRunning, !isPaused, let end = endDate else { return }
        isPaused = true
        pausedRemaining = max(0, end.timeIntervalSinceNow)
        remaining = pausedRemaining
        invalidate()
        pushState()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        let end = Date().addingTimeInterval(max(0, pausedRemaining))
        endDate = end
        startTicking()
        pushState()
    }

    /// Adopt the Live Activity's state after the user may have driven the timer
    /// from the Lock Screen while the app was backgrounded. Call on foreground.
    func reconcileFromActivity() {
        // No Live Activities on this device/setting → the in-app timer and its
        // notification are the whole story; never clear them from here.
        guard RestActivityController.isSupported else { return }
        guard let snap = RestActivityController.snapshot else {
            if isRunning { stopLocalOnly() } // ended from the Lock Screen
            return
        }
        exerciseName = snap.exerciseName
        total = snap.state.total
        endDate = snap.state.endDate // keep even while paused, so in-app +time can push it
        isRunning = true
        if snap.state.isPaused {
            isPaused = true
            pausedRemaining = snap.state.pausedRemaining
            remaining = pausedRemaining
            invalidate()
        } else {
            isPaused = false
            startTicking()
        }
    }

    // MARK: - Internals

    private func startTicking() {
        invalidate()
        tick()
        // 0.5s halves the observation churn vs 0.25s — nothing rendered needs
        // sub-second resolution, and endDate keeps the countdown accurate.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    /// Clear local state without touching the activity/notification (they were
    /// already ended elsewhere).
    private func stopLocalOnly() {
        invalidate()
        isRunning = false
        isPaused = false
        remaining = 0
        endDate = nil
    }

    private func pushState() {
        guard let end = endDate else { return }
        RestActivityController.applyDetached(
            RestActivityAttributes.ContentState(endDate: end, isPaused: isPaused, pausedRemaining: pausedRemaining, total: total),
            exerciseName: exerciseName
        )
    }

    private func tick() {
        guard let end = endDate, !isPaused else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            invalidate()
            isRunning = false
            RestActivityController.finishDetached()
            if hapticsEnabled {
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            }
        }
    }
}
