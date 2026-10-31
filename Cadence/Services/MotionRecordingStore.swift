import CadenceCore
import Foundation

/// The phone's motion recordings (design #339, section 8): kept in the app's
/// container, outside SwiftData and outside the backup, until the owner exports
/// them. Real recordings are workout data and never leave the device otherwise.
enum MotionRecordingStore {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MotionRecordings", isDirectory: true)
    }

    enum StoreError: Error {
        case unreadableSidecar
    }

    /// Store a recording the watch transferred. Idempotent by recording ID: a
    /// resend of one already stored changes nothing. Returns the recording ID.
    /// Must run before the transfer callback returns; the system deletes the
    /// incoming file afterwards.
    @discardableResult
    static func store(samplesAt incoming: URL, sidecar data: Data, root: URL = root) throws -> String {
        guard let sidecar = try? JSONDecoder().decode(MotionSidecar.self, from: data),
              UUID(uuidString: sidecar.recordingID) != nil else { throw StoreError.unreadableSidecar }
        try prepare(root)
        let folder = root.appendingPathComponent(sidecar.recordingID, isDirectory: true)
        let samples = folder.appendingPathComponent("samples.cdmr")
        if FileManager.default.fileExists(atPath: samples.path) { return sidecar.recordingID }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: incoming, to: samples)
        try data.write(to: folder.appendingPathComponent("sidecar.json"), options: .atomic)
        return sidecar.recordingID
    }

    static func list(root: URL = root) -> [MotionSidecar] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("sidecar.json")) else { return nil }
            return try? JSONDecoder().decode(MotionSidecar.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    static func totalBytes(root: URL = root) -> Int {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let url = enumerator?.nextObject() as? URL {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    static func delete(recordingID: String, root: URL = root) throws {
        guard UUID(uuidString: recordingID) != nil else { return }
        let folder = root.appendingPathComponent(recordingID, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    static func deleteAll(root: URL = root) throws {
        for sidecar in list(root: root) { try delete(recordingID: sidecar.recordingID, root: root) }
        removeExports()
    }

    /// Exported zips are copies of real data in tmp: remove them once they are
    /// no longer being shared, and before making a new one.
    static func removeExports(in directory: URL = FileManager.default.temporaryDirectory) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("Cadence-motion-recordings-") && file.pathExtension == "zip" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// One zip of every recording, for the share sheet.
    static func exportArchive(root: URL = root, now: Date = Date()) throws -> URL {
        try prepare(root)
        removeExports()
        var coordinationError: NSError?
        var archive: URL?
        var copyError: Error?
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cadence-motion-recordings-\(stamp).zip")
        // `.forUploading` hands back a zip of the folder; copy it out before
        // the coordinator deletes it.
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zipped, to: destination)
                archive = destination
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return archive ?? destination
    }

    /// Create the folder and keep it out of iCloud and Finder backups.
    private static func prepare(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = root
        try url.setResourceValues(values)
    }
}
