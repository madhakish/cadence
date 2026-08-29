import Foundation

/// The shared athlete-history fold (epic #155 Stage 1): one projection from
/// completed performed work to per-lift strength facts, consumed by template
/// seeding on both clients. Pure and order-independent; callers normalize
/// their own store's sets into `CompletedSetSample`s (completed, non-warmup,
/// positive load, at least one rep) because those filters live with each
/// client's models. Mirrors web `athleteHistoryIndex`.
///
/// Deliberately NOT a home for every history reader: the anchored rep-capped
/// `priorBestE1RM`, slot-scoped exposure recall, basis-partitioned PR
/// baselines, and uncapped chart series answer different questions and keep
/// their own scans (see the Stage 1 notes on #155).
public enum AthleteHistory {
    public struct CompletedSetSample: Sendable {
        public let exerciseName: String
        /// Milliseconds since epoch of the owning session's effective
        /// completion moment — every set in a session shares it.
        public let timestampMs: Double
        public let weightLb: Double
        public let reps: Int

        public init(exerciseName: String, timestampMs: Double, weightLb: Double, reps: Int) {
            self.exerciseName = exerciseName
            self.timestampMs = timestampMs
            self.weightLb = weightLb
            self.reps = reps
        }
    }

    public struct LiftHistoryProfile: Equatable, Sendable {
        /// The heaviest working load at the lift's most recent exposure —
        /// recency first, ties at the same moment resolved to the heavier
        /// load. This is "what did they lift last", never "their best".
        public var latestCompletedLoadLb: Double?
        public var latestExposureMs: Double?
        /// Lifetime Epley max across every sample — capacity for seeding a
        /// brand-new slot. No rep ceiling on purpose: seeding reads all
        /// history, unlike the regime input's capped `priorBestE1RM`.
        public var allTimeBestE1RMLb: Double?
    }

    public static func index(_ samples: [CompletedSetSample]) -> [String: LiftHistoryProfile] {
        var result: [String: LiftHistoryProfile] = [:]
        for sample in samples {
            var profile = result[sample.exerciseName] ?? LiftHistoryProfile()
            if let latest = profile.latestExposureMs {
                if sample.timestampMs > latest {
                    profile.latestExposureMs = sample.timestampMs
                    profile.latestCompletedLoadLb = sample.weightLb
                } else if sample.timestampMs == latest {
                    profile.latestCompletedLoadLb = Swift.max(profile.latestCompletedLoadLb ?? 0, sample.weightLb)
                }
            } else {
                profile.latestExposureMs = sample.timestampMs
                profile.latestCompletedLoadLb = sample.weightLb
            }
            let e1RM = ProgramProgression.epleyE1RM(weightLb: sample.weightLb, reps: sample.reps)
            if e1RM > (profile.allTimeBestE1RMLb ?? 0) { profile.allTimeBestE1RMLb = e1RM }
            result[sample.exerciseName] = profile
        }
        return result
    }
}
