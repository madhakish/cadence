import Foundation

/// Formatting for conditioning ("cardio") sets — distance, time, derived
/// speed, incline — shared by the logger and history rows so every view
/// renders the same label. Pure; mirrored 1:1 in web/js/core.js
/// (`cardioSpeedMph`, `cardioDurationLabel`, `cardioSetLabel`).
public enum CardioFormat {

    /// Miles per hour from distance + duration, rounded to one decimal.
    /// nil when either half is missing/zero (no speed without both).
    public static func speedMph(distanceMiles: Double?, durationSeconds: Int?) -> Double? {
        guard let miles = distanceMiles, miles > 0,
              let secs = durationSeconds, secs > 0 else { return nil }
        return (miles / (Double(secs) / 3600) * 10).rounded() / 10
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
