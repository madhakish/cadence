import Foundation

/// What a set's entered load means. This is deliberately separate from the
/// exercise's equipment and from `isPerSide` (which describes the rep count).
/// A set snapshots both basis and implement count so old training records keep
/// their original meaning when an exercise definition is edited later.
public enum LoadBasis: String, Codable, CaseIterable, Sendable {
    /// Total weight on a bar, including the bar itself.
    case totalBar
    /// Weight of one dumbbell, kettlebell, or similar implement.
    case perImplement
    /// Total external resistance shown by a machine, cable, vest, or sled.
    case externalTotal
    /// Assistance supplied to a bodyweight movement; lower is harder.
    case assisted
    /// Unloaded bodyweight work. Reps/duration are meaningful; entered load is not.
    case bodyweight

    public var label: String {
        switch self {
        case .totalBar: return "Total bar weight"
        case .perImplement: return "Per implement"
        case .externalTotal: return "External total"
        case .assisted: return "Assistance"
        case .bodyweight: return "Bodyweight"
        }
    }

    public var shortSuffix: String {
        switch self {
        case .perImplement: return " each"
        case .assisted: return " assistance"
        default: return ""
        }
    }

    /// Weight and tonnage PRs are only honest for external resistance where
    /// more weight represents more work. Assisted/bodyweight sets still earn
    /// rep-scheme and duration history, but never fake a heaviest-load PR.
    public var supportsLoadPR: Bool {
        self == .totalBar || self == .perImplement || self == .externalTotal
    }

    public var supportsVolume: Bool { supportsLoadPR }
}

public enum LoadSemantics {
    /// Safe legacy/default inference shared with the web app. Equipment is a
    /// starting point only; the library editor can override it explicitly.
    public static func inferredBasis(exerciseType: String?) -> LoadBasis {
        switch exerciseType?.lowercased() {
        case "barbell": return .totalBar
        case "dumbbell", "kettlebell": return .perImplement
        case "bodyweight": return .bodyweight
        default: return .externalTotal
        }
    }

    /// Conventional simultaneous implement count. Unilateral reps are handled
    /// independently by `isPerSide`, so a one-arm row is 1 implement × 2 sides.
    public static func inferredImplementCount(exerciseType: String?) -> Int {
        exerciseType?.lowercased() == "dumbbell" ? 2 : 1
    }

    public static func normalizedImplementCount(_ count: Int, basis: LoadBasis) -> Int {
        basis == .perImplement ? max(1, count) : 1
    }

    /// Total external tonnage. `nil` means tonnage is not a meaningful metric
    /// for this basis (unloaded bodyweight or assistance).
    public static func volume(
        weightLb: Double,
        reps: Int,
        isPerSide: Bool,
        basis: LoadBasis,
        implementCount: Int = 1
    ) -> Double? {
        guard basis.supportsVolume, weightLb >= 0, reps > 0 else { return nil }
        let implements = normalizedImplementCount(implementCount, basis: basis)
        let sides = isPerSide ? 2 : 1
        return weightLb * Double(reps * implements * sides)
    }

    /// Load PRs may only compare records that use the same interpretation.
    public static func compatible(_ lhs: LoadBasis, _ rhs: LoadBasis) -> Bool {
        lhs == rhs
    }
}
