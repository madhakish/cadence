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

    /// A correction to one banked set's performed record, applied after the
    /// session was completed: the lifter noticed the log is wrong (a set never
    /// marked complete, a weight banked at the stale plan). Only the fields the
    /// correction PROVIDES change, and only when they are sane — a blank or
    /// negative entry keeps the stored value rather than writing garbage into
    /// history. Everything else on the set (flags, warmup, load basis, planned
    /// values, body signals) is deliberately out of reach: editing reps cannot
    /// reset weight, and a correction cannot rewrite what was prescribed.
    /// Mirrors web `correctedSetValues`.
    public struct SetCorrection: Hashable, Sendable {
        public var weightLb: Double?
        public var reps: Int?
        public var durationSeconds: Int?
        public var status: SetStatus?

        public init(weightLb: Double? = nil, reps: Int? = nil,
                    durationSeconds: Int? = nil, status: SetStatus? = nil) {
            self.weightLb = weightLb
            self.reps = reps
            self.durationSeconds = durationSeconds
            self.status = status
        }
    }

    public static func correctedSetValues(
        weightLb: Double, reps: Int, durationSeconds: Int?, status: SetStatus,
        correction: SetCorrection
    ) -> (weightLb: Double, reps: Int, durationSeconds: Int?, status: SetStatus) {
        var corrected = (weightLb: weightLb, reps: reps,
                         durationSeconds: durationSeconds, status: status)
        if let value = correction.weightLb, value.isFinite, value >= 0 {
            corrected.weightLb = value
        }
        if let value = correction.reps, value >= 0 { corrected.reps = value }
        if let value = correction.durationSeconds, value >= 0 {
            corrected.durationSeconds = value
        }
        if let value = correction.status { corrected.status = value }
        return corrected
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
