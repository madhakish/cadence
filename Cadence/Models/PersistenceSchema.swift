import SwiftData

/// Current persistence schema. V3 through V8 are frozen in their own files;
/// every V9 field has a literal migration-safe default and needs no backfill.
///
/// V9 adds `Program.equipmentPolicyRaw` and
/// `ProgramDay.trainingIntentRaw`. `any` and `general` reproduce every V8
/// program exactly, so the migration is additive and lossless.
enum CadenceSchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(9, 0, 0)

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
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self]
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
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
        ]
    }
}

/// Migration path for a fresh store first created by the broken #72 build.
/// That build advertised V1 while writing a different model checksum.
enum Cadence72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV2.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self,
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self]
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
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
        ]
    }
}

/// Normal path for an install already upgraded by PR #73.
enum CadenceV3MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self,
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self]
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
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
        ]
    }
}

/// Path for a store already on V4 — an install that skipped the protein
/// retirement and arrives here two versions behind.
enum CadenceV4MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV4.self, CadenceSchemaV5.self, CadenceSchemaV6.self,
         CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self]
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
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
        ]
    }
}

/// Path for a store already on V5 — every install shipped since protein
/// logging was retired. `flights` is a new optional with no historical value to
/// recover, so SwiftData can add the column without touching a row.
enum CadenceV5MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV5.self, CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self,
         CadenceSchemaV9.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV5.self,
                         toVersion: CadenceSchemaV6.self),
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
        ]
    }
}

/// Path for a store already on V6 — every install shipped since conditioning
/// learned to count flights. `verticalPullMainsPromoted` is a new Bool with a
/// literal default, so SwiftData can add the column without touching a row.
enum CadenceV6MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
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
        [CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
        ]
    }
}

/// Common upgrade path for a store already on V8. The two V9 policy columns
/// carry literal legacy defaults, so SwiftData can add them without rewriting
/// any authored program or day.
enum CadenceV8MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV8.self, CadenceSchemaV9.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
        ]
    }
}
