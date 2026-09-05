import SwiftUI
import CadenceCore

/// One rack-resolution path for every native plate surface. Views may pass a
/// previously chosen `Loadout`, but whenever a target still needs solving it
/// comes through this function so station units, mixed inventory, collars and
/// loading policy cannot drift between the calculator, logger and lift pane.
func authoritativePlateSolution(
    targetLb: Double,
    fallbackUnit: WeightUnit,
    bar: Bar,
    gym: Gym?,
    stationDenomination: WeightUnit? = nil
) -> PlateSolution {
    let fallback = fallbackUnit == .kg ? Plate.standardKg : Plate.standardLb
    let rack = PlateMath.stationPlates(
        preference: stationDenomination,
        gymPlates: gym?.availablePlates ?? fallback
    )
    return PlateMath.solve(
        targetLb: targetLb,
        bar: bar,
        plates: rack,
        collarLb: gym?.collarWeightLb ?? 0,
        policy: gym?.loadingPolicy ?? .closest
    )
}

private enum PlatePalette {
    static let fill: [String: Color] = [
        "red": Color(hex: 0xD23B3B), "blue": Color(hex: 0x2F6FED), "green": Color(hex: 0x1FAA52),
        "yellow": Color(hex: 0xE8B008), "white": Color(hex: 0xEDEDED), "black": Color(hex: 0x1C1D22),
    ]
    static let stroke: [String: Color] = [
        "red": Color(hex: 0x7A1F1F), "blue": Color(hex: 0x1B3F8F), "green": Color(hex: 0x10632F),
        "yellow": Color(hex: 0x8A6A04), "white": Color(hex: 0x9A9A9A), "black": Color(hex: 0x3A3B42),
    ]

    static func labelColor(for token: String) -> Color {
        token == "white" || token == "yellow" ? Color(hex: 0x24262A) : .white
    }
}

/// A readable, face-on denomination key for a plate in the calculator. The
/// bar graphic stays an honest edge-on load-order diagram; this companion
/// view owns the large number that an edge-on plate cannot physically carry.
struct PlateFaceBadge: View {
    let plate: Plate
    let style: PlateVisualStyle

    private var token: String { plate.colorToken(for: style) }

    var body: some View {
        let foreground = PlatePalette.labelColor(for: token)
        ZStack {
            Circle()
                .fill(PlatePalette.fill[token] ?? Color(hex: 0x888888))
            Circle()
                .stroke(PlatePalette.stroke[token] ?? .black.opacity(0.3), lineWidth: 2)
            Circle()
                .stroke(foreground.opacity(0.34), lineWidth: 1)
                .padding(7)
            VStack(spacing: -2) {
                Text(Weight.trim(plate.value, decimals: 2))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                Text(plate.unit.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundStyle(foreground)
        }
        .frame(width: 52, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plate.label) plate")
    }
}

/// The actual loaded bar: collar-first mirrored stacks, competition colours,
/// reflective steel, and distinct bumper/calibrated-steel geometry. Mirrors
/// web/app/js/barbell.js. `unit` picks denominations; `plateStyle` picks the
/// physical plate family.
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
    /// Olympic lifts use full-diameter rubber bumpers; strength work and the
    /// calculator default to thinner, stepped calibrated steel.
    var plateStyle: PlateVisualStyle = .steel
    /// Compact set rows need one side only. The calculator has room to show
    /// the complete, mirrored bar so the loading answer cannot be mistaken for
    /// a count across both sides.
    var presentation: Presentation = .compactSide

    // Geometry shared with the web SVG.
    private static let height: CGFloat = 46
    private static let fullHeight: CGFloat = 124
    private static let sleeve: CGFloat = 18

    private func drawnPlateWidth(_ plate: Plate, scale: CGFloat = 1) -> CGFloat {
        let factor = CGFloat(plate.thicknessFactor(for: plateStyle))
        let base = plateStyle == .bumper ? 4.5 + 8.5 * factor : 3.2 + 5 * factor
        return max(plateStyle == .bumper ? 4.2 : 3.1, base * scale)
    }

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
            ?? authoritativePlateSolution(
                targetLb: weightLb,
                fallbackUnit: unit,
                bar: bar,
                gym: gym,
                stationDenomination: stationDenomination
            )
        let plates = solution.loadout.perSide.flatMap { Array(repeating: $0.plate, count: $0.count) }
        let compactGap: CGFloat = plateStyle == .bumper ? 1 : 0.7
        let compactWidths = plates.map { drawnPlateWidth($0, scale: 0.72) }
        let compactStackWidth = compactWidths.reduce(0, +) + CGFloat(max(0, plates.count - 1)) * compactGap
        let emptyWidth: CGFloat = solution.loadout.collarLb > 0 ? 96 : 74
        let width = max(plates.isEmpty ? emptyWidth : 50, Self.sleeve + 11 + compactStackWidth)
        let theoreticalTarget = targetWeightLb ?? weightLb
        let alternatives = PlateMath.prescriptionOptions(
            targetLb: theoreticalTarget, bar: bar, plates: stationPlates,
            collarLb: gym?.collarWeightLb ?? 0, policy: gym?.loadingPolicy ?? .closest
        )
        let shown: (Double) -> String = { lb in
            let value = unit == .kg ? Weight.kg(fromLb: lb) : lb
            return "\(Weight.trim(value)) \(unit.rawValue)"
        }
        let accessibilityLoad = plates.isEmpty
            ? (solution.loadout.collarLb > 0
               ? "\(bar.label) with collars, no plates"
               : "\(bar.label), bar only")
            : "\(solution.loadout.perSideLabel) per side on \(bar.label)\(solution.loadout.collarLb > 0 ? ", including collars" : "")"

        VStack(alignment: .leading, spacing: 2) {
            Canvas { ctx, size in
                let h = presentation == .fullBar ? size.height : Self.height
                func drawPlate(_ plate: Plate, rect: CGRect, side: String) {
                    let token = plate.colorToken(for: plateStyle)
                    let fill = PlatePalette.fill[token] ?? Color(hex: 0x888888)
                    let stroke = PlatePalette.stroke[token] ?? .black.opacity(0.3)
                    let radius: CGFloat = plateStyle == .bumper ? 2.4 : 1.2
                    let shadow = Path(roundedRect: rect.offsetBy(dx: 1, dy: 2), cornerRadius: radius)
                    ctx.fill(shadow, with: .color(.black.opacity(0.16)))
                    let body = Path(roundedRect: rect, cornerRadius: radius)
                    ctx.fill(body, with: .linearGradient(
                        Gradient(colors: [stroke, fill, fill, stroke]),
                        startPoint: CGPoint(x: rect.minX, y: rect.midY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                    ))
                    ctx.stroke(body, with: .color(stroke), lineWidth: 0.65)

                    let inset = min(2.2, rect.width * 0.32)
                    let faceX = side == "left" ? rect.minX + inset : rect.maxX - inset
                    let faceRX = min(2.5, max(1.05, rect.width * 0.32))
                    let faceRY = max(2, rect.height / 2 - 1.4)
                    let faceRect = CGRect(x: faceX - faceRX, y: rect.midY - faceRY,
                                          width: faceRX * 2, height: faceRY * 2)
                    let face = Path(ellipseIn: faceRect)
                    ctx.fill(face, with: .color(fill)); ctx.stroke(face, with: .color(stroke), lineWidth: 0.65)
                    let ringRY = plateStyle == .bumper ? max(2, faceRY - 1.4) : max(2, rect.height * 0.31)
                    let ring = Path(ellipseIn: CGRect(x: faceX - max(0.75, faceRX * 0.74),
                                                      y: rect.midY - ringRY,
                                                      width: max(1.5, faceRX * 1.48), height: ringRY * 2))
                    let ringColor: Color = token == "white" || token == "yellow" ? .black.opacity(0.35) : .white.opacity(0.34)
                    ctx.stroke(ring, with: .color(ringColor), lineWidth: 0.5)
                    let hubRX = max(0.75, faceRX * 0.62)
                    let hubRY = max(2.2, min(4.8, rect.height * 0.1))
                    let hub = Path(ellipseIn: CGRect(x: faceX - hubRX, y: rect.midY - hubRY,
                                                     width: hubRX * 2, height: hubRY * 2))
                    let steel = Gradient(colors: [Color(hex: 0x5D626A), Color(hex: 0xD5D8DC), Color(hex: 0x747A83)])
                    ctx.fill(hub, with: .linearGradient(steel,
                                                        startPoint: CGPoint(x: faceX, y: rect.midY - hubRY),
                                                        endPoint: CGPoint(x: faceX, y: rect.midY + hubRY)))
                    ctx.stroke(hub, with: .color(Color(hex: 0x555B63)), lineWidth: 0.45)

                    // A denomination belongs on the plate itself. Rotate the
                    // exact metadata label so even a thin calibrated change
                    // plate can carry "1.25 kg" without view-side rounding.
                    // The web renderer uses the same metadata and orientation.
                    var labelContext = ctx
                    labelContext.translateBy(x: rect.midX, y: rect.midY)
                    labelContext.rotate(by: .degrees(-90))
                    labelContext.draw(
                        Text(plate.label)
                            .font(.system(
                                size: presentation == .fullBar ? 9 : 5.6,
                                weight: .black,
                                design: .rounded
                            ))
                            .foregroundStyle(PlatePalette.labelColor(for: token)),
                        at: .zero,
                        anchor: .center
                    )
                }
                if presentation == .fullBar {
                    let width = max(240, size.width)
                    let midY = h / 2
                    let shoulder = min(100, max(76, width * 0.24))
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

                    let available = max(30, shoulder - 18)
                    let nominalGap: CGFloat = plateStyle == .bumper ? 1.05 : 0.75
                    let nominalWidths = plates.map { drawnPlateWidth($0) }
                    let nominal = nominalWidths.reduce(0, +) + CGFloat(max(0, plates.count - 1)) * nominalGap
                    let scale = nominal > available ? available / nominal : 1
                    let widths = plates.map { drawnPlateWidth($0, scale: scale) }
                    let gap = max(0.45, nominalGap * scale)
                    var leftCursor = shoulder - 6
                    var rightCursor = rightShoulder + 6
                    for (index, plate) in plates.enumerated() {
                        let plateWidth = widths[index]
                        let plateHeight = (h - 12) * CGFloat(plate.diameterFactor(for: plateStyle))
                        let leftRect = CGRect(x: leftCursor - plateWidth, y: (h - plateHeight) / 2,
                                              width: plateWidth, height: plateHeight)
                        let rightRect = CGRect(x: rightCursor, y: (h - plateHeight) / 2,
                                               width: plateWidth, height: plateHeight)
                        drawPlate(plate, rect: leftRect, side: "left")
                        drawPlate(plate, rect: rightRect, side: "right")
                        leftCursor = leftRect.minX - gap
                        rightCursor = rightRect.maxX + gap
                    }
                    if solution.loadout.collarLb > 0 {
                        for x in [leftCursor - 3.5, rightCursor] {
                            let collar = Path(roundedRect: CGRect(x: x, y: midY - 8, width: 3.5, height: 16), cornerRadius: 1)
                            ctx.fill(collar, with: .linearGradient(steel,
                                                                  startPoint: CGPoint(x: x, y: midY - 8),
                                                                  endPoint: CGPoint(x: x, y: midY + 8)))
                            ctx.stroke(collar, with: .color(Color(hex: 0x555B63)), lineWidth: 0.5)
                        }
                    }
                    if plates.isEmpty {
                        let label = solution.loadout.collarLb > 0 ? "bar + collars" : "bar only"
                        ctx.draw(Text(label).font(.system(size: 10)).foregroundStyle(.secondary),
                                 at: CGPoint(x: width / 2, y: midY - 9), anchor: .center)
                    }
                } else {
                    // bar shaft + sleeve face
                    ctx.fill(Path(roundedRect: CGRect(x: 0, y: h / 2 - 1.5, width: Self.sleeve + 4, height: 3), cornerRadius: 1.5),
                             with: .color(Color(hex: 0x9AA0AA)))
                    ctx.fill(Path(roundedRect: CGRect(x: Self.sleeve, y: h / 2 - 6, width: 3, height: 12), cornerRadius: 1),
                             with: .color(Color(hex: 0x7C828C)))

                    var x = Self.sleeve + 5
                    for (index, plate) in plates.enumerated() {
                        let plateWidth = compactWidths[index]
                        let ph = (h - 4) * CGFloat(plate.diameterFactor(for: plateStyle))
                        let rect = CGRect(x: x, y: (h - ph) / 2, width: plateWidth, height: ph)
                        drawPlate(plate, rect: rect, side: "right")
                        x += plateWidth + compactGap
                    }
                    if solution.loadout.collarLb > 0 {
                        let collar = Path(roundedRect: CGRect(x: x, y: h / 2 - 8, width: 3.5, height: 16), cornerRadius: 1)
                        let steel = Gradient(colors: [Color(hex: 0x5D626A), Color(hex: 0xD5D8DC), Color(hex: 0x747A83)])
                        ctx.fill(collar, with: .linearGradient(steel,
                                                              startPoint: CGPoint(x: x, y: h / 2 - 8),
                                                              endPoint: CGPoint(x: x, y: h / 2 + 8)))
                        ctx.stroke(collar, with: .color(Color(hex: 0x555B63)), lineWidth: 0.5)
                    }
                    if plates.isEmpty {
                        let label = solution.loadout.collarLb > 0 ? "bar + collars" : "bar only"
                        ctx.draw(Text(label).font(.system(size: 10)).foregroundStyle(.secondary),
                                 at: CGPoint(x: solution.loadout.collarLb > 0 ? x + 5 : Self.sleeve + 7,
                                             y: h / 2), anchor: .leading)
                    }
                }
            }
            .frame(width: presentation == .compactSide ? width : nil,
                   height: presentation == .compactSide ? Self.height : Self.fullHeight)
            .frame(maxWidth: presentation == .fullBar ? .infinity : nil)
            .accessibilityChildren {
                ForEach(Array(plates.enumerated()), id: \.offset) { index, plate in
                    Text("Left plate \(index + 1) of \(plates.count), \(plate.label)")
                    Text("Right plate \(index + 1) of \(plates.count), \(plate.label)")
                }
            }

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
        .accessibilityLabel("Barbell: \(accessibilityLoad)")
    }
}

/// The one totals hierarchy used anywhere Cadence explains a solved or
/// manually entered bar. Achieved weight is deliberately lb first, then kg,
/// regardless of entry unit or the mix of denominations on the sleeves.
struct LoadoutSummaryView: View {
    let requestedLb: Double?
    let loadout: Loadout

    private var differenceLb: Double? {
        requestedLb.map { loadout.totalLb - $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACHIEVED — BAR INCLUDED")
                .font(.caption.bold())
                .tracking(0.8)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                weight(Weight.trim(loadout.totalLb), unit: "lb", prominent: true)
                Text("/")
                    .font(.title3.weight(.light))
                    .foregroundStyle(.tertiary)
                weight(Weight.trim(Weight.kg(fromLb: loadout.totalLb)), unit: "kg", prominent: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Achieved total, bar included, \(Weight.both(lb: loadout.totalLb))")

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                if let requestedLb {
                    summaryRow("Requested", Weight.both(lb: requestedLb))
                }
                summaryRow("Bar", Weight.both(lb: loadout.bar.lb))
                summaryRow("Plates / side", loadout.perSideLabel)
                if loadout.collarLb > 0 {
                    summaryRow("Collars", Weight.both(lb: loadout.collarLb))
                }
                if let differenceLb {
                    let sign = differenceLb > 0.005 ? "+" : ""
                    summaryRow(
                        "Difference",
                        "\(sign)\(Weight.trim(differenceLb, decimals: 2)) lb / "
                            + "\(sign)\(Weight.trim(Weight.kg(fromLb: differenceLb), decimals: 2)) kg",
                        warning: abs(differenceLb) > 0.01
                    )
                }
            }
        }
    }

    private func weight(_ value: String, unit: String, prominent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: prominent ? 36 : 27, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(unit)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ label: String, _ value: String, warning: Bool = false) -> some View {
        GridRow {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(warning ? Theme.warn : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
// Plate colours use the shared Color(hex:) from Theme.swift.
