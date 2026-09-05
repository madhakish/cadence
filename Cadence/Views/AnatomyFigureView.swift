import SwiftUI
import CadenceCore

/// A weightlifting gorilla drawn in Da Vinci's Vitruvian construction. Primary
/// movers use the interaction red while supporting muscles use a quiet forged-
/// steel wash; engraved linework stays above both so the figure keeps its
/// hands, feet, face, and muscle boundaries.
struct AnatomyFigureView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let profile: AnatomyData.Profile
    @State private var selectedMuscle: String?

    private static let primaryColor = Color(red: 0.878, green: 0.271, blue: 0.227)   // #e0453a
    private static let secondaryColor = Color(hex: 0xA6ABB2) // forged-steel supporting wash
    private static let backAssetByMuscle = [
        "traps": "VitruvianBackTraps",
        "delts": "VitruvianBackDelts",
        "reardelts": "VitruvianBackDelts",
        "lats": "VitruvianBackLats",
        "triceps": "VitruvianBackTriceps",
        "lowerback": "VitruvianBackLowerback",
        "forearms": "VitruvianBackForearms",
        "glutes": "VitruvianBackGlutes",
        "hamstrings": "VitruvianBackHamstrings",
        "calves": "VitruvianBackCalves",
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                labeledFigure(view: "front", label: "Front")
                labeledFigure(view: "back", label: "Back")
            }
            muscleLegend("Primary", ids: profile.primary, color: Self.primaryColor)
            if !profile.secondary.isEmpty {
                muscleLegend("Supporting", ids: profile.secondary, color: Self.secondaryColor)
            }
            if let selectedMuscle {
                HStack {
                    Text("Selected")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(AnatomyData.muscleNames[selectedMuscle] ?? selectedMuscle)
                        .font(.callout.bold())
                    Spacer()
                    Button("Clear") { self.selectedMuscle = nil }
                        .font(.caption.bold())
                }
                .padding(.top, 2)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.shortMotion), value: selectedMuscle)
        .accessibilityIdentifier("anatomy-figure")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Muscles worked. \(AnatomyData.blurb(profile))")
    }

    private func labeledFigure(view: String, label: String) -> some View {
        VStack(spacing: 2) {
            figure(view: view)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func muscleLegend(_ label: String, ids: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Rectangle().fill(color).frame(width: 10, height: 10)
                Text(label.uppercased())
                    .font(.caption.bold())
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    let isSelected = selectedMuscle == id
                    Button {
                        selectedMuscle = isSelected ? nil : id
                    } label: {
                        HStack(spacing: 7) {
                            Rectangle()
                                .fill(color)
                                .frame(width: 4, height: 22)
                            Text(AnatomyData.muscleNames[id] ?? id)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .background(
                            isSelected ? color.opacity(0.16) : Theme.raised.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .stroke(isSelected ? color.opacity(0.85) : Theme.hairline, lineWidth: 0.75)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(AnatomyData.muscleNames[id] ?? id), \(label.lowercased()) muscle")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func figure(view: String) -> some View {
        ZStack {
            Image(view == "front" ? "VitruvianFront" : "VitruvianBack")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(1, contentMode: .fit)
            if view == "front" {
                frontHighlights
                    .blur(radius: 2.1)
                    .blendMode(.multiply)
            } else {
                backHighlights
                    .blur(radius: 1.8)
                    .blendMode(.multiply)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .compositingGroup()
        .mask {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.black)
                .padding(2)
                .blur(radius: 4)
        }
    }

    private var frontHighlights: some View {
        Canvas { ctx, size in
            let sx = size.width / 210.0
            let sy = size.height / 210.0
            func contour(_ pts: [[Double]]) -> Path {
                var p = Path()
                let points = pts.compactMap { point -> CGPoint? in
                    guard point.count == 2 else { return nil }
                    return CGPoint(x: point[0] * sx, y: point[1] * sy)
                }
                guard points.count > 2, let first = points.first, let last = points.last else { return p }
                func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                }
                p.move(to: midpoint(last, first))
                for index in points.indices {
                    let point = points[index]
                    let next = points[(index + 1) % points.count]
                    p.addQuadCurve(to: midpoint(point, next), control: point)
                }
                p.closeSubpath()
                return p
            }

            for r in AnatomyData.vitruvianFrontRegions {
                let path = contour(r.points)
                let focused = selectedMuscle == nil || selectedMuscle == r.id
                if profile.primary.contains(r.id) {
                    ctx.fill(path, with: .linearGradient(
                        Gradient(colors: [Self.primaryColor.opacity(focused ? 0.50 : 0.10), Self.primaryColor.opacity(focused ? 0.30 : 0.06)]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    ))
                } else if profile.secondary.contains(r.id) {
                    ctx.fill(path, with: .linearGradient(
                        Gradient(colors: [Self.secondaryColor.opacity(focused ? 0.36 : 0.08), Self.secondaryColor.opacity(focused ? 0.22 : 0.05)]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    ))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var backHighlights: some View {
        ZStack {
            ForEach(backAssets(profile.secondary), id: \.self) { asset in
                backMask(asset, color: Self.secondaryColor.opacity(backOpacity(asset: asset, primary: false)))
            }
            ForEach(backAssets(profile.primary), id: \.self) { asset in
                backMask(asset, color: Self.primaryColor.opacity(backOpacity(asset: asset, primary: true)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func backAssets(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { Self.backAssetByMuscle[$0] }.filter { seen.insert($0).inserted }
    }

    private func backOpacity(asset: String, primary: Bool) -> Double {
        guard let selectedMuscle,
              let selectedAsset = Self.backAssetByMuscle[selectedMuscle]
        else { return primary ? 0.50 : 0.32 }
        return selectedAsset == asset ? (primary ? 0.58 : 0.44) : (primary ? 0.10 : 0.07)
    }

    private func backMask(_ asset: String, color: Color) -> some View {
        Image(asset)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(color)
            .aspectRatio(1, contentMode: .fit)
    }
}

/// Minimal progress sparkline (top-set weight over recent sessions).
struct SparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let n = max(1, values.count - 1)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(n)
                    let y = maxV == minV ? h / 2 : h - h * CGFloat((v - minV) / (maxV - minV))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}
