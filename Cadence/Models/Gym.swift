import Foundation
import SwiftData
import CadenceCore

/// One plate denomination's availability at a gym.
struct PlateToggle: Codable, Hashable, Identifiable {
    var value: Double
    var unitRaw: String
    var enabled: Bool

    var id: String { "\(value)-\(unitRaw)" }
    var plate: Plate { Plate(value: value, unit: WeightUnit(rawValue: unitRaw) ?? .lb) }

    init(plate: Plate, enabled: Bool = true) {
        self.value = plate.value
        self.unitRaw = plate.unit.rawValue
        self.enabled = enabled
    }
}

@Model
final class Gym {
    @Attribute(.unique) var id: String = UUID().uuidString
    @Attribute(.unique) var name: String
    var isDefault: Bool
    /// Bar id, e.g. "45-lb" — see `Bar.id`. Older builds wrote untrimmed ids
    /// ("45.0-lb"); `Bar.by(id:)` accepts both.
    var defaultBarID: String
    var plateToggles: [PlateToggle]
    /// Combined collar/clip weight for the selected station, canonical pounds.
    var collarWeightLb: Double = 0
    var loadingPolicyRaw: String = "closest"
    /// Photo of the membership barcode/key tag, so a second car key ring
    /// isn't needed. Shown full-screen at max brightness for the scanner.
    @Attribute(.externalStorage) var barcodeImageData: Data?
    var barcodeLabel: String

    init(name: String, isDefault: Bool = false, defaultBar: Bar = .bar45lb) {
        self.name = name
        self.isDefault = isDefault
        self.defaultBarID = defaultBar.id
        self.plateToggles = Plate.allStandard.map { PlateToggle(plate: $0, enabled: true) }
        self.collarWeightLb = 0
        self.loadingPolicyRaw = LoadingPolicy.closest.rawValue
        self.barcodeLabel = "Membership tag"
    }

    var defaultBar: Bar {
        get { Bar.by(id: defaultBarID) }
        set { defaultBarID = newValue.id }
    }

    /// Plates currently available at this gym, for the solver.
    var availablePlates: [Plate] {
        plateToggles.filter(\.enabled).map(\.plate)
    }

    var loadingPolicy: LoadingPolicy {
        get { LoadingPolicy(rawValue: loadingPolicyRaw) ?? .closest }
        set { loadingPolicyRaw = newValue.rawValue }
    }
}

@Model
final class AppSettings {
    var unitDisplayRaw: String
    var proteinTargetGrams: Double
    var accessoryRestSeconds: Int
    // The four other configurable rest buckets (seconds). Defaults mirror the
    // old smart values; secondary rests less than a top main. New properties get
    // SwiftData defaults so existing stores migrate cleanly.
    var mainCompoundRestSeconds: Int = 300
    var olympicRestSeconds: Int = 240
    var mainUpperRestSeconds: Int = 180
    var secondaryRestSeconds: Int = 180
    // Manual rest by default — auto-start lies if you log a set after you've
    // already been resting. Mirrors web defaultSettings (db.js).
    var autoStartRest: Bool = false
    var haptics: Bool = true
    /// Present the default membership tag automatically on the first app
    /// foreground of a local calendar day. The tag is an arrival tool — this
    /// option keeps it instant without hijacking every mid-workout reopen.
    var gymTagFirstLaunchOfDay: Bool = false
    /// One-shot migration marker: old seeds stamped every exercise with a
    /// defaultRestSeconds, which (as the per-exercise override) froze the whole
    /// library out of the rest buckets. `Seeder.syncLibrary` clears values that
    /// still equal those retired stamps exactly once, then sets this.
    var restSeedStampsCleared: Bool = false
    /// One-shot snapshot migration for load basis/implement count. Once set,
    /// historical sets no longer inherit later library edits.
    var loadSemanticsMigrated: Bool = false
    var healthKitEnabled: Bool
    var seededAt: Date?
    /// Selected theme, raw value of `ThemeName` (mirrors web `settings.theme`).
    /// Stored as a String so this model stays free of the SwiftUI view layer.
    var themeNameRaw: String = "carbon"

    init() {
        self.unitDisplayRaw = UnitDisplay.lbPrimary.rawValue
        self.proteinTargetGrams = 100
        self.accessoryRestSeconds = 90
        self.mainCompoundRestSeconds = 300
        self.olympicRestSeconds = 240
        self.mainUpperRestSeconds = 180
        self.secondaryRestSeconds = 180
        self.autoStartRest = false
        self.haptics = true
        self.gymTagFirstLaunchOfDay = false
        // Fresh installs seed a stamp-free library — nothing to migrate. The
        // property's stored default stays false so PRE-EXISTING stores (which
        // carry the old stamps) run the one-shot clear in syncLibrary.
        self.restSeedStampsCleared = true
        self.loadSemanticsMigrated = false
        self.healthKitEnabled = false
        self.seededAt = nil
        self.themeNameRaw = "carbon"
    }

    var unitDisplay: UnitDisplay {
        get { UnitDisplay(rawValue: unitDisplayRaw) ?? .lbPrimary }
        set { unitDisplayRaw = newValue.rawValue }
    }

    /// The rest buckets as a `RestConfig` for `RestDefaults.seconds`.
    var restConfig: RestConfig {
        RestConfig(mainCompoundSeconds: mainCompoundRestSeconds, olympicSeconds: olympicRestSeconds,
                   mainUpperSeconds: mainUpperRestSeconds, secondarySeconds: secondaryRestSeconds,
                   accessorySeconds: accessoryRestSeconds)
    }
}
