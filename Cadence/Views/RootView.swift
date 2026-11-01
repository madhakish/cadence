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
    @Query(filter: #Predicate<WorkoutSession> { !$0.isCompleted })
    private var openSessions: [WorkoutSession]
    /// Bumped to rebuild Today from its root: the stack pops and the list
    /// starts at the top, without HomeView growing a path model for it.
    @State private var todayRoot = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            tabs

            // Plate math is one tap from anywhere. Non-negotiable. The button
            // floats in a band each tab's root list and the active session
            // reserve (see plateCalculatorClearance), so it never covers a
            // control.
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
        .onReceive(NotificationCenter.default.publisher(for: .watchRestChanged)) { note in
            guard let change = note.object as? RestTimer.Change else { return }
            restTimer.adopt(change.state, exerciseName: change.exerciseName)
        }
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

    // Tags are unchanged (Today is still 0, Body 3) so launch, deep links and
    // tests keep their meaning; only the visual order moved Today to the
    // middle, under the gorilla. The mark is drawn ~12% taller than the SF
    // Symbols beside it (GorillaMark is a 30 pt template) so it is easy to
    // mash; the system item supplies the Liquid Glass look, the 44 pt+ hit
    // area and the large content viewer.
    @ViewBuilder private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: tabSelection) {
                Tab("Program", systemImage: "list.bullet.clipboard", value: 1) { ProgramOverviewView() }
                Tab("History", systemImage: "calendar", value: 2) { HistoryView() }
                Tab(value: 0) { today } label: { Label("Today", image: "GorillaMark") }
                    .accessibilityHint("Returns to today's workout")
                Tab("Body", systemImage: "scalemass", value: 3) { BodyView(pendingSignals: $pendingSignals) }
                Tab("Settings", systemImage: "gearshape", value: 4) { SettingsView() }
            }
        } else {
            TabView(selection: tabSelection) {
                ProgramOverviewView()
                    .tabItem { Label("Program", systemImage: "list.bullet.clipboard") }
                    .tag(1)
                HistoryView()
                    .tabItem { Label("History", systemImage: "calendar") }
                    .tag(2)
                today
                    .tabItem { Label("Today", image: "GorillaMark") }
                    .tag(0)
                BodyView(pendingSignals: $pendingSignals)
                    .tabItem { Label("Body", systemImage: "scalemass") }
                    .tag(3)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(4)
            }
        }
    }

    private var today: some View {
        HomeView(pendingSessionID: $pendingSessionID).id(todayRoot)
    }

    /// The tab bar writes through here on every tap, including a tap on the
    /// tab that is already selected, which is how Today hears a second tap.
    /// Programmatic changes (deep links) assign `selection` directly and skip
    /// this, so a widget opening a workout is not second-guessed.
    private var tabSelection: Binding<Int> {
        Binding(get: { selection }, set: { tapped in
            if tapped == 0 { returnToToday() } else { selection = tapped }
        })
    }

    /// Today "drops back to the main screen and what you're doing": a workout
    /// being timed reopens its live session through the same path as the
    /// cadence://workout link; otherwise Today rebuilds from its root.
    private func returnToToday() {
        selection = 0
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { todayRoot += 1 }
        if let live = liveSessionID { pendingSessionID = live }
    }

    /// The open session whose workout clock is running. The durable clock
    /// record is the authority (it survives a relaunch before the session
    /// screen re-adopts it). A session opened only to read the plan is not in
    /// progress, and neither is a watch session waiting for review.
    private var liveSessionID: String? {
        guard let record = WorkoutClockPersistence.load() else { return nil }
        return openSessions.first {
            $0.id == record.sessionID && $0.syncReviewReasonRaw == nil
        }?.id
    }
}

extension View {
    /// Reserve an opaque band for the floating plate-calculator button, so
    /// intermediate rows cannot show through beneath it. Apply it to scroll content
    /// inside a NavigationStack: the same inset placed on the tab root,
    /// outside the stack, never reached the Settings form on device
    /// (#196), because the UIKit-backed stack manages its own safe area.
    @MainActor func plateCalculatorClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Theme.background
                .frame(height: Theme.plateButtonClearance)
        }
    }
}
