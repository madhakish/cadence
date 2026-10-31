import CadenceCore
import CoreMotion
import Foundation
import WatchKit

/// Records wrist motion during a watch session (design #339, section 8): device
/// motion at 50 Hz into the `MotionRecording` format, plus a sidecar of session
/// events and device metadata. Recordings wait in the app's container until the
/// phone acknowledges them. On by default, with an off switch.
@MainActor
final class MotionRecorder: ObservableObject {
    static let enabledKey = "motionRecordingEnabled"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published private(set) var isRecording = false
    /// The recording still being written, which must not be sent yet.
    var activeRecordingID: String? { isRecording ? directory?.lastPathComponent : nil }

    private let manager = CMMotionManager()
    private var writer: MotionFileWriter?
    private var sidecar: MotionSidecar?
    private var directory: URL?
    /// `CMDeviceMotion.timestamp` and `systemUptime` share this clock.
    private var startUptime: TimeInterval = 0
    /// Each one-second batch of live samples, for set detection (phase 5).
    var onSamples: (([MotionSample]) -> Void)?

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MotionRecordings", isDirectory: true)
    }

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start(sessionID: String) {
        guard isEnabled, !isRecording, manager.isDeviceMotionAvailable else { return }
        let id = UUID().uuidString
        let directory = Self.root.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let writer = try MotionFileWriter(url: directory.appendingPathComponent("samples.cdmr"),
                                              sampleRate: MotionRecording.defaultSampleRate)
            let device = WKInterfaceDevice.current()
            sidecar = MotionSidecar(
                recordingID: id, sessionID: sessionID, startedAt: Date(),
                sampleRate: MotionRecording.defaultSampleRate,
                device: .init(model: Self.machineIdentifier(),
                              wristLocation: device.wristLocation == .left ? "left" : "right",
                              crownOrientation: device.crownOrientation == .left ? "left" : "right"))
            writer.onBatch = { [weak self] batch in
                Task { @MainActor in self?.onSamples?(batch) }
            }
            self.writer = writer
            self.directory = directory
            startUptime = ProcessInfo.processInfo.systemUptime
            writer.startUptime = startUptime
            manager.deviceMotionUpdateInterval = 1 / MotionRecording.defaultSampleRate
            manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: writer.queue) { motion, _ in
                guard let motion else { return }
                writer.record(motion)
            }
            isRecording = true
            writeSidecar()
        } catch {
            stopUpdates()
        }
    }

    /// A session event, on the samples' clock.
    func note(_ kind: MotionEvent.Kind, setID: String? = nil, exerciseID: String? = nil, exerciseName: String? = nil,
              reps: Int? = nil, weightLb: Double? = nil, isWarmup: Bool? = nil) {
        guard isRecording else { return }
        let t = ProcessInfo.processInfo.systemUptime - startUptime
        sidecar?.events.append(MotionEvent(t: t, kind: kind, setID: setID, exerciseID: exerciseID,
                                           exerciseName: exerciseName, reps: reps, weightLb: weightLb,
                                           isWarmup: isWarmup))
        writeSidecar()
    }

    /// Ends the recording and returns its folder, ready to send to the phone.
    func stop() -> URL? {
        guard isRecording, let directory else { return nil }
        stopUpdates()
        writeSidecar()
        self.directory = nil
        sidecar = nil
        return directory
    }

    /// Finished recordings the phone has not acknowledged yet.
    static func pending() -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("sidecar.json").path) }
    }

    /// The phone stored it: the watch's copy goes.
    static func discard(recordingID: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(recordingID, isDirectory: true))
    }

    private func stopUpdates() {
        manager.stopDeviceMotionUpdates()
        writer?.close()
        writer = nil
        isRecording = false
    }

    private func writeSidecar() {
        guard let sidecar, let directory, let data = try? JSONEncoder().encode(sidecar) else { return }
        try? data.write(to: directory.appendingPathComponent("sidecar.json"), options: .atomic)
    }

    private static func machineIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Appends samples off the main thread, flushing in blocks so a long session
/// costs little battery and a suspension loses at most a second of motion.
final class MotionFileWriter: @unchecked Sendable {
    let queue: OperationQueue
    var startUptime: TimeInterval = 0
    /// Called on `queue` with each flushed block of samples.
    var onBatch: (([MotionSample]) -> Void)?
    private let handle: FileHandle
    private var buffer = Data()
    private var batch: [MotionSample] = []

    init(url: URL, sampleRate: Double) throws {
        FileManager.default.createFile(atPath: url.path, contents: MotionRecording.header(sampleRate: sampleRate))
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
    }

    /// Called on `queue` only.
    func record(_ motion: CMDeviceMotion) {
        let a = motion.userAcceleration, r = motion.rotationRate, g = motion.gravity, q = motion.attitude.quaternion
        let sample = MotionSample(
            t: Float(motion.timestamp - startUptime),
            userAcceleration: SIMD3(Float(a.x), Float(a.y), Float(a.z)),
            rotationRate: SIMD3(Float(r.x), Float(r.y), Float(r.z)),
            gravity: SIMD3(Float(g.x), Float(g.y), Float(g.z)),
            attitude: SIMD4(Float(q.x), Float(q.y), Float(q.z), Float(q.w)))
        MotionRecording.append(sample, to: &buffer)
        batch.append(sample)
        if buffer.count >= MotionRecording.bytesPerSample * 50 { flush() }
    }

    func close() {
        queue.addOperation { [self] in
            flush()
            try? handle.close()
        }
        queue.waitUntilAllOperationsAreFinished()
    }

    private func flush() {
        guard !buffer.isEmpty else { return }
        try? handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
        if !batch.isEmpty { onBatch?(batch) }
        batch.removeAll(keepingCapacity: true)
    }
}
