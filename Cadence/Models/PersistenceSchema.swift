import SwiftData

/// Current persistence schema. V3 and V4 are frozen in their own files; every
/// V5 field has a literal migration-safe default and is backfilled after
/// opening where historical values can be recovered.
///
/// V5 removes `ProteinEntry` and `AppSettings.proteinTargetGrams`, and adds
/// `AppSettings.birthYear`. Dropping an entity is a **destructive** change:
/// logged protein servings do not survive the upgrade and cannot be recovered
/// from a V5 backup either. That is the intended outcome — serving-level
/// logging only works with a real meal-entry surface, so the half-measure is
/// retired rather than left as a tracker nobody completes — but it is why this
/// ships as a SemVer major.
enum CadenceSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetEntry.self,
            LiftTrack.self,
            BodyweightEntry.self,
            CheckIn.self,
            Milestone.self,
            Gym.self,
            AppSettings.self,
            Program.self,
            ProgramDay.self,
            ProgramLift.self,
            ProgramAccessory.self,
            CoachingDecision.self,
        ]
    }
}

/// Migration path for stores created before PR #72 changed the V1 model in
/// place. SwiftData migration plans are linear, so this historical checksum
/// needs its own path to the current schema.
enum CadencePre72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV1.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV1.self,
                         toVersion: CadenceSchemaV3.self),
            .lightweight(fromVersion: CadenceSchemaV3.self,
                         toVersion: CadenceSchemaV4.self),
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
        ]
    }
}

/// Migration path for a fresh store first created by the broken #72 build.
/// That build advertised V1 while writing a different model checksum.
enum Cadence72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV2.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV2.self,
                         toVersion: CadenceSchemaV3.self),
            .lightweight(fromVersion: CadenceSchemaV3.self,
                         toVersion: CadenceSchemaV4.self),
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
        ]
    }
}

/// Normal path for an install already upgraded by PR #73.
enum CadenceV3MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV3.self,
                         toVersion: CadenceSchemaV4.self),
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
        ]
    }
}

/// Path for a store already on V4 — every install shipped since V4 became the
/// current schema, which is the common case for this upgrade.
enum CadenceV4MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV4.self, CadenceSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
        ]
    }
}
