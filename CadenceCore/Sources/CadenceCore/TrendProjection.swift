import Foundation

/// Where a lift is heading, fitted from what was actually performed.
///
/// The progression charts stop at today. That is honest but not useful for the
/// question a lifter actually asks — "at this rate, where am I in a month?" —
/// so this fits a least-squares line through the performed points and extends
/// it forward.
///
/// A projection is a claim about the future, and this file's whole job is to
/// keep that claim narrow:
///
/// - It describes the rate the history already shows. It is NOT a plan, not a
///   target, and not what the program engine will prescribe. Programmed work
///   has its own forward view (`ProgramEngine.exposurePreview`) which runs the
///   real engine; this is the empirical trend of performed weight, and the two
///   are allowed to disagree.
/// - It refuses more often than it answers. Too few exposures, too short a
///   span, or a lift not trained recently all return nil rather than a
///   confident-looking line drawn through noise.
/// - It reports how well the line actually describes the history
///   (`fitQuality`, R²) so the UI can show the trend's own uncertainty instead
///   of presenting every projection as equally sound.
/// - A downward trend projects downward. Bad news is data.
///
/// Everything here is a pure function of `[Sample]` — no dates, no timezones,
/// no unit assumptions. Callers pass days since any origin they like and
/// values in whatever unit they are already displaying; a linear fit commutes
/// with the lb→kg scaling, so the projection is the same line either way.
///
/// Mirrored 1:1 in web/app/js/core.js `projectTrend`.
public enum TrendProjection {
    /// One performed session: a day offset and the metric's value that day.
    public struct Sample: Equatable, Sendable {
        public let day: Double
        public let value: Double

        public init(day: Double, value: Double) {
            self.day = day
            self.value = value
        }
    }

    /// A point on the projected line.
    public struct Point: Equatable, Sendable {
        public let day: Double
        public let value: Double

        public init(day: Double, value: Double) {
            self.day = day
            self.value = value
        }
    }

    public struct Result: Equatable, Sendable {
        /// Fitted rate of change per week, in the caller's unit. Signed.
        public let perWeek: Double
        /// R² of the fit, 0...1. How much of the history the line explains —
        /// 1 is a line the lifter walked exactly, near 0 is noise the line
        /// happens to pass through.
        public let fitQuality: Double
        /// The projected line, from the last performed session to the horizon.
        /// Starts at the FITTED value on that day, not the performed one: the
        /// gap between the last dot and where the line begins is the fit's
        /// error, and hiding it by anchoring to the final point would dress a
        /// fluke session up as the new baseline.
        public let points: [Point]
        /// Value at the far end of the horizon — the headline number.
        public let horizonValue: Double
        /// Day offset of that value.
        public let horizonDay: Double

        public init(perWeek: Double, fitQuality: Double, points: [Point],
                    horizonValue: Double, horizonDay: Double) {
            self.perWeek = perWeek
            self.fitQuality = fitQuality
            self.points = points
            self.horizonValue = horizonValue
            self.horizonDay = horizonDay
        }
    }

    /// Fewer exposures than this is an anecdote, not a trend.
    public static let minimumSamples = 4
    /// Four sessions inside one week say nothing about a month from now.
    public static let minimumSpanDays: Double = 21
    /// A lift untouched for this long is not on a trajectory to extend.
    public static let stalenessLimitDays: Double = 35
    /// One projected point per week: enough to carry the line's shape without
    /// implying a session-by-session prediction nobody made.
    public static let stepDays: Double = 7

    /// Fit and extend, or refuse.
    ///
    /// - Parameters:
    ///   - samples: performed sessions, any order. Same-day duplicates are
    ///     kept — two exposures in a day are two pieces of evidence.
    ///   - horizonDays: how far past `asOfDay` to project.
    ///   - asOfDay: today, on the same origin as the samples.
    /// - Returns: nil when the history cannot honestly support a projection.
    public static func project(samples: [Sample], horizonDays: Double, asOfDay: Double) -> Result? {
        let usable = samples.filter { $0.value.isFinite && $0.day.isFinite }
        guard usable.count >= minimumSamples, horizonDays > 0 else { return nil }

        let days = usable.map(\.day)
        guard let first = days.min(), let last = days.max() else { return nil }
        guard last - first >= minimumSpanDays else { return nil }
        guard asOfDay - last <= stalenessLimitDays else { return nil }

        let n = Double(usable.count)
        let meanDay = days.reduce(0, +) / n
        let meanValue = usable.map(\.value).reduce(0, +) / n
        var covariance = 0.0
        var dayVariance = 0.0
        var valueVariance = 0.0
        for sample in usable {
            let dx = sample.day - meanDay
            let dy = sample.value - meanValue
            covariance += dx * dy
            dayVariance += dx * dx
            valueVariance += dy * dy
        }
        // Every exposure on the same day: no rate can be read from it. The
        // span guard above already rejects this, but the division must not
        // depend on that ordering to stay safe.
        guard dayVariance > 0 else { return nil }

        let slope = covariance / dayVariance
        let intercept = meanValue - slope * meanDay
        let fitted = { (day: Double) in max(0, intercept + slope * day) }

        // R² against the mean. A flat history is perfectly described by a flat
        // line, so zero variance is a perfect fit, not a divide-by-zero.
        var residual = 0.0
        for sample in usable {
            let error = sample.value - (intercept + slope * sample.day)
            residual += error * error
        }
        let fitQuality = valueVariance > 0 ? max(0, min(1, 1 - residual / valueVariance)) : 1

        let end = asOfDay + horizonDays
        guard end > last else { return nil }
        var points: [Point] = []
        var day = last
        while day < end {
            points.append(Point(day: day, value: fitted(day)))
            day += stepDays
        }
        points.append(Point(day: end, value: fitted(end)))

        return Result(perWeek: slope * 7, fitQuality: fitQuality, points: points,
                      horizonValue: fitted(end), horizonDay: end)
    }

    /// How far out a chart is projecting. The raw value IS the horizon in
    /// days, so the length travels with the case instead of living in a
    /// lookup the two platforms could disagree about.
    public enum Horizon: Int, CaseIterable, Sendable {
        case off = 0
        case oneMonth = 30
        case threeMonths = 90

        public var days: Double { Double(rawValue) }

        public var label: String {
            switch self {
            case .off: return "Off"
            case .oneMonth: return "1 month"
            case .threeMonths: return "3 months"
            }
        }
    }

    /// One line of plain language for the trend. Deliberately says "at this
    /// rate" every time — the number is a continuation of the past, and the
    /// copy should never let it read as a promise about the future.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `trendSummary`.
    public static func summary(perWeek: Double, horizonLabel: String,
                               horizonValue: String, unit: String) -> String {
        // Round the MAGNITUDE, then re-apply the sign. Rounding the signed
        // value splits the two platforms on exact halves — Swift rounds away
        // from zero, JavaScript toward +∞ — so −2.25/week reads as −2.3 on one
        // and −2.2 on the other for the same history.
        let magnitude = (abs(perWeek) * 10).rounded() / 10
        if magnitude == 0 {
            return "Holding flat · \(horizonValue) in \(horizonLabel) at this rate"
        }
        let sign = perWeek > 0 ? "+" : "−"
        let rate = magnitude == magnitude.rounded()
            ? String(format: "%.0f", magnitude)
            : String(format: "%.1f", magnitude)
        return "\(sign)\(rate) \(unit)/week · \(horizonValue) in \(horizonLabel) at this rate"
    }

    /// How much to trust the line, in a word. Thresholds are deliberately
    /// harsh: a projection the lifter should not lean on must not look like
    /// one they should.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `fitDescription`.
    public static func fitDescription(_ fitQuality: Double) -> String {
        switch fitQuality {
        case 0.75...: return "steady trend"
        case 0.4..<0.75: return "rough trend"
        default: return "very noisy — treat as a guess"
        }
    }
}
