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

/// Migration path for stores created before PR #72 changed the V1 model in
/// place. SwiftData migration plans are linear, so this historical checksum
/// needs its own path to the current schema.
enum CadencePre72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV1.self, CadenceSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV1.self,
                         toVersion: CadenceSchemaV3.self),
        ]
    }
}

/// Migration path for a fresh store first created by the broken #72 build.
/// That build advertised V1 while writing a different model checksum.
enum Cadence72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV2.self, CadenceSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV2.self,
                         toVersion: CadenceSchemaV3.self),
        ]
    }
}
