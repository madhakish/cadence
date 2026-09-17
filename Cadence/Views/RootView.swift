import SwiftUI
import SwiftData

struct RootView: View {
    /// Shared with HomeView's @AppStorage — two independent spellings of
    /// this key would silently fork the shown-today marker between the
    /// auto-present path and the prominent/compact styling.
    static let gymTagLastAutoDayKey = "gymTagLastAutoDay"

    @Binding var selection: Int
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [AppSettings]
    @Query private var gyms: [Gym]
    @State private var showPlateCalc = false
    @State private var showGymTag = false
    @State private var restTimer = RestTimer()
    @State private var workoutClock = WorkoutClock()
    @State private var pendingSessionID: String?
    @State private var pendingSignals = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selection) {
                HomeView(pendingSessionID: $pendingSessionID)
                    .plateCalculatorClearance()
                    .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
                    .tag(0)
                ProgramOverviewView()
                    .plateCalculatorClearance()
                    .tabItem { Label("Program", systemImage: "list.bullet.clipboard") }
                    .tag(1)
                HistoryView()
                    .plateCalculatorClearance()
                    .tabItem { Label("History", systemImage: "calendar") }
                    .tag(2)
                BodyView(pendingSignals: $pendingSignals)
                    .plateCalculatorClearance()
                    .tabItem { Label("Body", systemImage: "scalemass") }
                    .tag(3)
                SettingsView()
                    .plateCalculatorClearance()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(4)
            }

            // Plate math is one tap from anywhere. Non-negotiable. The button
            // floats in a band every tab root has already reserved (see
            // plateCalculatorClearance), so it never covers a control.
            Button {
                showPlateCalc = true
            } label: {
                Image(systemName: "circle.circle.fill")
                    .font(.title)
                    .frame(width: Theme.bigTap, height: Theme.bigTap)
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(Theme.onAccent)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 64)
            .accessibilityLabel("Plate calculator")
            .accessibilityIdentifier("plate-calculator-button")
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
            await NotificationService.cancelOrphanedHoldAlerts()
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
            } else if url.host == "signals" {
                // The link used to land ON the Signals screen; selecting the
                // tab that merely contains it would strip a navigation level
                // from every existing shortcut.
                selection = 3
                pendingSignals = true
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

extension View {
    /// Reserve the band the floating plate-calculator button occupies, so a
    /// tab's lists and forms scroll clear of it. Applied once at each tab
    /// root; every screen pushed inside that tab inherits the inset, which
    /// is what keeps this a layout rule rather than per-screen padding.
    func plateCalculatorClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: Theme.plateButtonClearance)
                .allowsHitTesting(false)
        }
    }
}
