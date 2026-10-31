import Foundation

// Wrist-motion recordings from watch sessions (design: docs/superpowers/specs/
// 2026-10-18-apple-watch-design.md, section 8). One recording per session: a
// compact binary file of device-motion samples plus a JSON sidecar of session
// events and device metadata. The watch writes them, the phone stores and
// exports them, and the phase-4 evaluation reads them.
//
// Swift-only by owner decision (like WatchSync.swift). Real recordings are
// workout and health data: they stay on the owner's devices unless exported,
// and are never committed or posted. Tests use synthetic samples only.

/// One device-motion reading (CoreMotion `CMDeviceMotion`), in its units:
/// user acceleration in g, rotation rate in rad/s, gravity in g, attitude as a
/// unit quaternion.
public struct MotionSample: Equatable, Sendable {
    /// Seconds since the recording started.
    public var t: Float
    public var userAcceleration: SIMD3<Float>
    public var rotationRate: SIMD3<Float>
    public var gravity: SIMD3<Float>
    public var attitude: SIMD4<Float>

    public init(t: Float, userAcceleration: SIMD3<Float>, rotationRate: SIMD3<Float>, gravity: SIMD3<Float>,
                attitude: SIMD4<Float>) {
        self.t = t
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.attitude = attitude
    }
}

public enum MotionRecording {
    /// File signature and layout version.
    public static let magic: [UInt8] = Array("CDMR".utf8)
    public static let version: UInt8 = 1
    /// Floats per sample: t, acceleration xyz, rotation xyz, gravity xyz, attitude xyzw.
    public static let floatsPerSample = 14
    public static var bytesPerSample: Int { floatsPerSample * MemoryLayout<Float32>.size }
    /// The design's default rate; enough for reps of roughly 0.2–1.5 Hz.
    public static let defaultSampleRate = 50.0

    /// Header: magic, version, three padding bytes, sample rate (Float64).
    public static func header(sampleRate: Double) -> Data {
        var data = Data(magic)
        data.append(contentsOf: [version, 0, 0, 0])
        withUnsafeBytes(of: sampleRate.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    public static let headerSize = 16

    /// One sample as little-endian Float32s, appended to `data`.
    public static func append(_ sample: MotionSample, to data: inout Data) {
        let values: [Float] = [
            sample.t,
            sample.userAcceleration.x, sample.userAcceleration.y, sample.userAcceleration.z,
            sample.rotationRate.x, sample.rotationRate.y, sample.rotationRate.z,
            sample.gravity.x, sample.gravity.y, sample.gravity.z,
            sample.attitude.x, sample.attitude.y, sample.attitude.z, sample.attitude.w,
        ]
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
    }

    public enum ReadError: Error, Equatable {
        case notARecording
        case unsupportedVersion(UInt8)
    }

    /// Parse a recording. A trailing partial sample (a write cut off when the
    /// app was suspended) is ignored rather than failing the whole file.
    public static func read(_ data: Data) throws -> (sampleRate: Double, samples: [MotionSample]) {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize, Array(bytes[0..<4]) == magic else { throw ReadError.notARecording }
        guard bytes[4] == version else { throw ReadError.unsupportedVersion(bytes[4]) }
        func uint64(at offset: Int) -> UInt64 {
            (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
        }
        func float(at offset: Int) -> Float {
            Float(bitPattern: (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) })
        }
        let rate = Double(bitPattern: uint64(at: 8))
        let count = (bytes.count - headerSize) / bytesPerSample
        var samples: [MotionSample] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            let base = headerSize + i * bytesPerSample
            let v = (0..<floatsPerSample).map { float(at: base + $0 * 4) }
            samples.append(MotionSample(t: v[0], userAcceleration: SIMD3(v[1], v[2], v[3]),
                                        rotationRate: SIMD3(v[4], v[5], v[6]), gravity: SIMD3(v[7], v[8], v[9]),
                                        attitude: SIMD4(v[10], v[11], v[12], v[13])))
        }
        return (rate, samples)
    }
}

/// What happened during a recording, so a labelled set can be cut from the
/// motion stream: the Done tap marks set end; the previous rest's end or the
/// focus change bounds the start (design section 8).
public struct MotionEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case setCompleted, setSkipped, setEdited, restStarted, restEnded, focusChanged, autoLogged
    }

    /// Seconds since the recording started, on the samples' clock.
    public var t: Double
    public var kind: Kind
    public var setID: String?
    public var exerciseID: String?
    /// The exercise's display name, so evaluation tables read as lifts.
    public var exerciseName: String?
    public var reps: Int?
    public var weightLb: Double?
    public var isWarmup: Bool?

    public init(t: Double, kind: Kind, setID: String? = nil, exerciseID: String? = nil, exerciseName: String? = nil,
                reps: Int? = nil, weightLb: Double? = nil, isWarmup: Bool? = nil) {
        self.t = t
        self.kind = kind
        self.setID = setID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.reps = reps
        self.weightLb = weightLb
        self.isWarmup = isWarmup
    }
}

/// The JSON written next to each recording.
public struct MotionSidecar: Codable, Hashable, Sendable {
    public struct Device: Codable, Hashable, Sendable {
        /// e.g. "Watch7,9"
        public var model: String
        /// "left" or "right": the sign of the signal depends on it.
        public var wristLocation: String
        /// "left" or "right" side of the case.
        public var crownOrientation: String

        public init(model: String, wristLocation: String, crownOrientation: String) {
            self.model = model
            self.wristLocation = wristLocation
            self.crownOrientation = crownOrientation
        }
    }

    public var recordingID: String
    public var sessionID: String
    public var startedAt: Date
    public var sampleRate: Double
    public var device: Device
    public var events: [MotionEvent]

    public init(recordingID: String, sessionID: String, startedAt: Date, sampleRate: Double, device: Device,
                events: [MotionEvent] = []) {
        self.recordingID = recordingID
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.sampleRate = sampleRate
        self.device = device
        self.events = events
    }

    /// Each completed set's window on the recording clock: from the latest
    /// rest end or focus change before it (or the recording start) to its
    /// Done tap. This is the labelled data phase 4 trains and scores on.
    public func labelledSets() -> [(event: MotionEvent, start: Double, end: Double)] {
        var boundary = 0.0
        var out: [(event: MotionEvent, start: Double, end: Double)] = []
        for event in events.sorted(by: { $0.t < $1.t }) {
            switch event.kind {
            case .restEnded, .focusChanged:
                boundary = event.t
            case .setCompleted:
                out.append((event, boundary, event.t))
                boundary = event.t
            default:
                break
            }
        }
        return out
    }
}
