import Foundation

/// A plate denomination in its native unit. Gyms toggle these on/off per inventory.
public struct Plate: Hashable, Codable, Sendable, Identifiable, Comparable {
    public let value: Double
    public let unit: WeightUnit

    public init(value: Double, unit: WeightUnit) {
        self.value = value
        self.unit = unit
    }

    public var id: String { "\(value)-\(unit.rawValue)" }

    /// Canonical weight in pounds.
    public var lb: Double { Weight.toLb(value, from: unit) }

    /// "45 lb" / "2.5 kg"
    public var label: String { "\(Weight.trim(value, decimals: 2)) \(unit.rawValue)" }

    public static func < (lhs: Plate, rhs: Plate) -> Bool { lhs.lb < rhs.lb }

    /// Standard kg plate set: 25, 20, 15, 10, 5, 2.5, 1.25.
    public static let standardKg: [Plate] = [25, 20, 15, 10, 5, 2.5, 1.25]
        .map { Plate(value: $0, unit: .kg) }

    /// Standard lb plate set: 45, 35, 25, 10, 5, 2.5.
    public static let standardLb: [Plate] = [45, 35, 25, 10, 5, 2.5]
        .map { Plate(value: $0, unit: .lb) }

    public static let allStandard: [Plate] = standardLb + standardKg
}

/// Barbell options.
public struct Bar: Hashable, Codable, Sendable, Identifiable {
    public let value: Double
    public let unit: WeightUnit

    public init(value: Double, unit: WeightUnit) {
        self.value = value
        self.unit = unit
    }

    public var id: String { "\(value)-\(unit.rawValue)" }
    public var lb: Double { Weight.toLb(value, from: unit) }
    public var label: String { "\(Weight.trim(value)) \(unit.rawValue) bar" }

    public static let bar45lb = Bar(value: 45, unit: .lb)
    public static let bar35lb = Bar(value: 35, unit: .lb)
    public static let bar20kg = Bar(value: 20, unit: .kg)
    public static let all: [Bar] = [.bar45lb, .bar35lb, .bar20kg]
}

/// N of one plate denomination on ONE side of the bar.
public struct PlateCount: Hashable, Codable, Sendable, Identifiable {
    public let plate: Plate
    public let count: Int

    public init(plate: Plate, count: Int) {
        self.plate = plate
        self.count = count
    }

    public var id: String { plate.id }
    public var lb: Double { plate.lb * Double(count) }
    public var label: String { count == 1 ? plate.label : "\(plate.label) ×\(count)" }
}

/// Everything on the bar: bar + per-side plates (mirrored on both sides).
public struct Loadout: Hashable, Codable, Sendable {
    public let bar: Bar
    public let perSide: [PlateCount]

    public init(bar: Bar, perSide: [PlateCount]) {
        self.bar = bar
        self.perSide = perSide.sorted { $0.plate.lb > $1.plate.lb }
    }

    public var perSideLb: Double { perSide.reduce(0) { $0 + $1.lb } }
    public var totalLb: Double { bar.lb + 2 * perSideLb }

    /// "45 lb + 15 kg" loading order, heaviest first.
    public var perSideLabel: String {
        perSide.isEmpty ? "bar only" : perSide.map(\.label).joined(separator: " + ")
    }
}
