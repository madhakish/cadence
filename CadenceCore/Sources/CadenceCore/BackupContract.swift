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
public enum BackupContract {
    public static let currentSchemaVersion = 6

    public static func supports(schemaVersion: Int?) -> Bool {
        let version = schemaVersion ?? 0
        return version >= 0 && version <= currentSchemaVersion
    }
}
