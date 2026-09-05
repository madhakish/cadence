import Foundation

/// The physical plate family shown by the equipment renderer. Olympic bumper
/// discs share a competition diameter; calibrated steel steps down with mass.
public enum PlateVisualStyle: String, CaseIterable, Sendable, Identifiable {
    case bumper = "Bumper"
    case steel = "Steel"

    public var id: String { rawValue }
}

/// A plate denomination in its native unit. Gyms toggle these on/off per inventory.
public struct Plate: Hashable, Codable, Sendable, Identifiable, Comparable {
    public let value: Double
    public let unit: WeightUnit

    public init(value: Double, unit: WeightUnit) {
        self.value = value
        self.unit = unit
    }

    // Trimmed like JS Number stringification ("45-lb", "2.5-lb") — this string
    // is a lookup key shared with the web app (plateId in core.js); "45.0-lb"
    // would silently fail to match there.
    public var id: String { "\(Weight.trim(value, decimals: 2))-\(unit.rawValue)" }

    /// Canonical weight in pounds.
    public var lb: Double { Weight.toLb(value, from: unit) }

    /// "45 lb" / "2.5 kg"
    public var label: String { "\(Weight.trim(value, decimals: 2)) \(unit.rawValue)" }

    /// Plate colour token (the user's gym scheme); the UI maps token → hex.
    /// kg is IWF: 25 red · 20 blue · 15 yellow · 10 green · 5 white · 2.5 red change plate.
    /// lb (colour bumpers): 55 red · 45 blue · 35 yellow · 25 green · 10 white ·
    /// 5 and under (and fractional) black iron.
    /// Mirrored 1:1 in web/app/js/core.js `plateColorToken`.
    public func colorToken(for style: PlateVisualStyle) -> String {
        if unit == .lb {
            if value >= 55 { return "red" }
            if value == 45 { return "blue" }
            if value == 35 { return "yellow" }
            if value == 25 { return "green" }
            if value == 10 { return "white" }
            return "black" // 5, 2.5, fractional
        }
        if value >= 25 { return "red" }
        if value == 20 { return "blue" }
        if value == 15 { return "yellow" }
        if value == 10 { return "green" }
        if value == 5 { return "white" }
        if value == 2.5 { return style == .bumper ? "red" : "black" }
        return "black" // 1.25 + misc
    }

    /// Backwards-compatible IWF/colour-bumper token.
    public var colorToken: String { colorToken(for: .bumper) }

    /// Diameter relative to a 450 mm competition disc. Bumpers 10 kg and up
    /// (and colour-coded 10 lb and up) remain full diameter; calibrated steel
    /// follows the common stepped competition profile.
    public func diameterFactor(for style: PlateVisualStyle) -> Double {
        if style == .bumper {
            if unit == .kg {
                if value >= 10 { return 1.0 }
                if value >= 5 { return 0.70 }
                if value >= 2.5 { return 0.55 }
                return 0.45
            }
            if value >= 10 { return 1.0 }
            if value >= 5 { return 0.55 }
            return 0.45
        }
        if lb >= 44 { return 1.0 }
        if lb >= 33 { return 0.89 }
        if lb >= 22 { return 0.72 }
        if lb >= 11 { return 0.51 }
        if lb >= 5 { return 0.42 }
        return 0.36
    }

    /// Relative axial thickness. Rubber bumpers consume substantially more
    /// sleeve than calibrated steel at the same denomination.
    public func thicknessFactor(for style: PlateVisualStyle) -> Double {
        if style == .bumper {
            if lb >= 50 { return 1.0 }
            if lb >= 44 { return 0.84 }
            if lb >= 33 { return 0.70 }
            if lb >= 22 { return 0.56 }
            if lb >= 11 { return 0.38 }
            if lb >= 5 { return 0.28 }
            return 0.22
        }
        if lb >= 50 { return 0.55 }
        if lb >= 44 { return 0.47 }
        if lb >= 33 { return 0.40 }
        if lb >= 22 { return 0.33 }
        if lb >= 11 { return 0.25 }
        if lb >= 5 { return 0.19 }
        return 0.15
    }

    public var sizeFactor: Double { diameterFactor(for: .steel) }

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

    // Same trimmed key format as Plate.id / web barId ("45-lb", "20-kg") —
    // gyms persist defaultBarId strings that both apps must resolve.
    public var id: String { "\(Weight.trim(value, decimals: 2))-\(unit.rawValue)" }
    public var lb: Double { Weight.toLb(value, from: unit) }
    public var label: String { "\(Weight.trim(value)) \(unit.rawValue) bar" }
    /// The lb denomination this bar loads plans under: an lb bar is its own
    /// label; a kg bar labels under its lb twin (a 20 kg bar IS the 45 in the
    /// same sense the plates are). Twin equivalence maths against this label,
    /// never the raw converted mass — 44.09 lb is not a clean lb plan.
    public var labelLb: Double {
        unit == .lb ? value
            : PlateMath.plateTwinKg.first(where: { $0.value == value })?.key ?? lb
    }

    public static let bar45lb = Bar(value: 45, unit: .lb)
    public static let bar35lb = Bar(value: 35, unit: .lb)
    public static let bar20kg = Bar(value: 20, unit: .kg)
    public static let bar15kg = Bar(value: 15, unit: .kg)
    public static let all: [Bar] = [.bar45lb, .bar35lb, .bar20kg, .bar15kg]

    /// Resolve a persisted id, falling back to the 45 lb bar like web `barById`.
    /// Also accepts legacy untrimmed ids ("20.0-kg") written by builds where
    /// `id` interpolated the raw Double — SwiftData gyms persisted those.
    public static func by(id: String) -> Bar {
        if let bar = all.first(where: { $0.id == id }) { return bar }
        let parts = id.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let value = Double(parts[0]),
              let unit = WeightUnit(rawValue: String(parts[1])) else { return .bar45lb }
        return all.first { $0.value == value && $0.unit == unit } ?? .bar45lb
    }
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
    /// Combined weight of the pair of collars/clips, canonical pounds.
    public let collarLb: Double

    public init(
        bar: Bar,
        perSide: [PlateCount],
        collarLb: Double = 0,
        preservesOrder: Bool = false
    ) {
        self.bar = bar
        self.perSide = preservesOrder ? perSide : perSide.sorted { $0.plate.lb > $1.plate.lb }
        self.collarLb = max(0, collarLb)
    }

    public var perSideLb: Double { perSide.reduce(0) { $0 + $1.lb } }
    public var totalLb: Double { bar.lb + collarLb + 2 * perSideLb }

    /// "45 lb + 15 kg" loading order, heaviest first.
    public var perSideLabel: String {
        perSide.isEmpty ? "bar only" : perSide.map(\.label).joined(separator: " + ")
    }
}
