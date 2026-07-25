import Foundation

/// Formatting and arithmetic for conditioning ("cardio") sets — distance,
/// time, speed, incline — shared by the logger and history rows so every view
/// renders the same label. Pure; mirrored 1:1 in web/js/core.js
/// (`cardioSpeedMph`, `cardioDistanceMiles`, `cardioDurationSeconds`,
/// `cardioDurationLabel`, `cardioSetLabel`).
///
/// Distance, duration, and speed are one relationship seen from three sides:
/// `distance = speed × time`. Any two give the third, so the logger can accept
/// whichever two the lifter actually knows. A treadmill or a rucking plan is
/// set by **speed and time** and the distance falls out; a GPS run gives
/// **distance and time** and the pace falls out. Only distance and duration are
/// persisted — speed is always recoverable from them, so there is no third
/// field to store, disagree with itself, or migrate.
public enum CardioFormat {

    /// Miles per hour from distance + duration, rounded to one decimal.
    /// nil when either half is missing/zero (no speed without both).
    public static func speedMph(distanceMiles: Double?, durationSeconds: Int?) -> Double? {
        guard let miles = distanceMiles, miles > 0,
              let secs = durationSeconds, secs > 0 else { return nil }
        return (miles / (Double(secs) / 3600) * 10).rounded() / 10
    }

    /// Miles from speed + duration — the treadmill case, where the lifter sets
    /// a pace and a time and never sees a distance until the belt stops.
    /// Rounded to two decimals, the granularity treadmills and watches report.
    /// nil when either half is missing/zero.
    public static func distanceMiles(speedMph: Double?, durationSeconds: Int?) -> Double? {
        guard let mph = speedMph, mph > 0,
              let secs = durationSeconds, secs > 0 else { return nil }
        return (mph * (Double(secs) / 3600) * 100).rounded() / 100
    }

    /// Seconds from distance + speed — "four miles at 3.5 mph" as a plan.
    /// nil when either half is missing/zero.
    public static func durationSeconds(distanceMiles: Double?, speedMph: Double?) -> Int? {
        guard let miles = distanceMiles, miles > 0,
              let mph = speedMph, mph > 0 else { return nil }
        return Int((miles / mph * 3600).rounded())
    }

    /// Formats a duration as minutes and seconds, including hours when needed.
    public static func durationLabel(seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Builds one compact line from whichever cardio fields were logged.
    /// Missing halves simply drop out; nothing logged → "—".
    public static func setLabel(distanceMiles: Double?, durationSeconds: Int?, inclinePercent: Double?) -> String {
        var parts: [String] = []
        if let miles = distanceMiles, miles > 0 { parts.append("\(Weight.trim(miles, decimals: 2)) mi") }
        if let secs = durationSeconds, secs > 0 { parts.append(durationLabel(seconds: secs)) }
        if let mph = speedMph(distanceMiles: distanceMiles, durationSeconds: durationSeconds) {
            parts.append("\(Weight.trim(mph)) mph")
        }
        if let incline = inclinePercent, incline > 0 { parts.append("\(Weight.trim(incline))%") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
