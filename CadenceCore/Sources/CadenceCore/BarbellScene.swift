import Foundation

/// Photographic face colourisation, mirrored by `plateTintMatrix` on web: a
/// 5×4 colour matrix (row-major R, G, B, A rows of five) that rebuilds every
/// channel from the texture's luminance. The plate keeps its photographed
/// shading — rim shadow, rubber grain, machining — and takes its hue from the
/// palette fill, instead of the earlier per-channel gains that clamped the
/// dark textures into one flat colour. The renderer applies it only to the
/// face, then restores the metal hub.
public struct PlateFaceTint: Equatable, Sendable {
    public let matrix: [Double]

    public static let identity: [Double] = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
    /// Median face luminance of each rendered sprite family (measured on the
    /// shipped PNGs, hub excluded). The lift maps it to 85% of the fill so
    /// the brighter 15% of texels keep headroom before clamping.
    public static func lift(for style: PlateVisualStyle) -> Double {
        0.85 / (style == .bumper ? 0.451 : 0.449)
    }
    /// Fraction of the lift mixed in as grey: highlights whiten instead of
    /// saturating to a single hue.
    public static let greyMix = 0.12

    /// Black iron is the untinted texture; every other token colourises the
    /// face from the palette fill.
    public init(token: String, style: PlateVisualStyle) {
        guard token != "black", let hex = PlatePalette.colours[token]?.fill else {
            matrix = PlateFaceTint.identity
            return
        }
        let fill = [Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255]
        let lift = PlateFaceTint.lift(for: style)
        let grey = lift * PlateFaceTint.greyMix
        let luma = [0.2126, 0.7152, 0.0722]
        var rows: [Double] = []
        for channel in fill {
            let weight = channel * lift + (1 - channel) * grey
            rows += luma.map { $0 * weight } + [0, 0]
        }
        rows += [0, 0, 0, 1, 0]
        matrix = rows
    }

    /// The colour a neutral texel of luminance `l` becomes: (r, g, b), clamped.
    public func apply(luminance l: Double) -> [Double] {
        [0, 5, 10].map { min(1, matrix[$0] * l + matrix[$0 + 1] * l + matrix[$0 + 2] * l) }
    }
}

/// Presentation-only equipment dimensions. These reference profiles do not
/// change a Plate's identity, inventory, recorded mass, or backup encoding.
/// An explicit 5 kg training bumper is full size; a change disc is a different
/// physical profile, never a camera-dependent inference from its weight.
public struct PlateGeometry: Equatable, Sendable {
    public let diameter: Double
    public let thickness: Double

    public init(diameter: Double, thickness: Double) {
        self.diameter = diameter
        self.thickness = thickness
    }

    private static let bumperTable: [String: [Double]] = [
        "25-kg": [450, 70], "20-kg": [450, 60], "15-kg": [450, 48],
        "10-kg": [450, 35], "5-kg": [450, 25],
        "55-lb": [450, 75], "45-lb": [450, 65], "35-lb": [450, 52],
        "25-lb": [450, 40], "10-lb": [450, 25],
    ]
    private static let steelTable: [String: [Double]] = [
        "25-kg": [450, 27], "20-kg": [450, 22], "15-kg": [400, 21],
        "10-kg": [325, 20], "5-kg": [230, 20],
        "55-lb": [450, 30], "45-lb": [450, 27], "35-lb": [400, 25],
        "25-lb": [325, 23], "10-lb": [230, 20],
    ]
    private static let changeTable: [String: [Double]] = [
        "2.5-kg": [210, 19], "2-kg": [190, 19], "1.5-kg": [175, 18],
        "1.25-kg": [160, 16], "1-kg": [160, 16], "0.5-kg": [135, 12],
        "5-lb": [190, 19], "2.5-lb": [160, 16], "1.25-lb": [135, 12],
    ]

    public static func reference(_ plate: Plate, style: PlateVisualStyle) -> PlateGeometry {
        let dimensions = (style == .bumper ? bumperTable : steelTable)[plate.id]
            ?? changeTable[plate.id] ?? [200, 20]
        return PlateGeometry(diameter: dimensions[0], thickness: dimensions[1])
    }

    /// The physical family a denomination belongs to in a style — a full-size
    /// bumper, a calibrated steel disc, or a change plate. It names the cell
    /// in the loadout summary and never changes geometry or mass. Mirrors
    /// web `plateFamily`.
    public static func family(_ plate: Plate, style: PlateVisualStyle) -> String {
        if style == .bumper, bumperTable[plate.id] != nil { return "bumper" }
        if steelTable[plate.id] != nil { return "steel" }
        return "change"
    }

    /// "Bumpers" / "Steel" / "Change" — the cell's second line.
    public static func familyLabel(_ family: String) -> String {
        switch family {
        case "bumper": return "Bumpers"
        case "steel": return "Steel"
        default: return "Change"
        }
    }
}

/// Orthographic scene shared with web barbell-scene.js. Order is the caller's
/// collar-outward order, including deliberately unsorted reverse-mode stacks.
/// Projection affects positions only. Dimensions and mass never change.
public struct BarbellScene: Sendable {
    public struct Disc: Sendable {
        public let plate: Plate
        public let side: Int
        public let index: Int
        public let x: Double
        public let y: Double
        public let radius: Double
        public let faceRadius: Double
        public let depth: Double

        /// The one spoken name for a plate on the bar, on both clients:
        /// "20 kg plate, 1 from inside, left side". Mirrors web
        /// `discAccessibilityLabel`.
        public var accessibilityLabel: String {
            "\(plate.label) plate, \(index + 1) from inside, \(side < 0 ? "left" : "right") side"
        }
    }

    public let discs: [Disc]
    public let width: Double
    public let height: Double
    public let shoulder: Double
    public let end: Double
    public let collar: Double
    public let axisX: Double
    public let axisY: Double
    public let faceScale: Double

    public init(loadout: Loadout, style: PlateVisualStyle, exploded: Bool,
                geometry: [String: PlateGeometry] = [:]) {
        let angle = (exploded ? 38.0 : 18.0) * Double.pi / 180
        axisX = cos(angle)
        axisY = -sin(angle) * 0.24
        faceScale = sin(angle)
        shoulder = loadout.bar == .bar15kg || loadout.bar == .bar35lb ? 145 : 165
        let plates = loadout.perSide.flatMap { Array(repeating: $0.plate, count: max(0, $0.count)) }
        var cursor = shoulder + 8.0
        var previousFaceRadius = 0.0
        var pending: [Disc] = []
        for (index, plate) in plates.enumerated() {
            let shape = geometry[plate.id] ?? PlateGeometry.reference(plate, style: style)
            let radius = max(1, shape.diameter) * 0.18
            let depth = max(1, shape.thickness) * 0.36
            let faceRadius = radius * faceScale
            // Reserve both adjacent projected faces, including a large disc
            // followed by a small change plate. Neither can hide the other.
            if exploded { cursor += (previousFaceRadius + faceRadius + 22) / axisX }
            for side in [-1, 1] {
                let center = Double(side) * (cursor + depth / 2)
                pending.append(Disc(plate: plate, side: side, index: index,
                    x: center * axisX, y: center * axisY, radius: radius,
                    faceRadius: faceRadius, depth: depth * axisX))
            }
            cursor += depth + (exploded ? 0 : 2)
            previousFaceRadius = faceRadius
        }
        collar = cursor + 8
        end = max(shoulder + 150, collar + 28)
        width = max(end * axisX + 25,
            pending.map { abs($0.x) + $0.faceRadius + $0.depth }.max() ?? 0) * 2 + 24
        height = max(110, pending.map { abs($0.y) + $0.radius }.max() ?? 0) * 2 + 40
        // Back-to-front paint order. Stack index remains stable for labels.
        discs = pending.sorted { $0.x < $1.x }
    }
}
