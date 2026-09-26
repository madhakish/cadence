import Foundation

/// A single working set, minimal shape for PR math.
public struct SetSample: Hashable, Codable, Sendable {
    public let weightLb: Double
    public let reps: Int
    public let isPerSide: Bool
    public let loadBasis: LoadBasis
    public let implementCount: Int
    /// Yards carried, for a distance-carry set only (`CardioFormat.carryYards`).
    /// nil for every rep-based set, including a carry logged as reps.
    public let distanceYards: Double?

    public init(weightLb: Double, reps: Int, isPerSide: Bool = false,
                loadBasis: LoadBasis = .totalBar, implementCount: Int = 1,
                distanceYards: Double? = nil) {
        self.weightLb = weightLb
        self.reps = reps
        self.isPerSide = isPerSide
        self.loadBasis = loadBasis
        self.implementCount = implementCount
        self.distanceYards = distanceYards
    }

    var isCarryDistance: Bool { (distanceYards ?? 0) > 0 }
}

/// An auto-detected milestone. Tone: terse, coach-like. No confetti.
public struct PREvent: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case heaviestSet
        case volumePR
        case firstScheme
        /// More reps at a weight than ever before at that rep count. History
        /// already rebuilt this table for a chart; nothing announced it.
        case repPR
        case programNote   // adaptive-progression explanation (deload), not a PR
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
    /// Epley degrades past ten reps and "most reps at a weight" stops being a
    /// strength claim, so rep PRs are only tracked inside that range.
    public static let repPRRepCeiling = 10

    /// Total working volume (Σ weight × reps) of a set list. A distance-carry
    /// set counts weight × yards instead (`LoadSemantics.carryVolume`).
    public static func volume(_ sets: [SetSample]) -> Double {
        sets.compactMap {
            if let yards = $0.distanceYards, yards > 0 {
                return LoadSemantics.carryVolume(weightLb: $0.weightLb, yards: yards, isPerSide: $0.isPerSide,
                                                 basis: $0.loadBasis, implementCount: $0.implementCount)
            }
            return LoadSemantics.volume(weightLb: $0.weightLb, reps: $0.reps, isPerSide: $0.isPerSide,
                                        basis: $0.loadBasis, implementCount: $0.implementCount)
        }.reduce(0, +)
    }

    /// The scheme the athlete ACTUALLY performed at the session's top weight:
    /// the largest group of top-weight sets sharing one rep count, breaking a
    /// tie toward the harder (higher-rep) group.
    ///
    /// Counting every top-weight set while reporting the group's MINIMUM reps
    /// describes work nobody did — 225×5 followed by a fatigue set of 225×2
    /// reads as "2×2", and 4×5 plus a dropped 3 reads as "5×3" (five triples
    /// for four fives and a three). Those strings are also banked as history
    /// schemes, so a fabricated scheme silently becomes the baseline every
    /// later session is measured against. Mirrored 1:1 in web/app/js/core.js.
    public static func topScheme(_ sets: [SetSample]) -> (weightLb: Double, sets: Int, reps: Int)? {
        guard let top = sets.map(\.weightLb).max() else { return nil }
        let topSets = sets.filter { abs($0.weightLb - top) < 1e-9 }
        guard !topSets.isEmpty else { return nil }
        let byReps = Dictionary(grouping: topSets, by: \.reps)
        guard let best = byReps.max(by: { lhs, rhs in
            lhs.value.count != rhs.value.count ? lhs.value.count < rhs.value.count : lhs.key < rhs.key
        }) else { return nil }
        return (top, best.value.count, best.key)
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
        // [INV-CARRY-LOGS-DISTANCE] A distance carry is compared only with
        // distance carries: its "reps" are a placeholder, so it earns the
        // heaviest-load and volume (load × yards) records and never a scheme
        // or rep PR. A carry logged as reps before stays in the rep lane.
        let carries = sessionSets.contains(where: \.isCarryDistance)
        let comparableSession = sessionSets.filter {
            LoadSemantics.compatible($0.loadBasis, basis) && $0.isCarryDistance == carries
        }
        let comparableHistory = historySets.filter {
            LoadSemantics.compatible($0.loadBasis, basis) && $0.isCarryDistance == carries
        }
        if carries {
            return carryEvents(exercise: exercise, basis: basis, session: comparableSession,
                               history: comparableHistory, historyVolumes: historyVolumes,
                               weightLabel: weightLabel, formatWeight: formatWeight)
        }

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
                // Bodyweight and assisted work carry no meaningful load, so
                // naming one reads as "First 3×10 — 0 lb push-ups". Reps are
                // the whole story there; only external resistance is quoted.
                let label = basis.supportsLoadPR
                    ? "First \(schemeKey) — \(weightLabel(top.weightLb)) \(exercise.lowercased())"
                    : "First \(schemeKey) \(exercise.lowercased())"
                events.append(PREvent(kind: .firstScheme, exercise: exercise, label: label))
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

        // Rep PR: more weight at a rep count than ever before at that same rep
        // count. History already rebuilt this exact table to draw a chart, so
        // the record existed — nothing announced it when it happened, which is
        // the whole value of a PR.
        //
        // Capped at `repPRRepCeiling`: past that, "most reps at a weight" is a
        // conditioning result rather than a strength one, and the table fills
        // with noise from long back-off sets.
        //
        // One event per exercise per session, chosen by Epley so a genuinely
        // harder set wins over a longer easy one — the same ranking the cycle's
        // strength sample uses.
        var bestByReps: [Int: Double] = [:]
        for set in comparableHistory where set.reps >= 1 && set.reps <= repPRRepCeiling {
            bestByReps[set.reps] = Swift.max(bestByReps[set.reps] ?? 0, set.weightLb)
        }
        let beaten = comparableSession.filter { set in
            guard set.reps >= 1, set.reps <= repPRRepCeiling else { return false }
            // A rep count never trained before is a first, not a rep PR — the
            // firstScheme event already speaks for that.
            guard let prior = bestByReps[set.reps] else { return false }
            return set.weightLb > prior + 1e-9
        }
        if let best = beaten.max(by: {
            ProgramProgression.epleyE1RM(weightLb: $0.weightLb, reps: $0.reps)
                < ProgramProgression.epleyE1RM(weightLb: $1.weightLb, reps: $1.reps)
        }) {
            let label = basis.supportsLoadPR
                ? "Rep PR — \(weightLabel(best.weightLb)) × \(best.reps) \(exercise.lowercased())"
                : "Rep PR — \(best.reps) reps \(exercise.lowercased())"
            events.append(PREvent(kind: .repPR, exercise: exercise, label: label))
        }

        return events
    }

    private static func carryEvents(
        exercise: String, basis: LoadBasis, session: [SetSample], history: [SetSample],
        historyVolumes: [Double], weightLabel: (Double) -> String, formatWeight: ((Double) -> String)?
    ) -> [PREvent] {
        var events: [PREvent] = []
        let priorMax = history.map(\.weightLb).max() ?? 0
        if basis.supportsLoadPR, let top = session.map(\.weightLb).max(), top > priorMax + 1e-9 {
            let yards = session.filter { abs($0.weightLb - top) < 1e-9 }.compactMap(\.distanceYards).max() ?? 0
            events.append(PREvent(
                kind: .heaviestSet,
                exercise: exercise,
                label: "\(weightLabel(top)) × \(CardioFormat.carryDistanceLabel(yards: yards)) — heaviest \(exercise.lowercased()) logged"
            ))
        }
        // A first distance session has no distance baseline: the prior volumes
        // are rep tonnage, a different quantity, so beating them is no record.
        let vol = volume(session)
        if basis.supportsVolume, !history.isEmpty, vol > (historyVolumes.max() ?? 0) + 1e-9 {
            let volumeLabel = formatWeight?(vol) ?? "\(Weight.trim(vol)) lb"
            events.append(PREvent(
                kind: .volumePR,
                exercise: exercise,
                label: "Volume PR — \(volumeLabel)·yd total \(exercise.lowercased())"
            ))
        }
        return events
    }
}
