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
    var plateTheme: PlateThemeID = .custom
    let plate: Plate
    let style: PlateVisualStyle
    var exactDenomination = false

    private var colour: PlateColour { PlateTheme.colour(plate, theme: plateTheme, style: style) }

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
                Text(plate.denomination)
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

/// Renders the solver's exact stack in the barbell studio.
/// `presentation` is chosen by the SURFACE (a set row vs the current set's
/// stage); `emphasis` is the state and changes only opacity — never geometry,
/// order, or labels.
struct BarbellView: View {
    enum Presentation: Equatable { case compactSide, fullBar, inspectionSide }
    enum Emphasis: Equatable { case current, standard, muted }
    let solution: PlateSolution
    var plateStyle: PlateVisualStyle = .steel
    var plateTheme: PlateThemeID = .custom
    var presentation: Presentation = .compactSide
    var exploded = false
    var emphasis: Emphasis = .standard
    var showsReadout = true

    static func minimumLegibleWidth(for loadout: Loadout, style: PlateVisualStyle, theme: PlateThemeID = .custom) -> CGFloat {
        CGFloat(max(320, BarbellScene(loadout: loadout, style: style, exploded: false, theme: theme).width * 1.2))
    }

    var body: some View {
        let scene = BarbellScene(loadout: solution.loadout, style: plateStyle, exploded: exploded, theme: plateTheme)
        // The studio renders the real bar on the platform: straight ahead for
        // a set row, three-quarter for the stage, the blowup for an exploded
        // inspection fallback. One scene behind every view.
        let shot: StudioShot = presentation == .compactSide ? .row : (presentation == .inspectionSide && exploded ? .blowup : .hero)
        let artwork = StudioImage(loadout: solution.loadout, style: plateStyle, theme: plateTheme, shot: shot)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
            if presentation == .fullBar {
                artwork.aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxHeight: 220)
            } else {
                artwork.frame(height: presentation == .compactSide ? 84 : nil)
            }
            if showsReadout && presentation != .inspectionSide && !solution.loadout.perSide.isEmpty {
                PlateStackReadout(loadout: solution.loadout)
            }
        }
        .opacity(emphasis == .muted ? 0.85 : 1)
        .accessibilityLabel("\(exploded ? "Exploded" : "Assembled") bar, \(Weight.both(lb: solution.loadout.totalLb))")
        .accessibilityChildren { Self.plateChildren(scene: scene, loadout: solution.loadout) }
    }

    /// Every plate as its own element, each side from the collar outward, then
    /// the bar-only or collar note — the same order web's focusable plate
    /// groups take. Shared with the 3D inspector.
    @ViewBuilder
    static func plateChildren(scene: BarbellScene, loadout: Loadout, exactDenominations: Bool = false) -> some View {
        ForEach([-1, 1], id: \.self) { side in
            ForEach(scene.discs.filter { $0.side == side }.sorted { $0.index < $1.index }, id: \.index) { disc in
                Text(exactDenominations
                         ? "\(inspectionPlateLabel(disc.plate)) plate, \(disc.index + 1) from inside, \(side < 0 ? "left" : "right") side"
                         : disc.accessibilityLabel)
                    .accessibilityIdentifier("barbell-plate-\(side < 0 ? "left" : "right")-\(disc.index)")
            }
        }
        if loadout.perSide.isEmpty {
            Text(loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
        } else if loadout.collarLb > 0 {
            Text("Collars, \(Weight.both(lb: loadout.collarLb)) total")
        }
    }
}

/// A screen-size denomination for every position on each mirrored sleeve.
/// The edge-on artwork is a load-order map, and cannot fit full-size text on
/// the physical face at phone width. This readout never scales with the map.
private struct PlateStackReadout: View {
    let loadout: Loadout

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Text("Each side · inside → outside")
                    .foregroundStyle(.secondary)
                ForEach(Array(loadout.perSide.flatMap { Array(repeating: $0.plate, count: max(0, $0.count)) }.enumerated()), id: \.offset) { index, plate in
                    Text(plate.label)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel("\(plate.label) plate, \(index + 1) from inside, each side")
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityIdentifier("barbell-plate-readout")
        .accessibilityHidden(true)
    }
}

/// Always offers inspection, even when a typical stack fits the phone.
struct BarbellStageView: View {
    let solution: PlateSolution
    let unit: WeightUnit
    var plateStyle: PlateVisualStyle = .steel
    var plateTheme: PlateThemeID = .custom
    var caption = "Mirrored stack · counts are per side"
    var onExpand: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let onExpand {
                BarbellView(solution: solution, plateStyle: plateStyle, plateTheme: plateTheme, presentation: .fullBar)
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
                BarbellView(solution: solution, plateStyle: plateStyle, plateTheme: plateTheme, presentation: .fullBar)
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
    @ScaledMetric(relativeTo: .subheadline) private var captionSize: CGFloat = 14
    let solution: PlateSolution
    var plateStyle: PlateVisualStyle = .steel
    var plateTheme: PlateThemeID = .custom
    @State private var exploded = false
    private let solid = BarbellSceneView.isSupported

    var body: some View {
        let scene = BarbellScene(loadout: solution.loadout, style: plateStyle, exploded: exploded, theme: plateTheme)
        let layout = BarbellInspector.layout(loadout: solution.loadout, style: plateStyle, explode: exploded ? 1 : 0, theme: plateTheme)
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let minimum = BarbellInspector.minimumWidth(layout: layout, viewportWidth: Double(proxy.size.width), exploded: exploded)
                let width = exploded ? max(proxy.size.width, CGFloat(minimum) * max(1, captionSize / 14)) : proxy.size.width
                ScrollView(.horizontal, showsIndicators: exploded && width > proxy.size.width) {
                    Group {
                        if solid {
                            BarbellSceneView(loadout: solution.loadout, plateStyle: plateStyle, plateTheme: plateTheme,
                                             exploded: exploded, reduceMotion: reduceMotion)
                        } else {
                            BarbellView(solution: solution, plateStyle: plateStyle, plateTheme: plateTheme, presentation: .inspectionSide, exploded: exploded)
                        }
                    }
                    .frame(width: width, height: 300)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle() }
                }
                .scrollDisabled(!exploded || width <= proxy.size.width)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .frame(height: 300)
            .accessibilityIdentifier("barbell-inspection-artwork")
            .accessibilityLabel("\(exploded ? "Exploded" : "Assembled") bar, \(Weight.both(lb: solution.loadout.totalLb))")
            .accessibilityHint(exploded ? "The near sleeve's plates are slid out; both sides are mirrored. Tap to assemble." : "The whole loaded bar. Tap to slide the plates out and inspect each one.")
            .accessibilityChildren { BarbellView.plateChildren(scene: scene, loadout: solution.loadout, exactDenominations: true) }
            Button(exploded ? "Plates slid out · tap to assemble" : "Loaded bar · tap to inspect") { toggle() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .accessibilityLabel(exploded ? "Assemble bar" : "Explode plates")
                .accessibilityValue(exploded ? "Exploded" : "Assembled")
                .accessibilityIdentifier("barbell-explode-toggle")
            Text("Plates per side").font(.headline)
            ForEach(Array(solution.loadout.perSide.enumerated()), id: \.offset) { _, count in
                HStack(spacing: 12) {
                    PlateFaceBadge(plateTheme: plateTheme, plate: count.plate, style: plateStyle, exactDenomination: true)
                    Text(inspectionPlateLabel(count.plate)).font(.body.monospacedDigit())
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
    var plateTheme: PlateThemeID = .custom
    /// The achieved total keeps its display proportion and follows Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var totalSize: CGFloat = 40

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
                 kind: PlateGeometry.familyLabel(PlateTheme.family(count.plate, theme: plateTheme, style: plateStyle)))
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
                            .font(.system(size: totalSize, weight: .black, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
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
                        LoadoutCell(cell: cell, style: plateStyle, theme: plateTheme)
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
        let theme: PlateThemeID

        var body: some View {
            HStack(spacing: 8) {
                if let plate = cell.plate {
                    PlateFaceBadge(plateTheme: theme, plate: plate, style: style)
                        .scaleEffect(0.5)
                        .frame(width: 26, height: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.count)
                        .font(.callout.bold().monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
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
// Colour(hex:) comes from Theme.swift; the plate hex values come from CadenceCore.
