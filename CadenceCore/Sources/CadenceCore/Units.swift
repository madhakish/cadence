import Foundation

/// Weight units. All weights are STORED in pounds (Double), always.
/// Conversion happens only at display/entry boundaries.
public enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case lb
    case kg

    /// Exact international avoirdupois pound.
    public static let kgPerLb = 0.453_592_37
    public static let lbPerKg = 1.0 / kgPerLb
}

public enum Weight {
    public static func lb(fromKg kg: Double) -> Double { kg * WeightUnit.lbPerKg }
    public static func kg(fromLb lb: Double) -> Double { lb * WeightUnit.kgPerLb }

    /// Convert a value in `unit` to canonical pounds.
    public static func toLb(_ value: Double, from unit: WeightUnit) -> Double {
        unit == .lb ? value : lb(fromKg: value)
    }

    /// Round to nearest increment (e.g. 5 lb plates-on-bar granularity).
    public static func round(_ valueLb: Double, to increment: Double) -> Double {
        guard increment > 0 else { return valueLb }
        return (valueLb / increment).rounded() * increment
    }

    /// "232" or "232.4" — drop trailing .0
    public static func trim(_ value: Double, decimals: Int = 1) -> String {
        let rounded = (value * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        var s = String(format: "%.\(decimals)f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// "232 lb / 105.4 kg"
    public static func both(lb value: Double) -> String {
        "\(trim(value)) lb / \(trim(kg(fromLb: value))) kg"
    }
}

/// How the user wants weights shown.
public enum UnitDisplay: String, Codable, CaseIterable, Sendable {
    case lbPrimary
    case kgPrimary
    case both

    public func format(lb: Double) -> String {
        switch self {
        case .lbPrimary: return "\(Weight.trim(lb)) lb"
        case .kgPrimary: return "\(Weight.trim(Weight.kg(fromLb: lb))) kg"
        case .both: return Weight.both(lb: lb)
        }
    }
}
