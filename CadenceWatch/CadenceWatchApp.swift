import SwiftUI

@main
struct CadenceWatchApp: App {
    @StateObject private var model = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.recorder)
                .environmentObject(model.motion)
                .task { if !model.isFixture { WatchLink.shared.activate(model) } }
        }
    }
}
