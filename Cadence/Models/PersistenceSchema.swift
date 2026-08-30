import SwiftData

/// Current persistence schema. V3 through V11 are frozen in their own files;
/// every V12 change is a brand-new model or a nil-valued optional on old
/// rows, and needs no backfill.
///
/// V12 adds the `ActivityDetail` model (typed, kind-discriminated metadata
/// for ad-hoc activity sessions — wood splitting first) and its optional
/// one-to-one relationship from `WorkoutSession`; every existing session
/// simply carries nil.
enum CadenceSchemaV12: VersionedSchema {
    static var versionIdentifier = Schema.Version(12, 0, 0)

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
            TrainingInterval.self,
            ActivityDetail.self,
        ]
    }
}

/// Migration path for stores created before PR #72 changed the V1 model in
/// place. SwiftData migration plans are linear, so this historical checksum
/// needs its own path to the current schema.
enum CadencePre72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV1.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self,
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self,
         CadenceSchemaV10.self, CadenceSchemaV11.self, CadenceSchemaV12.self]
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
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// Migration path for a fresh store first created by the broken #72 build.
/// That build advertised V1 while writing a different model checksum.
enum Cadence72MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV2.self, CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self,
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self,
         CadenceSchemaV10.self, CadenceSchemaV11.self, CadenceSchemaV12.self]
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
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// Normal path for an install already upgraded by PR #73.
enum CadenceV3MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV3.self, CadenceSchemaV4.self, CadenceSchemaV5.self,
         CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self,
         CadenceSchemaV10.self, CadenceSchemaV11.self, CadenceSchemaV12.self]
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
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// Path for a store already on V4 — an install that skipped the protein
/// retirement and arrives here two versions behind.
enum CadenceV4MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV4.self, CadenceSchemaV5.self, CadenceSchemaV6.self,
         CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self,
         CadenceSchemaV10.self, CadenceSchemaV11.self, CadenceSchemaV12.self]
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
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// Path for a store already on V5 — every install shipped since protein
/// logging was retired. `flights` is a new optional with no historical value to
/// recover, so SwiftData can add the column without touching a row.
enum CadenceV5MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV5.self, CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self,
         CadenceSchemaV9.self, CadenceSchemaV10.self, CadenceSchemaV11.self, CadenceSchemaV12.self]
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
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// Path for a store already on V6 — every install shipped since conditioning
/// learned to count flights. `verticalPullMainsPromoted` is a new Bool with a
/// literal default, so SwiftData can add the column without touching a row.
enum CadenceV6MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV6.self, CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self,
         CadenceSchemaV10.self, CadenceSchemaV11.self, CadenceSchemaV12.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV6.self,
                         toVersion: CadenceSchemaV7.self),
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// Path for a store already on V7 — every install shipped since vertical
/// pulling was promoted to main work. `stationDenominationRaw` is a new
/// optional with a `nil` default and no historical value to recover, so
/// SwiftData can add the column without touching a row.
enum CadenceV7MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV7.self, CadenceSchemaV8.self, CadenceSchemaV9.self, CadenceSchemaV10.self,
         CadenceSchemaV11.self, CadenceSchemaV12.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV7.self,
                         toVersion: CadenceSchemaV8.self),
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// Path for a store already on V8. The two V9 policy columns carry literal
/// legacy defaults, so SwiftData can add them without rewriting any authored
/// program or day.
enum CadenceV8MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV8.self, CadenceSchemaV9.self, CadenceSchemaV10.self,
         CadenceSchemaV11.self, CadenceSchemaV12.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV8.self,
                         toVersion: CadenceSchemaV9.self),
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// Common upgrade path for a store already on V9 — every install shipped
/// since programs gained explicit intent and equipment policy. V10 adds a
/// brand-new model (`TrainingInterval`, which old rows never reference) and
/// one Bool column with a literal `false` default, so SwiftData can upgrade
/// without touching a row.
enum CadenceV9MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV9.self, CadenceSchemaV10.self, CadenceSchemaV11.self, CadenceSchemaV12.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV9.self,
                         toVersion: CadenceSchemaV10.self),
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// V10 -> V11 (epic #155 Stage 2): stable portable identity. Every new
/// column is an optional (or the V10 rows simply lack it), so SwiftData can
/// upgrade without touching a row; the idempotent Seeder repairs derive the
/// deterministic legacy ids after open.
enum CadenceV10MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV10.self, CadenceSchemaV11.self, CadenceSchemaV12.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV10.self,
                         toVersion: CadenceSchemaV11.self),
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}

/// V11 -> V12: ad-hoc activity sessions (wood splitting first). V12 adds
/// only the brand-new `ActivityDetail` model and an optional to-one
/// relationship on `WorkoutSession` that every existing row leaves nil, so
/// SwiftData can upgrade without touching a row.
enum CadenceV11MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CadenceSchemaV11.self, CadenceSchemaV12.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CadenceSchemaV11.self,
                         toVersion: CadenceSchemaV12.self),
        ]
    }
}
