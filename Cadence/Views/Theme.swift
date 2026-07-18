import SwiftUI
import UIKit

/// The selectable themes. Raw values match the web `[data-theme]` keys and the
/// persisted `AppSettings.themeNameRaw`, so the two apps stay in lockstep.
enum ThemeName: String, CaseIterable, Identifiable, Codable {
    case memento, carbon, slate, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .memento: return "Memento"
        case .carbon: return "Carbon"
        case .slate: return "Slate"
        case .system: return "System"
        }
    }

    /// The three custom themes are dark by design; System follows the OS.
    var colorScheme: ColorScheme? { self == .system ? nil : .dark }

    /// Accent + semantic colours, mirroring web styles.css token blocks 1:1.
    /// (Backgrounds stay on the system grouped surfaces, which resolve dark
    /// under the forced dark scheme and follow the OS under System.)
    var palette: Palette {
        switch self {
        case .memento:
            return Palette(accent: Color(hex: 0xC9A24B), warn: Color(hex: 0xD29A3A),
                           hardStop: Color(hex: 0xD5352B), good: Color(hex: 0x5BA06A))
        case .carbon:
            return Palette(accent: Color(hex: 0xEF4444), warn: Color(hex: 0xEAB308),
                           hardStop: Color(hex: 0xDC2626), good: Color(hex: 0x4ADE80))
        case .slate:
            return Palette(accent: Color(hex: 0xE5484D), warn: Color(hex: 0xD29922),
                           hardStop: Color(hex: 0xDA3633), good: Color(hex: 0x3FB950))
        case .system:
            return Palette(accent: Color(lightHex: 0xC81E1E, darkHex: 0xEF4444),
                           warn: Color(lightHex: 0xB8860B, darkHex: 0xEAB308),
                           hardStop: Color(lightHex: 0xA51111, darkHex: 0xF0554F),
                           good: Color(lightHex: 0x1A8F43, darkHex: 0x4ADE80))
        }
    }
}

struct Palette {
    let accent, warn, hardStop, good: Color
}

/// Dark, minimal, chalk-hands-friendly. No streaks, no badges, no quotes.
/// `Theme.name` mirrors the persisted `AppSettings.themeNameRaw`; the root view
/// keeps it in sync each render so every static read below returns the active
/// palette. Main-actor isolated — it's read/written only from SwiftUI (UI) code.
@MainActor
enum Theme {
    /// Kept in sync with the persisted setting by `ThemedRoot`. Default Carbon
    /// (greyscale + red). A plain static var — assigning it triggers no
    /// re-render, so the root's `.id(theme)` drives the tree refresh.
    static var name: ThemeName = .carbon

    static var accent: Color { name.palette.accent }        // active / rest / interactive
    static var warn: Color { name.palette.warn }            // grindy / wobble (semantic)
    static var hardStop: Color { name.palette.hardStop }    // hard stop (semantic critical)
    static var good: Color { name.palette.good }            // clean rep (semantic)
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

    /// Dynamic colour resolving to the light or dark hex per the active trait
    /// collection — used by the System theme so it tracks the OS appearance.
    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? darkHex : lightHex
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// All user-facing copy in one place. Tone: terse, dry, coach-like.
enum Copy {
    static let sessionDone = "Bank it."
    static let stoppedEarly = "Clean reps over rep count."
    static let noSwelling = "All clear."
    static let swelling = "Pause and reassess before continuing."
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
