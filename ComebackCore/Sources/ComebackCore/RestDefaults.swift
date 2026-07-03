import Foundation

/// Smart per-exercise rest (seconds) by category + movement — not per-screen
/// magic values. Main lower 5:00, oly/explosive 4:00, main upper 3:00,
/// accessory 1:30 (or its own override), conditioning none. Pure; mirrored 1:1
/// in web/js/core.js `restDefaultSeconds`.
public enum RestDefaults {
    public static func seconds(category: String, name: String, exerciseDefaultRest: Int = 0) -> Int {
        if category == "Conditioning" { return 0 }
        if category == "Main" {
            if name.contains("Deadlift") || name.contains("Squat") { return 300 }
            if name.contains("Clean") || name.contains("Snatch") || name.contains("Push Press") { return 240 }
            return 180
        }
        return exerciseDefaultRest > 0 ? exerciseDefaultRest : 90
    }
}
