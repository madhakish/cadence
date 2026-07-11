import SwiftUI
import SwiftData

struct RootView: View {
    @Binding var selection: Int
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPlateCalc = false
    @State private var restTimer = RestTimer()
    @State private var workoutClock = WorkoutClock()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selection) {
                HomeView()
                    .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
                    .tag(0)
                HistoryView()
                    .tabItem { Label("History", systemImage: "calendar") }
                    .tag(1)
                BodyView()
                    .tabItem { Label("Body", systemImage: "scalemass") }
                    .tag(2)
                InjuryTimelineView()
                    .tabItem { Label("Signals", systemImage: "bolt.heart") }
                    .tag(3)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(4)
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
        .environment(workoutClock)
        .task {
            _ = await NotificationService.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            // The user may have paused/resumed/extended/skipped the rest from
            // the Lock Screen / Action Button while we were backgrounded —
            // adopt the activity's state.
            if phase == .active { restTimer.reconcileFromActivity() }
        }
    }
}
