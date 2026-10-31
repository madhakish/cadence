import SwiftUI

@main
struct CadenceWatchApp: App {
    @StateObject private var model = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.recorder)
                .task { if !model.isFixture { WatchLink.shared.activate(model) } }
        }
    }
}
