/// Version boundary for the cross-platform JSON backup contract.
///
/// Version 0 is the unversioned legacy shape. Version 1 adds explicit session
/// completion state and canonical program tags. Version 2 adds stable program
/// and gym identifiers plus explicit per-set lifecycle state.
public enum BackupContract {
    public static let currentSchemaVersion = 3

    public static func supports(schemaVersion: Int?) -> Bool {
        let version = schemaVersion ?? 0
        return version >= 0 && version <= currentSchemaVersion
    }
}
