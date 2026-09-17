import SwiftUI
import SwiftData
import CadenceCore
import AudioToolbox
import UIKit

/// An attempt stays separate from the prefilled set until the athlete logs it.
/// Closing cancels the attempt; backgrounding keeps the deadline running.
struct HoldTimerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [AppSettings]
    @Bindable var set: SetEntry
    let exerciseName: String
    let onStatusChange: (SetStatus, SetStatus) -> Void

    @State private var clock: HoldClock.State?
    @State private var now = Date().timeIntervalSince1970
    @State private var confirmDiscard = false
    private let ticks = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private var running: Bool { clock != nil && clock?.stoppedEpoch == nil }
    private var elapsed: Int { clock.map { HoldClock.loggedSeconds($0, now: now) } ?? 0 }
    private var remaining: Int { clock.map { HoldClock.remaining($0, now: now) } ?? 0 }
    private var reachedTarget: Bool { clock != nil && remaining == 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(exerciseName).font(.title2.bold())
                    Text(running ? "HOLD" : (reachedTarget ? "HOLD COMPLETE" : "STOPPED"))
                        .font(.headline).foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("hold-timer-status")
                    Text(mmss(running ? remaining : elapsed))
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityLabel(running ? "Hold time remaining" : "Time held")
                        .accessibilityValue("\(running ? remaining : elapsed) seconds")
                        .accessibilityIdentifier("hold-timer-clock")
                    if let clock {
                        Text("Target \(CardioFormat.durationLabel(seconds: clock.targetSeconds))")
                            .foregroundStyle(.secondary)
                    }
                    if running {
                        Button("Stop hold") { stop() }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                            .accessibilityIdentifier("hold-timer-stop")
                    } else {
                        Button("Log \(CardioFormat.durationLabel(seconds: elapsed))") { log() }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                            .disabled(elapsed == 0)
                            .accessibilityIdentifier("hold-timer-log")
                        Button("Try again") { start() }.buttonStyle(.bordered)
                    }
                    Text("Log records this attempt and completes the set. Closing leaves the set unchanged.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(24)
            }
            .navigationTitle("Hold timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { confirmDiscard = true }
                }
            }
            .confirmationDialog("Discard this timed attempt?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard attempt", role: .destructive) { dismiss() }
                Button("Keep attempt", role: .cancel) { }
            }
        }
        .interactiveDismissDisabled()
        .onAppear { if clock == nil { start() } }
        .onDisappear { NotificationService.cancelHoldDone() }
        .onReceive(ticks) { _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func start() {
        now = Date().timeIntervalSince1970
        let target = min(1800, max(1, set.durationSeconds ?? set.plannedDurationSeconds ?? 30))
        clock = HoldClock.start(seconds: target, now: now)
        NotificationService.scheduleHoldDone(in: TimeInterval(target), exerciseName: exerciseName)
    }

    private func refresh() {
        now = Date().timeIntervalSince1970
        guard running, remaining == 0 else { return }
        stop()
        // A background notification already supplies its sound. On-screen,
        // give the athlete an audible cue without requiring a clock glance.
        if scenePhase == .active {
            AudioServicesPlaySystemSound(1005)
            if settingsList.first?.haptics != false {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            UIAccessibility.post(notification: .announcement, argument: "Hold complete")
        }
    }

    private func stop() {
        now = Date().timeIntervalSince1970
        if let clock { self.clock = HoldClock.stop(clock, now: now) }
        NotificationService.cancelHoldDone()
    }

    private func log() {
        guard !running, elapsed > 0 else { return }
        let previous = set.status
        set.durationSeconds = elapsed
        set.status = .completed
        guard PersistenceErrorCenter.shared.save(context, operation: "Logging the timed hold") else { return }
        onStatusChange(previous, .completed)
        dismiss()
    }
}
