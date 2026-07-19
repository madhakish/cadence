import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            if let container = bootstrap.container {
                ThemedRoot()
                    .modelContainer(container)
                    .onChange(of: scenePhase) { _, phase in
                        guard phase == .background, !bootstrap.isTemporary else { return }
                        do { try BackupCheckpointService.create(context: container.mainContext, reason: "background") }
                        catch { BackupCheckpointService.recordFailure(error) }
                    }
            } else {
                StartupRecoveryView(bootstrap: bootstrap)
            }
        }
    }
}

@MainActor
final class AppBootstrap: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isTemporary = false

    init() { loadPersistentStore() }

    func loadPersistentStore() {
        container = nil
        errorMessage = nil
        isTemporary = false
        do {
            let schema = Schema(versionedSchema: CadenceSchemaV2.self)
            let config = ModelConfiguration(schema: schema)
            let loaded = try ModelContainer(for: schema, migrationPlan: CadenceMigrationPlan.self,
                                            configurations: config)
            try prepare(loaded)
            container = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openTemporaryStore() {
        do {
            let schema = Schema(versionedSchema: CadenceSchemaV2.self)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let loaded = try ModelContainer(for: schema, migrationPlan: CadenceMigrationPlan.self,
                                            configurations: config)
            try prepare(loaded)
            isTemporary = true
            container = loaded
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepare(_ container: ModelContainer) throws {
        try Seeder.seedIfNeeded(context: container.mainContext)
        try Seeder.syncLibrary(context: container.mainContext)
    }
}

private struct StartupRecoveryView: View {
    @ObservedObject var bootstrap: AppBootstrap

    var body: some View {
        ContentUnavailableView {
            Label("Cadence couldn't open your training data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Your store was not deleted. Retry first; a temporary session is available if you need the app at the gym, but it will not persist.")
        } actions: {
            Button("Retry", action: bootstrap.loadPersistentStore)
                .buttonStyle(.borderedProminent)
            Button("Open temporary session", action: bootstrap.openTemporaryStore)
                .buttonStyle(.bordered)
            if let message = bootstrap.errorMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding()
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
