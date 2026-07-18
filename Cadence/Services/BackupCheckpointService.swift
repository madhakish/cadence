import Foundation
import SwiftData

/// Small rotating, on-device recovery history. Checkpoints can undo a valid
/// but unwanted import/reset; they are deliberately separate from the portable
/// JSON export and disappear if the app itself is deleted.
enum BackupCheckpointService {
    static let lastSuccessKey = "backupCheckpointLastSuccess"
    static let lastFailureKey = "backupCheckpointLastFailure"
    private static let keepCount = 3

    @discardableResult
    static func create(context: ModelContext, reason: String = "automatic") throws -> URL {
        try context.save()
        let data = try ExportService.jsonData(context: context)
        let directory = try checkpointDirectory()
        let milliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        let url = directory.appendingPathComponent("cadence-checkpoint-\(milliseconds)-\(reason)-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        try prune()
        let stamp = ISO8601DateFormatter().string(from: .now)
        UserDefaults.standard.set(stamp, forKey: lastSuccessKey)
        UserDefaults.standard.removeObject(forKey: lastFailureKey)
        return url
    }

    static func latestData() throws -> Data? {
        guard let url = try checkpointURLs().first else { return nil }
        return try Data(contentsOf: url)
    }

    static func recordFailure(_ error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: lastFailureKey)
    }

    private static func checkpointDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = base.appendingPathComponent("Cadence/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func checkpointURLs() throws -> [URL] {
        let directory = try checkpointDirectory()
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("cadence-checkpoint-") && $0.pathExtension == "json" }
        .sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    private static func prune() throws {
        for url in try checkpointURLs().dropFirst(keepCount) { try FileManager.default.removeItem(at: url) }
    }
}
