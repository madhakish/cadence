import Foundation

/// Reconciling logged conditioning against what Apple Health recorded over the
/// same window. Pure; mirrored 1:1 in web/js/core.js (`healthOverlapSeconds`,
/// `healthSampleBelongsToSession`, `healthCompare`, `healthComparisonLabel`).
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

    /// Compare a logged conditioning distance against Health's for one session.
    /// Either side may be absent; both absent is `.neither`.
    public static func compare(loggedMiles: Double?, healthMiles: Double?) -> Verdict {
        let logged = (loggedMiles ?? 0) > 0 ? loggedMiles! : nil
        let health = (healthMiles ?? 0) > 0 ? healthMiles! : nil
        switch (logged, health) {
        case (nil, nil):
            return .neither
        case let (nil, .some(h)):
            return .onlyHealth(miles: h)
        case let (.some(l), nil):
            return .onlyLogged(miles: l)
        case let (.some(l), .some(h)):
            let allowed = max(toleranceMiles, max(l, h) * toleranceFraction)
            if abs(h - l) <= allowed + 1e-9 { return .agree(miles: l) }
            return h > l
                ? .healthHigher(loggedMiles: l, healthMiles: h)
                : .loggedHigher(loggedMiles: l, healthMiles: h)
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
}
