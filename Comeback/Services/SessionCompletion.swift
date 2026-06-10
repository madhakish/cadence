import Foundation
import SwiftData
import ComebackCore

/// End-of-session summary: volume per lift, top sets, milestones hit.
struct SessionSummary {
    struct LiftLine: Identifiable {
        let id = UUID()
        let exerciseName: String
        let topSetLabel: String
        let volumeLb: Double
    }

    let lines: [LiftLine]
    let milestones: [PREvent]
}

enum SessionCompletion {

    /// Close out a session: detect PRs against all prior completed sessions,
    /// persist milestones, advance any matching lift tracks, and arm the
    /// next-morning knee check-in if the session included running.
    @discardableResult
    static func finish(_ session: WorkoutSession, context: ModelContext) -> SessionSummary {
        session.isCompleted = true

        var lines: [SessionSummary.LiftLine] = []
        var allEvents: [PREvent] = []

        for entry in session.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            let working = entry.workingSets.map { SetSample(weightLb: $0.weightLb, reps: $0.reps) }
            guard !working.isEmpty else { continue }

            if let top = entry.topSet {
                lines.append(SessionSummary.LiftLine(
                    exerciseName: exercise.name,
                    topSetLabel: "\(Weight.trim(top.weightLb))×\(top.reps)",
                    volumeLb: entry.workingVolumeLb
                ))
            }

            let history = priorHistory(for: exercise.name, before: session.date, context: context)
            let events = PRDetection.evaluate(
                exercise: exercise.name,
                sessionSets: working,
                historySets: history.sets,
                historyVolumes: history.volumes,
                historySchemes: history.schemes
            )
            for event in events {
                context.insert(Milestone(
                    date: session.date, exerciseName: exercise.name,
                    kind: event.kind, label: event.label
                ))
            }
            allEvents.append(contentsOf: events)

            advanceTrackIfNeeded(for: exercise.name, context: context)
        }

        if session.includesRunning {
            NotificationService.scheduleKneeCheckIn(afterSessionOn: session.date)
        }

        try? context.save()
        return SessionSummary(lines: lines, milestones: allEvents)
    }

    /// All working sets / volumes / top schemes for an exercise across prior
    /// completed sessions.
    private static func priorHistory(
        for exerciseName: String,
        before date: Date,
        context: ModelContext
    ) -> (sets: [SetSample], volumes: [Double], schemes: Set<String>) {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.isCompleted && $0.date < date }
        )
        let sessions = (try? context.fetch(descriptor)) ?? []

        var sets: [SetSample] = []
        var volumes: [Double] = []
        var schemes: Set<String> = []

        for s in sessions {
            for entry in s.exercises where entry.exercise?.name == exerciseName {
                let working = entry.workingSets.map { SetSample(weightLb: $0.weightLb, reps: $0.reps) }
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

    private static func advanceTrackIfNeeded(for exerciseName: String, context: ModelContext) {
        let descriptor = FetchDescriptor<LiftTrack>(
            predicate: #Predicate { $0.exerciseName == exerciseName }
        )
        guard let track = try? context.fetch(descriptor).first else { return }
        track.completeSession()
    }
}
