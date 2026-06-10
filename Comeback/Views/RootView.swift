import SwiftUI
import SwiftData

struct RootView: View {
    @State private var showPlateCalc = false
    @State private var restTimer = RestTimer()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                HomeView()
                    .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "calendar") }
                BodyView()
                    .tabItem { Label("Body", systemImage: "scalemass") }
                InjuryTimelineView()
                    .tabItem { Label("Signals", systemImage: "bolt.heart") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }

            // Plate math is one tap from anywhere. Non-negotiable.
            Button {
                showPlateCalc = true
            } label: {
                Image(systemName: "circle.circle.fill")
                    .font(.title)
                    .frame(width: Theme.bigTap, height: Theme.bigTap)
                    .background(Theme.accent.gradient, in: Circle())
                    .foregroundStyle(.black)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 64)
            .accessibilityLabel("Plate calculator")
        }
        .sheet(isPresented: $showPlateCalc) {
            NavigationStack { PlateCalculatorView() }
        }
        .environment(restTimer)
        .task {
            _ = await NotificationService.requestAuthorization()
        }
    }
}
