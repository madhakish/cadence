import Foundation
import SwiftData
import ComebackCore

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
    /// Bar id, e.g. "45.0-lb" — see `Bar.id`.
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
        get { Bar.all.first { $0.id == defaultBarID } ?? .bar45lb }
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
    var mainLiftRestSeconds: Int
    var accessoryRestSeconds: Int
    var healthKitEnabled: Bool
    var seededAt: Date?

    init() {
        self.unitDisplayRaw = UnitDisplay.lbPrimary.rawValue
        self.proteinTargetGrams = 175
        self.mainLiftRestSeconds = 300
        self.accessoryRestSeconds = 90
        self.healthKitEnabled = false
        self.seededAt = nil
    }

    var unitDisplay: UnitDisplay {
        get { UnitDisplay(rawValue: unitDisplayRaw) ?? .lbPrimary }
        set { unitDisplayRaw = newValue.rawValue }
    }
}
