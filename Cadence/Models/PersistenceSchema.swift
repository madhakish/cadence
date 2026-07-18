import SwiftData

/// Explicit persistence baseline. Future model changes add a new version and
/// migration stage instead of asking SwiftData to infer the app's history.
enum CadenceSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
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
            ProgramAccessory.self,
        ]
    }
}

enum CadenceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CadenceSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
