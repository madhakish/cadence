import CadenceCore
import Foundation
import SwiftData

/// One owner for "what PRs did this exposure earn" (epic #155 Stage 0/6),
/// shared by bank time (`SessionCompletion`) and the post-correction rebuild
/// so a rebuilt milestone can never disagree with the one banking wrote.
/// Models-only on purpose: the hostless macOS suite compiles it, which is
/// what makes the rebuild testable at all. Mirrors web `rebuildMilestones`
/// and its helpers in views/session.js.
enum MilestoneProjection {
    /// PR kinds this projection owns. Everything else in the milestone store
    /// (notably `programNote`) is written elsewhere and never touched here.
    static let ownedKinds: Set<PREvent.Kind> = [.heaviestSet, .firstScheme, .volumePR, .repPR]

    static func sample(_ set: SetEntry) -> SetSample {
        SetSample(weightLb: set.weightLb, reps: set.reps, isPerSide: set.isPerSide,
                  loadBasis: set.loadBasis, implementCount: set.resolvedImplementCount)
    }

    /// All working sets / volumes / top schemes for an exercise across prior
    /// completed sessions. Work logged inside an active-recovery span never
    /// joins the baseline: a heavy recovery set left in history would suppress
    /// every later legitimate PR forever (INV-RECOVERY-WORK-IS-OFF-PROGRAM).
    static func priorHistory(
        for exerciseName: String,
        basis: LoadBasis,
        before date: Date,
        context: ModelContext,
        excludingOffProgram intervals: [TrainingIntervalSnapshot] = []
    ) throws -> (sets: [SetSample], volumes: [Double], schemes: Set<String>) {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.isCompleted && $0.date < date }
        )
        let sessions = try context.fetch(descriptor).filter {
            !TrainingIntervals.isOffProgramTime(
                $0.date.timeIntervalSince1970 * 1000, intervals: intervals
            )
        }
        var sets: [SetSample] = []
        var volumes: [Double] = []
        var schemes: Set<String> = []
        for session in sessions {
            for entry in session.exercises where entry.exercise?.name == exerciseName {
                let working = entry.workingSets.map(sample).filter { $0.loadBasis == basis }
                guard !working.isEmpty else { continue }
                sets.append(contentsOf: working)
                volumes.append(PRDetection.volume(working))
                if let top = PRDetection.topScheme(working) {
                    schemes.insert("\(top.sets)×\(top.reps)")
                }
            }
        }
        return (sets, volumes, schemes)
    }

    /// Regenerate PR milestones for the affected lifts deterministically from
    /// the canonical sessions — replayed in order, never appended to. Records
    /// this projection does not own are left exactly as they are, and
    /// replaying unchanged history reproduces the same set (idempotent).
    @discardableResult
    static func rebuild(
        exerciseNames: Set<String>,
        context: ModelContext,
        intervals: [TrainingIntervalSnapshot] = [],
        formatWeight: @escaping (Double) -> String
    ) throws -> Int {
        guard !exerciseNames.isEmpty else { return 0 }
        let ordered = try context.fetch(
            FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.isCompleted },
                sortBy: [SortDescriptor(\.date)]
            )
        )
        var rebuilt: [(date: Date, name: String, event: PREvent)] = []
        for session in ordered {
            guard !TrainingIntervals.isOffProgramTime(
                session.date.timeIntervalSince1970 * 1000, intervals: intervals) else { continue }
            for name in exerciseNames {
                let working = session.exercises
                    .filter { $0.exercise?.name == name }
                    .flatMap(\.workingSets).map(sample)
                guard let basis = working.first?.loadBasis else { continue }
                let scoped = working.filter { $0.loadBasis == basis }
                let history = try priorHistory(for: name, basis: basis, before: session.date,
                                               context: context, excludingOffProgram: intervals)
                let events = PRDetection.evaluate(
                    exercise: name, sessionSets: scoped, historySets: history.sets,
                    historyVolumes: history.volumes, historySchemes: history.schemes,
                    formatWeight: formatWeight
                )
                for event in events { rebuilt.append((session.date, name, event)) }
            }
        }
        // Replace only what this projection owns.
        for milestone in try context.fetch(FetchDescriptor<Milestone>()) {
            guard let name = milestone.exerciseName, exerciseNames.contains(name),
                  let kind = PREvent.Kind(rawValue: milestone.kindRaw),
                  ownedKinds.contains(kind) else { continue }
            context.delete(milestone)
        }
        let exercisesByName = try context.fetch(FetchDescriptor<Exercise>()).indexedByName()
        for entry in rebuilt {
            let milestone = Milestone(date: entry.date, exerciseName: entry.name,
                                      kind: entry.event.kind, label: entry.event.label)
            milestone.exerciseID = exercisesByName[entry.name]?.id
            context.insert(milestone)
        }
        return rebuilt.count
    }
}
