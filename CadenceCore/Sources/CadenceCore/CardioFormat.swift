import Foundation

/// Formatting and arithmetic for conditioning ("cardio") sets — distance,
/// time, speed, flights, incline — shared by the logger and history rows so
/// every view renders the same label. Pure; mirrored 1:1 in web/app/js/core.js
/// (`cardioSpeedMph`, `cardioDistanceMiles`, `cardioDurationSeconds`,
/// `cardioFlightPace`, `cardioFlights`, `cardioFlightDurationSeconds`,
/// `cardioDurationLabel`, `cardioSetLabel`).
///
/// Distance, duration, and speed are one relationship seen from three sides:
/// `distance = speed × time`. Any two give the third, so the logger can accept
/// whichever two the lifter actually knows. A treadmill or a rucking plan is
/// set by **speed and time** and the distance falls out; a GPS run gives
/// **distance and time** and the pace falls out. Only distance and duration are
/// persisted — speed is always recoverable from them, so there is no third
/// field to store, disagree with itself, or migrate.
///
/// Flights repeat that relationship against a yardstick that is not ground
/// covered — see the climbed-flights section below — and are persisted the same
/// way: the count and the duration, never the pace.
public enum CardioFormat {

    /// Miles per hour from distance + duration, rounded to one decimal.
    /// nil when either half is missing/zero (no speed without both).
    public static func speedMph(distanceMiles: Double?, durationSeconds: Int?) -> Double? {
        guard let miles = distanceMiles, miles > 0,
              let secs = durationSeconds, secs > 0 else { return nil }
        return (miles / (Double(secs) / 3600) * 10).rounded() / 10
    }

    /// Miles from speed + duration — the treadmill case, where the lifter sets
    /// a pace and a time and never sees a distance until the belt stops.
    /// nil when either half is missing/zero.
    ///
    /// Kept to four decimals rather than the two a treadmill displays: at two,
    /// a one-minute interval cannot tell 3.0 mph from 3.1 (both land on
    /// 0.05 mi), so the stepper would refuse to advance and a logged pace would
    /// read back as a different one. Display trims; storage does not.
    public static func distanceMiles(speedMph: Double?, durationSeconds: Int?) -> Double? {
        guard let mph = speedMph, mph > 0,
              let secs = durationSeconds, secs > 0 else { return nil }
        return (mph * (Double(secs) / 3600) * 10_000).rounded() / 10_000
    }

    /// Seconds from distance + speed — "four miles at 3.5 mph" as a plan.
    /// nil when either half is missing/zero.
    public static func durationSeconds(distanceMiles: Double?, speedMph: Double?) -> Int? {
        guard let miles = distanceMiles, miles > 0,
              let mph = speedMph, mph > 0 else { return nil }
        return Int((miles / mph * 3600).rounded())
    }

    // MARK: - Climbed flights

    /// Conditioning measured in **flights climbed**, not ground covered. A
    /// stair climber's belt goes nowhere, so miles and miles-per-hour describe
    /// it with a unit it does not have: the console counts floors, and the
    /// training variable is how many and how fast.
    ///
    /// Flights and distance are the same shape of relationship seen against a
    /// different yardstick — `flights = pace × time` — so the same solve-the-
    /// third rule applies, with pace in flights per minute rather than miles
    /// per hour. Minutes, because a climber's console reads in floors per
    /// minute and an hourly rate on a twenty-minute effort is a number nobody
    /// checks against the machine.
    public static let flightClimbers: Set<String> = ["Stair Climber"]

    /// Whether this conditioning movement is measured in flights.
    public static func climbsFlights(exerciseName: String) -> Bool {
        flightClimbers.contains(exerciseName)
    }

    /// Flights per minute from flights + duration, rounded to one decimal.
    /// nil when either half is missing/zero (no pace without both).
    public static func flightPace(flights: Double?, durationSeconds: Int?) -> Double? {
        guard let flights, flights > 0,
              let secs = durationSeconds, secs > 0 else { return nil }
        return (flights / (Double(secs) / 60) * 10).rounded() / 10
    }

    /// Flights from pace + duration — the planned case, "twenty minutes at
    /// eight floors a minute". nil when either half is missing/zero.
    ///
    /// Kept to four decimals for the same reason distance is: a pace set on a
    /// short interval has to read back as the pace that was set, and rounding
    /// to whole flights would collapse neighbouring paces onto one count.
    /// Display trims; storage does not.
    public static func flights(pacePerMinute: Double?, durationSeconds: Int?) -> Double? {
        guard let pace = pacePerMinute, pace > 0,
              let secs = durationSeconds, secs > 0 else { return nil }
        return (pace * (Double(secs) / 60) * 10_000).rounded() / 10_000
    }

    /// Seconds from flights + pace — "sixty floors at eight a minute" as a
    /// plan. nil when either half is missing/zero.
    public static func durationSeconds(flights: Double?, pacePerMinute: Double?) -> Int? {
        guard let flights, flights > 0,
              let pace = pacePerMinute, pace > 0 else { return nil }
        return Int((flights / pace * 60).rounded())
    }

    /// "170 flights", "1 flight". Trimmed to one decimal: a count entered by
    /// hand is whole, but one solved from a pace over a short interval is not,
    /// and rounding it away would contradict the pace shown beside it.
    public static func flightsLabel(_ flights: Double) -> String {
        let text = Weight.trim(flights, decimals: 1)
        return "\(text) \(text == "1" ? "flight" : "flights")"
    }

    // MARK: - Loaded carries

    /// Conditioning that carries external load. A ruck is a walk with a pack
    /// on, and the pack weight is the training variable — progressing it is the
    /// whole point of rucking. Zeroing the load the way unloaded cardio does
    /// throws that away and makes a 60 lb ruck indistinguishable from a stroll.
    public static let loadedCarries: Set<String> = ["Ruck", "Sled Push", "Sled Pull"]

    /// Whether this conditioning movement carries a load worth logging.
    public static func carriesLoad(exerciseName: String) -> Bool {
        loadedCarries.contains(exerciseName)
    }

    /// Where a loaded carry starts when nothing has been logged yet. A 20 lb
    /// pack is the conventional entry point — heavy enough to train, light
    /// enough that form and feet survive the first few outings. Sleds vary far
    /// too much by surface and implement to have an honest default.
    public static func defaultLoadLb(exerciseName: String) -> Double? {
        exerciseName == "Ruck" ? 20 : nil
    }

    /// Loaded carries move in plates and full pack increments, not the 2.5 lb
    /// steps a barbell lift wants.
    public static let loadIncrementLb: Double = 10

    // MARK: - Which fields an editor offers

    /// Which fields a conditioning set is edited with.
    ///
    /// Decided by the movement AND by what the set already holds: a climb
    /// logged in miles before flights existed keeps its distance block, because
    /// a field that disappears takes the only way to correct the value with it.
    ///
    /// One source for the editor's rows, the editor's section header, and the
    /// row's affordance line, so a row can never advertise a field the editor
    /// withholds — the three had already drifted apart when each decided for
    /// itself. Mirrored in web/app/js/core.js (`cardioFields`).
    public struct CardioFields: Equatable, Sendable {
        public let load: Bool
        public let flights: Bool
        public let distance: Bool
        public let incline: Bool

        /// Ordered field names, matching the order the rows appear in.
        public var names: [String] {
            var out: [String] = []
            if load { out.append("load") }
            if flights { out.append("flights") }
            if distance { out.append("distance") }
            out.append("time")
            if distance { out.append("speed") }
            if flights { out.append("pace") }
            if incline { out.append("incline") }
            return out
        }

        /// "flights · time · pace" — the affordance line under a set row.
        public var label: String { names.joined(separator: " · ") }

        /// "Flights · time · pace" — the same list as an editor section header.
        public var headerLabel: String {
            var out = names
            guard let first = out.first else { return "" }
            out[0] = first.prefix(1).uppercased() + String(first.dropFirst())
            return out.joined(separator: " · ")
        }
    }

    public static func fields(
        exerciseName: String, flights: Double?, distanceMiles: Double?, inclinePercent: Double?
    ) -> CardioFields {
        let climbs = climbsFlights(exerciseName: exerciseName)
        return CardioFields(
            load: carriesLoad(exerciseName: exerciseName),
            flights: climbs || (flights ?? 0) > 0,
            distance: !climbs || (distanceMiles ?? 0) > 0,
            // A climber's grade is the machine, not a setting — unless a legacy
            // set already carries one.
            incline: !climbs || (inclinePercent ?? 0) > 0
        )
    }

    /// Formats a duration as minutes and seconds, including hours when needed.
    public static func durationLabel(seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Builds one compact line from whichever cardio fields were logged.
    /// Missing halves simply drop out; nothing logged → "—".
    /// `loadLb` is the carried weight for a ruck or sled — omitted entirely for
    /// unloaded work, which has none.
    ///
    /// Driven by what the set actually holds rather than by the exercise, so a
    /// stair-climber set logged in miles before flights existed still renders
    /// the distance it was recorded with instead of reading empty.
    public static func setLabel(
        distanceMiles: Double?, durationSeconds: Int?, inclinePercent: Double?,
        loadLb: Double? = nil, flights: Double? = nil
    ) -> String {
        var parts: [String] = []
        if let lb = loadLb, lb > 0 { parts.append("\(Weight.trim(lb)) lb") }
        if let flights, flights > 0 { parts.append(flightsLabel(flights)) }
        if let miles = distanceMiles, miles > 0 { parts.append("\(Weight.trim(miles, decimals: 2)) mi") }
        if let secs = durationSeconds, secs > 0 { parts.append(durationLabel(seconds: secs)) }
        if let mph = speedMph(distanceMiles: distanceMiles, durationSeconds: durationSeconds) {
            parts.append("\(Weight.trim(mph)) mph")
        }
        if let pace = flightPace(flights: flights, durationSeconds: durationSeconds) {
            parts.append("\(Weight.trim(pace)) fl/min")
        }
        if let incline = inclinePercent, incline > 0 { parts.append("\(Weight.trim(incline))%") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
