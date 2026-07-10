import ActivityKit
import AppIntents
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

/// The whole-rest range, so `Text(timerInterval:)` counts down to `endDate`
/// without depending on render-time "now".
private func restRange(_ state: RestActivityAttributes.ContentState) -> ClosedRange<Date> {
    let start = state.endDate.addingTimeInterval(-max(1, state.total))
    return start <= state.endDate ? start...state.endDate : state.endDate...state.endDate
}

struct RestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer").font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    restTimerText(context.state, font: .title3.monospacedDigit().bold())
                        .foregroundStyle(restAccent)
                }
                DynamicIslandExpandedRegion(.center) {
                    if !context.attributes.exerciseName.isEmpty {
                        Text(context.attributes.exerciseName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    controls(context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer").foregroundStyle(restAccent)
            } compactTrailing: {
                restTimerText(context.state, font: .caption.monospacedDigit().bold())
                    .foregroundStyle(restAccent)
                    .frame(minWidth: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(restAccent)
            }
            // Tapping the activity opens the app by default; no deep link handled.
        }
    }
}

private struct RestLockScreenView: View {
    let context: ActivityViewContext<RestActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(context.state.isPaused ? "Rest · paused" : "Rest", systemImage: "timer")
                    .font(.subheadline.bold())
                Spacer()
                restTimerText(context.state, font: .title.monospacedDigit().bold())
                    .foregroundStyle(restAccent)
            }
            if !context.attributes.exerciseName.isEmpty {
                Text(context.attributes.exerciseName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            controls(context.state)
        }
        .padding()
    }
}

/// The Pause/Resume · +0:30 · End button row, shared by the Lock Screen and the
/// expanded Dynamic Island.
@ViewBuilder
private func controls(_ state: RestActivityAttributes.ContentState) -> some View {
    HStack(spacing: 10) {
        if state.isPaused {
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

@ViewBuilder
private func restTimerText(_ state: RestActivityAttributes.ContentState, font: Font) -> some View {
    if state.isPaused {
        Text(mmssStatic(state.pausedRemaining)).font(font)
    } else {
        Text(timerInterval: restRange(state), countsDown: true).font(font).monospacedDigit()
    }
}
