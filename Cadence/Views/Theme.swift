import SwiftUI

/// Dark, minimal, chalk-hands-friendly. No streaks, no badges, no quotes.
/// "Carbon": neutral greyscale ground, red as the single signal. Mirrors the
/// web `styles.css` :root tokens.
enum Theme {
    static let accent = Color(hex: 0xEF4444)    // red — active / rest / interactive
    static let warn = Color(hex: 0xEAB308)      // amber — grindy / wobble (semantic)
    static let hardStop = Color(hex: 0xDC2626)  // deep red — hard stop (semantic critical)
    static let good = Color(hex: 0x4ADE80)      // green — clean rep (semantic)
    static let card = Color(.secondarySystemGroupedBackground)

    /// Minimum touch target for between-sets thumbs.
    static let bigTap: CGFloat = 56
}

extension Color {
    /// Hex literal, 0xRRGGBB.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// All user-facing copy in one place. Tone: terse, dry, coach-like.
enum Copy {
    static let sessionDone = "Bank it."
    static let stoppedEarly = "Clean reps over rep count."
    static let noSwelling = "Clear. Carry on."
    static let swelling = "Hard stop on running. Let it settle."
    static let restOver = "Rest over."
    static let offTarget = "Closest load is off target."
    static let emptyHistory = "Nothing logged yet."
    static let shelved = "Shelved"
}

extension View {
    func cardStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The one mm:ss formatter for the app (web equivalent: ui.mmss).
func mmss(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
