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
/// gate runs before validation on both clients. Version 6 adds the per-set
/// `flights` count for conditioning measured in climbed floors; a v5 binary
/// reading it would silently drop the count, so the version gate has to stop
/// the bundle first.
public enum BackupContract {
    public static let currentSchemaVersion = 6

    public static func supports(schemaVersion: Int?) -> Bool {
        let version = schemaVersion ?? 0
        return version >= 0 && version <= currentSchemaVersion
    }
}
