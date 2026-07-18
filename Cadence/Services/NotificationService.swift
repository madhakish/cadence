import Foundation
import UserNotifications

/// Local notifications only: rest timer done + next-morning knee check-in.
enum NotificationService {

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Fires when the rest period ends. Terse, like everything else.
    static func scheduleRestDone(in seconds: TimeInterval, exerciseName: String) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over."
        content.body = "\(exerciseName) — next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "rest-timer", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelRestDone() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest-timer"])
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
