import Foundation

/// Formatting and arithmetic for conditioning ("cardio") sets — distance,
/// time, speed, incline — shared by the logger and history rows so every view
/// renders the same label. Pure; mirrored 1:1 in web/app/js/core.js
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
    /// nil when either half is missing/zero.
    ///
    /// Kept to four decimals rather than the two a treadmill displays: at two,
    /// a one-minute interval cannot tell 3.0 mph from 3.1 (both land on
    /// 0.05 mi), so the stepper would refuse to advance and a logged pace would
    /// read back as a different one. Display trims; storage does not.
    public static func distanceMiles(speedMph: Double?, durationSeconds: Int?) -> Double? {
        guard let mph = speedMph, mph > 0,
              let secs = durationSeconds, secs > 0 else { return nil }
        return (mph * (Double(secs) / 3600) * 10_000).rounded() / 10_000
    }

    /// Seconds from distance + speed — "four miles at 3.5 mph" as a plan.
    /// nil when either half is missing/zero.
    public static func durationSeconds(distanceMiles: Double?, speedMph: Double?) -> Int? {
        guard let miles = distanceMiles, miles > 0,
              let mph = speedMph, mph > 0 else { return nil }
        return Int((miles / mph * 3600).rounded())
    }

    // MARK: - Loaded carries

    /// Conditioning that carries external load. A ruck is a walk with a pack
    /// on, and the pack weight is the training variable — progressing it is the
    /// whole point of rucking. Zeroing the load the way unloaded cardio does
    /// throws that away and makes a 60 lb ruck indistinguishable from a stroll.
    public static let loadedCarries: Set<String> = ["Ruck", "Sled Push", "Sled Pull"]

    /// Whether this conditioning movement carries a load worth logging.
    public static func carriesLoad(exerciseName: String) -> Bool {
        loadedCarries.contains(exerciseName)
    }

    /// Where a loaded carry starts when nothing has been logged yet. A 20 lb
    /// pack is the conventional entry point — heavy enough to train, light
    /// enough that form and feet survive the first few outings. Sleds vary far
    /// too much by surface and implement to have an honest default.
    public static func defaultLoadLb(exerciseName: String) -> Double? {
        exerciseName == "Ruck" ? 20 : nil
    }

    /// Loaded carries move in plates and full pack increments, not the 2.5 lb
    /// steps a barbell lift wants.
    public static let loadIncrementLb: Double = 10

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
    /// `loadLb` is the carried weight for a ruck or sled — omitted entirely for
    /// unloaded work, which has none.
    public static func setLabel(
        distanceMiles: Double?, durationSeconds: Int?, inclinePercent: Double?, loadLb: Double? = nil
    ) -> String {
        var parts: [String] = []
        if let lb = loadLb, lb > 0 { parts.append("\(Weight.trim(lb)) lb") }
        if let miles = distanceMiles, miles > 0 { parts.append("\(Weight.trim(miles, decimals: 2)) mi") }
        if let secs = durationSeconds, secs > 0 { parts.append(durationLabel(seconds: secs)) }
        if let mph = speedMph(distanceMiles: distanceMiles, durationSeconds: durationSeconds) {
            parts.append("\(Weight.trim(mph)) mph")
        }
        if let incline = inclinePercent, incline > 0 { parts.append("\(Weight.trim(incline))%") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
