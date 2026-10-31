import CadenceCore
import Foundation
import XCTest

/// The phone's motion recordings (#336): outside SwiftData and the backup,
/// stored once per recording, exported as one zip. Synthetic data only.
final class MotionRecordingStoreTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func syntheticRecording(in folder: URL) throws -> (samples: URL, sidecar: Data, id: String) {
        var data = MotionRecording.header(sampleRate: 50)
        for i in 0..<100 {
            MotionRecording.append(MotionSample(t: Float(i) / 50, userAcceleration: SIMD3(0, 0, Float(i % 7)),
                                                rotationRate: .zero, gravity: SIMD3(0, -1, 0),
                                                attitude: SIMD4(0, 0, 0, 1)), to: &data)
        }
        let samples = folder.appendingPathComponent("incoming.cdmr")
        try data.write(to: samples)
        let id = UUID().uuidString
        let sidecar = MotionSidecar(recordingID: id, sessionID: "synthetic", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                    sampleRate: 50, device: .init(model: "Watch7,9", wristLocation: "left", crownOrientation: "right"),
                                    events: [MotionEvent(t: 1.5, kind: .setCompleted, setID: "s1", reps: 5, weightLb: 185)])
        return (samples, try JSONEncoder().encode(sidecar), id)
    }

    func testARecordingIsStoredOnceKeptOutOfTheBackupAndExported() throws {
        let workspace = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("MotionRecordings")
        let incoming = try syntheticRecording(in: workspace)

        XCTAssertEqual(try MotionRecordingStore.store(samplesAt: incoming.samples, sidecar: incoming.sidecar, root: root), incoming.id)
        XCTAssertEqual(try MotionRecordingStore.store(samplesAt: incoming.samples, sidecar: incoming.sidecar, root: root), incoming.id,
                       "a resend of a stored recording changes nothing")
        let listed = MotionRecordingStore.list(root: root)
        XCTAssertEqual(listed.map(\.recordingID), [incoming.id])
        XCTAssertEqual(listed.first?.events.first?.reps, 5)
        let stored = try Data(contentsOf: root.appendingPathComponent(incoming.id).appendingPathComponent("samples.cdmr"))
        XCTAssertEqual(try MotionRecording.read(stored).samples.count, 100)
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true,
                       "recordings are not part of the backup")

        let archive = try MotionRecordingStore.exportArchive(root: root)
        defer { try? FileManager.default.removeItem(at: archive) }
        let zip = try Data(contentsOf: archive)
        XCTAssertGreaterThan(zip.count, 100)
        XCTAssertEqual(Array(zip.prefix(2)), [0x50, 0x4B], "a zip archive (PK header)")
    }

    func testAnUnreadableSidecarIsRejected() throws {
        let workspace = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let incoming = try syntheticRecording(in: workspace)
        XCTAssertThrowsError(try MotionRecordingStore.store(samplesAt: incoming.samples, sidecar: Data("{}".utf8),
                                                            root: workspace.appendingPathComponent("r")))
    }
}
