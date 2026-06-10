import Foundation
import Observation

/// Countdown between sets. Defaults: 5:00 main-lift work sets, 1:30 accessory,
/// overridable per exercise. Schedules a local notification so the phone can
/// sit face-down on the chalk bucket.
@Observable
final class RestTimer {
    private(set) var remaining: TimeInterval = 0
    private(set) var total: TimeInterval = 0
    private(set) var isRunning = false
    private var endDate: Date?
    private var timer: Timer?

    var progress: Double {
        total > 0 ? max(0, remaining / total) : 0
    }

    var display: String {
        let r = Int(remaining.rounded())
        return String(format: "%d:%02d", r / 60, r % 60)
    }

    func start(seconds: Int, exerciseName: String) {
        stop()
        guard seconds > 0 else { return }
        total = TimeInterval(seconds)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        isRunning = true
        NotificationService.scheduleRestDone(in: total, exerciseName: exerciseName)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
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
        endDate = end.addingTimeInterval(TimeInterval(seconds))
        total += TimeInterval(seconds)
        tick()
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            timer?.invalidate()
            timer = nil
            isRunning = false
        }
    }
}
