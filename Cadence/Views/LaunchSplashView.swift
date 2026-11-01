import SwiftUI
import UIKit

/// The cold open. iOS shows the static launch screen (LaunchMark centred on
/// LaunchBackground, see project.yml) while the process starts; this overlay
/// takes over on exactly that frame, sets "CADENCE" under the gorilla, burns
/// a fuse along it and gets out of the way. 1.2 s, once per process.
///
/// It is an overlay on whatever the scene shows, never a gate: the store opens
/// and RootView mounts underneath it, so its `.task` work and the gym tag's
/// full-screen cover (presented above this view) never wait on it. A tap ends
/// it, and a deep link or the gym tag opening skips the rest of it.
enum LaunchSplash {
    // The beats, in seconds from the first frame.
    static let wordIn = 0.0...0.28        // wordmark fades and rises into place
    static let burn = 0.16...0.86         // spark travels left to right
    static let pop = 0.86...1.0           // flash at the end of the fuse
    static let fadeOut = 0.95...1.2       // the whole overlay dissolves
    static var duration: Double { fadeOut.upperBound }

    // Reduce Motion: no spark, no travel, only opacity.
    static let calmWordIn = 0.0...0.2
    static let calmFadeOut = 0.5...0.8

    /// Point size of the mark; LaunchMark's pixels are rendered for it
    /// (docs/design-pass/launch/render_launch_mark.py, MARK_PT).
    static let markSize: CGFloat = 220

    /// Decided once per process, at the first scene's first render.
    @MainActor static let playsThisLaunch = decide(ProcessInfo.processInfo.arguments)
    /// Latched when the splash appears, so a scene that returns from the
    /// background, or one the system rebuilds later, never replays it.
    @MainActor static var played = false
    @MainActor static var shouldShow: Bool { playsThisLaunch && !played }

    @MainActor static func decide(_ arguments: [String]) -> Bool {
#if DEBUG
        if frozenFrame(arguments) != nil { return true }
#endif
        // Screenshot and accessibility suites launch the app dozens of times;
        // they get the app, not the show.
        if arguments.contains("--visual-proof") { return false }
        // VoiceOver: nothing to announce and nothing to trap a double-tap.
        if UIAccessibility.isVoiceOverRunning { return false }
        // The gym-tag intent can run before the scene exists. The tag wins.
        if UserDefaults.standard.bool(forKey: OpenGymTagIntent.pendingKey) { return false }
        return true
    }

#if DEBUG
    /// `--launch-splash-frame=<seconds>` pins the animation at one instant so
    /// the visual-proof suite can photograph it frame by frame.
    static func frozenFrame(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Double? {
        arguments.lazy.compactMap { arg -> Double? in
            guard arg.hasPrefix("--launch-splash-frame=") else { return nil }
            return Double(arg.dropFirst("--launch-splash-frame=".count))
        }.first
    }
#endif
}

extension View {
    /// Plays the cold open over this view on a cold launch.
    func launchSplash() -> some View { modifier(LaunchSplashModifier()) }
}

private struct LaunchSplashModifier: ViewModifier {
    @State private var showing = LaunchSplash.shouldShow
    /// RootView stamps this key when it auto-presents the gym tag; a change
    /// while the splash runs means the tag is on its way up.
    @State private var gymTagDayAtStart = UserDefaults.standard.double(forKey: RootView.gymTagLastAutoDayKey)

    func body(content: Content) -> some View {
        content
            .overlay {
                if showing {
                    LaunchSplashView { showing = false }
                }
            }
            // Observes only: RootView's own handler still routes the URL.
            .onOpenURL { _ in showing = false }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)) { _ in
                guard showing else { return }
                let defaults = UserDefaults.standard
                if defaults.bool(forKey: OpenGymTagIntent.pendingKey)
                    || defaults.double(forKey: RootView.gymTagLastAutoDayKey) != gymTagDayAtStart {
                    showing = false
                }
            }
    }
}

struct LaunchSplashView: View {
    var finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var start: Date?

    // The splash cannot know the theme before the store opens, and the launch
    // screen it continues cannot know it at all, so it commits to Foundry's
    // palette: its canvas is LaunchBackground, its fire is Foundry's accent.
    private let ember = ThemeName.carbon.palette.accent
    private static let chalk = Color(red: 238 / 255, green: 234 / 255, blue: 226 / 255)
    private static let wordSize: CGFloat = 34
    private static let tracking: CGFloat = 11
    private static let overhang: CGFloat = 48

    private var reduceMotion: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--launch-splash-reduce-motion") { return true }
#endif
        return systemReduceMotion
    }

    var body: some View {
        TimelineView(.animation(paused: frozen != nil)) { timeline in
            let t = elapsed(at: timeline.date)
            frame(at: t)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .accessibilityHidden(true)
        .task {
            LaunchSplash.played = true
            guard frozen == nil else { return }
            let begin = Date()
            start = begin
            let end = reduceMotion ? LaunchSplash.calmFadeOut.upperBound : LaunchSplash.duration
            // A tap or a deep link removes the view and cancels this task;
            // a cancelled sleep throws, so no stray haptic after a skip.
            do {
                if !reduceMotion {
                    try await Task.sleep(for: .seconds(LaunchSplash.pop.lowerBound))
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
                }
                try await Task.sleep(for: .seconds(end - Date().timeIntervalSince(begin)))
            } catch { return }
            finish()
        }
    }

    private var frozen: Double? {
#if DEBUG
        LaunchSplash.frozenFrame()
#else
        nil
#endif
    }

    private func elapsed(at date: Date) -> Double {
        if let frozen { return frozen }
        guard let start else { return 0 }
        return max(0, date.timeIntervalSince(start))
    }

    private func frame(at t: Double) -> some View {
        let calm = reduceMotion
        let wordIn = progress(t, calm ? LaunchSplash.calmWordIn : LaunchSplash.wordIn)
        let fade = progress(t, calm ? LaunchSplash.calmFadeOut : LaunchSplash.fadeOut)
        let rise = calm ? 0 : (1 - easeOut(wordIn)) * 10
        return ZStack {
            Color("LaunchBackground")
            // Natural size, dead centre: the same pixels in the same place as
            // the launch screen, so the hand-off has nothing to jump.
            Image("LaunchMark")
            VStack(spacing: 10) {
                Text("CADENCE")
                    .font(.system(size: Self.wordSize, weight: .black).width(.condensed))
                    .tracking(Self.tracking)
                    // Tracking trails the last glyph; pad the front to match.
                    .padding(.leading, Self.tracking)
                    .foregroundStyle(Self.chalk)
                    .fixedSize()
                    .opacity(easeOut(wordIn))
                    .offset(y: rise)
                    .overlay(alignment: .bottom) {
                        // Canvas clips to its bounds, and the pop and the sparks
                        // fly past the wordmark: overhang so they are not sliced.
                        Canvas { context, size in
                            drawFuse(in: &context, size: size, t: t, calm: calm,
                                     inset: Self.tracking / 2 + Self.overhang)
                        }
                        .frame(height: 2 * Self.overhang)
                        .padding(.horizontal, -Self.overhang)
                        .offset(y: 10 + Self.overhang) // line sits 10 pt under the glyphs
                    }
            }
            .offset(y: LaunchSplash.markSize / 2 + 38)
        }
        .opacity(1 - easeIn(fade))
    }

    // MARK: - The fuse

    private func drawFuse(in context: inout GraphicsContext, size: CGSize, t: Double, calm: Bool, inset: CGFloat) {
        let y = size.height / 2
        let x0 = inset, x1 = size.width - inset
        let length = x1 - x0
        let cord = Color(red: 0.24, green: 0.25, blue: 0.27)
        let hot = Color(red: 1, green: 0.62, blue: 0.24)
        let whiteHot = Color(red: 1, green: 0.96, blue: 0.88)

        func line(_ a: CGFloat, _ b: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: a, y: y))
            p.addLine(to: CGPoint(x: b, y: y))
            return p
        }

        if calm {
            // Reduce Motion: the burnt line, already cold, fading in with the name.
            let appear = easeOut(progress(t, LaunchSplash.calmWordIn))
            context.stroke(line(x0, x1), with: .color(Self.chalk.opacity(0.85 * appear)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            return
        }

        // The cord fades in with the wordmark, then burns at a steady rate.
        let cordIn = easeOut(progress(t, 0.08...0.22))
        let burned = progress(t, LaunchSplash.burn)
        let tip = x0 + length * burned
        let popT = progress(t, LaunchSplash.pop)
        let popping = t >= LaunchSplash.pop.lowerBound

        if tip < x1 {
            context.stroke(line(tip, x1), with: .color(cord.opacity(cordIn)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        guard t >= LaunchSplash.burn.lowerBound else { return }

        // Burnt trail: cold chalk behind, glowing through oxide and orange to
        // white at the tip. After the pop the heat drains out of it.
        let heat = popping ? 70 * (1 - popT) : 70.0
        let trail = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: Self.chalk.opacity(0.85), location: 0),
                .init(color: ember, location: 0.45),
                .init(color: hot, location: 0.8),
                .init(color: whiteHot, location: 1),
            ]),
            startPoint: CGPoint(x: tip - max(heat, 0.01), y: y),
            endPoint: CGPoint(x: tip, y: y))
        context.stroke(line(x0, tip), with: popping && heat < 1 ? .color(Self.chalk.opacity(0.85)) : trail,
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Additive glow under the hot end of the trail.
        context.drawLayer { glow in
            glow.blendMode = .plusLighter
            glow.addFilter(.blur(radius: 4))
            glow.stroke(line(max(x0, tip - heat * 0.6), tip), with: .color(ember.opacity(0.8)),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }

        context.drawLayer { fire in
            fire.blendMode = .plusLighter

            // Sparks shed along the burn: deterministic, so a frozen proof
            // frame is the same every run.
            for i in 0..<Self.sparkCount {
                let seed = Double(i)
                let born = LaunchSplash.burn.lowerBound + (seed + 0.5 + 0.6 * (rand(seed, 1) - 0.5))
                    / Double(Self.sparkCount) * (LaunchSplash.burn.upperBound - LaunchSplash.burn.lowerBound)
                let life = 0.16 + 0.14 * rand(seed, 2)
                let age = t - born
                guard age >= 0, age <= life else { continue }
                let origin = x0 + length * progress(born, LaunchSplash.burn)
                drawSpark(in: &fire, from: CGPoint(x: origin, y: y), age: age, life: life,
                          angle: .pi * (1.08 + 0.75 * rand(seed, 3)), speed: 70 + 90 * rand(seed, 4),
                          hot: hot, whiteHot: whiteHot)
            }

            // The pop: a short radial burst off the end of the fuse.
            if popping {
                for i in 0..<Self.burstCount {
                    let seed = 100 + Double(i)
                    let life = 0.12 + 0.08 * rand(seed, 2)
                    let age = t - LaunchSplash.pop.lowerBound
                    guard age <= life else { continue }
                    let angle = 2 * Double.pi * (Double(i) + rand(seed, 3) * 0.6) / Double(Self.burstCount)
                    drawSpark(in: &fire, from: CGPoint(x: x1, y: y), age: age, life: life, angle: angle,
                              speed: 120 + 110 * rand(seed, 4), hot: hot, whiteHot: whiteHot)
                }
            }

            if !popping && burned > 0 {
                // The ember at the tip, flickering a little.
                let flicker = 1 + 0.18 * sin(t * 97) * sin(t * 61 + 1)
                glowDot(in: &fire, at: CGPoint(x: tip, y: y), radius: 13 * flicker, color: ember, opacity: 0.75)
                glowDot(in: &fire, at: CGPoint(x: tip, y: y), radius: 6 * flicker, color: hot, opacity: 0.9)
                glowDot(in: &fire, at: CGPoint(x: tip, y: y), radius: 2.6, color: whiteHot, opacity: 1)
            } else if popping {
                // Flash: a white core and a wide horizontal flare, both gone in 140 ms.
                let fall = (1 - popT) * (1 - popT)
                let r = 6 + 34 * easeOut(popT)
                glowDot(in: &fire, at: CGPoint(x: x1, y: y), radius: r, color: ember, opacity: 0.8 * fall)
                glowDot(in: &fire, at: CGPoint(x: x1, y: y), radius: r * 0.45, color: whiteHot, opacity: fall)
                let flare = CGRect(x: x1 - r * 1.8, y: y - 1.5, width: r * 3.6, height: 3)
                fire.fill(Path(ellipseIn: flare), with: .color(whiteHot.opacity(0.9 * fall)))
            }
        }
    }

    private static let sparkCount = 22
    private static let burstCount = 12

    private func drawSpark(in context: inout GraphicsContext, from origin: CGPoint, age: Double, life: Double,
                           angle: Double, speed: Double, hot: Color, whiteHot: Color) {
        let gravity = 420.0
        let vx = cos(angle) * speed, vy = sin(angle) * speed
        func at(_ a: Double) -> CGPoint {
            CGPoint(x: origin.x + vx * a, y: origin.y + vy * a + 0.5 * gravity * a * a)
        }
        let k = age / life
        var streak = Path()
        streak.move(to: at(max(0, age - 0.025)))
        streak.addLine(to: at(age))
        let color = k < 0.35 ? whiteHot : (k < 0.7 ? hot : ember)
        context.stroke(streak, with: .color(color.opacity(1 - k * k)),
                       style: StrokeStyle(lineWidth: 1.4 * (1 - 0.5 * k), lineCap: .round))
    }

    private func glowDot(in context: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
            center: p, startRadius: 0, endRadius: radius))
    }

    // MARK: - Arithmetic

    private func progress(_ t: Double, _ range: ClosedRange<Double>) -> Double {
        min(1, max(0, (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    private func easeOut(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }
    private func easeIn(_ x: Double) -> Double { x * x }

    /// Cheap deterministic noise in 0..<1.
    private func rand(_ seed: Double, _ salt: Double) -> Double {
        let v = sin(seed * 12.9898 + salt * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }
}
