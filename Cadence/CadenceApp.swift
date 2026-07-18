import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for:
                Exercise.self,
                WorkoutSession.self,
                SessionExercise.self,
                SetEntry.self,
                LiftTrack.self,
                BodyweightEntry.self,
                ProteinEntry.self,
                CheckIn.self,
                Milestone.self,
                Gym.self,
                AppSettings.self,
                Program.self,
                ProgramDay.self,
                ProgramLift.self,
                ProgramAccessory.self
            )
            try Seeder.seedIfNeeded(context: container.mainContext)
            try Seeder.syncLibrary(context: container.mainContext) // top up the library on already-seeded installs
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .background else { return }
                    do { try BackupCheckpointService.create(context: container.mainContext, reason: "background") }
                    catch { BackupCheckpointService.recordFailure(error) }
                }
        }
        .modelContainer(container)
    }
}

/// Reads the persisted theme, mirrors it into `Theme.name`, and applies the
/// tint + colour scheme app-wide. The tab selection is hoisted ABOVE the
/// `.id(theme)` refresh so switching themes (from Settings) rebuilds the tree
/// with the new palette without bouncing you back to the first tab.
struct ThemedRoot: View {
    @Query private var settings: [AppSettings]
    @State private var tab = 0
    @StateObject private var persistenceErrors = PersistenceErrorCenter.shared

    private var theme: ThemeName {
        ThemeName(rawValue: settings.first?.themeNameRaw ?? "carbon") ?? .carbon
    }

    var body: some View {
        Theme.name = theme // keep the static mirror current for every read this render
        return RootView(selection: $tab)
            .tint(Theme.accent)
            .preferredColorScheme(theme.colorScheme)
            .id(theme)
            .alert("Couldn't save", isPresented: Binding(
                get: { persistenceErrors.message != nil },
                set: { if !$0 { persistenceErrors.message = nil } }
            )) {
                Button("OK") { persistenceErrors.message = nil }
            } message: {
                Text(persistenceErrors.message ?? "")
            }
    }
}
