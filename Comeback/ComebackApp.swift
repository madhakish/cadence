import SwiftUI
import SwiftData

@main
struct ComebackApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for:
                Exercise.self,
                WorkoutSession.self,
                SessionExercise.self,
                SetEntry.self,
                LiftTrack.self,
                BodyweightEntry.self,
                ProteinEntry.self,
                CheckIn.self,
                Milestone.self,
                Gym.self,
                AppSettings.self,
                Program.self,
                ProgramDay.self,
                ProgramLift.self,
                ProgramAccessory.self
            )
            Seeder.seedIfNeeded(context: container.mainContext)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
