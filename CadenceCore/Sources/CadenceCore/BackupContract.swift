/// Version boundary for the cross-platform JSON backup contract.
///
/// Version 0 is the unversioned legacy shape. Version 1 adds explicit session
/// completion state and canonical program tags. Version 2 adds stable program
/// and gym identifiers plus explicit per-set lifecycle state. Version 3
/// separates immutable prescriptions from performed work. Version 4 adds the
/// methodology prescription styles (linear fives, Texas day slots, 5/3/1,
/// max/dynamic effort) — older importers reject them cleanly by version.
/// Version 5 adds the AMRAP prescription block, the rep-PR milestone, and
/// reps-in-reserve set flags. Each is a new value in an enum the importer
/// validates against a whitelist, so a v5 bundle read by a v4 binary must fail
/// on the VERSION check rather than on the enum — which is why the version
/// gate runs before validation on both clients.
///
/// Version 6 retires protein logging: the `protein` array and
/// `settings.proteinTargetGrams` are gone, and `settings.birthYear` is added
/// for age-adjusted protein guidance. This is the first **lossy** version
/// boundary — a v≤5 bundle still imports, but its protein entries are dropped
/// on the way in because the store has nowhere to put them. Older importers
/// reject a v6 bundle on the version gate, as they should: it carries a field
/// they do not know and is missing one they expect.
///
/// Version 7 adds the per-set `flights` count for conditioning measured in
/// climbed floors. Additive and lossless — but a v6 binary would parse the
/// bundle happily and silently drop the count, which is data loss disguised as
/// a clean restore, so the version gate has to refuse it first.
///
/// Version 8 adds the per-exercise `stationDenomination` ("lb" / "kg",
/// optional) — the plate denomination a lift's station stocks, driving which
/// inventory the solver prescribes against. Additive and lossless — but a v7
/// binary would parse the bundle happily and silently drop the preference,
/// putting the lifter's kg deadlift station back on lb math after a restore,
/// so the version gate has to refuse it first.
///
/// Version 9 adds the program-level `equipmentPolicy` and per-day
/// `trainingIntent`. Both are additive, and older bundles restore with the
/// literal legacy values `any` and `general` respectively.
public enum BackupContract {
    public static let currentSchemaVersion = 9

    public static func supports(schemaVersion: Int?) -> Bool {
        let version = schemaVersion ?? 0
        return version >= 0 && version <= currentSchemaVersion
    }
}
