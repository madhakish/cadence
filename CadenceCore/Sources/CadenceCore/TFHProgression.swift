import Foundation

/// TFH's authored intent is independent of an exercise's load convention.
/// Stable performance under maintenance is not a failed development attempt.
public enum TFHIntent: String, Codable, Sendable { case develop, maintain, practice }

public struct TFHAnchor: Codable, Equatable, Sendable {
    public var id: String
    public var exerciseId: String
    public var weightLb: Double
    public var reps: [Int]
    public var minReps: Int
    public var maxReps: Int
    public var incrementLb: Double
    public var loadBasis: LoadBasis
    public var implementCount: Int
    public var isPerSide: Bool
    public var intent: TFHIntent
    public var benchmarkEnabled: Bool

    public init(id: String, exerciseId: String, weightLb: Double, reps: [Int],
                minReps: Int, maxReps: Int, incrementLb: Double,
                loadBasis: LoadBasis, implementCount: Int, isPerSide: Bool = false,
                intent: TFHIntent = .develop, benchmarkEnabled: Bool = false) {
        self.id = id; self.exerciseId = exerciseId; self.weightLb = weightLb; self.reps = reps
        self.minReps = minReps; self.maxReps = maxReps; self.incrementLb = incrementLb
        self.loadBasis = loadBasis; self.implementCount = implementCount
        self.isPerSide = isPerSide; self.intent = intent; self.benchmarkEnabled = benchmarkEnabled
    }

    public var isValid: Bool {
        !id.isEmpty && !exerciseId.isEmpty && weightLb.isFinite && weightLb >= 0
            && minReps > 0 && maxReps >= minReps && maxReps <= 1000 && !reps.isEmpty && reps.count <= 10
            && reps.allSatisfy { $0 >= minReps && $0 <= maxReps }
            && implementCount > 0 && incrementLb.isFinite && incrementLb >= 0
            && (loadBasis != .bodyweight || weightLb == 0)
    }
}

public struct TFHSet: Codable, Equatable, Sendable {
    public var weightLb: Double
    public var reps: Int
    public var plannedWeightLb: Double?
    public var plannedReps: Int?
    public var status: String
    public var loadBasis: LoadBasis
    public var implementCount: Int
    public var isPerSide: Bool
    public var quality: String?
    public var stoppedEarly: Bool
    public var hasBodyFlag: Bool
    public var benchmark: Bool
    public var stopReason: String?
    public var restSeconds: Double?

    public init(weightLb: Double, reps: Int, plannedWeightLb: Double?, plannedReps: Int?,
                status: String = "completed", loadBasis: LoadBasis, implementCount: Int,
                isPerSide: Bool = false, quality: String? = nil, stoppedEarly: Bool = false,
                hasBodyFlag: Bool = false, benchmark: Bool = false,
                stopReason: String? = nil, restSeconds: Double? = nil) {
        self.weightLb = weightLb; self.reps = reps; self.plannedWeightLb = plannedWeightLb
        self.plannedReps = plannedReps; self.status = status; self.loadBasis = loadBasis
        self.implementCount = implementCount; self.isPerSide = isPerSide; self.quality = quality
        self.stoppedEarly = stoppedEarly; self.hasBodyFlag = hasBodyFlag
        self.benchmark = benchmark; self.stopReason = stopReason; self.restSeconds = restSeconds
    }
}

public struct TFHExposure: Codable, Equatable, Sendable {
    public var id: String
    public var anchorId: String
    public var exerciseId: String
    public var cycle: Int
    public var rotation: Int
    public var sets: [TFHSet]
    /// A caller-supplied, recorded benchmark context. Missing is not equal to
    /// known identical conditions. Do not generate it from current settings.
    public var context: String?

    public init(id: String, anchorId: String, exerciseId: String, cycle: Int,
                rotation: Int, sets: [TFHSet], context: String? = nil) {
        self.id = id; self.anchorId = anchorId; self.exerciseId = exerciseId
        self.cycle = cycle; self.rotation = rotation; self.sets = sets; self.context = context
    }
}

public struct TFHPrescription: Codable, Equatable, Sendable {
    public var weightLb: Double
    public var reps: [Int]
    public var benchmark: Bool
    public var state: String
    public var reason: String
    public var evidenceIds: [String]
}

public struct TFHAssessment: Codable, Equatable, Sendable {
    public var state: String
    public var reason: String
    public var evidenceIds: [String]
}

/// Bounded, evidence-driven policy; not a fitted physiological growth curve.
/// Mirrors tfhProject/tfhPlateau in web/app/js/core.js. No clock or persistence.
public enum TFHProgression {
    private static let tolerance = 0.001
    private static func same(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b, a.isFinite, b.isFinite else { return false }
        return abs(a - b) <= tolerance
    }

    private static func history(_ a: TFHAnchor, _ exposures: [TFHExposure],
                                _ cycle: Int, _ rotation: Int) -> [TFHExposure] {
        exposures.filter {
            $0.anchorId == a.id && $0.exerciseId == a.exerciseId && $0.cycle > 0
                && (1...3).contains($0.rotation)
                && ($0.cycle < cycle || ($0.cycle == cycle && $0.rotation < rotation))
        }.sorted { ($0.cycle, $0.rotation) < ($1.cycle, $1.rotation) }
    }

    private static func planSets(_ a: TFHAnchor, _ e: TFHExposure) -> Bool {
        e.sets.count == a.reps.count && e.sets.allSatisfy { s in
            guard let plannedWeight = s.plannedWeightLb, let plannedReps = s.plannedReps else { return false }
            return plannedWeight.isFinite && plannedWeight >= 0 && plannedReps > 0 && plannedReps <= 1000
                && (a.loadBasis != .bodyweight || plannedWeight == 0)
                && s.loadBasis == a.loadBasis && s.implementCount == a.implementCount
                && s.isPerSide == a.isPerSide
        }
    }

    private static func usable(_ a: TFHAnchor, _ e: TFHExposure) -> Bool {
        planSets(a, e) && e.sets.allSatisfy { s in
            s.status == "completed" && s.quality == "clean" && !s.stoppedEarly && !s.hasBodyFlag
                && s.weightLb.isFinite && s.weightLb >= 0 && s.reps > 0 && s.reps <= 1000
                && (a.loadBasis != .bodyweight || s.weightLb == 0)
        }
    }

    private static func made(_ a: TFHAnchor, _ e: TFHExposure) -> Bool {
        usable(a, e) && e.sets.allSatisfy {
            same($0.weightLb, $0.plannedWeightLb) && $0.reps >= ($0.plannedReps ?? Int.max)
        }
    }

    private static func ambiguous(_ history: [TFHExposure]) -> Bool {
        Set(history.map { "\($0.cycle):\($0.rotation)" }).count != history.count
    }

    public static func project(anchor a: TFHAnchor, exposures: [TFHExposure],
                               cycle: Int, rotation: Int) -> TFHPrescription? {
        guard a.isValid, cycle > 0, (1...4).contains(rotation) else { return nil }
        var plan = TFHPrescription(weightLb: a.weightLb, reps: a.reps, benchmark: false,
                                  state: "learning", reason: "Starting from the authored TFH targets.", evidenceIds: [])
        let history = history(a, exposures, cycle, rotation)
        // Abstain instead of silently resetting progressed work to the starting anchor.
        guard !ambiguous(history) else { return nil }
        let reference = history.last(where: { $0.rotation == rotation }) ?? history.last
        let recentWorkSupportsProgress = history.last.map { made(a, $0) } ?? true
        if let reference {
            guard planSets(a, reference), reference.sets.allSatisfy({
                guard let reps = $0.plannedReps else { return false }
                return reps >= a.minReps && reps <= a.maxReps
            }) else { return nil }
            let sets = reference.sets
            let uniform = sets.allSatisfy { same($0.plannedWeightLb, sets[0].plannedWeightLb) }
            guard uniform else { return nil }
            if uniform, let weight = sets[0].plannedWeightLb {
                plan.weightLb = weight
                plan.reps = sets.compactMap(\.plannedReps)
                plan.evidenceIds = [reference.id]
            }
            let earned = uniform && made(a, reference) && recentWorkSupportsProgress
            plan.state = "hold"
            plan.reason = "Repeat the comparable prescription; more work has not been earned."
            if earned && a.intent == .develop && rotation != 4 {
                if let index = plan.reps.firstIndex(where: { $0 < a.maxReps }) {
                    plan.reps[index] += 1
                    plan.state = "progress"
                    plan.reason = "Add one total work rep while preserving the load and number of sets."
                } else {
                    let top = Array(history.filter { $0.rotation == reference.rotation }.suffix(2))
                    let topIsConsecutive = top.count == 2 && top[1].cycle - top[0].cycle == 1
                    let topIsComplete = topIsConsecutive && top.allSatisfy { e in
                        usable(a, e) && e.sets.allSatisfy { s in
                            same(s.weightLb, plan.weightLb) && same(s.plannedWeightLb, plan.weightLb)
                                && (s.plannedReps ?? 0) >= a.maxReps && s.reps >= (s.plannedReps ?? Int.max)
                        }
                    }
                    let step = a.incrementLb
                    let relativeStep = plan.weightLb > 0 ? step / plan.weightLb : Double.infinity
                    // TFH candidate guard, not a measured physiological threshold.
                    let canLoad = a.loadBasis != .bodyweight && step > 0
                        && relativeStep <= 0.10 + 1e-9 && topIsComplete
                    if canLoad && (a.loadBasis != .assisted || step <= plan.weightLb) {
                        plan.weightLb += a.loadBasis == .assisted ? -step : step
                        plan.reps = plan.reps.map { _ in a.minReps }
                        plan.state = "progress"
                        plan.reason = "Two matching top-range exposures support one equipment step; reps restart at the authored minimum."
                        plan.evidenceIds = top.suffix(2).map(\.id)
                    } else {
                        plan.reason = "The rep range is complete. Hold while the next equipment step or skill change is reviewed."
                    }
                }
            }
        }
        if a.intent != .develop {
            plan.state = a.intent == .maintain ? "maintain" : "practice"
            plan.reason = "Preserve the authored capability while other priorities develop."
        }
        if rotation == 4 {
            plan.reps = Array(plan.reps.prefix(max(1, (plan.reps.count + 1) / 2))).map { _ in a.minReps }
            if a.loadBasis != .bodyweight && a.loadBasis != .assisted {
                let step = a.incrementLb
                plan.weightLb = step > 0 ? floor((plan.weightLb * 0.8 + 1e-9) / step) * step : plan.weightLb * 0.8
            }
            plan.state = "recover"
            plan.reason = "Light recovery work; no progression or capacity test."
        }
        plan.benchmark = recentWorkSupportsProgress && rotation == 3
            && a.intent == .develop && a.benchmarkEnabled
        return plan
    }

    public static func plateau(anchor a: TFHAnchor, exposures: [TFHExposure],
                               completedCycles: [Int], currentCycle: Int) -> TFHAssessment {
        func result(_ state: String, _ reason: String, _ ids: [String] = []) -> TFHAssessment {
            TFHAssessment(state: state, reason: reason, evidenceIds: ids)
        }
        guard a.isValid, currentCycle > 0 else { return result("learning", "TFH targets are incomplete.") }
        guard a.intent == .develop else {
            return result("notAssessing", "Intentional maintenance and skill practice are not plateau attempts.")
        }
        let cycles = Array(Set(completedCycles).filter { $0 > 0 && $0 < currentCycle }.sorted().suffix(3))
        guard cycles.count == 3, cycles[2] - cycles[0] == 2, cycles[2] == currentCycle - 1 else {
            return result("learning", "A complete baseline and two subsequent complete comparable cycles are required.")
        }
        let history = history(a, exposures, currentCycle, 1).filter { cycles.contains($0.cycle) }
        guard history.count == 9, !ambiguous(history), history.allSatisfy({ usable(a, $0) }) else {
            return result("learning", "The three-cycle evidence is incomplete or ambiguous.")
        }
        let ids = history.map(\.id)
        var changed = false
        var declined = false
        var progressReason: String?
        for c in 1..<cycles.count {
            for rotation in 1...3 {
                guard let old = history.first(where: { $0.cycle == cycles[c - 1] && $0.rotation == rotation }),
                      let next = history.first(where: { $0.cycle == cycles[c] && $0.rotation == rotation }) else {
                    return result("learning", "The three-cycle evidence is incomplete or ambiguous.")
                }
                let sameLoads = zip(old.sets, next.sets).allSatisfy { same($0.weightLb, $1.weightLb) }
                let oldReps = old.sets.reduce(0) { $0 + $1.reps }
                let nextReps = next.sets.reduce(0) { $0 + $1.reps }
                let comparableContext = old.context != nil && old.context != "" && old.context == next.context
                if comparableContext && sameLoads && nextReps > oldReps {
                    progressReason = "More clean work at the same load."
                }
                let harder = zip(old.sets, next.sets).allSatisfy {
                    a.loadBasis == .assisted ? $1.weightLb <= $0.weightLb : $1.weightLb >= $0.weightLb
                }
                if comparableContext && !sameLoads && harder && zip(old.sets, next.sets).allSatisfy({ $1.reps >= $0.reps }) {
                    progressReason = "The same or greater work was completed at a harder load."
                }
                if !sameLoads || oldReps != nextReps { changed = true }
                if comparableContext && sameLoads && nextReps < oldReps { declined = true }
                if !comparableContext { changed = true }
            }
        }
        if declined { return result("review", "Comparable performance fell; review recovery and workload.", ids) }
        if let progressReason { return result("progressing", progressReason, ids) }
        if changed { return result("learning", "Changed load or context prevents a flat-capacity comparison.", ids) }
        let peaks = history.filter { $0.rotation == 3 }
        for e in peaks {
            guard let last = e.sets.last, last.benchmark, last.stopReason == "technicalLimit",
                  let rest = last.restSeconds, rest.isFinite, rest > 0 else {
                return result("learning", "A comparable uncapped technical benchmark is missing.", ids)
            }
            let base = peaks[0]
            if !same(last.restSeconds, base.sets.last?.restSeconds)
                || zip(e.sets.dropLast(), base.sets.dropLast()).contains(where: { $0.reps != $1.reps || !same($0.weightLb, $1.weightLb) }) {
                return result("learning", "Benchmark rest or preceding work changed.", ids)
            }
        }
        return result("possiblePlateau", "No measurable improvement across two complete cycles after the baseline. Review the plan.", ids)
    }
}
