import Foundation

/// Duration entry only; does not change RestDefaults' zero/fallback semantics.
/// Matches the existing native/web backup validators' 0...3600-second range.
public enum RestDuration {
    public static let maximumSeconds = 3600

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
