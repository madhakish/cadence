import Foundation

/// A recording as exported from the phone: samples plus sidecar.
public struct MotionRecordingData: Sendable {
    public var sidecar: MotionSidecar
    public var samples: [MotionSample]

    public init(sidecar: MotionSidecar, samples: [MotionSample]) {
        self.sidecar = sidecar
        self.samples = samples
    }
}

/// Per-exercise accuracy against design #339's bar (section 9), measured on
/// recordings held out from the signature build: each recording is scored with
/// a signature learned from the owner's other recordings. Runs offline on the
/// developer's machine; only the aggregate table may be posted.
public enum DetectorEvaluation {
    public struct ExerciseResult: Equatable, Sendable {
        public var exerciseID: String
        public var name: String
        public var sets: Int
        public var exact: Int
        public var withinOne: Int
        public var endWithin5s: Int
        /// Detections with no matching Done tap across the exercise's stretch of
        /// each session: its sets, the rests between them, setup and walking.
        public var falseDetections: Int
        public var recordings: Int

        public var exactRate: Double { sets > 0 ? Double(exact) / Double(sets) : 0 }
        public var withinOneRate: Double { sets > 0 ? Double(withinOne) / Double(sets) : 0 }
        public var endRate: Double { sets > 0 ? Double(endWithin5s) / Double(sets) : 0 }
        public var falsePer100Sets: Double { sets > 0 ? Double(falseDetections) * 100 / Double(sets) : 0 }

        /// The bar: at least 10 held-out sets; exact on 90%, ±1 on 98%; set end
        /// within 5 s on 95%; at most one false detection per 100 real sets.
        public var passes: Bool {
            sets >= 10 && exactRate >= 0.90 && withinOneRate >= 0.98 && endRate >= 0.95 && falsePer100Sets <= 1
        }

        public var verdict: String {
            if recordings < 2 { return "needs a second session" }
            if sets < 10 { return "needs \(10 - sets) more sets" }
            return passes ? "enable" : "stay manual"
        }
    }

    /// Completed sets of one exercise in a recording, with their motion.
    public static func labelledSets(_ exerciseID: String, in recording: MotionRecordingData) -> [LabelledMotionSet] {
        recording.sidecar.labelledSets().filter { $0.event.exerciseID == exerciseID }.compactMap { set in
            guard let reps = set.event.reps else { return nil }
            let samples = recording.samples.filter { Double($0.t) >= set.start && Double($0.t) <= set.end }
            return LabelledMotionSet(samples: samples, reps: reps, end: set.end)
        }
    }

    public static func evaluate(_ recordings: [MotionRecordingData]) -> [ExerciseResult] {
        var names: [String: String] = [:]
        for recording in recordings {
            for event in recording.sidecar.events where event.kind == .setCompleted {
                if let id = event.exerciseID { names[id] = names[id] ?? event.exerciseName ?? id }
            }
        }
        return names.keys.sorted { names[$0]! < names[$1]! }.map { exerciseID in
            var result = ExerciseResult(exerciseID: exerciseID, name: names[exerciseID]!, sets: 0, exact: 0,
                                        withinOne: 0, endWithin5s: 0, falseDetections: 0, recordings: 0)
            let holding = recordings.filter { !labelledSets(exerciseID, in: $0).isEmpty }
            result.recordings = holding.count
            for (index, heldOut) in holding.enumerated() {
                let truth = heldOut.sidecar.labelledSets().filter { $0.event.exerciseID == exerciseID }
                result.sets += truth.count
                let training = holding.enumerated().filter { $0.offset != index }
                    .flatMap { labelledSets(exerciseID, in: $0.element) }
                guard let signature = RepDetector.signature(exerciseID: exerciseID, from: training,
                                                            sampleRate: heldOut.sidecar.sampleRate) else { continue }
                // The exercise's stretch of the session: from its first set's
                // boundary to a minute after its last Done tap.
                let spanStart = truth.map(\.start).min() ?? 0
                let spanEnd = (truth.map(\.end).max() ?? 0) + 60
                let span = heldOut.samples.filter { Double($0.t) >= spanStart && Double($0.t) <= spanEnd }
                var detections = RepDetector.detect(span, signature: signature, sampleRate: heldOut.sidecar.sampleRate)
                for set in truth {
                    // The detection that ends inside this set's window or shortly after its Done tap.
                    guard let match = detections.firstIndex(where: { $0.end >= set.start && $0.end <= set.end + 15 }) else {
                        continue
                    }
                    let found = detections.remove(at: match)
                    let reps = set.event.reps ?? 0
                    if found.reps == reps { result.exact += 1 }
                    if abs(found.reps - reps) <= 1 { result.withinOne += 1 }
                    if abs(found.end - set.end) <= 5 { result.endWithin5s += 1 }
                }
                result.falseDetections += detections.count
            }
            return result
        }
    }

    /// Signatures for the exercises that pass the bar, each learned from all of
    /// its labelled sets. Only these are ever sent to the watch: an exercise is
    /// auto-logged only after it has been shown accurate on the owner's own
    /// recordings (design anti-goal 4).
    public static func enabledSignatures(_ recordings: [MotionRecordingData]) -> [RepSignature] {
        evaluate(recordings).filter(\.passes).compactMap { result in
            let sets = recordings.flatMap { labelledSets(result.exerciseID, in: $0) }
            let rate = recordings.first?.sidecar.sampleRate ?? MotionRecording.defaultSampleRate
            return RepDetector.signature(exerciseID: result.exerciseID, from: sets, sampleRate: rate)
        }
    }

    /// The aggregate table: the only output that may be shared.
    public static func table(_ results: [ExerciseResult]) -> String {
        func pct(_ value: Double) -> String { String(format: "%5.1f%%", value * 100) }
        var lines = ["exercise                       sets   exact     ±1   end≤5s  false/100  verdict"]
        for r in results {
            let name = r.name.count > 28 ? String(r.name.prefix(27)) + "…" : r.name
            lines.append(name.padding(toLength: 30, withPad: " ", startingAt: 0)
                + String(format: "%5d", r.sets) + "  " + pct(r.exactRate) + " " + pct(r.withinOneRate) + "  "
                + pct(r.endRate) + "  " + String(format: "%8.1f", r.falsePer100Sets) + "  " + r.verdict)
        }
        return lines.joined(separator: "\n")
    }
}
