import Foundation

/// The five user-tunable rest buckets (seconds). Stored in settings; mirrored
/// in web `defaultSettings`. These are the SMART DEFAULTS an exercise falls to
/// when it has no explicit rest of its own — see `RestDefaults.seconds`.
public struct RestConfig: Codable, Hashable, Sendable {
    public var mainCompoundSeconds: Int // main squat & hinge lifts
    public var olympicSeconds: Int      // main olympic lifts
    public var mainUpperSeconds: Int    // other main lifts (presses etc.)
    public var secondarySeconds: Int    // complementary program lifts
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

/// Smart per-exercise rest (seconds), resolved in a fixed precedence order:
///
/// 1. The exercise's own rest (`exerciseDefaultRest > 0`) wins everywhere —
///    it's the deliberate exception (set via ⏱ in the logger or the library).
/// 2. Conditioning never rests (the work IS the clock).
/// 3. The exercise's role in today's program: complementary lifts get the
///    secondary bucket (a back-off squat rests 3:00, not a top squat's 5:00);
///    accessories get the accessory bucket.
/// 4. Otherwise the movement decides, keyed on `movementGroup` — the same
///    data-driven grouping that powers swaps — never on name matching:
///    main squat/hinge → mainCompound, main olympic → olympic, any other
///    main → mainUpper, everything else → accessory.
///
/// Pure; mirrored 1:1 in web/js/core.js `restDefaultSeconds`.
public enum RestDefaults {
    public static func seconds(category: String, movementGroup: String, role: String? = nil,
                               config: RestConfig = .standard, exerciseDefaultRest: Int = 0) -> Int {
        if exerciseDefaultRest > 0 { return exerciseDefaultRest } // per-exercise rest wins everywhere
        if category == "Conditioning" || movementGroup == "conditioning" { return 0 }
        if role == "complementary" { return config.secondarySeconds }
        if role == "accessory" { return config.accessorySeconds }
        if category == "Main" {
            if movementGroup == "squat" || movementGroup == "hinge" { return config.mainCompoundSeconds }
            if movementGroup == "olympic" { return config.olympicSeconds }
            return config.mainUpperSeconds
        }
        return config.accessorySeconds
    }
}
