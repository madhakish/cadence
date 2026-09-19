import SwiftUI
import CadenceCore

/// One rack-resolution path for native callers. The resulting `PlateSolution`
/// is the only value `BarbellView` accepts, so station units, mixed inventory,
/// collars, and loading policy cannot drift inside the presentation layer.
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
    return PlateMath.solveLoad(
        weightLb: targetLb,
        bar: bar,
        plates: rack,
        collarLb: gym?.collarWeightLb ?? 0,
        policy: gym?.loadingPolicy ?? .closest
    )
}

/// Plate colours come from the one table in CadenceCore (`PlatePalette`);
/// this only turns its hex into SwiftUI colours.
private extension PlateColour {
    var fillColor: Color { Color(hex: fill) }
    var edgeColor: Color { Color(hex: edge) }
    var inkColor: Color { Color(hex: ink) }
}

/// A readable, face-on denomination key for a plate in the calculator. The
/// bar graphic stays an honest edge-on load-order diagram; this companion
/// view owns the large number that an edge-on plate cannot physically carry.
/// Decorative: every use pairs it with a readable denomination label.
struct PlateFaceBadge: View {
    let plate: Plate
    let style: PlateVisualStyle

    private var colour: PlateColour { PlatePalette.colour(for: plate.colorToken(for: style)) }

    var body: some View {
        let foreground = colour.inkColor
        ZStack {
            Circle()
                .fill(colour.fillColor)
            Circle()
                .stroke(colour.edgeColor, lineWidth: 2)
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
        .accessibilityHidden(true)
    }
}

/// Renders the solver's exact stack with the approved photographic plate faces.
/// `presentation` is chosen by the SURFACE (a set row vs the current set's
/// stage); `emphasis` is the state and changes only opacity — never geometry,
/// order, or labels.
struct BarbellView: View {
    enum Presentation: Equatable { case compactSide, fullBar }
    enum Emphasis: Equatable { case current, standard, muted }
    let solution: PlateSolution
    var plateStyle: PlateVisualStyle = .steel
    var presentation: Presentation = .compactSide
    var exploded = false
    var emphasis: Emphasis = .standard

    static func minimumLegibleWidth(for loadout: Loadout, style: PlateVisualStyle) -> CGFloat {
        CGFloat(max(320, BarbellScene(loadout: loadout, style: style, exploded: false).width * 0.55))
    }

    var body: some View {
        let scene = BarbellScene(loadout: solution.loadout, style: plateStyle, exploded: exploded)
        Canvas { context, size in
            let scale = min(size.width / scene.width, size.height / scene.height)
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            let metal = Gradient(colors: [Color(hex: 0x535B64), Color(hex: 0xC2C9CC),
                Color(hex: 0xF2F3F0), Color(hex: 0x8B959E), Color(hex: 0x343B43)])
            func point(_ position: Double) -> CGPoint {
                CGPoint(x: position * scene.axisX, y: position * scene.axisY)
            }
            func shaft(_ from: Double, _ to: Double, _ width: CGFloat) {
                let a = point(from), b = point(to)
                var path = Path()
                path.move(to: a); path.addLine(to: b)
                context.stroke(path, with: .linearGradient(metal,
                    startPoint: CGPoint(x: a.x, y: a.y - width / 2),
                    endPoint: CGPoint(x: a.x, y: a.y + width / 2)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            shaft(-scene.end, scene.end, 7)
            shaft(-scene.end, -scene.shoulder, 12)
            shaft(scene.shoulder, scene.end, 12)
            for side in [-1.0, 1.0] {
                let p = point(side * scene.shoulder)
                let rect = CGRect(x: p.x - 4, y: p.y - 18, width: 8, height: 36)
                context.fill(Path(ellipseIn: rect), with: .linearGradient(metal,
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }
            for x in stride(from: -scene.shoulder + 24, to: scene.shoulder - 24, by: 4) where abs(x) >= 42 {
                let p = point(x)
                var line = Path()
                line.move(to: CGPoint(x: p.x - 1, y: p.y - 3))
                line.addLine(to: CGPoint(x: p.x + 2, y: p.y + 3))
                context.stroke(line, with: .color(Color(hex: 0x4C535B)), lineWidth: 0.6)
            }
            let image = context.resolve(Image(plateStyle == .bumper ? "PlateBumper" : "PlateSteel"))
            for disc in scene.discs {
                let token = disc.plate.colorToken(for: plateStyle)
                let colour = PlatePalette.colour(for: token)
                let edge = colour.edgeColor
                let x = disc.x + disc.depth / 2
                let face = CGRect(x: x - disc.faceRadius, y: disc.y - disc.radius,
                    width: disc.faceRadius * 2, height: disc.radius * 2)
                let rear = face.offsetBy(dx: -disc.depth, dy: 0)
                context.fill(Path(ellipseIn: rear), with: .color(edge))
                context.fill(Path(CGRect(x: disc.x - disc.depth / 2, y: face.minY,
                    width: disc.depth, height: face.height)), with: .color(edge))
                let gains = PlateFaceTint(token: token)
                var matrix = ColorMatrix()
                matrix.r1 = Float(gains.red)
                matrix.g2 = Float(gains.green)
                matrix.b3 = Float(gains.blue)
                context.drawLayer { tinted in
                    tinted.addFilter(.colorMatrix(matrix))
                    tinted.draw(image, in: face)
                }
                context.drawLayer { hub in
                    hub.clip(to: Path(ellipseIn: face.insetBy(dx: face.width * 0.3825,
                                                             dy: face.height * 0.3825)))
                    hub.draw(image, in: face)
                }
                let label = Text(Weight.trim(disc.plate.value, decimals: 2))
                    .font(.system(size: exploded ? 14 : 10, weight: .heavy))
                    .foregroundColor(colour.inkColor)
                context.draw(label, at: CGPoint(x: x, y: disc.y - disc.radius * 0.48))
            }
            if solution.loadout.collarLb > 0 {
                for side in [-1.0, 1.0] {
                    let p = point(side * scene.collar)
                    let rect = CGRect(x: p.x - 4, y: p.y - 13, width: 8, height: 26)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .linearGradient(metal,
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                }
            }
        }
        .frame(height: presentation == .compactSide ? 84 : nil)
        .opacity(emphasis == .muted ? 0.85 : 1)
        .accessibilityLabel("\(exploded ? "Exploded" : "Assembled") bar, \(Weight.both(lb: solution.loadout.totalLb))")
        .accessibilityChildren {
            ForEach([-1, 1], id: \.self) { side in
                ForEach(scene.discs.filter { $0.side == side }.sorted { $0.index < $1.index }, id: \.index) { disc in
                    Text(disc.accessibilityLabel)
                        .accessibilityIdentifier("barbell-plate-\(side < 0 ? "left" : "right")-\(disc.index)")
                }
            }
            if solution.loadout.perSide.isEmpty {
                Text(solution.loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
            } else if solution.loadout.collarLb > 0 {
                Text("Collars, \(Weight.both(lb: solution.loadout.collarLb)) total")
            }
        }
    }
}

/// Always offers inspection, even when a typical stack fits the phone.
struct BarbellStageView: View {
    let solution: PlateSolution
    let unit: WeightUnit
    var plateStyle: PlateVisualStyle = .steel
    var caption = "Mirrored stack · counts are per side"
    var onExpand: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let onExpand {
                BarbellView(solution: solution, plateStyle: plateStyle, presentation: .fullBar)
                    .frame(height: 170)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onExpand)
                Button(action: onExpand) {
                        Label("Inspect plates", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.callout.bold())
                            .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Inspect loaded bar and explode plates")
                .accessibilityIdentifier("expand-loaded-bar")
            } else {
                BarbellView(solution: solution, plateStyle: plateStyle, presentation: .fullBar)
                    .frame(height: 170)
            }
            Text(solution.loadout.perSide.isEmpty
                 ? (solution.loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
                 : "Per side: \(solution.loadout.perSideLabel)")
                .font(.body.monospacedDigit())
            Text(caption).font(.caption).foregroundStyle(.secondary)
            if abs(solution.deviationLb) > 0.01 {
                Text("Difference: \(solution.deviationLb > 0 ? "+" : "")\(Weight.trim(solution.deviationLb, decimals: 2)) lb")
                    .font(.caption.bold()).foregroundStyle(Theme.warn)
            } else if !solution.satisfiesPolicy {
                Text("Closest available · policy not exact").font(.caption.bold()).foregroundStyle(Theme.warn)
            }
        }
    }
}

/// Shared by calculator, workout, and contextual exercise sheets.
struct BarbellInspectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let solution: PlateSolution
    var plateStyle: PlateVisualStyle = .steel
    @State private var exploded = true

    var body: some View {
        let scene = BarbellScene(loadout: solution.loadout, style: plateStyle, exploded: exploded)
        VStack(alignment: .leading, spacing: 12) {
            Button(exploded ? "Assemble bar" : "Explode plates") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Theme.shortMotion)) { exploded.toggle() }
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityValue(exploded ? "Exploded" : "Assembled")
            .accessibilityIdentifier("barbell-explode-toggle")
            Text("Swipe across · inside → outside").font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    BarbellView(solution: solution, plateStyle: plateStyle, presentation: .fullBar, exploded: exploded)
                        .frame(width: exploded ? max(proxy.size.width, scene.width) : proxy.size.width,
                               height: exploded ? scene.height : 230)
                }
            }
            .frame(height: exploded ? scene.height + 20 : 250)
            .accessibilityIdentifier("barbell-inspection-artwork")
            Text("Plates per side").font(.headline)
            ForEach(Array(solution.loadout.perSide.enumerated()), id: \.offset) { _, count in
                HStack(spacing: 12) {
                    PlateFaceBadge(plate: count.plate, style: plateStyle)
                    Text(count.plate.label).font(.body.monospacedDigit())
                    Spacer()
                    Text("× \(count.count)").font(.body.bold().monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
            if solution.loadout.perSide.isEmpty {
                Text(solution.loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
            }
            if !solution.satisfiesPolicy {
                Label("Closest available · policy not exact", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warn)
            }
        }
        .padding(.horizontal)
    }
}

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
// Colour(hex:) comes from Theme.swift; the plate hex values come from CadenceCore.
