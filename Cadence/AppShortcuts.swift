import AppIntents

/// Surfaces the rest control to the system: the Action Button (set it to this
/// shortcut in Settings → Action Button), Spotlight, and Siri. One shortcut,
/// one thumb: start rest for the current lift, or skip the one running —
/// the deliberate alternative to hijacking the volume buttons.
struct CadenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRestIntent(),
            phrases: [
                "Start rest in \(.applicationName)",
                "Skip rest in \(.applicationName)",
                "\(.applicationName) rest"
            ],
            shortTitle: "Rest timer",
            systemImageName: "timer"
        )
    }
}
