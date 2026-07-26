import Foundation

/// Bodyweight-derived protein guidance.
///
/// Deliberately advisory, and deliberately outside the programming engine —
/// nothing here feeds progression, readiness, or prescription. The stored
/// `proteinTargetGrams` stays whatever the lifter set; this only offers a
/// number to compare it against.
///
/// The daily figure is the plateau Morton et al. (2018, BJSM 52:376-384)
/// found for resistance-training gains in fat-free mass — 1.62 g/kg/day,
/// rounded here to 1.6 — which sits inside the ISSN's 1.4-2.0 g/kg range.
/// The per-meal figure is the higher threshold PROT-AGE (Bauer et al. 2013)
/// recommends for older adults, whose muscle shows a blunted response to a
/// given dose; hitting the daily total in two sittings is not the same as
/// spreading it across three or four.
///
/// Mirrored 1:1 in web/app/js/core.js.
public enum ProteinGuidance {

    /// Daily total, g per kg of bodyweight.
    public static let dailyGramsPerKg = 1.6
    /// Per meal, g per kg — the threshold that matters more with age.
    public static let mealGramsPerKg = 0.4
    /// Meals the daily total is assumed to be spread across.
    public static let mealsPerDay = 4

    /// Suggested daily protein for a bodyweight, rounded to a usable 5 g.
    /// Nil when there is no bodyweight to work from — the app never invents
    /// one, and a guess here would be a guess about the lifter's body.
    public static func dailyTargetGrams(bodyweightLb: Double?) -> Double? {
        guard let bodyweightLb, bodyweightLb > 0 else { return nil }
        let kg = Weight.kg(fromLb: bodyweightLb)
        return (kg * dailyGramsPerKg / 5).rounded() * 5
    }

    /// Suggested protein per meal, rounded to 5 g.
    public static func perMealGrams(bodyweightLb: Double?) -> Double? {
        guard let bodyweightLb, bodyweightLb > 0 else { return nil }
        let kg = Weight.kg(fromLb: bodyweightLb)
        return (kg * mealGramsPerKg / 5).rounded() * 5
    }

    /// One line of guidance, or nil when there is no bodyweight logged.
    public static func summary(bodyweightLb: Double?) -> String? {
        guard let daily = dailyTargetGrams(bodyweightLb: bodyweightLb),
              let meal = perMealGrams(bodyweightLb: bodyweightLb) else { return nil }
        return "\(Weight.trim(daily)) g/day at \(Weight.trim(dailyGramsPerKg, decimals: 2)) g/kg, "
            + "about \(Weight.trim(meal)) g per meal across \(mealsPerDay)."
    }
}
