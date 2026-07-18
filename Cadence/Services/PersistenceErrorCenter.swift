import SwiftUI
import SwiftData

/// One app-wide error surface for user-initiated SwiftData writes. Views make
/// their optimistic mutation, then call `save`; a failure rolls the context
/// back and the root presents an actionable alert instead of pretending the
/// edit stuck.
@MainActor
final class PersistenceErrorCenter: ObservableObject {
    static let shared = PersistenceErrorCenter()

    @Published var message: String?

    private init() {}

    @discardableResult
    func save(_ context: ModelContext, operation: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            report(error, operation: operation, context: context)
            return false
        }
    }

    func report(_ error: Error, operation: String, context: ModelContext? = nil) {
        context?.rollback()
        message = "\(operation) failed. Cadence rolled back that change. Try again; if it keeps failing, export a JSON backup before restarting the app.\n\n\(error.localizedDescription)"
    }
}

extension View {
    func saveChangesOnDisappear(_ context: ModelContext, operation: String) -> some View {
        onDisappear { PersistenceErrorCenter.shared.save(context, operation: operation) }
    }
}
