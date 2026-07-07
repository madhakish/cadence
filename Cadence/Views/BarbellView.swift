import SwiftUI
import CadenceCore

/// Compact one-side barbell graphic: the actual loaded plates for a weight at
/// a station, coloured to the plate scheme — heaviest plate inboard. Mirrors
/// web/js/barbell.js (same geometry and hex palette). `unit` picks the plate
/// denominations; the bar is chosen separately (most bars are 45 lb whichever
/// plates you load).
struct BarbellView: View {
    let weightLb: Double
    let unit: WeightUnit
    let bar: Bar
    let gym: Gym?

    private static let fill: [String: Color] = [
        "red": Color(rgb: 0xD23B3B), "blue": Color(rgb: 0x2F6FED), "green": Color(rgb: 0x1FAA52),
        "yellow": Color(rgb: 0xE8B008), "white": Color(rgb: 0xEDEDED), "black": Color(rgb: 0x1C1D22),
    ]
    private static let stroke: [String: Color] = [
        "red": Color(rgb: 0x7A1F1F), "blue": Color(rgb: 0x1B3F8F), "green": Color(rgb: 0x10632F),
        "yellow": Color(rgb: 0x8A6A04), "white": Color(rgb: 0x9A9A9A), "black": Color(rgb: 0x3A3B42),
    ]

    // Geometry shared with the web SVG.
    private static let height: CGFloat = 30
    private static let plateW: CGFloat = 7
    private static let gap: CGFloat = 1.5
    private static let sleeve: CGFloat = 18

    /// The plate denominations of the chosen unit that exist at this gym
    /// (mirrors web `stationPlates`).
    private var stationPlates: [Plate] {
        var list = gym?.availablePlates ?? Plate.allStandard
        list = list.filter { $0.unit == unit }
        if list.isEmpty { list = unit == .kg ? Plate.standardKg : Plate.standardLb }
        return list
    }

    var body: some View {
        let solution = PlateMath.solve(targetLb: weightLb, bar: bar, plates: stationPlates)
        let plates = solution.loadout.perSide.flatMap { Array(repeating: $0.plate, count: $0.count) }
        let width = max(46, Self.sleeve + 6 + CGFloat(plates.count) * (Self.plateW + Self.gap) + 4)

        VStack(alignment: .leading, spacing: 2) {
            Canvas { ctx, _ in
                let h = Self.height
                // bar shaft + sleeve face
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: h / 2 - 1.5, width: Self.sleeve + 4, height: 3), cornerRadius: 1.5),
                         with: .color(Color(rgb: 0x9AA0AA)))
                ctx.fill(Path(roundedRect: CGRect(x: Self.sleeve, y: h / 2 - 6, width: 3, height: 12), cornerRadius: 1),
                         with: .color(Color(rgb: 0x7C828C)))

                var x = Self.sleeve + 5
                for plate in plates {
                    let tok = plate.colorToken
                    let ph = (h - 4) * CGFloat(plate.sizeFactor)
                    let rect = Path(roundedRect: CGRect(x: x, y: (h - ph) / 2, width: Self.plateW, height: ph), cornerRadius: 1.5)
                    ctx.fill(rect, with: .color(Self.fill[tok] ?? Color(rgb: 0x888888)))
                    ctx.stroke(rect, with: .color(Self.stroke[tok] ?? .black.opacity(0.3)), lineWidth: 0.75)
                    x += Self.plateW + Self.gap
                }
                if plates.isEmpty {
                    ctx.draw(Text("bar only").font(.system(size: 10)).foregroundStyle(.secondary),
                             at: CGPoint(x: Self.sleeve + 7, y: h / 2), anchor: .leading)
                }
            }
            .frame(width: width, height: Self.height)

            if solution.isOffTarget {
                let total = unit == .kg ? Weight.kg(fromLb: solution.loadout.totalLb) : solution.loadout.totalLb
                Text("≈ closest \(Weight.trim(total)) \(unit.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
            }
        }
        .accessibilityLabel("Barbell: \(solution.loadout.perSideLabel) per side on \(bar.label)")
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
