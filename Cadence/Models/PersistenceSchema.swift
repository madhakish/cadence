import SwiftData

/// Current persistence schema. Never edit an older schema in place: shipped
/// stores identify it by both version and checksum.
enum CadenceSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

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
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV1.self, CadenceSchemaV2.self, CadenceSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            // Two V1 checksums shipped: pre-#72 and #72's mutated model. Each
            // migrates directly to the safe final shape; neither must pass
            // through the other's incompatible WorkoutSession.id definition.
            .lightweight(fromVersion: CadenceSchemaV1.self,
                         toVersion: CadenceSchemaV3.self),
            .lightweight(fromVersion: CadenceSchemaV2.self,
                         toVersion: CadenceSchemaV3.self),
        ]
    }
}
