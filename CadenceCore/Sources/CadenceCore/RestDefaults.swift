import Foundation

/// The five user-tunable rest buckets (seconds). Defaults match the old
/// hard-coded smart values, except **secondary** (complementary program lifts),
/// which now rests less than a top main. Stored in settings; mirrored in
/// web `defaultSettings`.
public struct RestConfig: Codable, Hashable, Sendable {
    public var mainCompoundSeconds: Int // deadlift / squat
    public var olympicSeconds: Int      // clean / snatch / push press
    public var mainUpperSeconds: Int    // other main lifts
    public var secondarySeconds: Int    // complementary lifts
    public var accessorySeconds: Int    // accessories

    public init(mainCompoundSeconds: Int = 300, olympicSeconds: Int = 240,
                mainUpperSeconds: Int = 180, secondarySeconds: Int = 180, accessorySeconds: Int = 90) {
        self.mainCompoundSeconds = mainCompoundSeconds
        self.olympicSeconds = olympicSeconds
        self.mainUpperSeconds = mainUpperSeconds
        self.secondarySeconds = secondarySeconds
        self.accessorySeconds = accessorySeconds
    }

    public static let standard = RestConfig()
}

/// Smart per-exercise rest (seconds) by role → category → movement, all
/// configurable via `RestConfig`. A per-exercise override (`exerciseDefaultRest
/// > 0`) still wins for ANY movement. Conditioning is 0. Complementary
/// ("secondary") lifts get the secondary bucket regardless of movement, so a
/// light back-off squat rests 3:00, not the 5:00 of a top squat. Pure; mirrored
/// 1:1 in web/js/core.js `restDefaultSeconds`.
public enum RestDefaults {
    public static func seconds(category: String, name: String, role: String? = nil,
                               config: RestConfig = .standard, exerciseDefaultRest: Int = 0) -> Int {
        if exerciseDefaultRest > 0 { return exerciseDefaultRest } // per-exercise override wins everywhere
        if category == "Conditioning" { return 0 }
        if role == "complementary" { return config.secondarySeconds }
        if role == "accessory" { return config.accessorySeconds }
        if category == "Main" {
            if name.contains("Deadlift") || name.contains("Squat") { return config.mainCompoundSeconds }
            if name.contains("Clean") || name.contains("Snatch") || name.contains("Push Press") { return config.olympicSeconds }
            return config.mainUpperSeconds
        }
        return config.accessorySeconds
    }
}
