import XCTest
@testable import CadenceCore

/// Recording format (#336). Synthetic samples only: real recordings are
/// workout and health data and never enter the repository.
final class MotionRecordingTests: XCTestCase {
    private func sample(_ i: Int) -> MotionSample {
        let t = Float(i) / 50
        return MotionSample(t: t, userAcceleration: SIMD3(sin(t), cos(t), -0.5),
                            rotationRate: SIMD3(0.1, -0.2, Float(i)), gravity: SIMD3(0, -1, 0),
                            attitude: SIMD4(0, 0, 0.7071, 0.7071))
    }

    func testSamplesRoundTripThroughTheBinaryFormat() throws {
        var data = MotionRecording.header(sampleRate: 50)
        XCTAssertEqual(data.count, MotionRecording.headerSize)
        let samples = (0..<250).map(sample)
        for s in samples { MotionRecording.append(s, to: &data) }
        XCTAssertEqual(data.count, MotionRecording.headerSize + 250 * MotionRecording.bytesPerSample)
        let read = try MotionRecording.read(data)
        XCTAssertEqual(read.sampleRate, 50)
        XCTAssertEqual(read.samples, samples)
    }

    func testAboutThreeKilobytesASecondAtFiftyHertz() {
        // Design section 8: about 3 KB/s, roughly 12 MB for a 70-minute session.
        let perSecond = Double(MotionRecording.bytesPerSample) * MotionRecording.defaultSampleRate
        XCTAssertEqual(perSecond, 2800)
        XCTAssertLessThan(perSecond * 70 * 60 / 1_000_000, 12)
    }

    func testATruncatedTailIsIgnoredAndJunkIsRejected() throws {
        var data = MotionRecording.header(sampleRate: 50)
        MotionRecording.append(sample(0), to: &data)
        MotionRecording.append(sample(1), to: &data)
        data.removeLast(7)
        XCTAssertEqual(try MotionRecording.read(data).samples, [sample(0)])
        XCTAssertThrowsError(try MotionRecording.read(Data("not a recording at all".utf8)))
        var future = MotionRecording.header(sampleRate: 50)
        future[4] = 9
        XCTAssertEqual(try? MotionRecording.read(future).sampleRate, nil)
    }

    func testCompletedSetsAreLabelledFromTheirBoundaryToTheDoneTap() throws {
        let sidecar = MotionSidecar(
            recordingID: "r", sessionID: "s", startedAt: Date(timeIntervalSince1970: 1_800_000_000), sampleRate: 50,
            device: .init(model: "Watch7,9", wristLocation: "left", crownOrientation: "right"),
            events: [
                MotionEvent(t: 5, kind: .focusChanged, exerciseID: "bench"),
                MotionEvent(t: 30, kind: .setCompleted, setID: "b1", exerciseID: "bench", reps: 5, weightLb: 185),
                MotionEvent(t: 30.2, kind: .restStarted),
                MotionEvent(t: 150, kind: .restEnded),
                MotionEvent(t: 178, kind: .setCompleted, setID: "b2", exerciseID: "bench", reps: 5, weightLb: 185),
            ])
        let decoded = try JSONDecoder().decode(MotionSidecar.self, from: JSONEncoder().encode(sidecar))
        XCTAssertEqual(decoded, sidecar)
        let sets = decoded.labelledSets()
        XCTAssertEqual(sets.map(\.event.setID), ["b1", "b2"])
        XCTAssertEqual(sets[0].start, 5); XCTAssertEqual(sets[0].end, 30)
        XCTAssertEqual(sets[1].start, 150, "the rest's end bounds the next set"); XCTAssertEqual(sets[1].end, 178)
    }
}
