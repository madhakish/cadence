import Foundation
import SwiftData

/// The process's **one** store, and the one ladder that opens it.
///
/// This used to live entirely inside `AppBootstrap`, which is a `@MainActor`
/// `ObservableObject` owned by the SwiftUI `App`. That was fine while only the
/// app touched SwiftData. It stopped being fine when the Lock Screen gained a
/// Done button: a `LiveActivityIntent` runs in the app's process but can be
/// relaunched into it with no scene, so there was no container to write to.
///
/// The obvious workaround — let the intent open its own container — is the one
/// thing this repository forbids outright. A second opening path can disagree
/// with the first about which migration applies, and its failure mode is
/// creating a fresh store beside the real one: the lifter's log silently
/// replaced by an empty one. So there is exactly one ladder, here, and both
/// callers memoise the same instance.
///
/// Sharing the *instance* also matters for correctness in the ordinary case:
/// `@Query` in the logger only observes changes made through the container it
/// was handed. Two containers over one file would leave the app showing a set
/// as planned after the Lock Screen completed it.
enum PersistenceStack {

    /// Guards `opened`. Intents can arrive off the main actor while the app is
    /// launching on it, and both racing to build a container over the same
    /// SQLite file is how you get two of them.
    private static let lock = NSLock()
    private static var opened: ModelContainer?

    /// The container, opening the store on first use.
    ///
    /// Deliberately does **not** seed. Seeding is the app launch path's job
    /// (`AppBootstrap.prepare`); a live workout already implies a seeded store,
    /// and running the seeder from a background button tap is work nobody asked
    /// for on a locked phone.
    static func container() throws -> ModelContainer {
        lock.lock()
        defer { lock.unlock() }
        if let opened { return opened }
        let container = try openUnlocked().container
        opened = container
        return container
    }

    /// The container if one is already open, without opening one.
    ///
    /// For callers that must not cause a store to be opened as a side effect —
    /// an intent firing while the app sits in the startup recovery screen has
    /// no business forcing the store it just failed to open.
    static var existing: ModelContainer? {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    /// Publish a container built elsewhere as the process's store.
    ///
    /// `AppBootstrap` uses this for the temporary in-memory recovery store, so
    /// that an intent firing during recovery writes to the same throwaway store
    /// the user is looking at rather than to the real one behind it.
    static func adopt(_ container: ModelContainer) {
        lock.lock()
        defer { lock.unlock() }
        opened = container
    }

    /// Every schema this app has shipped, in the order worth trying.
    ///
    /// V4 first: it is the checksum every install shipped since V4 became
    /// current carries, so it is the common case and the cheapest match. The
    /// inferred lightweight attempt stays last and stays non-destructive — it
    /// exists for checksums that are not one of the snapshots we know by name.
    static func openUnlocked() throws -> (container: ModelContainer, label: String) {
        let candidates: [(String, () throws -> ModelContainer)] = [
            ("V4 staged migration", { try makeContainer(migrationPlan: CadenceV4MigrationPlan.self) }),
            ("V3 staged migration", { try makeContainer(migrationPlan: CadenceV3MigrationPlan.self) }),
            ("pre-72 staged migration", { try makeContainer(migrationPlan: CadencePre72MigrationPlan.self) }),
            ("72 staged migration", { try makeContainer(migrationPlan: Cadence72MigrationPlan.self) }),
            // Builds before the schema repair changed the advertised V1
            // checksum in place. If an installed checksum is not one of the
            // snapshots we know by name, let Core Data infer the same additive
            // lightweight migration from the store metadata. This is
            // non-destructive and is deliberately the last attempt.
            ("inferred lightweight migration", { try makeUnplannedContainer() }),
        ]
        var failures: [String] = []
        for (label, open) in candidates {
            do {
                return (try open(), label)
            } catch {
                let nsError = error as NSError
                failures.append("\(label): \(nsError.domain) \(nsError.code)")
            }
        }
        throw OpenFailure(failures: failures)
    }

    /// No supported schema matched. Carries every attempt's failure so the
    /// recovery screen can say which ladders were tried rather than a shrug.
    struct OpenFailure: LocalizedError {
        let failures: [String]
        var errorDescription: String? {
            "Cadence could not match this store to a supported schema. "
                + failures.joined(separator: " · ")
        }
    }

    static func makeContainer<Plan: SchemaMigrationPlan>(
        migrationPlan: Plan.Type,
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV5.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: config
        )
    }

    static func makeUnplannedContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV5.self)
        let config = ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, migrationPlan: nil, configurations: config)
    }
}
