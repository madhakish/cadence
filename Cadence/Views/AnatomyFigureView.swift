import SwiftUI
import CadenceCore

/// A weightlifting gorilla drawn in Da Vinci's Vitruvian construction. Primary
/// movers are red and supporting muscles blue; engraved linework stays above
/// the colour so the figure keeps its hands, feet, face, and muscle boundaries.
struct AnatomyFigureView: View {
    let profile: AnatomyData.Profile

    private static let primaryColor = Color(red: 0.878, green: 0.271, blue: 0.227)   // #e0453a
    private static let secondaryColor = Color(red: 0.227, green: 0.482, blue: 0.835) // #3a7bd5
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
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                labeledFigure(view: "front", label: "Ape front")
                labeledFigure(view: "back", label: "Ape back")
            }
            muscleLine("Primary", ids: profile.primary, color: Self.primaryColor)
            if !profile.secondary.isEmpty {
                muscleLine("Supporting", ids: profile.secondary, color: Self.secondaryColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AnatomyData.blurb(profile))
    }

    private func labeledFigure(view: String, label: String) -> some View {
        VStack(spacing: 2) {
            figure(view: view)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func muscleLine(_ label: String, ids: [String], color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).fontWeight(.semibold)
            Text(ids.map { AnatomyData.muscleNames[$0] ?? $0 }.joined(separator: ", "))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                if profile.primary.contains(r.id) {
                    ctx.fill(path, with: .linearGradient(
                        Gradient(colors: [Self.primaryColor.opacity(0.48), Self.primaryColor.opacity(0.30)]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    ))
                } else if profile.secondary.contains(r.id) {
                    ctx.fill(path, with: .linearGradient(
                        Gradient(colors: [Self.secondaryColor.opacity(0.34), Self.secondaryColor.opacity(0.22)]),
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
                backMask(asset, color: Self.secondaryColor.opacity(0.32))
            }
            ForEach(backAssets(profile.primary), id: \.self) { asset in
                backMask(asset, color: Self.primaryColor.opacity(0.50))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func backAssets(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { Self.backAssetByMuscle[$0] }.filter { seen.insert($0).inserted }
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
