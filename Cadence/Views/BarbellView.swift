import SwiftUI
import CadenceCore

/// Compact one-side barbell graphic: the actual loaded plates for a weight at
/// a station, coloured to the plate scheme — heaviest plate inboard. Mirrors
/// web/app/js/barbell.js (same geometry and hex palette). `unit` picks the plate
/// denominations; the bar is chosen separately (most bars are 45 lb whichever
/// plates you load).
struct BarbellView: View {
    enum Presentation: Equatable {
        case compactSide
        case fullBar
    }

    let weightLb: Double
    let unit: WeightUnit
    let bar: Bar
    let gym: Gym?
    /// The unsnapped programming target. When it differs from `weightLb`, the
    /// view explains the selected rack load and both directional alternatives.
    var targetWeightLb: Double? = nil
    /// Draw THIS loadout instead of re-solving — the plate calculator's hero
    /// must match its own answer (which may span both unit systems), and
    /// reverse mode must draw exactly what the user says is on the bar.
    var loadout: Loadout? = nil
    /// The lift's station plate denomination (v8): the deadlift platform by
    /// the window stocks only kg plates. nil = the gym inventory.
    var stationDenomination: WeightUnit? = nil
    /// Compact set rows need one side only. The calculator has room to show
    /// the complete, mirrored bar so the loading answer cannot be mistaken for
    /// a count across both sides.
    var presentation: Presentation = .compactSide

    private static let fill: [String: Color] = [
        "red": Color(hex: 0xD23B3B), "blue": Color(hex: 0x2F6FED), "green": Color(hex: 0x1FAA52),
        "yellow": Color(hex: 0xE8B008), "white": Color(hex: 0xEDEDED), "black": Color(hex: 0x1C1D22),
    ]
    private static let stroke: [String: Color] = [
        "red": Color(hex: 0x7A1F1F), "blue": Color(hex: 0x1B3F8F), "green": Color(hex: 0x10632F),
        "yellow": Color(hex: 0x8A6A04), "white": Color(hex: 0x9A9A9A), "black": Color(hex: 0x3A3B42),
    ]

    // Geometry shared with the web SVG.
    private static let height: CGFloat = 30
    private static let plateW: CGFloat = 7
    private static let gap: CGFloat = 1.5
    private static let sleeve: CGFloat = 18

    /// Every enabled denomination at this gym. `unit` is only the fallback
    /// rack when no gym exists; a configured mixed rack must draw the same
    /// achieved load the prescription solver stored. `Gym.availablePlates`
    /// also repairs legacy empty inventories without erasing an intentional
    /// nonempty/all-disabled bar-only rack.
    private var stationPlates: [Plate] {
        // The lift's station preference filters the rack to its own
        // denomination — applied to the no-gym fallback too, matching web:
        // a kg-only station stays kg even before any gym is configured.
        let rack = gym?.availablePlates
            ?? (unit == .kg ? Plate.standardKg : Plate.standardLb)
        return PlateMath.stationPlates(preference: stationDenomination, gymPlates: rack)
    }

    var body: some View {
        let solution = loadout.map { PlateSolution(loadout: $0, targetLb: weightLb) }
            ?? PlateMath.solve(targetLb: weightLb, bar: bar, plates: stationPlates,
                               collarLb: gym?.collarWeightLb ?? 0,
                               policy: gym?.loadingPolicy ?? .closest)
        let plates = solution.loadout.perSide.flatMap { Array(repeating: $0.plate, count: $0.count) }
        let width = max(46, Self.sleeve + 6 + CGFloat(plates.count) * (Self.plateW + Self.gap) + 4)
        let theoreticalTarget = targetWeightLb ?? weightLb
        let alternatives = PlateMath.prescriptionOptions(
            targetLb: theoreticalTarget, bar: bar, plates: stationPlates,
            collarLb: gym?.collarWeightLb ?? 0, policy: gym?.loadingPolicy ?? .closest
        )
        let shown: (Double) -> String = { lb in
            let value = unit == .kg ? Weight.kg(fromLb: lb) : lb
            return "\(Weight.trim(value)) \(unit.rawValue)"
        }

        VStack(alignment: .leading, spacing: 2) {
            Canvas { ctx, size in
                let h = presentation == .fullBar ? size.height : Self.height
                if presentation == .fullBar {
                    let width = max(240, size.width)
                    let midY = h / 2
                    let shoulder = min(82, max(62, width * 0.24))
                    let rightShoulder = width - shoulder
                    let shaft = Path(roundedRect: CGRect(x: 8, y: midY - 2, width: width - 16, height: 4), cornerRadius: 2)
                    let leftSleeve = Path(roundedRect: CGRect(x: 8, y: midY - 3, width: shoulder - 8, height: 6), cornerRadius: 3)
                    let rightSleeve = Path(roundedRect: CGRect(x: rightShoulder, y: midY - 3,
                                                              width: shoulder - 8, height: 6), cornerRadius: 3)
                    let steel = Gradient(colors: [Color(hex: 0x5D626A), Color(hex: 0xD5D8DC), Color(hex: 0x747A83)])
                    ctx.fill(Path(roundedRect: CGRect(x: 9, y: midY + 3, width: width - 18, height: 5), cornerRadius: 2.5),
                             with: .color(.black.opacity(0.12)))
                    ctx.fill(shaft, with: .linearGradient(steel,
                                                         startPoint: CGPoint(x: 0, y: midY - 2),
                                                         endPoint: CGPoint(x: 0, y: midY + 2)))
                    ctx.fill(leftSleeve, with: .linearGradient(steel,
                                                               startPoint: CGPoint(x: 0, y: midY - 3),
                                                               endPoint: CGPoint(x: 0, y: midY + 3)))
                    ctx.fill(rightSleeve, with: .linearGradient(steel,
                                                                startPoint: CGPoint(x: 0, y: midY - 3),
                                                                endPoint: CGPoint(x: 0, y: midY + 3)))
                    let leftCollar = Path(roundedRect: CGRect(x: shoulder - 3, y: midY - 11, width: 6, height: 22), cornerRadius: 2)
                    let rightCollar = Path(roundedRect: CGRect(x: rightShoulder - 3, y: midY - 11, width: 6, height: 22), cornerRadius: 2)
                    ctx.fill(leftCollar, with: .linearGradient(steel,
                                                               startPoint: CGPoint(x: 0, y: midY - 11),
                                                               endPoint: CGPoint(x: 0, y: midY + 11)))
                    ctx.fill(rightCollar, with: .linearGradient(steel,
                                                                startPoint: CGPoint(x: 0, y: midY - 11),
                                                                endPoint: CGPoint(x: 0, y: midY + 11)))

                    for x in stride(from: shoulder + 14, through: rightShoulder - 14, by: 7) {
                        var knurl = Path()
                        knurl.move(to: CGPoint(x: x, y: midY - 1.7))
                        knurl.addLine(to: CGPoint(x: x + 1.8, y: midY + 1.7))
                        ctx.stroke(knurl, with: .color(.black.opacity(0.25)), lineWidth: 0.45)
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: 5, y: midY - 3, width: 6, height: 6)),
                             with: .color(Color(hex: 0x6C727A)))
                    ctx.fill(Path(ellipseIn: CGRect(x: width - 11, y: midY - 3, width: 6, height: 6)),
                             with: .color(Color(hex: 0x6C727A)))

                    let available = max(30, shoulder - 16)
                    let nominal = CGFloat(plates.count) * (Self.plateW + Self.gap)
                    let scale = nominal > 0 ? min(1, available / nominal) : 1
                    let plateWidth = max(3.5, Self.plateW * scale)
                    let gap = max(0.8, Self.gap * scale)
                    var leftX = shoulder - 6 - plateWidth
                    var rightX = rightShoulder + 6
                    for plate in plates {
                        let tok = plate.colorToken
                        let plateHeight = (h - 12) * CGFloat(plate.sizeFactor)
                        let left = Path(roundedRect: CGRect(x: leftX, y: (h - plateHeight) / 2,
                                                           width: plateWidth, height: plateHeight), cornerRadius: 2.4)
                        let right = Path(roundedRect: CGRect(x: rightX, y: (h - plateHeight) / 2,
                                                            width: plateWidth, height: plateHeight), cornerRadius: 2.4)
                        let fill = Self.fill[tok] ?? Color(hex: 0x888888)
                        let stroke = Self.stroke[tok] ?? .black.opacity(0.3)
                        ctx.fill(left, with: .color(fill)); ctx.stroke(left, with: .color(stroke), lineWidth: 0.75)
                        ctx.fill(right, with: .color(fill)); ctx.stroke(right, with: .color(stroke), lineWidth: 0.75)
                        for rect in [left.boundingRect, right.boundingRect] {
                            var shine = Path()
                            shine.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 1.2))
                            shine.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 1.2))
                            ctx.stroke(shine, with: .color(.white.opacity(0.28)), lineWidth: 0.65)
                        }
                        leftX -= plateWidth + gap
                        rightX += plateWidth + gap
                    }
                    if plates.isEmpty {
                        ctx.draw(Text("bar only").font(.system(size: 10)).foregroundStyle(.secondary),
                                 at: CGPoint(x: width / 2, y: midY - 9), anchor: .center)
                    }
                } else {
                    // bar shaft + sleeve face
                    ctx.fill(Path(roundedRect: CGRect(x: 0, y: h / 2 - 1.5, width: Self.sleeve + 4, height: 3), cornerRadius: 1.5),
                             with: .color(Color(hex: 0x9AA0AA)))
                    ctx.fill(Path(roundedRect: CGRect(x: Self.sleeve, y: h / 2 - 6, width: 3, height: 12), cornerRadius: 1),
                             with: .color(Color(hex: 0x7C828C)))

                    var x = Self.sleeve + 5
                    for plate in plates {
                        let tok = plate.colorToken
                        let ph = (h - 4) * CGFloat(plate.sizeFactor)
                        let rect = Path(roundedRect: CGRect(x: x, y: (h - ph) / 2, width: Self.plateW, height: ph), cornerRadius: 1.5)
                        ctx.fill(rect, with: .color(Self.fill[tok] ?? Color(hex: 0x888888)))
                        ctx.stroke(rect, with: .color(Self.stroke[tok] ?? .black.opacity(0.3)), lineWidth: 0.75)
                        x += Self.plateW + Self.gap
                    }
                    if plates.isEmpty {
                        ctx.draw(Text("bar only").font(.system(size: 10)).foregroundStyle(.secondary),
                                 at: CGPoint(x: Self.sleeve + 7, y: h / 2), anchor: .leading)
                    }
                }
            }
            .frame(width: presentation == .compactSide ? width : nil,
                   height: presentation == .compactSide ? Self.height : 78)
            .frame(maxWidth: presentation == .fullBar ? .infinity : nil)

            if solution.isOffTarget {
                let total = unit == .kg ? Weight.kg(fromLb: solution.loadout.totalLb) : solution.loadout.totalLb
                Text("≈ closest \(Weight.trim(total)) \(unit.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
            } else if !solution.satisfiesPolicy {
                Text("closest available · policy not exact")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
            }
            if abs(theoreticalTarget - solution.loadout.totalLb) > 0.01 {
                Text("Target \(shown(theoreticalTarget)) · load \(shown(solution.loadout.totalLb))")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.warn)
                if let below = alternatives.below {
                    Text("Below \(shown(below.loadout.totalLb)) · \(below.loadout.perSideLabel)/side")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let above = alternatives.above,
                   alternatives.below == nil
                    || abs(above.loadout.totalLb - (alternatives.below?.loadout.totalLb ?? 0)) > 0.01 {
                    Text("Above \(shown(above.loadout.totalLb)) · \(above.loadout.perSideLabel)/side")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel("Barbell: \(solution.loadout.perSideLabel) per side on \(bar.label)\(solution.loadout.collarLb > 0 ? ", including collars" : "")")
    }
}
// Plate colours use the shared Color(hex:) from Theme.swift.
