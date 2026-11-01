import Foundation

/// Duration entry only; does not change RestDefaults' zero/fallback semantics.
/// Matches the existing native/web backup validators' 0...3600-second range.
public enum RestDuration {
    public static let maximumSeconds = 3600
    /// The rests people actually take. Anything else is one stepper away.
    public static let presets = [60, 90, 120, 180, 240, 300]
    /// Fine adjustment grain. Nobody's recovery hinges on 1:37 versus 1:38.
    public static let stepSeconds = 15

    /// One stepper press. An off-grid value (a stored 1:37, a running timer's
    /// 2:41) lands on the next 15-second mark in that direction rather than
    /// staying off-grid forever; the result is clamped to 0...maximumSeconds.
    public static func stepped(_ seconds: Int, up: Bool) -> Int {
        let value = min(max(0, seconds), maximumSeconds)
        let floor = value / stepSeconds * stepSeconds
        let next = up ? floor + stepSeconds : (floor == value ? value - stepSeconds : floor)
        return min(max(0, next), maximumSeconds)
    }

    public static func parse(hours: String, minutes: String, seconds: String) -> Int? {
        let fields = [hours, minutes, seconds].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var values: [Int] = []
        for field in fields {
            guard field.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let value = Int(field.isEmpty ? "0" : field), value <= maximumSeconds else { return nil }
            values.append(value)
        }
        let total = values[0] * 3600 + values[1] * 60 + values[2]
        return total <= maximumSeconds ? total : nil
    }

    public static func label(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
