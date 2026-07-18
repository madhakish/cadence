import WidgetKit
import SwiftUI

/// The extension's entry point: the workout Live Activity, plus (iOS 18) the
/// Control Center rest control. No Home Screen widgets.
@main
struct CadenceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutActivityWidget()
        if #available(iOS 18.0, *) {
            RestControl()
            GymTagControl()
        }
    }
}
