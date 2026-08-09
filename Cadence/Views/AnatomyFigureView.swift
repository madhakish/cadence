import SwiftUI
import CadenceCore

/// The Vitruvian front/back muscle figure: primary movers red, supporting
/// blue, everything else a neutral anatomical silhouette. Geometry comes from
/// AnatomyData in CadenceCore (fixture-locked to the web's copy), so both
/// apps draw the identical figure.
struct AnatomyFigureView: View {
    let profile: AnatomyData.Profile

    private static let primaryColor = Color(red: 0.878, green: 0.271, blue: 0.227)   // #e0453a
    private static let secondaryColor = Color(red: 0.227, green: 0.482, blue: 0.835) // #3a7bd5

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                labeledFigure(view: "front", label: "Front")
                labeledFigure(view: "back", label: "Back")
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
        Canvas { ctx, size in
            let sx = size.width / 210.0
            let sy = size.height / 224.0
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

            let orbit = Path(ellipseIn: CGRect(x: 3 * sx, y: 9 * sy, width: 204 * sx, height: 204 * sy))
            ctx.stroke(orbit, with: .color(Color.primary.opacity(0.14)), lineWidth: 0.7)

            let neutral = Gradient(colors: [Color.primary.opacity(0.15), Color.primary.opacity(0.035)])
            for b in AnatomyData.body {
                let path = contour(b)
                ctx.fill(path, with: .linearGradient(neutral,
                                                     startPoint: CGPoint(x: size.width / 2, y: 0),
                                                     endPoint: CGPoint(x: size.width / 2, y: size.height)))
                ctx.stroke(path, with: .color(Color.primary.opacity(0.13)), lineWidth: 0.55)
            }
            for r in AnatomyData.regions where r.view == view {
                let path = contour(r.points)
                if profile.primary.contains(r.id) {
                    ctx.fill(path, with: .linearGradient(
                        Gradient(colors: [Self.primaryColor.opacity(0.96), Self.primaryColor.opacity(0.68)]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    ))
                    ctx.stroke(path, with: .color(Self.primaryColor.opacity(0.9)), lineWidth: 0.55)
                } else if profile.secondary.contains(r.id) {
                    ctx.fill(path, with: .linearGradient(
                        Gradient(colors: [Self.secondaryColor.opacity(0.88), Self.secondaryColor.opacity(0.58)]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    ))
                    ctx.stroke(path, with: .color(Self.secondaryColor.opacity(0.8)), lineWidth: 0.5)
                } else {
                    ctx.fill(path, with: .color(Color.primary.opacity(0.035)))
                }
            }
        }
        .aspectRatio(210.0 / 224.0, contentMode: .fit)
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
