import AppIntents
import SwiftUI
import WidgetKit

/// iOS 18 Control Center / Lock Screen / Action Button control: one button
/// that arms the current lift's rest or skips the one running (the deliberate
/// alternative to hijacking the volume buttons). The button fires
/// `ToggleRestIntent` — a `LiveActivityIntent`, so it runs in the app's
/// process and can drive the workout activity from the background.
@available(iOS 18.0, *)
struct RestControl: ControlWidget {
    static let kind = "com.madhakish.Cadence.RestControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleRestIntent()) {
                Label("Rest timer", systemImage: "timer")
            }
        }
        .displayName("Rest timer")
        .description("Start rest for the current lift, or skip the rest that's running.")
    }
}
