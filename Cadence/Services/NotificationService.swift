import Foundation
import UserNotifications

/// Local notifications only: hold complete + next-morning knee check-in. The
/// rest notification is owned by WorkoutActivityController, which also
/// drives the Live Activity's rest face; both use CompletionCue's tone.
enum NotificationService {

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    @MainActor private static var holdRequestID: String?
    @MainActor private static var holdRequestTask: Task<Void, Never>?

    /// Ask before starting the attempt, so answering the permission prompt
    /// never consumes seconds that the athlete has not held.
    static func authorizeHoldAlerts() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { return await requestAuthorization() }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    @MainActor
    static func scheduleHoldDone(in seconds: TimeInterval, exerciseName: String) {
        guard seconds > 0 else { return }
        cancelHoldDone()
        let id = "hold-timer-\(UUID().uuidString)"
        holdRequestID = id
        let content = UNMutableNotificationContent()
        content.title = "Hold complete."
        content.body = "\(exerciseName) — target time reached."
        content.sound = CompletionCue.notificationSound
        let request = UNNotificationRequest(identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        holdRequestTask = Task {
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            do { try await center.add(request) }
            catch { return } // The visible timer and foreground cue still work.
            // Cancellation can race the asynchronous add. Remove only this
            // attempt's request, never a newer hold or the rest notification.
            if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [id]) }
        }
    }

    @MainActor
    static func cancelHoldDone() {
        holdRequestTask?.cancel()
        holdRequestTask = nil
        if let id = holdRequestID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
        holdRequestID = nil
    }

    @MainActor
    static func cancelOrphanedHoldAlerts() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let orphaned = requests.map(\.identifier).filter {
            ($0 == "hold-timer" || $0.hasPrefix("hold-timer-")) && $0 != holdRequestID
        }
        center.removePendingNotificationRequests(withIdentifiers: orphaned)
    }

    /// Next morning at 08:00 after a running session: a generic knee check-in.
    static func scheduleKneeCheckIn(afterSessionOn sessionDate: Date) {
        let calendar = Calendar.current
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: sessionDate) else { return }
        var comps = calendar.dateComponents([.year, .month, .day], from: nextDay)
        comps.hour = 8

        let content = UNMutableNotificationContent()
        content.title = "Knee check-in after running"
        content.body = "How does it feel this morning? Log a quick signal either way."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "knee-checkin-\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
