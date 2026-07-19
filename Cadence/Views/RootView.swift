import SwiftUI
import SwiftData

struct RootView: View {
    private static let gymTagLastAutoDayKey = "gymTagLastAutoDay"

    @Binding var selection: Int
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [AppSettings]
    @Query private var gyms: [Gym]
    @State private var showPlateCalc = false
    @State private var showGymTag = false
    @State private var restTimer = RestTimer()
    @State private var workoutClock = WorkoutClock()
    @State private var pendingSessionID: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selection) {
                HomeView(pendingSessionID: $pendingSessionID)
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
        .fullScreenCover(isPresented: $showGymTag) {
            GymCardView(gym: gyms.first { $0.isDefault } ?? gyms.first)
        }
        .environment(restTimer)
        .environment(workoutClock)
        .task {
            openPendingGymTagIfNeeded()
            autoPresentGymTagIfNeeded()
        }
        .onOpenURL { url in
            guard url.scheme == "cadence" else { return }
            if url.host == "gym-tag" {
                showGymTag = true
            } else if url.host == "workout", let id = url.pathComponents.dropFirst().first, !id.isEmpty {
                selection = 0
                pendingSessionID = id
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The user may have paused/resumed/extended/skipped the rest from
            // the Lock Screen / Action Button while we were backgrounded —
            // adopt the activity's state.
            if phase == .active {
                restTimer.reconcileFromActivity()
                openPendingGymTagIfNeeded()
                autoPresentGymTagIfNeeded()
            }
        }
    }

    private func openPendingGymTagIfNeeded() {
        guard UserDefaults.standard.bool(forKey: OpenGymTagIntent.pendingKey) else { return }
        UserDefaults.standard.set(false, forKey: OpenGymTagIntent.pendingKey)
        showGymTag = true
    }

    private func autoPresentGymTagIfNeeded() {
        guard settingsList.first?.gymTagFirstLaunchOfDay == true,
              gyms.contains(where: { $0.barcodeImageData != nil }) else { return }
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: Self.gymTagLastAutoDayKey) != day else { return }
        defaults.set(day, forKey: Self.gymTagLastAutoDayKey)
        showGymTag = true
    }
}
