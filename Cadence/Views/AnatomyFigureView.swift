import SwiftUI
import CadenceCore

/// A weightlifting gorilla drawn in Da Vinci's Vitruvian construction. Primary
/// movers use the interaction red while supporting muscles use a quiet forged-
/// steel wash; multiply blending preserves the engraved linework and the figure's
/// hands, feet, face, and muscle boundaries.
struct AnatomyFigureView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let profile: AnatomyData.Profile
    @State private var selectedMuscle: String?

    private static let primaryColor = Color(red: 0.878, green: 0.271, blue: 0.227)   // #e0453a
    private static let secondaryColor = Theme.forgedSteel
    private static let frontAssetByMuscle = [
        "traps": "VitruvianFrontTraps", "delts": "VitruvianFrontDelts",
        "chest": "VitruvianFrontChest", "biceps": "VitruvianFrontBiceps",
        "forearms": "VitruvianFrontForearms", "obliques": "VitruvianFrontObliques",
        "abs": "VitruvianFrontAbs", "quads": "VitruvianFrontQuads",
        "adductors": "VitruvianFrontAdductors",
    ]
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
            highlights(view: view)
                .blur(radius: 0.35)
                .blendMode(.multiply)
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

    // Both views use the exact SVG contours shared with web, registered to the
    // 1254×1254 source image. Do not smooth or mirror them again in presentation.
    private func highlights(view: String) -> some View {
        let primaryAssets = assets(profile.primary, view: view)
        let supportingAssets = assets(profile.secondary, view: view)
            .filter { !primaryAssets.contains($0) }
        return ZStack {
            ForEach(supportingAssets, id: \.self) { asset in
                regionMask(asset, color: Self.secondaryColor.opacity(maskOpacity(asset: asset, view: view, primary: false)))
            }
            ForEach(primaryAssets, id: \.self) { asset in
                regionMask(asset, color: Self.primaryColor.opacity(maskOpacity(asset: asset, view: view, primary: true)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func assets(_ ids: [String], view: String) -> [String] {
        let map = view == "front" ? Self.frontAssetByMuscle : Self.backAssetByMuscle
        var seen = Set<String>()
        return ids.compactMap { map[$0] }.filter { seen.insert($0).inserted }
    }

    private func maskOpacity(asset: String, view: String, primary: Bool) -> Double {
        guard let selectedMuscle else { return primary ? 0.50 : 0.32 }
        let map = view == "front" ? Self.frontAssetByMuscle : Self.backAssetByMuscle
        return map[selectedMuscle] == asset ? 0.72 : 0.08
    }

    private func regionMask(_ asset: String, color: Color) -> some View {
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
