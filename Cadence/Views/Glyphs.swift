import SwiftUI
import CadenceCore

/// Where the program is in its rotation — four equal ticks with the current one
/// lit. Mirrors the web `.rotation` component (ui.js).
///
/// This replaced a rising-bar "wave" glyph that drew Volume / Load / Peak as
/// climbing and recovery as a drop. That shape is a claim about the
/// prescription, and the program-level indicator is shared by slots that have
/// nothing to do with each other's: a novice `linearFives` slot and a `5/3/1`
/// slot sit under the same counter and neither one waves. Position is the only
/// thing this indicator actually knows, so it is the only thing it draws. The
/// per-slot badge says what each slot does.
struct RotationGlyph: View {
    /// Current rotation, 1–4.
    let week: Int

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(1...ProgramProgression.deloadWeek, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i == week ? Theme.accent : Color(.tertiarySystemFill))
                    .frame(width: 5, height: 10)
            }
        }
        // `.accessibilityElement` is load-bearing, not decoration. A stack of
        // Shapes contains no accessibility element of its own, so a bare
        // `.accessibilityLabel` here has nothing to attach to and the rotation
        // simply goes unannounced. That was survivable while a phase name sat
        // beside the glyph; now that the neighbouring "R3" is decorative, this
        // view is the only thing that can say where the program is.
        //
        // Call sites whose adjacent text already reads the rotation mark the
        // glyph `.accessibilityHidden(true)` so it is not announced twice.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProgramEngine.rotationLabel(rotation: week))
    }
}

/// What a program slot actually does — `Main · 5/3/1`, `Complementary ·
/// Secondary volume` — plus the current phase, but ONLY where the phase
/// vocabulary describes the slot's prescription.
///
/// Both strings come from shared core (`ProgramEngine.slotBadge` /
/// `slotPhaseLabel`), so native and web cannot label the same slot differently
/// and neither can drift from the engine that produces the sets.
struct SlotPrescriptionBadge: View {
    let lift: ProgramLift
    let rotation: Int
    var movementGroup: String?
    var focus: TrainingFocus = .strength

    private var badge: String {
        ProgramEngine.slotBadge(role: lift.role, prescriptionStyle: lift.prescription,
                                movementGroup: movementGroup, focus: focus)
    }

    private var phase: String? {
        ProgramEngine.slotPhaseLabel(rotation: rotation, role: lift.role,
                                     prescriptionStyle: lift.prescription,
                                     movementGroup: movementGroup, focus: focus)
    }

    var body: some View {
        // The two facts stay separate elements so the phase can be absent
        // without leaving a dangling separator, and so VoiceOver reads one
        // combined label instead of two fragments.
        HStack(spacing: 4) {
            Text(badge)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let phase {
                Text(phase)
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.map { "\(badge), \($0)" } ?? badge)
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
