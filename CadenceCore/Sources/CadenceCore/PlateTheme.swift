import Foundation

/// The equipment look a gym has chosen: which real plate family fills the bar
/// (dimensions, construction, finish, colour rule) for each unit. Presentation
/// only — a theme never changes a plate's identity, recorded mass, inventory
/// toggles, or the solver. Mirrored 1:1 by `web/app/js/plate-theme.js`.
///
/// Raw values are persisted on `Gym.plateThemeRaw` and in backups; they are
/// append-only identifiers, never renamed.
public enum PlateThemeID: String, CaseIterable, Codable, Sendable, Identifiable {
    case iwfCompetition
    case iwfTraining
    case ipfCalibrated
    case ipfCalibratedGloss
    case lbColourBumpers
    case lbBlackIron
    case lbGreyHammertone
    case lbMachinedSteel
    case blackBumpersBand
    case cadenceHouse
    /// Today's mixed behaviour: colour bumpers by value, steel by style.
    case custom

    public var id: String { rawValue }

    /// Short picker title.
    public var label: String {
        switch self {
        case .iwfCompetition: return "IWF Competition"
        case .iwfTraining: return "IWF Training"
        case .ipfCalibrated: return "IPF Calibrated"
        case .ipfCalibratedGloss: return "IPF Calibrated · gloss"
        case .lbColourBumpers: return "lb Colour Bumpers"
        case .lbBlackIron: return "lb Black Iron"
        case .lbGreyHammertone: return "lb Grey Hammertone"
        case .lbMachinedSteel: return "lb Machined Steel"
        case .blackBumpersBand: return "Black Bumpers · colour band"
        case .cadenceHouse: return "Cadence House"
        case .custom: return "Custom"
        }
    }

    /// The unit the theme was designed around; the other unit uses its sibling set.
    public var primaryUnit: WeightUnit {
        switch self {
        case .lbColourBumpers, .lbBlackIron, .lbGreyHammertone, .lbMachinedSteel: return .lb
        default: return .kg
        }
    }

    /// Migration default for a gym that has never chosen: a single-unit
    /// inventory reads as that unit's plainest real set, anything mixed stays
    /// `custom`. Descriptive, editable, never a rules claim.
    public static func inferred(from units: some Collection<WeightUnit>) -> PlateThemeID {
        let set = Set(units)
        if set == [.lb] { return .lbBlackIron }
        if set == [.kg] { return .iwfCompetition }
        return .custom
    }
}

/// Surface finish of a plate body.
public enum PlateFinish: String, Sendable {
    case rubber, powder, gloss, castIron, hammertone, machined
}

/// Finish of the metal hub insert.
public enum PlateHubFinish: String, Sendable {
    case chrome, blackSteel, castIron, hammertone
}

/// Finish of the bar shaft (sleeves stay chrome).
public enum BarFinish: String, Sendable {
    case chrome, blackOxide
}

/// A plate body's material. `photoFamily` is the photographed face sprite
/// family, or nil for a procedural face.
public struct PlateMaterial: Equatable, Sendable {
    public let finish: PlateFinish
    public let metal: Double
    public let roughness: Double
    public let photoFamily: PlateVisualStyle?

    public init(finish: PlateFinish, metal: Double, roughness: Double, photoFamily: PlateVisualStyle?) {
        self.finish = finish
        self.metal = metal
        self.roughness = roughness
        self.photoFamily = photoFamily
    }
}

/// Fractions of the plate radius: metal hub insert, hub mask on a
/// photographed face, and outer edge of the label band.
public struct PlateRatios: Equatable, Sendable {
    public let hub: Double
    public let photoHub: Double
    public let rim: Double
}

/// One theme's full description. Mirrors `PLATE_THEMES` in
/// web/app/js/plate-theme.js; web/tests/fixtures/plate-themes.json pins both.
/// Dimensions (mm) trace to docs/design-pass/PLATE-REFERENCE.md. `custom` has
/// no tables: every accessor returns today's style-driven behaviour for it.
public struct PlateTheme: Sendable {
    struct Row: Sendable {
        let diameter: Double
        let thickness: Double
        let family: String
    }

    enum ColourRule: Sendable {
        /// Fill per plate id, ink by luminance.
        case table([String: UInt32])
        /// One fill and ink for every denomination.
        case mono(fill: UInt32, ink: UInt32)
        /// Black body, colour band and numerals per plate id.
        case band([String: UInt32])
    }

    struct BaseMaterial: Sendable {
        let finish: PlateFinish
        let metal: Double
        let roughness: Double
        var changeRoughness: Double?
        let photoFamily: PlateVisualStyle?
    }

    /// Plate ids per unit, heaviest first.
    public let sets: [WeightUnit: [String]]
    let plates: [String: Row]
    let colourRule: ColourRule?
    let baseMaterial: BaseMaterial?
    /// Chrome change discs (calibrated sets) and their roughness.
    var chrome: [String] = []
    var chromeRoughness = 0.0
    public var hubRatio: Double?
    public var photoHubRatio: Double?
    public var rimRatio: Double?
    public var hubFinish = PlateHubFinish.chrome
    /// Construction details the renderer adds: boltedHub, chromeBoreRing,
    /// calibrationPlugs, machinedRimRing, colourBand, hubRing (a ring at the
    /// hub edge in the numeral colour).
    public var details: [String] = []
    public var brand = "CADENCE"
    public var barFinish = BarFinish.chrome
    public var backdrop: UInt32 = 0x17181B

    init(sets: [WeightUnit: [String]], plates: [String: Row], colour: ColourRule?, material: BaseMaterial?) {
        self.sets = sets
        self.plates = plates
        self.colourRule = colour
        self.baseMaterial = material
    }

    // Real-equipment dimensions (mm) per product line.
    private static let iwfBumper: [String: [Double]] = [
        "25-kg": [450, 66], "20-kg": [450, 55], "15-kg": [450, 42], "10-kg": [450, 29],
    ]
    private static let iwfChange: [String: [Double]] = [
        "5-kg": [230, 26], "2.5-kg": [210, 19], "2-kg": [190, 19], "1.5-kg": [175, 18],
        "1-kg": [160, 15], "0.5-kg": [135, 12.5], "1.25-kg": [160, 12],
    ]
    private static let ipfSteel: [String: [Double]] = [
        "25-kg": [450, 27], "20-kg": [450, 22.5], "15-kg": [400, 21], "10-kg": [325, 21],
        "5-kg": [228, 21.5], "2.5-kg": [190, 16], "1.25-kg": [160, 12],
    ]
    private static let lbBumper: [String: [Double]] = [
        "55-lb": [450, 70], "45-lb": [450, 60], "35-lb": [450, 49], "25-lb": [450, 38], "10-lb": [450, 21],
    ]
    private static let lbChangeRubber: [String: [Double]] = [
        "5-lb": [190, 19], "2.5-lb": [162, 15], "1.25-lb": [133, 10],
    ]
    private static let lbIron: [String: [Double]] = [
        "45-lb": [450, 50], "35-lb": [360, 34.5], "25-lb": [276, 34.5], "10-lb": [229, 20],
        "5-lb": [190, 14.5], "2.5-lb": [162, 12],
    ]
    private static let lbMachined: [String: [Double]] = [
        "45-lb": [448, 38], "35-lb": [360, 38], "25-lb": [300, 38], "10-lb": [228, 31],
        "5-lb": [195, 21], "2.5-lb": [162, 16],
    ]
    private static let kgIron: [String: [Double]] = [
        "20-kg": [450, 36], "15-kg": [400, 32], "10-kg": [345, 29], "5-kg": [275, 22],
        "2.5-kg": [225, 18], "1.25-kg": [170, 14],
    ]

    // Federation colour rules as they photograph (matte rubber / painted steel).
    private static let iwf: [String: UInt32] = [
        "25-kg": 0xC6302C, "20-kg": 0x234FAE, "15-kg": 0xE2B21C, "10-kg": 0x1F8B45, "5-kg": 0xE8E5DF,
        "2.5-kg": 0xC6302C, "2-kg": 0x234FAE, "1.5-kg": 0xE2B21C, "1-kg": 0x1F8B45, "0.5-kg": 0xE8E5DF,
        "1.25-kg": 0x2A2B2F,
    ]
    private static let iwfBright: [String: UInt32] = [
        "25-kg": 0xD63A34, "20-kg": 0x2B63C9, "15-kg": 0xF0C020, "10-kg": 0x2BA552, "5-kg": 0xEFECE6,
        "2.5-kg": 0xD63A34, "2-kg": 0x2B63C9, "1.5-kg": 0xF0C020, "1-kg": 0x2BA552, "0.5-kg": 0xEFECE6,
        "1.25-kg": 0x2A2B2F,
    ]
    private static let ipf: [String: UInt32] = [
        "25-kg": 0xB3262B, "20-kg": 0x1E3F8C, "15-kg": 0xD6A50F, "10-kg": 0x196D3B, "5-kg": 0xDAD8D3,
        "2.5-kg": 0x1E1F22, "1.25-kg": 0xB9BCC0,
        "45-lb": 0x1E3F8C, "35-lb": 0xD6A50F, "25-lb": 0x196D3B, "10-lb": 0xDAD8D3, "5-lb": 0x1E1F22,
        "2.5-lb": 0xB9BCC0,
    ]
    private static let ipfGloss: [String: UInt32] = [
        "25-kg": 0xC22A2F, "20-kg": 0x2148A6, "15-kg": 0xE0AD12, "10-kg": 0x1D7A42, "5-kg": 0xE2E0DC,
        "2.5-kg": 0x202126, "1.25-kg": 0xC4C7CB,
        "45-lb": 0x2148A6, "35-lb": 0xE0AD12, "25-lb": 0x1D7A42, "10-lb": 0xE2E0DC, "5-lb": 0x202126,
        "2.5-lb": 0xC4C7CB,
    ]
    private static let echo: [String: UInt32] = [
        "55-lb": 0xC2332F, "45-lb": 0x2358B4, "35-lb": 0xE1B21A, "25-lb": 0x23964B, "10-lb": 0xE9E6E0,
        "5-lb": 0x202124, "2.5-lb": 0x202124, "1.25-lb": 0x202124,
    ]
    /// Black change plates carry no colour band; their numerals print light.
    private static let unbanded: Set<UInt32> = [0x202124, 0x2A2B2F]
    private static let darkInk: UInt32 = 0x1F2124, lightInk: UInt32 = 0xF2F1EE, tableFallback: UInt32 = 0x26272B
    private static let bandBody: UInt32 = 0x1F2023, bandFallback: UInt32 = 0x8A8D92, bandDarkInk: UInt32 = 0xD3D4D7

    private static func ids(_ unit: WeightUnit, _ values: [Double]) -> [String] {
        values.map { Plate(value: $0, unit: unit).id }
    }
    private static let kgFull = ids(.kg, [25, 20, 15, 10, 5, 2.5, 1.25])
    private static let lbBumperSet = ids(.lb, [55, 45, 35, 25, 10, 5, 2.5])
    private static let lbStandard = ids(.lb, [45, 35, 25, 10, 5, 2.5])
    private static let kgFrom20 = ids(.kg, [20, 15, 10, 5, 2.5, 1.25])

    private static func rows(_ table: [String: [Double]], _ family: String) -> [String: Row] {
        table.mapValues { Row(diameter: $0[0], thickness: $0[1], family: family) }
    }
    private static func merge(_ tables: [String: Row]...) -> [String: Row] {
        tables.reduce(into: [:]) { $0.merge($1) { _, new in new } }
    }
    private static let rubberPlates = merge(rows(iwfBumper, "bumper"), rows(iwfChange, "change"),
                                            rows(lbBumper, "bumper"), rows(lbChangeRubber, "change"))
    private static let calibratedPlates = merge(rows(ipfSteel, "ipf"), rows(lbMachined, "ipf"))
    private static let ironPlates = merge(rows(lbIron, "iron"), rows(kgIron, "iron"))
    /// Chrome change discs on the calibrated sets (1.25 kg, and 2.5 lb in pounds).
    private static let calibratedChrome = ["1.25-kg", "1.25-lb", "2.5-lb"]

    private static func build(_ id: PlateThemeID) -> PlateTheme {
        switch id {
        case .iwfCompetition:
            var t = PlateTheme(sets: [.kg: ids(.kg, [25, 20, 15, 10, 5, 2.5, 2, 1.5, 1, 0.5]), .lb: lbBumperSet],
                plates: rubberPlates, colour: .table(iwf.merging(echo) { _, new in new }),
                material: BaseMaterial(finish: .rubber, metal: 0, roughness: 0.72, changeRoughness: 0.6, photoFamily: .bumper))
            t.hubRatio = 0.5
            t.details = ["boltedHub"]
            return t
        case .iwfTraining:
            var t = PlateTheme(sets: [.kg: kgFull, .lb: lbBumperSet],
                plates: rubberPlates, colour: .table(iwfBright.merging(echo) { _, new in new }),
                material: BaseMaterial(finish: .rubber, metal: 0, roughness: 0.62, photoFamily: .bumper))
            t.hubRatio = 0.42; t.photoHubRatio = 0.42
            t.hubFinish = .blackSteel
            t.details = ["chromeBoreRing"]
            return t
        case .ipfCalibrated:
            var t = PlateTheme(sets: [.kg: kgFull, .lb: lbStandard], plates: calibratedPlates, colour: .table(ipf),
                material: BaseMaterial(finish: .powder, metal: 0.1, roughness: 0.38, photoFamily: .steel))
            t.chrome = calibratedChrome; t.chromeRoughness = 0.26
            t.hubRatio = 0.2; t.photoHubRatio = 0.2; t.rimRatio = 0.84
            t.details = ["calibrationPlugs"]
            return t
        case .ipfCalibratedGloss:
            var t = PlateTheme(sets: [.kg: kgFull, .lb: lbStandard], plates: calibratedPlates, colour: .table(ipfGloss),
                material: BaseMaterial(finish: .gloss, metal: 0.12, roughness: 0.24, photoFamily: nil))
            t.chrome = calibratedChrome; t.chromeRoughness = 0.22
            t.hubRatio = 0.2; t.photoHubRatio = 0.2; t.rimRatio = 0.84
            t.details = ["calibrationPlugs", "machinedRimRing"]
            return t
        case .lbColourBumpers:
            var t = PlateTheme(sets: [.lb: ids(.lb, [55, 45, 35, 25, 10, 5, 2.5, 1.25]), .kg: kgFull],
                plates: rubberPlates, colour: .table(echo.merging(iwf) { _, new in new }),
                material: BaseMaterial(finish: .rubber, metal: 0, roughness: 0.66, photoFamily: .bumper))
            t.hubRatio = 0.36; t.photoHubRatio = 0.36
            return t
        case .lbBlackIron:
            var t = PlateTheme(sets: [.lb: lbStandard, .kg: kgFrom20], plates: ironPlates,
                colour: .mono(fill: 0x25262A, ink: 0xD3D4D7),
                material: BaseMaterial(finish: .castIron, metal: 0.18, roughness: 0.58, photoFamily: nil))
            t.hubRatio = 0.26; t.photoHubRatio = 0.24; t.rimRatio = 0.88
            t.hubFinish = .castIron
            return t
        case .lbGreyHammertone:
            var t = PlateTheme(sets: [.lb: lbStandard, .kg: kgFrom20], plates: ironPlates,
                colour: .mono(fill: 0x6B6D72, ink: 0x1A1B1E),
                material: BaseMaterial(finish: .hammertone, metal: 0.25, roughness: 0.52, photoFamily: nil))
            t.hubRatio = 0.26; t.photoHubRatio = 0.24; t.rimRatio = 0.88
            t.hubFinish = .hammertone
            return t
        case .lbMachinedSteel:
            var t = PlateTheme(sets: [.lb: lbStandard, .kg: kgFrom20],
                plates: merge(rows(lbMachined, "machined"), rows(ipfSteel, "machined")),
                colour: .mono(fill: 0x9A9DA2, ink: 0x1A1B1E),
                material: BaseMaterial(finish: .machined, metal: 1, roughness: 0.32, photoFamily: nil))
            t.hubRatio = 0.22; t.photoHubRatio = 0.2
            return t
        case .blackBumpersBand:
            var t = PlateTheme(sets: [.kg: kgFull, .lb: lbBumperSet],
                plates: rubberPlates, colour: .band(iwf.merging(echo) { _, new in new }),
                material: BaseMaterial(finish: .rubber, metal: 0, roughness: 0.7, photoFamily: .bumper))
            t.hubRatio = 0.42; t.photoHubRatio = 0.42
            t.hubFinish = .blackSteel
            t.details = ["colourBand", "chromeBoreRing"]
            return t
        case .cadenceHouse:
            var t = PlateTheme(sets: [.kg: kgFull, .lb: lbBumperSet],
                plates: rubberPlates, colour: .mono(fill: 0x2A2C30, ink: 0xE0413C),
                material: BaseMaterial(finish: .rubber, metal: 0, roughness: 0.68, photoFamily: .bumper))
            t.hubRatio = 0.46; t.photoHubRatio = 0.46
            t.barFinish = .blackOxide
            t.backdrop = 0x101114
            t.details = ["hubRing"]
            return t
        case .custom:
            return PlateTheme(sets: [.kg: Plate.standardKg.map(\.id), .lb: Plate.standardLb.map(\.id)],
                plates: [:], colour: nil, material: nil)
        }
    }

    private static let all: [PlateThemeID: PlateTheme] =
        Dictionary(uniqueKeysWithValues: PlateThemeID.allCases.map { ($0, build($0)) })

    public static func description(_ theme: PlateThemeID) -> PlateTheme { all[theme]! }

    /// Label ink by sRGB luminance of the fill: dark on light plates, light on dark.
    public static func ink(for fill: UInt32) -> UInt32 {
        let r = Double(fill >> 16), g = Double((fill >> 8) & 255), b = Double(fill & 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 150 ? darkInk : lightInk
    }

    /// The theme's plate list for a unit, heaviest first. custom = today's standard set.
    public static func set(for unit: WeightUnit, theme: PlateThemeID = .custom) -> [Plate] {
        (description(theme).sets[unit] ?? []).compactMap { id in
            Double(id.split(separator: "-")[0]).map { Plate(value: $0, unit: unit) }
        }
    }

    /// Real dimensions (mm). A plate outside the theme's tables keeps today's style profile.
    public static func geometry(_ plate: Plate, theme: PlateThemeID = .custom,
                                style: PlateVisualStyle = .steel) -> PlateGeometry {
        guard let row = description(theme).plates[plate.id] else {
            return PlateGeometry.reference(plate, style: style)
        }
        return PlateGeometry(diameter: row.diameter, thickness: row.thickness)
    }

    /// "bumper" | "steel" | "change" (custom), "ipf" | "iron" | "machined" (themes).
    public static func family(_ plate: Plate, theme: PlateThemeID = .custom,
                              style: PlateVisualStyle = .steel) -> String {
        description(theme).plates[plate.id]?.family ?? PlateGeometry.family(plate, style: style)
    }

    public static func colour(_ plate: Plate, theme: PlateThemeID = .custom,
                              style: PlateVisualStyle = .bumper) -> PlateColour {
        switch description(theme).colourRule {
        case nil:
            return PlatePalette.colour(for: plate.colorToken(for: style))
        case .mono(let fill, let ink):
            return PlateColour(fill: fill, edge: fill, ink: ink)
        case .table(let table):
            let fill = table[plate.id] ?? tableFallback
            return PlateColour(fill: fill, edge: fill, ink: ink(for: fill))
        case .band(let table):
            let edge = table[plate.id] ?? bandFallback
            return PlateColour(fill: bandBody, edge: edge, ink: unbanded.contains(edge) ? bandDarkInk : edge)
        }
    }

    /// The rim colour band, or nil where the theme has none for this plate.
    public static func band(_ plate: Plate, theme: PlateThemeID = .custom) -> UInt32? {
        guard case .band(let table) = description(theme).colourRule,
              let band = table[plate.id], !unbanded.contains(band) else { return nil }
        return band
    }

    public static func material(_ plate: Plate, theme: PlateThemeID = .custom,
                                style: PlateVisualStyle = .steel) -> PlateMaterial {
        let t = description(theme)
        let kind = family(plate, theme: theme, style: style)
        guard let base = t.baseMaterial else {
            return kind == "bumper"
                ? PlateMaterial(finish: .rubber, metal: 0, roughness: 0.68, photoFamily: style)
                : PlateMaterial(finish: .powder, metal: 0.08, roughness: 0.36, photoFamily: style)
        }
        if t.chrome.contains(plate.id) {
            return PlateMaterial(finish: .machined, metal: 1, roughness: t.chromeRoughness, photoFamily: base.photoFamily)
        }
        let roughness = kind != "bumper" ? base.changeRoughness ?? base.roughness : base.roughness
        return PlateMaterial(finish: base.finish, metal: base.metal, roughness: roughness, photoFamily: base.photoFamily)
    }

    /// Family defaults when the theme is silent.
    public static func ratios(_ plate: Plate, theme: PlateThemeID = .custom,
                              style: PlateVisualStyle = .steel) -> PlateRatios {
        let t = description(theme)
        let kind = family(plate, theme: theme, style: style)
        let familyHub = kind == "bumper" ? 0.57 : 0.245
        return PlateRatios(hub: t.hubRatio ?? familyHub, photoHub: t.photoHubRatio ?? familyHub,
                           rim: t.rimRatio ?? (kind == "bumper" ? 0.9 : ["steel", "ipf", "machined"].contains(kind) ? 0.86 : 1))
    }
}
