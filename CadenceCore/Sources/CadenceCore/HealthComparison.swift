import Foundation

/// Reconciling what Cadence logged against what Apple Health recorded. Pure;
/// mirrored 1:1 in web/js/core.js (`healthOverlapSeconds`,
/// `healthSampleBelongsToSession`, `healthCompare`, `healthComparisonLabel`,
/// `healthSourceIsForeign`, `healthIsSameWeighIn`, `healthAsleepSeconds`).
///
/// Health is a **second opinion, never an authority**. A watch measures a ruck
/// more honestly than a lifter estimating afterwards; a treadmill belt measures
/// a walk more honestly than a wrist. Neither wins by default, so this layer
/// reports the disagreement and leaves the decision — and the writing — to the
/// person who did the work. Nothing here mutates a log.
///
/// A set carries no timestamp, only the session does, so comparison is at the
/// session's conditioning total. Claiming to match an individual set would be
/// precision the data cannot support.
public enum HealthComparison {

    /// Distances closer than this are the same distance. GPS, a treadmill belt,
    /// and a wrist accelerometer will never agree exactly, and reporting every
    /// hundredth of a mile as a discrepancy would train the lifter to ignore
    /// the comparison entirely.
    public static let toleranceMiles = 0.05
    /// Long efforts get proportional slack — 2% of a ten-mile ruck is a fifth
    /// of a mile, and that is still agreement between two honest instruments.
    public static let toleranceFraction = 0.02

    /// The shape of a disagreement, independent of what is being compared.
    /// `Verdict` below is the conditioning-distance dressing on this; the
    /// bodyweight and protein suggestions use the bare kind with their own
    /// tolerances rather than duplicating the arithmetic.
    public enum VerdictKind: String, Equatable {
        case agree, healthHigher, loggedHigher, onlyHealth, onlyLogged, neither
    }

    /// How a logged conditioning total lines up with Health's.
    public enum Verdict: Equatable {
        /// Both sources have a distance and they agree within tolerance.
        case agree(miles: Double)
        /// Health recorded further than the log says.
        case healthHigher(loggedMiles: Double, healthMiles: Double)
        /// The log claims further than Health recorded.
        case loggedHigher(loggedMiles: Double, healthMiles: Double)
        /// Health has conditioning the log never captured.
        case onlyHealth(miles: Double)
        /// Logged by hand, with nothing in Health to check it against —
        /// an unworn watch, or a session logged after the fact.
        case onlyLogged(miles: Double)
        /// Neither source has anything to say.
        case neither

        /// Whether adopting Health's number would actually change the log.
        public var isDiscrepancy: Bool {
            switch self {
            case .healthHigher, .loggedHigher, .onlyHealth: return true
            case .agree, .onlyLogged, .neither: return false
            }
        }

        /// The distance Health would write if the lifter adopts it.
        /// nil when there is nothing of Health's to adopt.
        public var adoptableMiles: Double? {
            switch self {
            case let .healthHigher(_, healthMiles): return healthMiles
            case let .loggedHigher(_, healthMiles): return healthMiles
            case let .onlyHealth(miles): return miles
            case .agree, .onlyLogged, .neither: return nil
            }
        }
    }

    /// Seconds two half-open time ranges share. Zero when they merely touch.
    public static func overlapSeconds(
        aStart: Date, aEnd: Date, bStart: Date, bEnd: Date
    ) -> Int {
        let start = max(aStart, bStart)
        let end = min(aEnd, bEnd)
        return end > start ? Int(end.timeIntervalSince(start).rounded()) : 0
    }

    /// Whether a Health workout belongs to a session, by majority overlap.
    ///
    /// Requiring containment would drop the walk a lifter started in the car
    /// park before opening the app; accepting any overlap at all would claim
    /// the bike commute that ended as the session began.
    public static func sampleBelongsToSession(
        sampleStart: Date, sampleEnd: Date, sessionStart: Date, sessionEnd: Date
    ) -> Bool {
        let sampleSeconds = sampleEnd.timeIntervalSince(sampleStart)
        guard sampleSeconds > 0 else { return false }
        let shared = overlapSeconds(
            aStart: sampleStart, aEnd: sampleEnd, bStart: sessionStart, bEnd: sessionEnd
        )
        return Double(shared) >= sampleSeconds / 2
    }

    /// Compare any two measurements of the same thing. Zero and nil are both
    /// absence — "Health has nothing to say" is never "Health says zero".
    ///
    /// `toleranceFraction` gives long efforts proportional slack; pass 0 for a
    /// quantity where a flat band is the honest one (a weigh-in does not get
    /// looser as the lifter gets heavier).
    public static func verdictKind(
        logged: Double?, health: Double?,
        toleranceAbsolute: Double, toleranceFraction: Double = 0
    ) -> VerdictKind {
        let l = (logged ?? 0) > 0 ? logged! : nil
        let h = (health ?? 0) > 0 ? health! : nil
        switch (l, h) {
        case (nil, nil): return .neither
        case (nil, .some): return .onlyHealth
        case (.some, nil): return .onlyLogged
        case let (.some(l), .some(h)):
            let allowed = max(toleranceAbsolute, max(l, h) * toleranceFraction)
            if abs(h - l) <= allowed + 1e-9 { return .agree }
            return h > l ? .healthHigher : .loggedHigher
        }
    }

    /// Compare a logged conditioning distance against Health's for one session.
    /// Either side may be absent; both absent is `.neither`.
    public static func compare(loggedMiles: Double?, healthMiles: Double?) -> Verdict {
        let logged = (loggedMiles ?? 0) > 0 ? loggedMiles! : nil
        let health = (healthMiles ?? 0) > 0 ? healthMiles! : nil
        switch verdictKind(logged: logged, health: health,
                           toleranceAbsolute: toleranceMiles,
                           toleranceFraction: toleranceFraction) {
        case .neither: return .neither
        case .onlyHealth: return .onlyHealth(miles: health ?? 0)
        case .onlyLogged: return .onlyLogged(miles: logged ?? 0)
        case .agree: return .agree(miles: logged ?? 0)
        case .healthHigher: return .healthHigher(loggedMiles: logged ?? 0, healthMiles: health ?? 0)
        case .loggedHigher: return .loggedHigher(loggedMiles: logged ?? 0, healthMiles: health ?? 0)
        }
    }

    /// One line stating what each source says. Never phrased as a correction —
    /// the lifter decides which instrument they trust for this session.
    public static func label(_ verdict: Verdict) -> String {
        switch verdict {
        case let .agree(miles):
            return "Health agrees: \(Weight.trim(miles, decimals: 2)) mi"
        case let .healthHigher(logged, health):
            return "Health recorded \(Weight.trim(health, decimals: 2)) mi · you logged \(Weight.trim(logged, decimals: 2)) mi"
        case let .loggedHigher(logged, health):
            return "You logged \(Weight.trim(logged, decimals: 2)) mi · Health recorded \(Weight.trim(health, decimals: 2)) mi"
        case let .onlyHealth(miles):
            return "Health recorded \(Weight.trim(miles, decimals: 2)) mi that isn't logged"
        case .onlyLogged:
            return "Nothing in Health for this session"
        case .neither:
            return "No conditioning distance"
        }
    }

    // MARK: - Anti-echo

    /// [INV-HEALTH-IS-A-SECOND-OPINION] Whether a Health sample came from
    /// somewhere other than Cadence itself.
    ///
    /// Load-bearing, and invisible when wrong. Cadence writes workouts,
    /// bodyweight and protein into Health; without this every read would find
    /// those writes and "confirm" the log against a mirror of itself. A
    /// cross-check that always agrees is worse than no cross-check, because it
    /// looks like corroboration.
    ///
    /// An unattributable sample counts as foreign. Discounting a sample we
    /// cannot prove is ours would silently drop a real second opinion, and the
    /// failure mode of the other choice — offering the lifter their own number
    /// back — is visible the first time it happens.
    public static func sourceIsForeign(
        bundleIdentifier: String?, appBundleIdentifier: String?
    ) -> Bool {
        guard let app = appBundleIdentifier?.trimmingCharacters(in: .whitespaces),
              !app.isEmpty else { return true }
        guard let source = bundleIdentifier?.trimmingCharacters(in: .whitespaces),
              !source.isEmpty else { return true }
        return source.caseInsensitiveCompare(app) != .orderedSame
    }

    // MARK: - Bodyweight

    /// Two weigh-ins closer than this are the same weigh-in. A scale reports to
    /// a tenth of a pound and Health round-trips through kilograms, so exact
    /// equality would offer the lifter an "import" of a weight they just typed.
    public static let weighInToleranceLb = 0.2

    /// Whether a Health weigh-in is one Cadence already has.
    ///
    /// Same calendar day *and* same number. A genuine second weigh-in later the
    /// same day is a different weight and stays offerable; yesterday's weight
    /// is a different day and is not a duplicate of today's.
    public static func isSameWeighIn(
        loggedLb: Double, loggedDate: Date,
        healthLb: Double, healthDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard calendar.isDate(loggedDate, inSameDayAs: healthDate) else { return false }
        return abs(loggedLb - healthLb) <= weighInToleranceLb + 1e-9
    }

    // MARK: - Sleep

    /// The `HKCategoryValueSleepAnalysis` stages that count as sleep.
    /// `inBed` is time on the mattress, not time asleep, and `awake` is
    /// explicitly not sleep; counting either would inflate a night by hours.
    public static let asleepStages: Set<String> = [
        "asleepUnspecified", "asleepCore", "asleepDeep", "asleepREM",
    ]

    /// Total time actually asleep, from stage samples of `(stage, seconds)`.
    ///
    /// Watches emit overlapping stage samples across sources; the caller is
    /// responsible for handing over one source's stages, which the anti-echo
    /// filter already does.
    public static func asleepSeconds(stages: [(stage: String, seconds: Int)]) -> Int {
        stages.reduce(0) { total, entry in
            guard asleepStages.contains(entry.stage), entry.seconds > 0 else { return total }
            return total + entry.seconds
        }
    }
}
