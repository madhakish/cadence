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

    /// The set an "up next" affordance acts on: the first **planned,
    /// non-warmup** set, in stored order. nil when the exercise has nothing
    /// left to do.
    ///
    /// This rule was written by hand in three places — the iOS logger's
    /// current-row highlight, the web logger's `.current` class, and now the
    /// Lock Screen's Done button. Three copies of "which set am I on" is three
    /// chances to disagree, and the Lock Screen disagreeing is the worst of
    /// them: it would complete a different set from the one it displayed.
    ///
    /// Warmups are skipped deliberately. They are often left unflagged, and a
    /// forgotten warmup must not hold the working sets hostage — the same
    /// reasoning the in-app highlight already used.
    ///
    /// Skipped sets are passed over rather than treated as an end: a lifter who
    /// skips set 2 is still working on set 3.
    public static func currentSetIndex(isWarmup: [Bool], statuses: [String]) -> Int? {
        let count = Swift.min(isWarmup.count, statuses.count)
        for index in 0..<count where !isWarmup[index] && statuses[index] == "planned" {
            return index
        }
        return nil
    }

    /// How many working sets are done and how many there are, for a
    /// "Set 3 of 5" readout. Warmups are excluded from both halves so the
    /// count matches what `currentSetIndex` walks.
    ///
    /// `position` is 1-based and counts the current set itself, so it reads as
    /// the set being worked rather than the number already banked. Skipped sets
    /// still occupy a position — the lifter did plan five.
    public static func workingSetProgress(
        isWarmup: [Bool], statuses: [String]
    ) -> (position: Int, total: Int)? {
        let count = Swift.min(isWarmup.count, statuses.count)
        let working = (0..<count).filter { !isWarmup[$0] }
        guard !working.isEmpty else { return nil }
        guard let current = currentSetIndex(isWarmup: isWarmup, statuses: statuses) else {
            return (working.count, working.count)
        }
        let position = (working.firstIndex(of: current) ?? 0) + 1
        return (position, working.count)
    }
}
