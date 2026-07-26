import Foundation

/// Prescription state shared by native and web. A missing legacy value is
/// performed only when it already belongs to banked history; ambiguous open
/// sessions stay planned.
public enum SetStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case completed
    case skipped
}

public enum SetLifecycle {
    public static let qualityValues = ["clean", "grindy", "wobble"]

    /// Reps left in reserve, coarse on purpose.
    ///
    /// A number entry invites false precision — RIR accuracy is a trainable
    /// skill and averages about a rep of error even in experienced lifters, so
    /// three buckets carry the signal the literature actually supports.
    ///
    /// Deliberately a SEPARATE group from `qualityValues`. Quality says how the
    /// bar moved; RIR says how close to failure it was, and those are different
    /// questions — a set can be clean at 3+ reps in reserve or clean at 1. Each
    /// group is internally exclusive; the two never exclude each other.
    public static let rirValues = ["rir1", "rir2", "rir3plus"]

    public static func resolve(_ rawValue: String?, sessionCompleted: Bool) -> SetStatus {
        rawValue.flatMap { SetStatus(rawValue: $0) } ?? (sessionCompleted ? .completed : .planned)
    }

    public static func quality(in flags: [String]) -> String? {
        flags.first { qualityValues.contains($0) }
    }

    public static func rir(in flags: [String]) -> String? {
        flags.first { rirValues.contains($0) }
    }

    /// Quality and RIR are each mutually exclusive within their own group;
    /// stopped-early remains independent.
    ///
    /// Every writer of a flag list goes through here. That matters: this used
    /// to rebuild the list from quality and stopped-early alone, so any flag
    /// outside those two was silently dropped on export — a new flag would
    /// appear to work and then vanish on restore.
    public static func normalizedFlags(
        quality: String?, stoppedEarly: Bool, rir: String? = nil
    ) -> [String] {
        var result: [String] = []
        if let quality, qualityValues.contains(quality) { result.append(quality) }
        if let rir, rirValues.contains(rir) { result.append(rir) }
        if stoppedEarly { result.append("stopped early") }
        return result
    }
}
