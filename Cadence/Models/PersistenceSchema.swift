import SwiftData

/// Current persistence schema. V3, V4, V5, V6, and V7 are frozen in their own
/// files; every V8 field has a literal migration-safe default and needs no
/// backfill.
///
/// V8 adds `Exercise.stationDenominationRaw`, the per-lift station plate
/// preference: the deadlift station that stocks only kg plates solves against
/// the kg inventory while the squat racks keep the gym's lb plates, configured
/// once on the exercise the same way it already carries its own rest default.
/// It is a new optional String with a `nil` default and no historical value to
/// recover — `nil` means "use the gym inventory", which is exactly what every
/// existing exercise did before the field existed — so the migration is
/// additive and lossless.
enum CadenceSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)

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
        [CadenceSchemaV1.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self,
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self]
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
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
        ]
    }
}

/// Migration path for a fresh store first created by the broken #72 build.
/// That build advertised V1 while writing a different model checksum.
enum Cadence72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV2.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self,
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self]
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
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
        ]
    }
}

/// Normal path for an install already upgraded by PR #73.
enum CadenceV3MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self,
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV3.self,
                         toVersion: CadenceSchemaV4.self),
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
        ]
    }
}

/// Path for a store already on V4 — an install that skipped the protein
/// retirement and arrives here two versions behind.
enum CadenceV4MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV4.self, CadenceSchemaV5.self, CadenceSchemaV6.self,
         CadenceSchemaV7.self, CadenceSchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV4.self,
                         toVersion: CadenceSchemaV5.self),
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
        ]
    }
}

/// Path for a store already on V5 — every install shipped since protein
/// logging was retired. `flights` is a new optional with no historical value to
/// recover, so SwiftData can add the column without touching a row.
enum CadenceV5MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV5.self, CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
        ]
    }
}

/// Path for a store already on V6 — every install shipped since conditioning
/// learned to count flights. `verticalPullMainsPromoted` is a new Bool with a
/// literal default, so SwiftData can add the column without touching a row.
enum CadenceV6MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
        ]
    }
}

/// Path for a store already on V7 — every install shipped since vertical
/// pulling was promoted to main work, which is the common case for this
/// upgrade. `stationDenominationRaw` is a new optional with a `nil` default
/// and no historical value to recover, so SwiftData can add the column
/// without touching a row.
enum CadenceV7MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV7.self, CadenceSchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
        ]
    }
}
