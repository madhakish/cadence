import Foundation

/// Bodyweight- and age-derived protein guidance.
///
/// Advisory only, and deliberately outside the programming engine — nothing
/// here feeds progression, readiness, or prescription. Since schema V5 there is
/// no protein tracker and no stored target either: serving-level logging only
/// works with a real meal-entry surface, so what remains is a figure to aim at
/// rather than a number to tick off.
///
/// The daily figure is the plateau Morton et al. (2018, BJSM 52:376-384) found
/// for resistance-training gains in fat-free mass — 1.62 g/kg/day, rounded here
/// to 1.6 — which sits inside the ISSN's 1.4-2.0 g/kg range.
///
/// **On training type:** 1.6 g/kg *is* the resistance-training figure. That
/// meta-analysis pooled RT trials specifically, so the modality is already
/// inside the number. There is no per-session multiplier here, because scaling
/// a daily intake by what one day's workout happened to be is not something the
/// evidence supports — total training over weeks is what moves the requirement,
/// and Cadence's programs are all resistance training.
///
/// **On age:** the per-meal threshold is where age genuinely changes the
/// answer. Older muscle shows a blunted response to a given dose, so the same
/// daily total split the same way does less. Moore et al. (2015, J Gerontol A
/// 70:57-62) put the per-meal plateau near 0.24 g/kg for younger adults and
/// near 0.40 g/kg for older ones, the higher figure PROT-AGE (Bauer et al.
/// 2013) recommends. Hitting a daily total in two sittings is not the same as
/// spreading it across four.
///
/// Mirrored 1:1 in web/app/js/core.js.
public enum ProteinGuidance {

    /// Daily total, g per kg of bodyweight.
    public static let dailyGramsPerKg = 1.6
    /// Per meal, g per kg, for adults under `olderAdultAge`.
    public static let mealGramsPerKgYounger = 0.25
    /// Per meal, g per kg, from `olderAdultAge` onward.
    public static let mealGramsPerKgOlder = 0.4
    /// The age PROT-AGE uses for its older-adult recommendations.
    public static let olderAdultAge = 65
    /// Meals the daily total is assumed to be spread across.
    public static let mealsPerDay = 4

    /// Age in whole years, or nil when the lifter has not given a usable birth
    /// year. Never guessed: a default age would silently apply the wrong
    /// per-meal threshold to someone who never answered.
    public static func age(birthYear: Int, inYear currentYear: Int) -> Int? {
        guard birthYear > 1900, currentYear >= birthYear else { return nil }
        let years = currentYear - birthYear
        return years <= 120 ? years : nil
    }

    /// The per-meal threshold that applies at an age. Without an age this is
    /// the older-adult figure — the conservative direction, because eating to
    /// the higher per-dose threshold costs a younger lifter nothing, while
    /// under-dosing an older one is the failure that matters.
    public static func mealGramsPerKg(age: Int?) -> Double {
        guard let age else { return mealGramsPerKgOlder }
        return age >= olderAdultAge ? mealGramsPerKgOlder : mealGramsPerKgYounger
    }

    /// Suggested daily protein for a bodyweight, rounded to a usable 5 g.
    /// Nil when there is no bodyweight to work from — the app never invents
    /// one, and a guess here would be a guess about the lifter's body.
    public static func dailyTargetGrams(bodyweightLb: Double?) -> Double? {
        guard let bodyweightLb, bodyweightLb > 0 else { return nil }
        let kg = Weight.kg(fromLb: bodyweightLb)
        return (kg * dailyGramsPerKg / 5).rounded() * 5
    }

    /// Suggested protein per meal, rounded to 5 g.
    public static func perMealGrams(bodyweightLb: Double?, age: Int? = nil) -> Double? {
        guard let bodyweightLb, bodyweightLb > 0 else { return nil }
        let kg = Weight.kg(fromLb: bodyweightLb)
        return (kg * mealGramsPerKg(age: age) / 5).rounded() * 5
    }

    /// One line of guidance, or nil when there is no bodyweight logged.
    public static func summary(bodyweightLb: Double?, age: Int? = nil) -> String? {
        guard let daily = dailyTargetGrams(bodyweightLb: bodyweightLb),
              let meal = perMealGrams(bodyweightLb: bodyweightLb, age: age) else { return nil }
        return "\(Weight.trim(daily)) g/day at \(Weight.trim(dailyGramsPerKg, decimals: 2)) g/kg, "
            + "about \(Weight.trim(meal)) g per meal across \(mealsPerDay)."
    }

    /// Why the per-meal figure is what it is, or nil without an age to explain
    /// it. Shown beside the summary so the number changing after a birth year
    /// is entered reads as intended rather than as a bug.
    public static func perMealRationale(age: Int?) -> String? {
        guard let age else { return nil }
        return age >= olderAdultAge
            ? "Per-meal figure uses the higher \(Weight.trim(mealGramsPerKgOlder, decimals: 2)) g/kg "
                + "threshold for adults \(olderAdultAge)+; muscle responds less to a given dose with age."
            : "Per-meal figure uses \(Weight.trim(mealGramsPerKgYounger, decimals: 2)) g/kg, "
                + "rising to \(Weight.trim(mealGramsPerKgOlder, decimals: 2)) g/kg from \(olderAdultAge)."
    }
}
