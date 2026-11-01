import SwiftUI
import UIKit

/// The selectable themes. Raw values match the web `[data-theme]` keys and the
/// persisted `AppSettings.themeNameRaw`, so the two apps stay in lockstep. The
/// keys are a theme's identity; the labels are what the visual pass renamed
/// (Foundry was Carbon, Heritage Gold was Memento), so a saved choice never
/// changes meaning. Declaration order is picker order: Foundry leads as the
/// recommended default.
enum ThemeName: String, CaseIterable, Identifiable, Codable {
    case carbon, memento, titanium, slate, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .carbon: return "Foundry"
        case .memento: return "Heritage Gold"
        case .titanium: return "Titanium"
        case .slate: return "Slate"
        case .system: return "System"
        }
    }

    /// Foundry, Heritage Gold, and Slate are dark by design; Titanium is the
    /// one light theme; System follows the OS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .titanium: return .light
        case .carbon, .memento, .slate: return .dark
        }
    }

    /// The primary canvas, matching the web theme's `--bg` token. Raised
    /// controls retain their system surfaces; the canvas carries the theme.
    var background: Color {
        switch self {
        case .carbon: return Color(hex: 0x0C0D0E)
        case .memento: return Color(hex: 0x0A0908)
        case .titanium: return Color(hex: 0xE6E9EC)
        case .slate: return Color(hex: 0x0D1117)
        case .system: return Color(lightHex: 0xF5F5F7, darkHex: 0x0C0D0E)
        }
    }

    /// Accent + semantic colours, mirroring web styles.css token blocks 1:1.
    /// Foundry, Slate and dark System share oxide red #F04A3E, and it means
    /// "now / act" only: the current set, the primary action, focus. Logged
    /// data reads in primary (chalk) and structure in steel greys. Oxide clears
    /// 4.5:1 on each dark canvas and on `Theme.card` (#1C1C1E, 4.66:1); it is
    /// not a text colour on `Theme.raised` (#2C2C2E, 3.82:1).
    /// `onAccent` is the label colour on an accent-filled
    /// control — chosen per theme to clear WCAG AA on that fill, never assumed
    /// white. Physical plate colours and anatomy role colours are not here:
    /// they come from equipment and muscle metadata, never from the theme.
    var palette: Palette {
        switch self {
        case .carbon:
            return Palette(accent: Color(hex: 0xF04A3E), onAccent: Color(hex: 0x0C0D0E),
                           warn: Color(hex: 0xEAB308), hardStop: Color(hex: 0xFF7A73),
                           good: Color(hex: 0x4ADE80))
        case .memento:
            return Palette(accent: Color(hex: 0xC9A24B), onAccent: Color(hex: 0x0A0908),
                           warn: Color(hex: 0xD29A3A), hardStop: Color(hex: 0xFF7A73),
                           good: Color(hex: 0x5BA06A))
        case .titanium:
            return Palette(accent: Color(hex: 0x0B615C), onAccent: Color(hex: 0xFFFFFF),
                           warn: Color(hex: 0x7A4F00), hardStop: Color(hex: 0xA51111),
                           good: Color(hex: 0x146633))
        case .slate:
            return Palette(accent: Color(hex: 0xF04A3E), onAccent: Color(hex: 0x0D1117),
                           warn: Color(hex: 0xD29922), hardStop: Color(hex: 0xFF7A73),
                           good: Color(hex: 0x3FB950))
        case .system:
            return Palette(accent: Color(lightHex: 0xC81E1E, darkHex: 0xF04A3E),
                           onAccent: Color(lightHex: 0xFFFFFF, darkHex: 0x0C0D0E),
                           warn: Color(lightHex: 0x7A4F00, darkHex: 0xEAB308),
                           hardStop: Color(lightHex: 0xA51111, darkHex: 0xFF7A73),
                           good: Color(lightHex: 0x146633, darkHex: 0x4ADE80))
        }
    }
}

struct Palette {
    let accent, onAccent, warn, hardStop, good: Color
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
    static var onAccent: Color { name.palette.onAccent }    // label on an accent fill
    static var background: Color { name.background }       // primary list canvas
    static let card = Color(.secondarySystemGroupedBackground)
    static let raised = Color(.tertiarySystemGroupedBackground)
    static let hairline = Color.primary.opacity(0.14)
    /// Subtle top edge on the current-set card. Web twin: `--edge`.
    static let edge = Color.primary.opacity(0.07)
    static let forgedSteel = Color(hex: 0xA6ABB2)
    /// 3D inspector backdrops: the studio's charcoal cyclorama, near black, and warm paper.
    static let sceneStudio = Color(hex: 0x1B1D21)
    static let sceneDark = Color(hex: 0x0A0B0D)
    static let scenePaper = Color(hex: 0xE6E2DA)

    /// Industrial geometry: almost square, but not sharp enough to snag a
    /// thumb-sized control. Shared by the few surfaces that genuinely need a
    /// boundary; spacing and dividers do the rest of the grouping.
    static let cornerRadius: CGFloat = 4
    static let shortMotion: Double = 0.16

    /// Minimum touch target for between-sets thumbs.
    static let bigTap: CGFloat = 56
    /// The band above the tab bar that the floating plate-calculator button
    /// occupies (its 56-point face plus the 16 points it floats above the
    /// bar). Every tab root reserves exactly this much so content scrolls
    /// clear of the button instead of ending underneath it.
    static let plateButtonClearance: CGFloat = bigTap + 16
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

/// The type vocabulary: two styles, both SF condensed at a heavy weight and
/// both scaled by Dynamic Type through a text style. Everything else stays on
/// the stock text styles. Web twin of `figure`: `.load-numeral`.
extension Font {
    /// Loads, reps, totals, durations: the numbers a lifter reads from across
    /// the rack. Condensed black with fixed-width digits so a changing value
    /// never shifts its row.
    static func figure(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, weight: .black).width(.condensed).monospacedDigit()
    }

    /// The same figure at a hero size larger than `.largeTitle`. Pass a
    /// `@ScaledMetric(relativeTo:)` value, never a bare literal, or the figure
    /// stops following Dynamic Type.
    static func figure(scaled size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed).monospacedDigit()
    }

    /// Exercise, day and session names: condensed heavy, so a long lift name
    /// keeps one line and still reads as a heading.
    static func display(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, weight: .heavy).width(.condensed)
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
    static let emptyVolume = "No volume history"
    static let emptyRepPRs = "No rep PRs"
    static let shelved = "Shelved"
    static let noExercisesMatch = "No exercises match. Clear the filters or search by movement, equipment, or alias — or add a custom exercise."
}

extension View {
    /// Plain primary lists share the web canvas instead of inheriting an
    /// empty system-black background. Row controls keep their native styling.
    func themeListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    /// The one primary-action treatment: accent fill, the theme's own label
    /// colour, industrial corner. Web twin: `.btn.primary`. A site that needs
    /// a different fill still adds `.tint(...)` after it.
    func primaryActionStyle() -> some View {
        buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: Theme.cornerRadius))
            .foregroundStyle(Theme.onAccent)
    }

    func cardStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.hairline, lineWidth: 0.5)
            }
    }
}

/// The one mm:ss formatter for the app (web equivalent: ui.mmss).
func mmss(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
