import SwiftData

/// Current persistence schema. V3, V4, and V5 are frozen in their own files;
/// every V6 field has a literal migration-safe default and is backfilled after
/// opening where historical values can be recovered.
///
/// V6 adds `SetEntry.flights`, the count for conditioning a machine measures in
/// climbed floors rather than ground covered. It is a new optional with no
/// historical value to recover, so the migration is additive and lossless: an
/// upgraded store gains an empty column and every conditioning set keeps the
/// distance it was logged with.
enum CadenceSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

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
        [CadenceSchemaV1.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self, CadenceSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV1.self,
                         toVersion: CadenceSchemaV3.self),
            .lightweight(fromVersion: CadenceSchemaV3.self,
                         toVersion: CadenceSchemaV4.self),
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
        ]
    }
}

/// Migration path for a fresh store first created by the broken #72 build.
/// That build advertised V1 while writing a different model checksum.
enum Cadence72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV2.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self, CadenceSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV2.self,
                         toVersion: CadenceSchemaV3.self),
            .lightweight(fromVersion: CadenceSchemaV3.self,
                         toVersion: CadenceSchemaV4.self),
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
        ]
    }
}

/// Normal path for an install already upgraded by PR #73.
enum CadenceV3MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self, CadenceSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV3.self,
                         toVersion: CadenceSchemaV4.self),
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
        ]
    }
}

/// Path for a store already on V4 — an install that skipped the protein
/// retirement and arrives here two versions behind.
enum CadenceV4MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV4.self, CadenceSchemaV5.self, CadenceSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
        ]
    }
}

/// Path for a store already on V5 — every install shipped since protein
/// logging was retired, which is the common case for this upgrade. `flights` is
/// a new optional with no historical value to recover, so SwiftData can add the
/// column without touching a row.
enum CadenceV5MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV5.self, CadenceSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
        ]
    }
}
