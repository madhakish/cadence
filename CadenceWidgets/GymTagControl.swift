import SwiftUI
import WidgetKit
import AppIntents
import Foundation

/// Arrival-first Control Center / Lock Screen button. It opens the app and
/// hands RootView a direct route to the default membership tag.
@available(iOS 18.0, *)
struct GymTagControl: ControlWidget {
    static let kind = "com.madhakish.Cadence.GymTagControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            // A URL route crosses the widget/app process boundary reliably;
            // UserDefaults.standard is intentionally not shared by the two.
            ControlWidgetButton(action: OpenURLIntent(URL(string: "cadence://gym-tag")!)) {
                Label("Gym Tag", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Gym Tag")
        .description("Open your default gym membership barcode.")
    }
}
