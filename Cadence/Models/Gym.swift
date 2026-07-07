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
    @Attribute(.unique) var name: String
    var isDefault: Bool
    /// Bar id, e.g. "45-lb" — see `Bar.id`. Older builds wrote untrimmed ids
    /// ("45.0-lb"); `Bar.by(id:)` accepts both.
    var defaultBarID: String
    var plateToggles: [PlateToggle]
    /// Photo of the membership barcode/key tag, so a second car key ring
    /// isn't needed. Shown full-screen at max brightness for the scanner.
    @Attribute(.externalStorage) var barcodeImageData: Data?
    var barcodeLabel: String

    init(name: String, isDefault: Bool = false, defaultBar: Bar = .bar45lb) {
        self.name = name
        self.isDefault = isDefault
        self.defaultBarID = defaultBar.id
        self.plateToggles = Plate.allStandard.map { PlateToggle(plate: $0, enabled: true) }
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
}

@Model
final class AppSettings {
    var unitDisplayRaw: String
    var proteinTargetGrams: Double
    var accessoryRestSeconds: Int
    // Manual rest by default — auto-start lies if you log a set after you've
    // already been resting. Mirrors web defaultSettings (db.js).
    var autoStartRest: Bool = false
    var haptics: Bool = true
    var healthKitEnabled: Bool
    var seededAt: Date?

    init() {
        self.unitDisplayRaw = UnitDisplay.lbPrimary.rawValue
        self.proteinTargetGrams = 175
        self.accessoryRestSeconds = 90
        self.autoStartRest = false
        self.haptics = true
        self.healthKitEnabled = false
        self.seededAt = nil
    }

    var unitDisplay: UnitDisplay {
        get { UnitDisplay(rawValue: unitDisplayRaw) ?? .lbPrimary }
        set { unitDisplayRaw = newValue.rawValue }
    }
}
