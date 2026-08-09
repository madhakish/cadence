import SwiftUI
import CadenceCore

/// The stylized front/back muscle figure: primary movers red, supporting
/// blue, everything else a neutral silhouette. Geometry comes from
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
            let sx = size.width / 100.0
            let sy = size.height / 220.0
            func poly(_ pts: [[Double]]) -> Path {
                var p = Path()
                guard let first = pts.first, first.count == 2 else { return p }
                p.move(to: CGPoint(x: first[0] * sx, y: first[1] * sy))
                for pt in pts.dropFirst() where pt.count == 2 {
                    p.addLine(to: CGPoint(x: pt[0] * sx, y: pt[1] * sy))
                }
                p.closeSubpath()
                return p
            }
            for b in AnatomyData.body {
                ctx.fill(poly(b), with: .color(.primary.opacity(0.08)))
            }
            for r in AnatomyData.regions where r.view == view {
                if profile.primary.contains(r.id) {
                    ctx.fill(poly(r.points), with: .color(Self.primaryColor.opacity(0.85)))
                } else if profile.secondary.contains(r.id) {
                    ctx.fill(poly(r.points), with: .color(Self.secondaryColor.opacity(0.7)))
                } else {
                    ctx.fill(poly(r.points), with: .color(.primary.opacity(0.06)))
                }
            }
        }
        .aspectRatio(100.0 / 220.0, contentMode: .fit)
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
