import ActivityKit
import AppIntents
import CadenceCore
import SwiftUI
import WidgetKit

/// Carbon-red accent on the system's dark activity chrome. The activity runs in
/// its own process and can't read the app's selected theme, so it uses a fixed
/// accent (the Carbon default); the countdown reads as red either way.
private let restAccent = Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)

private func mmssStatic(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// The whole-rest range, so `Text(timerInterval:)` counts down to the end
/// without depending on render-time "now".
private func restRange(_ rest: RestClock.State) -> ClosedRange<Date> {
    let end = Date(timeIntervalSince1970: rest.endEpoch)
    let start = end.addingTimeInterval(-max(1, rest.total))
    return start <= end ? start...end : end...end
}

/// One Live Activity, two faces: the session stopwatch (elapsed count-up +
/// current lift) that swaps to the rest countdown + controls while a rest is
/// running. Which face shows is decided per-render from `state.rest`.
struct WorkoutActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.rest == nil ? "Workout" : "Rest",
                          systemImage: context.state.rest == nil ? "stopwatch" : "timer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let rest = context.state.rest {
                        restTimerText(rest, font: .title3.monospacedDigit().bold())
                            .foregroundStyle(restAccent)
                    } else {
                        elapsedText(context.attributes.startDate, font: .title3.monospacedDigit().bold())
                            .foregroundStyle(.primary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if !context.state.currentLift.isEmpty {
                        Text(context.state.currentLift).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let rest = context.state.rest {
                        restControls(rest)
                    } else {
                        startRestButton(context.state)
                    }
                }
            } compactLeading: {
                if let rest = context.state.rest {
                    Image(systemName: rest.paused ? "pause.fill" : "timer").foregroundStyle(restAccent)
                } else {
                    Image(systemName: "stopwatch").foregroundStyle(.secondary)
                }
            } compactTrailing: {
                if let rest = context.state.rest {
                    restTimerText(rest, font: .caption.monospacedDigit().bold())
                        .foregroundStyle(restAccent)
                        .frame(minWidth: 44)
                } else {
                    elapsedText(context.attributes.startDate, font: .caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44)
                }
            } minimal: {
                Image(systemName: context.state.rest == nil ? "stopwatch" : "timer")
                    .foregroundStyle(context.state.rest == nil ? .secondary : restAccent)
            }
            // Tapping the activity opens the app by default; no deep link handled.
        }
    }
}

private struct WorkoutLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let rest = context.state.rest {
                HStack {
                    Label(rest.paused ? "Rest · paused" : "Rest", systemImage: "timer")
                        .font(.subheadline.bold())
                    Spacer()
                    restTimerText(rest, font: .title.monospacedDigit().bold())
                        .foregroundStyle(restAccent)
                }
                if !context.state.currentLift.isEmpty {
                    Text(context.state.currentLift).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                restControls(rest)
            } else {
                HStack {
                    Label("Workout", systemImage: "stopwatch")
                        .font(.subheadline.bold())
                    Spacer()
                    elapsedText(context.attributes.startDate, font: .title.monospacedDigit().bold())
                }
                HStack {
                    if !context.state.currentLift.isEmpty {
                        Text(context.state.currentLift).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    startRestButton(context.state)
                }
            }
        }
        .padding()
    }
}

/// The session stopwatch, counting up from the workout's start.
@ViewBuilder
private func elapsedText(_ startDate: Date, font: Font) -> some View {
    Text(startDate, style: .timer)
        .font(font)
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
}

/// The Pause/Resume · +0:30 · End button row, shared by the Lock Screen and the
/// expanded Dynamic Island.
@ViewBuilder
private func restControls(_ rest: RestClock.State) -> some View {
    HStack(spacing: 10) {
        if rest.paused {
            Button(intent: ResumeRestIntent()) { Label("Resume", systemImage: "play.fill") }
        } else {
            Button(intent: PauseRestIntent()) { Label("Pause", systemImage: "pause.fill") }
        }
        Button(intent: AddRestTimeIntent()) { Label("0:30", systemImage: "goforward.30") }
        Button(intent: EndRestIntent()) { Label("End", systemImage: "xmark") }
            .tint(.secondary)
    }
    .font(.caption.bold())
    .buttonStyle(.bordered)
    .tint(restAccent)
}

/// The elapsed face's one action: arm the current lift's default rest.
@ViewBuilder
private func startRestButton(_ state: WorkoutActivityAttributes.ContentState) -> some View {
    Button(intent: ToggleRestIntent()) {
        Label(state.defaultRestSeconds > 0 ? "Rest \(mmssStatic(TimeInterval(state.defaultRestSeconds)))" : "Rest",
              systemImage: "timer")
    }
    .font(.caption.bold())
    .buttonStyle(.bordered)
    .tint(restAccent)
}

@ViewBuilder
private func restTimerText(_ rest: RestClock.State, font: Font) -> some View {
    if rest.paused {
        Text(mmssStatic(rest.pausedRemaining)).font(font)
    } else {
        Text(timerInterval: restRange(rest), countsDown: true).font(font).monospacedDigit()
    }
}
