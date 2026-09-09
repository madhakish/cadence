import Foundation
import SwiftData
import CadenceCore

/// TFH owns no mutable weight/stall grades. Its inputs are the authored cohort
/// and immutable session prescriptions; corrections are read on the next plan.
enum TFHProgramService {
    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let reason): return "TFH: \(reason)" }
        }
    }

    static func encode<T: Encodable>(_ value: T?) throws -> Data? {
        try value.map { try JSONEncoder().encode($0) }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) throws -> T? {
        try data.map { try JSONDecoder().decode(type, from: $0) }
    }

    static func policy(_ program: Program) throws -> TFHProgramPolicy? {
        guard let p = try decode(TFHProgramPolicy.self, program.tfhPolicyData) else { return nil }
        let slots = program.days.flatMap { $0.lifts.map { ($0.id, $0.exerciseID) }
            + $0.accessories.map { ($0.id, $0.exerciseID) } }
        guard p.isValid, p.dayOrders == program.orderedDays.map(\.order), p.layout == layout(program),
              Set(slots.map { $0.0 }).count == slots.count,
              p.anchors.allSatisfy({ id, anchor in
                  slots.contains { $0.0 == id && $0.1 == anchor.exerciseId }
              }) else { throw Failure.invalid("The program composition changed. Review TFH setup before starting.") }
        return p
    }

    static func layout(_ program: Program) -> [String: String] {
        var out: [String: String] = [:]
        for day in program.days {
            for l in day.lifts { out[l.id] = "\(day.order):\(l.roleRaw):\(l.order)" }
            for a in day.accessories { out[a.id] = "\(day.order):accessory:\(a.order)" }
        }
        return out
    }

    static func cohort(_ program: Program, _ policy: TFHProgramPolicy,
                       _ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.filter { s in
            s.isCompleted && s.programID == program.id && s.tfhPolicyID == policy.id
                && s.tfhExcludedFromProgression != true
                && s.exercises.contains { e in
                    e.programSlotID != nil && e.workingSets.contains { PrescriptionBlockKind(rawValue: $0.prescriptionBlockRaw) != .warmup }
                }
        }
    }

    static func position(_ program: Program, policy: TFHProgramPolicy,
                         sessions: [WorkoutSession]) throws -> TFHPosition {
        let completed = try cohort(program, policy, sessions).map { s -> TFHCompletion in
            guard let cycle = s.programCycleNumber, let rotation = s.programWeek,
                  let day = s.programDayIndex, cycle >= policy.startCycle,
                  (1...4).contains(rotation), day >= 0 else { throw Failure.invalid("A completed session has incomplete position tags.") }
            return TFHCompletion(cycle: cycle, rotation: rotation, dayOrder: day)
        }
        guard let position = TFHSchedule.position(policy: policy, completions: completed) else {
            throw Failure.invalid("Session positions are ambiguous. Review duplicate history before starting.")
        }
        return position
    }

    @discardableResult
    static func synchronize(_ program: Program, sessions: [WorkoutSession]) throws -> TFHPosition? {
        guard let p = try policy(program) else { return nil }
        let next = try position(program, policy: p, sessions: sessions)
        program.cycleNumber = next.cycle; program.currentWeek = next.rotation
        program.nextDayIndex = next.dayOrder
        return next
    }

    static func exposures(_ program: Program, policy: TFHProgramPolicy,
                          sessions: [WorkoutSession]) throws -> [TFHExposure] {
        try cohort(program, policy, sessions).flatMap { session in
            try session.orderedExercises.compactMap { entry -> TFHExposure? in
                guard let anchor = try decode(TFHAnchor.self, entry.tfhAnchorData) else { return nil }
                guard anchor.isValid, let cycle = session.programCycleNumber,
                      let rotation = session.programWeek, entry.exerciseID == anchor.exerciseId else {
                    throw Failure.invalid("A session's TFH identity or prescription is incomplete.")
                }
                let sets = try entry.plannedWorkingSets.map { set -> TFHSet in
                    let benchmark = try decode(TFHBenchmarkResult.self, set.tfhBenchmarkData)
                    guard benchmark?.isValid != false else { throw Failure.invalid("Invalid benchmark evidence.") }
                    return TFHSet(weightLb: set.weightLb, reps: set.reps,
                                  plannedWeightLb: set.plannedWeightLb, plannedReps: set.plannedReps,
                                  status: set.status.rawValue, loadBasis: set.loadBasis,
                                  implementCount: set.resolvedImplementCount, isPerSide: set.isPerSide,
                                  quality: set.quality?.rawValue,
                                  stoppedEarly: set.flags.contains(.stoppedEarly), hasBodyFlag: set.bodyFlagSite != nil,
                                  benchmark: set.tfhBenchmarkData != nil,
                                  stopReason: benchmark?.stopReason?.rawValue, restSeconds: benchmark?.restSeconds)
                }
                return TFHExposure(id: "\(session.id):\(entry.programSlotID ?? anchor.id)", anchorId: anchor.id,
                                   exerciseId: anchor.exerciseId, cycle: cycle, rotation: rotation,
                                   sets: sets, context: session.tfhContext)
            }
        }
    }

    static func prescription(_ program: Program, slotID: String, sessions: [WorkoutSession],
                             rotation: Int? = nil) throws -> (TFHAnchor, TFHPrescription)? {
        guard let p = try policy(program), let anchor = p.anchors[slotID] else { return nil }
        let next = try position(program, policy: p, sessions: sessions)
        guard let plan = TFHProgression.project(anchor: anchor,
                exposures: try exposures(program, policy: p, sessions: sessions),
                cycle: next.cycle, rotation: rotation ?? next.rotation) else {
            throw Failure.invalid("The recorded targets for this slot cannot be compared. Review its history or start a new TFH cohort.")
        }
        return (anchor, plan)
    }

    /// A reviewable starting point, never automatic migration of past grades.
    /// Only an exact slot and exercise match can seed actual performed loading.
    static func draft(_ program: Program, exercises: [Exercise], sessions: [WorkoutSession]) throws -> TFHProgramPolicy {
        var anchors: [String: TFHAnchor] = [:]
        let mine = sessions.filter { $0.isCompleted && $0.programID == program.id }
            .sorted { $0.effectiveCompletionDate > $1.effectiveCompletionDate }
        func make(id: String, name: String, weight: Double, sets: Int, reps: Int, min: Int, max: Int,
                  step: Double) throws {
            guard let ex = exercises.first(where: { $0.name == name }), let exerciseID = ex.id else {
                throw Failure.invalid("\(name) needs a stable exercise identity.")
            }
            if ex.type == .timed || ex.type == .conditioning { return }
            let previous = mine.lazy.compactMap { s in
                s.exercises.first { $0.programSlotID == id && $0.exerciseID == exerciseID }
            }.first
            let work = previous?.workingSets ?? []
            let uniform = !work.isEmpty && work.allSatisfy { abs($0.weightLb - work[0].weightLb) < 0.001 }
            let startingWeight = ex.loadBasis == .bodyweight ? 0 : (uniform ? work[0].weightLb : weight)
            let lo = Swift.max(1, min), hi = Swift.max(Swift.max(1, min), max)
            let startingReps = Swift.min(hi, Swift.max(lo, reps))
            anchors[id] = TFHAnchor(id: UUID().uuidString, exerciseId: exerciseID, weightLb: startingWeight,
                reps: Array(repeating: startingReps, count: Swift.min(10, Swift.max(1, sets))),
                minReps: lo, maxReps: hi, incrementLb: ex.type == .dumbbell ? 5 : step,
                loadBasis: ex.loadBasis, implementCount: ex.resolvedImplementCount, isPerSide: ex.isUnilateral,
                intent: ex.movementGroup == "olympic" ? .practice : .develop)
        }
        for day in program.orderedDays {
            for l in day.orderedLifts {
                try make(id: l.id, name: l.exerciseName, weight: l.baseWeightLb,
                         sets: l.doubleProgressionSets, reps: l.currentReps,
                         min: l.minimumReps, max: l.maximumReps, step: program.roundingLb)
            }
            for a in day.orderedAccessories {
                try make(id: a.id, name: a.exerciseName, weight: a.weightLb, sets: a.sets,
                         reps: a.currentReps, min: a.minReps, max: a.maxReps, step: a.incrementLb)
            }
        }
        let maxCycle = mine.compactMap(\.programCycleNumber).max() ?? 0
        let start = Swift.max(program.cycleNumber, maxCycle + 1)
        let orders = program.orderedDays.map(\.order)
        return TFHProgramPolicy(id: UUID().uuidString, startCycle: start, dayOrders: orders,
                                recoveryDayOrders: Array(orders.prefix(2)), anchors: anchors, layout: layout(program))
    }

    static func activate(_ draft: TFHProgramPolicy, program: Program,
                         exercises: [Exercise], context: ModelContext) throws {
        guard draft.isValid else { throw Failure.invalid("Review the rep ranges, loads, and recovery days.") }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        guard !sessions.contains(where: { !$0.isCompleted && $0.programID == program.id }) else {
            throw Failure.invalid("Finish or discard this program's open session before changing its method.")
        }
        do {
            // Stamp library identities without changing slot or historical IDs.
            for day in program.days {
                for l in day.lifts { l.exerciseID = exercises.first { $0.name == l.exerciseName }?.id }
                for a in day.accessories { a.exerciseID = exercises.first { $0.name == a.exerciseName }?.id }
            }
            program.tfhPolicyData = try encode(draft)
            _ = try synchronize(program, sessions: sessions)
            try context.save()
        } catch { context.rollback(); throw error }
    }

    static func complete(_ session: WorkoutSession, program: Program, context: ModelContext) throws {
        guard let p = try policy(program), session.tfhPolicyID == p.id else { return }
        // The caller has marked this session complete within its save/rollback
        // boundary. Fetch includes pending changes. No legacy grade is replayed.
        _ = try synchronize(program, sessions: context.fetch(FetchDescriptor<WorkoutSession>()))
    }
}
