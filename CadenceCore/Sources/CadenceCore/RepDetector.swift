import Foundation

// Rep and set-end detection from wrist motion (design: docs/superpowers/specs/
// 2026-10-18-apple-watch-design.md, section 9). The simplest approach that can
// meet the accuracy bar: per exercise, project user acceleration onto the axis
// the owner's reps move along, band-pass it around their rep tempo, count peaks
// with hysteresis and group them into sets. Everything is learned from the
// owner's labelled sets (the Done tap marks set end); nothing is hand-tuned per
// lift. Swift-only, like the other watch modules; tests use synthetic motion.

/// What the detector knows about one exercise, built from labelled sets.
public struct RepSignature: Codable, Hashable, Sendable {
    public var exerciseID: String
    /// Unit axis in the watch's frame along which the reps move.
    public var axis: [Double]
    /// Typical seconds per rep.
    public var repPeriod: Double
    /// Typical peak height of the filtered signal, in g.
    public var amplitude: Double
    /// Typical seconds from the last rep to the Done tap (racking, stepping back).
    public var endLag: Double
    public var trainingSets: Int

    public init(exerciseID: String, axis: [Double], repPeriod: Double, amplitude: Double, endLag: Double,
                trainingSets: Int) {
        self.exerciseID = exerciseID
        self.axis = axis
        self.repPeriod = repPeriod
        self.amplitude = amplitude
        self.endLag = endLag
        self.trainingSets = trainingSets
    }
}

/// A set the detector found in a motion stream.
public struct DetectedSet: Equatable, Sendable {
    public var start: Double
    /// Estimated set end on the recording clock (where the Done tap would be).
    public var end: Double
    public var reps: Int
    /// 0…1: regularity of the rep tempo and strength of the motion.
    public var confidence: Double
}

/// A labelled set: its motion window and the reps the owner logged.
public struct LabelledMotionSet: Sendable {
    public var samples: [MotionSample]
    public var reps: Int
    /// The Done tap, on the samples' clock.
    public var end: Double

    public init(samples: [MotionSample], reps: Int, end: Double) {
        self.samples = samples
        self.reps = reps
        self.end = end
    }
}

public enum RepDetector {
    /// Fewest reps that count as a set: a single swing of the arm is not one.
    public static let minimumReps = 2

    // MARK: Signatures

    /// Learn an exercise's signature from labelled sets. Nil when there is not
    /// enough motion to learn from.
    public static func signature(exerciseID: String, from sets: [LabelledMotionSet],
                                 sampleRate: Double = MotionRecording.defaultSampleRate) -> RepSignature? {
        let usable = sets.filter { $0.reps >= minimumReps && $0.samples.count > Int(sampleRate) }
        guard !usable.isEmpty else { return nil }
        // Axis: the principal direction of each set's acceleration, signs aligned.
        var reference: [Double]?
        var summed = [0.0, 0.0, 0.0]
        for set in usable {
            var axis = principalAxis(set.samples)
            if let reference, dot(axis, reference) < 0 { axis = axis.map { -$0 } }
            if reference == nil { reference = axis }
            for i in 0..<3 { summed[i] += axis[i] }
        }
        let axis = normalized(summed)
        // Tempo from each set's autocorrelation; amplitude and end lag from its peaks.
        var periods: [Double] = []
        for set in usable {
            let signal = project(set.samples, on: axis)
            if let period = dominantPeriod(signal, sampleRate: sampleRate) { periods.append(period) }
        }
        guard let period = median(periods) else { return nil }
        var amplitudes: [Double] = []
        var lags: [Double] = []
        for set in usable {
            let filtered = bandPass(project(set.samples, on: axis), period: period, sampleRate: sampleRate)
            // Only real rep peaks: noise in setup and racking makes tiny ones.
            // The owner logged how many reps there were, so keep that many of
            // the strongest peaks above a third of the set's largest.
            let strongest = filtered.max() ?? 0
            guard strongest > 0 else { continue }
            let candidates = findPeaks(filtered, threshold: strongest / 3, period: period, sampleRate: sampleRate)
            let reps = candidates.sorted { filtered[$0] > filtered[$1] }.prefix(set.reps).sorted()
            amplitudes += reps.map { filtered[$0] }
            if let last = reps.last {
                lags.append(max(0, set.end - Double(set.samples[last].t)))
            }
        }
        guard let amplitude = median(amplitudes), amplitude > 0 else { return nil }
        return RepSignature(exerciseID: exerciseID, axis: axis, repPeriod: period, amplitude: amplitude,
                            endLag: median(lags) ?? 2, trainingSets: usable.count)
    }

    // MARK: Detection

    /// Every set in `samples` that moves like `signature`.
    public static func detect(_ samples: [MotionSample], signature: RepSignature,
                              sampleRate: Double = MotionRecording.defaultSampleRate) -> [DetectedSet] {
        guard samples.count > 2 else { return [] }
        let filtered = bandPass(project(samples, on: signature.axis), period: signature.repPeriod, sampleRate: sampleRate)
        let peaks = findPeaks(filtered, threshold: 0.4 * signature.amplitude, period: signature.repPeriod,
                              sampleRate: sampleRate)
        // Peaks closer than a long pause belong to one set.
        var groups: [[Int]] = []
        for peak in peaks {
            if let last = groups.last?.last,
               Double(samples[peak].t - samples[last].t) <= 2.5 * signature.repPeriod {
                groups[groups.count - 1].append(peak)
            } else {
                groups.append([peak])
            }
        }
        return groups.filter { $0.count >= minimumReps }.map { group in
            let times = group.map { Double(samples[$0].t) }
            let intervals = zip(times.dropFirst(), times).map { $0 - $1 }
            let mean = intervals.reduce(0, +) / Double(max(1, intervals.count))
            let spread = sqrt(intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(1, intervals.count)))
            let regularity = mean > 0 ? max(0, 1 - spread / mean) : 0
            let strength = min(1, (group.map { filtered[$0] }.reduce(0, +) / Double(group.count)) / signature.amplitude)
            return DetectedSet(start: times.first! - signature.repPeriod / 2, end: times.last! + signature.endLag,
                               reps: group.count, confidence: (regularity * strength * 100).rounded() / 100)
        }
    }

    // MARK: Signal processing

    static func project(_ samples: [MotionSample], on axis: [Double]) -> [Double] {
        samples.map {
            Double($0.userAcceleration.x) * axis[0] + Double($0.userAcceleration.y) * axis[1]
                + Double($0.userAcceleration.z) * axis[2]
        }
    }

    /// Smooth away jitter faster than a rep, then remove drift slower than one.
    static func bandPass(_ signal: [Double], period: Double, sampleRate: Double) -> [Double] {
        let fast = movingAverage(signal, window: max(1, Int((0.15 * period * sampleRate).rounded())))
        let slow = movingAverage(signal, window: max(3, Int((1.5 * period * sampleRate).rounded())))
        return zip(fast, slow).map { $0 - $1 }
    }

    /// Local maxima above `threshold`, at least half a rep apart, with the
    /// signal crossing below zero between them so one rep never counts twice.
    static func findPeaks(_ signal: [Double], threshold: Double, period: Double, sampleRate: Double) -> [Int] {
        let minGap = Int(0.5 * period * sampleRate)
        var peaks: [Int] = []
        var armed = true
        var candidate: Int?
        for i in 1..<max(1, signal.count - 1) {
            let value = signal[i]
            if value < 0 {
                if let c = candidate {
                    if let last = peaks.last, c - last < minGap {
                        if signal[c] > signal[last] { peaks[peaks.count - 1] = c }
                    } else {
                        peaks.append(c)
                    }
                    candidate = nil
                }
                armed = true
            } else if armed, value > threshold, value >= signal[i - 1], value >= signal[i + 1] {
                if candidate.map({ value > signal[$0] }) ?? true { candidate = i }
            }
        }
        if let c = candidate, peaks.last.map({ c - $0 >= minGap }) ?? true { peaks.append(c) }
        return peaks
    }

    /// The lag of the strongest autocorrelation between 0.4 s and 8 s.
    static func dominantPeriod(_ signal: [Double], sampleRate: Double) -> Double? {
        let mean = signal.reduce(0, +) / Double(max(1, signal.count))
        let x = signal.map { $0 - mean }
        let minLag = Int(0.4 * sampleRate)
        let maxLag = min(Int(8 * sampleRate), x.count / 2)
        guard maxLag > minLag else { return nil }
        let energy = x.reduce(0) { $0 + $1 * $1 }
        guard energy > 0 else { return nil }
        var best: (lag: Int, value: Double)?
        var previous = Double.infinity
        var rising = false
        for lag in minLag...maxLag {
            var sum = 0.0
            for i in 0..<(x.count - lag) { sum += x[i] * x[i + lag] }
            let r = sum / energy
            // The first local maximum after the curve turns up is the fundamental.
            if r > previous { rising = true } else if rising, best == nil, previous > 0.2 {
                best = (lag - 1, previous)
            }
            previous = r
        }
        return best.map { Double($0.lag) / sampleRate }
    }

    /// Centred moving average; the edges average the samples they have.
    static func movingAverage(_ signal: [Double], window: Int) -> [Double] {
        guard window > 1, !signal.isEmpty else { return signal }
        var prefix = [0.0]
        prefix.reserveCapacity(signal.count + 1)
        for value in signal { prefix.append(prefix[prefix.count - 1] + value) }
        let half = window / 2
        return (0..<signal.count).map { i in
            let lo = max(0, i - half)
            let hi = min(signal.count, i - half + window)
            return (prefix[hi] - prefix[lo]) / Double(hi - lo)
        }
    }

    static func principalAxis(_ samples: [MotionSample]) -> [Double] {
        let points = samples.map { [Double($0.userAcceleration.x), Double($0.userAcceleration.y), Double($0.userAcceleration.z)] }
        let n = Double(max(1, points.count))
        let mean = (0..<3).map { i in points.reduce(0) { $0 + $1[i] } / n }
        var c = [[Double]](repeating: [0, 0, 0], count: 3)
        for p in points {
            for i in 0..<3 { for j in 0..<3 { c[i][j] += (p[i] - mean[i]) * (p[j] - mean[j]) / n } }
        }
        var v = normalized([1, 0.7, 0.4])
        for _ in 0..<60 {
            v = normalized((0..<3).map { i in (0..<3).reduce(0) { $0 + c[i][$1] * v[$1] } })
        }
        return v
    }

    static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }

    static func normalized(_ v: [Double]) -> [Double] {
        let length = sqrt(dot(v, v))
        return length > 0 ? v.map { $0 / length } : [1, 0, 0]
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

/// Live set detection on the watch (design section 10): the batch detector run
/// over the motion since the last reported set, reporting each set once, after
/// no further rep could still join it. Feed it samples as they arrive; reset it
/// when the exercise in focus changes.
public struct StreamingSetDetector: Sendable {
    public let signature: RepSignature
    public let sampleRate: Double
    private(set) var buffer: [MotionSample] = []
    private var reportedThrough = -Double.infinity

    public init(signature: RepSignature, sampleRate: Double = MotionRecording.defaultSampleRate) {
        self.signature = signature
        self.sampleRate = sampleRate
    }

    /// Seconds of motion kept at most: room for the longest plausible set, a
    /// two-rep lead-in, 50 reps and the settle after them. `RepDetector.detect`
    /// is linear in the samples it is given and runs on every batch, so this
    /// bounds the watch's work per batch; a longer set loses its first reps.
    public var window: Double { 52 * signature.repPeriod + settle }

    /// Seconds after the last rep before a set is final: its learned end lag,
    /// and at least long enough that a slow final rep would already have come.
    public var settle: Double { max(signature.endLag, 1.5 * signature.repPeriod) }

    public mutating func append(_ samples: [MotionSample]) -> DetectedSet? {
        buffer += samples
        guard let now = buffer.last.map({ Double($0.t) }) else { return nil }
        // Drop what was already reported, but never trim into a set that has not
        // been: a set longer than a short window would lose its first reps.
        let keepFrom = max(reportedThrough, now - window)
        if let keep = buffer.firstIndex(where: { Double($0.t) >= keepFrom }), keep > 0 {
            buffer.removeFirst(keep)
        }
        let sets = RepDetector.detect(buffer, signature: signature, sampleRate: sampleRate)
        guard let done = sets.last(where: { set in
            let lastRep = set.end - signature.endLag
            return now >= lastRep + settle && set.start > reportedThrough
        }) else { return nil }
        reportedThrough = done.end
        return done
    }

    public mutating func reset() {
        buffer.removeAll()
        reportedThrough = -.infinity
    }
}
