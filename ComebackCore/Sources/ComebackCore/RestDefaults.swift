import Foundation

/// Smart per-exercise rest (seconds) by category + movement — not per-screen
/// magic values. A per-exercise override (`exerciseDefaultRest > 0`) wins for
/// ANY movement; otherwise main lower 5:00, oly/explosive 4:00, main upper
/// 3:00, accessory 1:30, conditioning none. Pure; mirrored 1:1 in
/// web/js/core.js `restDefaultSeconds`.
public enum RestDefaults {
    public static func seconds(category: String, name: String, exerciseDefaultRest: Int = 0) -> Int {
        if exerciseDefaultRest > 0 { return exerciseDefaultRest } // per-exercise override wins everywhere
        if category == "Conditioning" { return 0 }
        if category == "Main" {
            if name.contains("Deadlift") || name.contains("Squat") { return 300 }
            if name.contains("Clean") || name.contains("Snatch") || name.contains("Push Press") { return 240 }
            return 180
        }
        return 90
    }
}
