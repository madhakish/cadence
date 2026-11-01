import XCTest
@testable import CadenceCore

/// Rep and set-end detection (#337) on synthetic motion only: real recordings
/// are workout data and never enter the repository.
final class RepDetectorTests: XCTestCase {
    /// Deterministic generator so a failure names a reproducible seed.
    private struct Noise {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) % 1_000_000) / 500_000 - 1  // −1…1
        }
    }

    private struct Lift {
        var id: String
        var name: String
        var axis: SIMD3<Float>
        var period: Double
        var amplitude: Float
    }

    private let rate = 50.0
    private let bench = Lift(id: "bench", name: "Bench Press", axis: SIMD3(0.2, 0.9, 0.39), period: 2.2, amplitude: 0.35)
    private let curl = Lift(id: "curl", name: "Biceps Curl", axis: SIMD3(0.8, -0.1, 0.59), period: 1.6, amplitude: 0.5)

    /// A session: per set, walking/setup, the reps, racking, the Done tap, then rest.
    private func session(seed: UInt64, sets: [(Lift, Int)]) -> MotionRecordingData {
        var noise = Noise(state: seed)
        var samples: [MotionSample] = []
        var events: [MotionEvent] = []
        var t = 0.0
        func emit(_ seconds: Double, _ signal: (Double) -> SIMD3<Float>) {
            let start = t
            while t < start + seconds {
                let n = SIMD3<Float>(Float(noise.next()), Float(noise.next()), Float(noise.next())) * 0.012
                samples.append(MotionSample(t: Float(t), userAcceleration: signal(t - start) + n,
                                            rotationRate: .zero, gravity: SIMD3(0, -1, 0), attitude: SIMD4(0, 0, 0, 1)))
                t += 1 / rate
            }
        }
        func walk(_ seconds: Double) {
            emit(seconds) { s in SIMD3(0, Float(0.06 * sin(2 * .pi * 1.8 * s)), Float(0.03 * sin(2 * .pi * 0.9 * s))) }
        }
        var current: String?
        for (lift, reps) in sets {
            if current != lift.id {
                events.append(MotionEvent(t: t, kind: .focusChanged, exerciseID: lift.id, exerciseName: lift.name))
                current = lift.id
            } else {
                events.append(MotionEvent(t: t, kind: .restEnded))
            }
            walk(4)
            emit(1.5) { s in lift.axis * Float(0.05 * sin(2 * .pi * 0.3 * s)) }  // unrack, settle
            // Reps with ±8% tempo jitter, integrated as phase.
            var phase = 0.0
            var periods = (0..<reps).map { _ in lift.period * (1 + 0.08 * noise.next()) }
            let total = periods.reduce(0, +)
            emit(total) { s in
                while !periods.isEmpty, s > phase + periods[0] { phase += periods.removeFirst() }
                guard let p = periods.first else { return .zero }
                return lift.axis * lift.amplitude * Float(sin(2 * .pi * (s - phase) / p))
            }
            emit(2.5) { _ in .zero }  // rack, step back
            events.append(MotionEvent(t: t, kind: .setCompleted, setID: UUID().uuidString, exerciseID: lift.id,
                                      exerciseName: lift.name, reps: reps, weightLb: 135))
            events.append(MotionEvent(t: t, kind: .restStarted))
            // Rest: fidgets (single blips) and a walk to the water fountain.
            let rest = 60 + 30 * abs(noise.next())
            emit(rest / 2) { s in s.truncatingRemainder(dividingBy: 13) < 0.4 ? SIMD3(0.12, 0.05, -0.08) : .zero }
            walk(rest / 2)
        }
        let sidecar = MotionSidecar(recordingID: UUID().uuidString, sessionID: "synthetic-\(seed)",
                                    startedAt: Date(timeIntervalSince1970: 1_800_000_000), sampleRate: rate,
                                    device: .init(model: "Watch7,9", wristLocation: "left", crownOrientation: "right"),
                                    events: events)
        return MotionRecordingData(sidecar: sidecar, samples: samples)
    }

    func testASignatureLearnsTheAxisAndTempoFromLabelledSets() throws {
        let recording = session(seed: 1, sets: [(bench, 5), (bench, 5), (bench, 6)])
        let sets = DetectorEvaluation.labelledSets("bench", in: recording)
        XCTAssertEqual(sets.count, 3)
        let signature = try XCTUnwrap(RepDetector.signature(exerciseID: "bench", from: sets))
        let axis = RepDetector.normalized([Double(bench.axis.x), Double(bench.axis.y), Double(bench.axis.z)])
        XCTAssertGreaterThan(abs(RepDetector.dot(signature.axis, axis)), 0.95)
        XCTAssertEqual(signature.repPeriod, bench.period, accuracy: bench.period * 0.12)
        // A rep peaks a quarter of the way in: three quarters of the last rep,
        // then 2.5 s of racking, lie between the last peak and the Done tap.
        XCTAssertEqual(signature.endLag, 2.5 + 0.75 * bench.period, accuracy: 0.5, "last peak to the Done tap")
        XCTAssertEqual(signature.trainingSets, 3)
    }

    func testHeldOutSetsAreCountedExactlyAndEndNearTheDoneTap() throws {
        let training = session(seed: 2, sets: [(bench, 5), (bench, 5), (bench, 8), (bench, 3)])
        let heldOut = session(seed: 3, sets: [(bench, 5), (bench, 7), (bench, 4)])
        let signature = try XCTUnwrap(RepDetector.signature(exerciseID: "bench",
                                                            from: DetectorEvaluation.labelledSets("bench", in: training)))
        let detected = RepDetector.detect(heldOut.samples, signature: signature)
        let truth = heldOut.sidecar.labelledSets()
        XCTAssertEqual(detected.map(\.reps), truth.map { $0.event.reps! }, "every set, with its exact reps, and nothing else")
        for (found, set) in zip(detected, truth) {
            XCTAssertEqual(found.end, set.end, accuracy: 5, "set end within 5 s of the Done tap")
            XCTAssertGreaterThan(found.confidence, 0.5)
        }
    }

    func testRestsFidgetsAndWalkingDetectNothing() throws {
        let training = session(seed: 4, sets: [(bench, 5), (bench, 5), (bench, 6)])
        let signature = try XCTUnwrap(RepDetector.signature(exerciseID: "bench",
                                                            from: DetectorEvaluation.labelledSets("bench", in: training)))
        var noise = Noise(state: 5)
        var t = 0.0
        var quiet: [MotionSample] = []
        while t < 600 {  // ten minutes of rest, fidgets and walking
            let walking = t.truncatingRemainder(dividingBy: 120) > 90
            let blip = t.truncatingRemainder(dividingBy: 17) < 0.4
            let a = walking ? SIMD3<Float>(0, Float(0.06 * sin(2 * .pi * 1.8 * t)), 0)
                : (blip ? SIMD3<Float>(0.12, 0.05, -0.08) : .zero)
            quiet.append(MotionSample(t: Float(t), userAcceleration: a + SIMD3(Float(noise.next()), Float(noise.next()), 0) * 0.012,
                                      rotationRate: .zero, gravity: SIMD3(0, -1, 0), attitude: SIMD4(0, 0, 0, 1)))
            t += 1 / rate
        }
        XCTAssertEqual(RepDetector.detect(quiet, signature: signature), [])
    }

    func testTheEvaluationTableAppliesTheBarPerExercise() {
        // Three sessions: bench gets 12 held-out sets; curls only 6.
        let recordings = [
            session(seed: 10, sets: [(bench, 5), (bench, 5), (bench, 5), (bench, 6), (curl, 10), (curl, 10)]),
            session(seed: 11, sets: [(bench, 3), (bench, 5), (bench, 8), (bench, 5), (curl, 12), (curl, 8)]),
            session(seed: 12, sets: [(bench, 5), (bench, 4), (bench, 6), (bench, 5), (curl, 10), (curl, 9)]),
        ]
        let results = DetectorEvaluation.evaluate(recordings)
        XCTAssertEqual(results.map(\.name), ["Bench Press", "Biceps Curl"])
        let benchResult = results[0]
        XCTAssertEqual(benchResult.sets, 12)
        XCTAssertGreaterThanOrEqual(benchResult.exactRate, 0.9)
        XCTAssertEqual(benchResult.falseDetections, 0)
        XCTAssertTrue(benchResult.passes)
        XCTAssertEqual(benchResult.verdict, "enable")
        XCTAssertEqual(results[1].sets, 6)
        XCTAssertFalse(results[1].passes, "fewer than 10 held-out sets never enable an exercise")
        XCTAssertEqual(results[1].verdict, "needs 4 more sets")
        let table = DetectorEvaluation.table(results)
        XCTAssertTrue(table.contains("Bench Press"))
        XCTAssertTrue(table.contains("enable"))
        XCTAssertFalse(table.contains("synthetic-"), "the table carries no session identifiers")
    }

    func testOneSessionIsNotEnoughToJudge() {
        let results = DetectorEvaluation.evaluate([session(seed: 20, sets: (0..<12).map { _ in (bench, 5) })])
        XCTAssertEqual(results.first?.verdict, "needs a second session")
        XCTAssertFalse(results.first?.passes ?? true)
    }
}
