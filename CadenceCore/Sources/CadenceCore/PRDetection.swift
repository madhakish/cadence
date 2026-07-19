import Foundation

/// A single working set, minimal shape for PR math.
public struct SetSample: Hashable, Codable, Sendable {
    public let weightLb: Double
    public let reps: Int
    public let isPerSide: Bool
    public let loadBasis: LoadBasis
    public let implementCount: Int

    public init(weightLb: Double, reps: Int, isPerSide: Bool = false,
                loadBasis: LoadBasis = .totalBar, implementCount: Int = 1) {
        self.weightLb = weightLb
        self.reps = reps
        self.isPerSide = isPerSide
        self.loadBasis = loadBasis
        self.implementCount = implementCount
    }
}

/// An auto-detected milestone. Tone: terse, coach-like. No confetti.
public struct PREvent: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case heaviestSet
        case volumePR
        case firstScheme
        case programNote   // adaptive-progression explanation (deload/ceiling), not a PR
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
        sets.compactMap {
            LoadSemantics.volume(weightLb: $0.weightLb, reps: $0.reps, isPerSide: $0.isPerSide,
                                 basis: $0.loadBasis, implementCount: $0.implementCount)
        }.reduce(0, +)
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
        historySchemes: Set<String>,
        formatWeight: ((Double) -> String)? = nil
    ) -> [PREvent] {
        guard !sessionSets.isEmpty else { return [] }
        var events: [PREvent] = []
        let weightLabel = formatWeight ?? { Weight.trim($0) }
        let basis = sessionSets[0].loadBasis
        let comparableSession = sessionSets.filter { LoadSemantics.compatible($0.loadBasis, basis) }
        let comparableHistory = historySets.filter { LoadSemantics.compatible($0.loadBasis, basis) }

        let priorMax = comparableHistory.map(\.weightLb).max() ?? 0

        if let top = topScheme(comparableSession) {
            if basis.supportsLoadPR, top.weightLb > priorMax + 1e-9 {
                let scheme = top.sets > 1 ? "\(weightLabel(top.weightLb))×\(top.sets)×\(top.reps)" : "\(weightLabel(top.weightLb))×\(top.reps)"
                events.append(PREvent(
                    kind: .heaviestSet,
                    exercise: exercise,
                    label: "\(scheme) — heaviest \(exercise.lowercased()) logged"
                ))
            }

            let schemeKey = "\(top.sets)×\(top.reps)"
            if !historySchemes.contains(schemeKey) {
                events.append(PREvent(
                    kind: .firstScheme,
                    exercise: exercise,
                    label: "First \(schemeKey) — \(weightLabel(top.weightLb)) \(exercise.lowercased())"
                ))
            }
        }

        let vol = volume(comparableSession)
        let priorVolMax = historyVolumes.max() ?? 0
        if basis.supportsVolume, vol > priorVolMax + 1e-9, !historyVolumes.isEmpty {
            let volumeLabel = formatWeight?(vol) ?? "\(Weight.trim(vol)) lb"
            events.append(PREvent(
                kind: .volumePR,
                exercise: exercise,
                label: "Volume PR — \(volumeLabel) total \(exercise.lowercased())"
            ))
        }

        return events
    }
}
