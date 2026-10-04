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

    /// Whether a double-progression slot on this basis has a load step to
    /// earn. A bodyweight identity carries no external load, so its rep-window
    /// top is advisory — it climbs past it because reps are the only way it
    /// progresses (see `ProgramProgression.repWindow`'s `capped`). Adding a
    /// belt is switching to the weighted identity, not incrementing this one.
    /// Mirrored in web/app/js/core.js `supportsLoadableIncrement`.
    public var supportsLoadableIncrement: Bool { self != .bodyweight }
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

    /// Movements whose conventional implement count differs from what their
    /// equipment type implies: an overhead triceps extension is one dumbbell
    /// held in both hands, a front-rack carry is two kettlebells, a suitcase
    /// carry is one bell in one hand. These are defaults for unset counts;
    /// a valid saved count always remains the athlete's choice.
    public static let conventionalImplementCounts: [String: Int] = [
        "DB Overhead Triceps Extension": 1,
        "Farmer Carry": 2,
        "Suitcase Carry": 1,
        "Front-rack Carry": 2,
        "Overhead Carry": 1,
    ]

    /// A backup carries the count the exercise currently resolves to. An
    /// unset sentinel must not turn into a different count when restored.
    /// Mirrored in web/app/js/core.js `backupImplementCount`.
    public static func backupImplementCount(stored: Int, exerciseType: String?, basis: LoadBasis,
                                            exerciseName: String? = nil) -> Int {
        resolvedImplementCount(stored: stored, exerciseType: exerciseType, exerciseName: exerciseName, basis: basis)
    }

    /// The implement count an exercise row resolves to. A positive saved
    /// count wins even when it equals the equipment default: the store cannot
    /// distinguish an old default from a deliberate choice. Only an unset
    /// count takes the named convention. Sets snapshot the result.
    /// Mirrored in web/app/js/core.js `resolvedImplementCount`.
    public static func resolvedImplementCount(
        stored: Int, exerciseType: String?, exerciseName: String?, basis: LoadBasis
    ) -> Int {
        let typeDefault = inferredImplementCount(exerciseType: exerciseType)
        let named = exerciseName.flatMap { conventionalImplementCounts[$0] }
        return normalizedImplementCount(stored > 0 ? stored : (named ?? typeDefault), basis: basis)
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

    /// Tonnage of a distance-carry set: the rep formula with yards in place
    /// of reps — per-hand load × yards × implements × sides. `nil` under the
    /// same bases `volume` refuses.
    public static func carryVolume(
        weightLb: Double,
        yards: Double,
        isPerSide: Bool,
        basis: LoadBasis,
        implementCount: Int = 1
    ) -> Double? {
        guard basis.supportsVolume, weightLb >= 0, yards > 0 else { return nil }
        let implements = normalizedImplementCount(implementCount, basis: basis)
        let sides = isPerSide ? 2 : 1
        return weightLb * yards * Double(implements * sides)
    }

    /// The hero load with its basis stated: "50 lb · 22.7 kg each". A
    /// per-implement number without "each" reads as the total in the hands.
    public static func heroLoadLabel(weightLb: Double, basis: LoadBasis) -> String {
        guard weightLb > 0 else { return "BW" }
        return "\(Weight.trim(weightLb)) lb · \(Weight.trim(Weight.kg(fromLb: weightLb))) kg\(basis.shortSuffix)"
    }

    /// Load PRs may only compare records that use the same interpretation.
    public static func compatible(_ lhs: LoadBasis, _ rhs: LoadBasis) -> Bool {
        lhs == rhs
    }
}
