import Foundation

/// A single working set, minimal shape for PR math.
public struct SetSample: Hashable, Codable, Sendable {
    public let weightLb: Double
    public let reps: Int

    public init(weightLb: Double, reps: Int) {
        self.weightLb = weightLb
        self.reps = reps
    }
}

/// An auto-detected milestone. Tone: terse, coach-like. No confetti.
public struct PREvent: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case heaviestSet
        case volumePR
        case firstScheme
    }

    public let kind: Kind
    public let exercise: String
    public let label: String

    public init(kind: Kind, exercise: String, label: String) {
        self.kind = kind
        self.exercise = exercise
        self.label = label
    }
}

public enum PRDetection {
    /// Total working volume (Σ weight × reps) of a set list.
    public static func volume(_ sets: [SetSample]) -> Double {
        sets.reduce(0) { $0 + $1.weightLb * Double($1.reps) }
    }

    /// "5×3" scheme string for the top-weight group of a session.
    public static func topScheme(_ sets: [SetSample]) -> (weightLb: Double, sets: Int, reps: Int)? {
        guard let top = sets.map(\.weightLb).max() else { return nil }
        let topSets = sets.filter { abs($0.weightLb - top) < 1e-9 }
        guard let reps = topSets.map(\.reps).min(), !topSets.isEmpty else { return nil }
        return (top, topSets.count, reps)
    }

    /// Evaluate one exercise's session against its history.
    ///
    /// - Parameters:
    ///   - exercise: display name ("Deadlift").
    ///   - sessionSets: this session's working sets (no warmups).
    ///   - historySets: all prior working sets for this exercise.
    ///   - historyVolumes: per-session working volumes for this exercise.
    ///   - historySchemes: "sets×reps" scheme strings previously completed.
    public static func evaluate(
        exercise: String,
        sessionSets: [SetSample],
        historySets: [SetSample],
        historyVolumes: [Double],
        historySchemes: Set<String>
    ) -> [PREvent] {
        guard !sessionSets.isEmpty else { return [] }
        var events: [PREvent] = []

        let priorMax = historySets.map(\.weightLb).max() ?? 0

        if let top = topScheme(sessionSets) {
            if top.weightLb > priorMax + 1e-9 {
                let scheme = top.sets > 1 ? "\(Weight.trim(top.weightLb))×\(top.sets)×\(top.reps)" : "\(Weight.trim(top.weightLb))×\(top.reps)"
                events.append(PREvent(
                    kind: .heaviestSet,
                    exercise: exercise,
                    label: "\(scheme) — heaviest \(exercise.lowercased()) of the comeback"
                ))
            }

            let schemeKey = "\(top.sets)×\(top.reps)"
            if !historySchemes.contains(schemeKey) {
                events.append(PREvent(
                    kind: .firstScheme,
                    exercise: exercise,
                    label: "First \(schemeKey) — \(Weight.trim(top.weightLb)) \(exercise.lowercased())"
                ))
            }
        }

        let vol = volume(sessionSets)
        let priorVolMax = historyVolumes.max() ?? 0
        if vol > priorVolMax + 1e-9, !historyVolumes.isEmpty {
            events.append(PREvent(
                kind: .volumePR,
                exercise: exercise,
                label: "Volume PR — \(Weight.trim(vol)) lb total \(exercise.lowercased())"
            ))
        }

        return events
    }
}
