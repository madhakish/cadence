import SwiftUI

/// The 4-week cycle at a glance: Volume / Load / Peak / Deload as rising bars
/// with the deload dropped low, the current rotation lit in accent. Mirrors
/// the web `.wave` component (ui.js).
struct WaveGlyph: View {
    /// Current rotation, 1–4.
    let week: Int

    private static let heights: [CGFloat] = [8, 12, 16, 6]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i == week ? Theme.accent : Color(.tertiarySystemFill))
                    .frame(width: 5, height: Self.heights[i - 1])
            }
        }
        .accessibilityLabel("Rotation \(week) of 4")
    }
}

/// Tiny trend line — no axes, just the shape of the last few sessions.
/// Mirrors the web `sparkline` (charts.js).
struct Sparkline: View {
    /// Oldest → newest. Fewer than two points renders nothing.
    let values: [Double]
    var width: CGFloat = 64
    var height: CGFloat = 20

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            func pt(_ i: Int) -> CGPoint {
                let x = 1 + CGFloat(i) / CGFloat(values.count - 1) * (size.width - 4)
                let y = hi == lo ? size.height / 2
                    : size.height - 2 - CGFloat((values[i] - lo) / (hi - lo)) * (size.height - 4)
                return CGPoint(x: x, y: y)
            }
            var path = Path()
            path.move(to: pt(0))
            for i in 1..<values.count { path.addLine(to: pt(i)) }
            ctx.stroke(path, with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let last = pt(values.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2.4, y: last.y - 2.4, width: 4.8, height: 4.8)),
                     with: .color(Theme.accent))
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
