import AppIntents
import Foundation

/// Opens Cadence directly into the default membership tag. The intent runs in
/// either the app or widget-extension process, so a tiny UserDefaults handoff
/// lets RootView consume the route after the app becomes active.
struct OpenGymTagIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Gym Tag"
    static var description = IntentDescription("Show the default gym membership barcode.")
    static var openAppWhenRun = true
    static let pendingKey = "openGymTagPending"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(true, forKey: Self.pendingKey)
        return .result(dialog: "Opening your gym tag.")
    }
}
