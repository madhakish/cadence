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
///
/// Version 10 adds the `intervals` collection (typed calendar spans: deload,
/// rest, away, active recovery) and the per-session-exercise `barIdManual`
/// marker (emitted only when true). Both are additive: a v≤9 bundle restores
/// with no intervals and every bar treated as stamped — exactly the pre-v10
/// behavior. Older importers reject a v10 bundle on the version gate, which
/// is correct: silently dropping a declared break would turn it back into an
/// apparent lapse after a restore.
public enum BackupContract {
    public static let currentSchemaVersion = 10

    public static func supports(schemaVersion: Int?) -> Bool {
        let version = schemaVersion ?? 0
        return version >= 0 && version <= currentSchemaVersion
    }

    /// One named entity as seen on either side of a restore preview: its
    /// store identity (`id`), the label the user reads (`name`), and a
    /// caller-built fingerprint of the remaining fields worth diffing. Callers
    /// own how `id` and `signature` are derived per collection — exercises and
    /// lift tracks key on their own name, gyms/sessions/programs key on a
    /// separate stable id — so this stays a generic id/name/signature
    /// comparison, not a parser.
    public struct NamedEntity: Equatable {
        public let id: String
        public let name: String
        public let signature: String

        public init(id: String, name: String, signature: String) {
            self.id = id
            self.name = name
            self.signature = signature
        }
    }

    public enum NamedEntityStatus: String, Equatable {
        case new, changed, unchanged, removed
    }

    public struct NamedEntityDiff: Equatable {
        public let name: String
        public let id: String
        public let status: NamedEntityStatus

        public init(name: String, id: String, status: NamedEntityStatus) {
            self.name = name
            self.id = id
            self.status = status
        }
    }

    /// Classifies each incoming entity against the current store's matching
    /// id: an id absent from the current store is new; a matching id whose
    /// name and signature both match is unchanged; anything else — a rename
    /// or any other field edit — is changed.
    ///
    /// `includeRemoved` decides whether a current id the bundle omits is
    /// reported as `removed`. Every collection's restore write clears the
    /// store and re-inserts only the bundle's records — so an omitted id is
    /// genuinely dropped — with one native exception: the native exercise
    /// importer upserts by name and never deletes, so a caller previewing
    /// that one path must pass `false` there rather than claim a removal the
    /// restore will not actually perform.
    public static func namedRestoreDiff(
        current: [NamedEntity], incoming: [NamedEntity], includeRemoved: Bool = true
    ) -> [NamedEntityDiff] {
        var byID: [String: NamedEntity] = [:]
        for entity in current { byID[entity.id] = entity }
        var matchedIDs: Set<String> = []
        var result = incoming.map { entity -> NamedEntityDiff in
            matchedIDs.insert(entity.id)
            guard let existing = byID[entity.id] else {
                return NamedEntityDiff(name: entity.name, id: entity.id, status: .new)
            }
            let unchanged = existing.name == entity.name && existing.signature == entity.signature
            return NamedEntityDiff(name: entity.name, id: entity.id, status: unchanged ? .unchanged : .changed)
        }
        guard includeRemoved else { return result }
        for entity in current where !matchedIDs.contains(entity.id) {
            result.append(NamedEntityDiff(name: entity.name, id: entity.id, status: .removed))
        }
        return result
    }

    /// Per-collection named restore diff for all five collections a restore
    /// preview names individually: exercises, lift tracks, gyms, sessions,
    /// and programs.
    public struct NamedRestorePreview: Equatable {
        public let exercises: [NamedEntityDiff]
        public let tracks: [NamedEntityDiff]
        public let gyms: [NamedEntityDiff]
        public let sessions: [NamedEntityDiff]
        public let programs: [NamedEntityDiff]

        public init(
            exercises: [NamedEntityDiff], tracks: [NamedEntityDiff], gyms: [NamedEntityDiff],
            sessions: [NamedEntityDiff], programs: [NamedEntityDiff]
        ) {
            self.exercises = exercises
            self.tracks = tracks
            self.gyms = gyms
            self.sessions = sessions
            self.programs = programs
        }

        /// True only when every classified item across all five collections
        /// is unchanged — the signal a restore UI uses to skip its
        /// destructive confirm gate entirely. A `removed` or `new`/`changed`
        /// entry both count as "not a no-op", same as before.
        public var isNoOp: Bool {
            [exercises, tracks, gyms, sessions, programs].allSatisfy { collection in
                collection.allSatisfy { $0.status == .unchanged }
            }
        }
    }

    public static func namedRestorePreview(
        currentExercises: [NamedEntity], incomingExercises: [NamedEntity],
        currentTracks: [NamedEntity], incomingTracks: [NamedEntity],
        currentGyms: [NamedEntity], incomingGyms: [NamedEntity],
        currentSessions: [NamedEntity], incomingSessions: [NamedEntity],
        currentPrograms: [NamedEntity], incomingPrograms: [NamedEntity],
        // The native exercise importer never deletes (see namedRestoreDiff);
        // every other caller leaves this at the default.
        includeRemovedExercises: Bool = true
    ) -> NamedRestorePreview {
        NamedRestorePreview(
            exercises: namedRestoreDiff(current: currentExercises, incoming: incomingExercises, includeRemoved: includeRemovedExercises),
            tracks: namedRestoreDiff(current: currentTracks, incoming: incomingTracks),
            gyms: namedRestoreDiff(current: currentGyms, incoming: incomingGyms),
            sessions: namedRestoreDiff(current: currentSessions, incoming: incomingSessions),
            programs: namedRestoreDiff(current: currentPrograms, incoming: incomingPrograms)
        )
    }
}
