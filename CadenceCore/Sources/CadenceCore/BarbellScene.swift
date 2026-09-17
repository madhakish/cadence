import Foundation

/// Photographic face channel gains, mirrored by plateTintGains on web.
/// The renderer applies these only to the face, then restores the metal hub.
public struct PlateFaceTint: Equatable, Sendable {
    public let red, green, blue: Double

    public init(token: String) {
        let colors = ["red": 0xD23B3B, "blue": 0x2F6FED, "green": 0x1FAA52,
                      "yellow": 0xE8B008, "white": 0xEDEDED]
        if let hex = colors[token] {
            red = Double((hex >> 16) & 255) / 255 * 3.2
            green = Double((hex >> 8) & 255) / 255 * 3.2
            blue = Double(hex & 255) / 255 * 3.2
        } else {
            red = 1; green = 1; blue = 1
        }
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

    public static func reference(_ plate: Plate, style: PlateVisualStyle) -> PlateGeometry {
        let bumper: [String: [Double]] = [
            "25-kg": [450, 70], "20-kg": [450, 60], "15-kg": [450, 48],
            "10-kg": [450, 35], "5-kg": [450, 25],
            "55-lb": [450, 75], "45-lb": [450, 65], "35-lb": [450, 52],
            "25-lb": [450, 40], "10-lb": [450, 25],
        ]
        let steel: [String: [Double]] = [
            "25-kg": [450, 27], "20-kg": [450, 22], "15-kg": [400, 21],
            "10-kg": [325, 20], "5-kg": [230, 20],
            "55-lb": [450, 30], "45-lb": [450, 27], "35-lb": [400, 25],
            "25-lb": [325, 23], "10-lb": [230, 20],
        ]
        let change: [String: [Double]] = [
            "2.5-kg": [210, 19], "2-kg": [190, 19], "1.5-kg": [175, 18],
            "1.25-kg": [160, 16], "1-kg": [160, 16], "0.5-kg": [135, 12],
            "5-lb": [190, 19], "2.5-lb": [160, 16], "1.25-lb": [135, 12],
        ]
        let dimensions = (style == .bumper ? bumper : steel)[plate.id]
            ?? change[plate.id] ?? [200, 20]
        return PlateGeometry(diameter: dimensions[0], thickness: dimensions[1])
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
