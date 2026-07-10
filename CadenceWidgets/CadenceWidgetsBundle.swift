import WidgetKit
import SwiftUI

/// The extension's entry point. Only the rest Live Activity for now — no Home
/// Screen widgets.
@main
struct CadenceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestActivityWidget()
    }
}
