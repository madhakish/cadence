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
        token == "white" || token == "yellow" || token == "green"
            ? Color(hex: 0x24262A) : .white
    }
}

/// A readable, face-on denomination key for a plate in the calculator. The
/// bar graphic stays an honest edge-on load-order diagram; this companion
/// view owns the large number that an edge-on plate cannot physically carry.
/// Decorative: every use pairs it with a readable denomination label.
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
        .accessibilityHidden(true)
    }
}

/// Renders the solver's exact stack with the approved photographic plate faces.
struct BarbellView: View {
    enum Presentation: Equatable { case compactSide, fullBar }
    let solution: PlateSolution
    var plateStyle: PlateVisualStyle = .steel
    var presentation: Presentation = .compactSide
    var exploded = false

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
                let edge = PlatePalette.stroke[token] ?? .gray
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
                    .foregroundColor(PlatePalette.labelColor(for: token))
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
        .accessibilityLabel("\(exploded ? "Exploded" : "Assembled") bar, \(Weight.both(lb: solution.loadout.totalLb))")
        .accessibilityChildren {
            ForEach([-1, 1], id: \.self) { side in
                ForEach(scene.discs.filter { $0.side == side }.sorted { $0.index < $1.index }, id: \.index) { disc in
                    Text("\(side < 0 ? "Left" : "Right") plate \(disc.index + 1) from inside, \(disc.plate.label)")
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
                HStack {
                    Text("Tap to inspect").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onExpand) {
                        Label("Larger view", systemImage: "arrow.up.right")
                            .labelStyle(.titleAndIcon)
                            .font(.callout.bold())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Inspect loaded bar and explode plates")
                    .accessibilityIdentifier("expand-loaded-bar")
                }
            } else {
                BarbellView(solution: solution, plateStyle: plateStyle, presentation: .fullBar)
                    .frame(height: 170)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
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
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    BarbellView(solution: solution, plateStyle: plateStyle, presentation: .fullBar, exploded: exploded)
                        .frame(width: exploded ? max(proxy.size.width, scene.width) : proxy.size.width,
                               height: exploded ? scene.height : 230)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle() }
                }
            }
            .frame(height: exploded ? scene.height + 20 : 250)
            .accessibilityIdentifier("barbell-inspection-artwork")
            // One quiet line says which view this is and what a tap does; the
            // same control is the accessible toggle.
            HStack {
                Button(exploded ? "38° inspection · tap to collapse" : "Front view · tap to inspect") { toggle() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityLabel(exploded ? "Assemble bar" : "Explode plates")
                    .accessibilityValue(exploded ? "Exploded" : "Assembled")
                    .accessibilityIdentifier("barbell-explode-toggle")
                Spacer()
                if exploded {
                    Text("Swipe across · inside → outside").font(.caption).foregroundStyle(.secondary)
                }
            }
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

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: Theme.shortMotion)) { exploded.toggle() }
    }
}

/// The one totals composition used anywhere Cadence explains a solved or
/// entered bar — the calculator, the current set, the exercise pane, the
/// workout preview. What was achieved, pounds first, kilograms after; how far
/// from what was asked; which bar and what is on each side; and one cell per
/// plate family so the rack is readable at a glance. Web twin:
/// `loadoutSummary` in barbell.js.
struct LoadoutSummaryView: View {
    let requestedLb: Double?
    let loadout: Loadout
    var plateStyle: PlateVisualStyle = .steel

    private var differenceLb: Double? {
        requestedLb.map { loadout.totalLb - $0 }
    }

    private var perSideText: String {
        loadout.perSide.isEmpty
            ? (loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
            : "\(loadout.perSideLabel) / side"
    }

    private struct Cell: Identifiable {
        let id: String
        let plate: Plate?
        let count: String
        let kind: String
    }

    /// One cell per denomination, counting both sleeves, then the collars.
    private var cells: [Cell] {
        var result = loadout.perSide.map { count in
            Cell(id: count.plate.id,
                 plate: count.plate,
                 count: "\(count.count * 2) × \(count.plate.label)",
                 kind: PlateGeometry.familyLabel(PlateGeometry.family(count.plate, style: plateStyle)))
        }
        if loadout.collarLb > 0 {
            result.append(Cell(id: "collars", plate: nil, count: "2 collars", kind: "Outermost"))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACHIEVED WITH BAR")
                        .font(.caption.bold())
                        .tracking(0.8)
                        .foregroundStyle(Theme.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Weight.trim(loadout.totalLb))
                            .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                        Text("lb")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(Weight.trim(Weight.kg(fromLb: loadout.totalLb)))
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        Text("kg")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let requestedLb, let differenceLb {
                    let sign = differenceLb > 0.005 ? "+" : ""
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(sign)\(Weight.trim(differenceLb, decimals: 2)) lb")
                            .font(.callout.bold().monospacedDigit())
                            .foregroundStyle(abs(differenceLb) > 0.01 ? Theme.warn : .secondary)
                        Text("from \(Weight.trim(requestedLb)) lb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text(loadout.bar.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(perSideText)
                    .font(.body.bold().monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)

            if !cells.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(cells) { cell in
                        LoadoutCell(cell: cell, style: plateStyle)
                    }
                }
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = ["Achieved total, bar included, \(Weight.both(lb: loadout.totalLb))"]
        if let requestedLb, let differenceLb {
            let sign = differenceLb > 0.005 ? "plus " : (differenceLb < -0.005 ? "minus " : "")
            parts.append("from \(Weight.trim(requestedLb)) lb, \(sign)\(Weight.trim(abs(differenceLb), decimals: 2)) lb")
        }
        return parts.joined(separator: ", ")
    }

    private struct LoadoutCell: View {
        let cell: Cell
        let style: PlateVisualStyle

        var body: some View {
            HStack(spacing: 8) {
                if let plate = cell.plate {
                    PlateFaceBadge(plate: plate, style: style)
                        .scaleEffect(0.5)
                        .frame(width: 26, height: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.count)
                        .font(.callout.bold().monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(cell.kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.hairline, lineWidth: 0.5))
            .accessibilityElement(children: .combine)
        }
    }
}
// Plate colours use the shared Color(hex:) from Theme.swift.
