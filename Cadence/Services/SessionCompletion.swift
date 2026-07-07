import Foundation
import SwiftData
import CadenceCore

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
    /// persist milestones, advance any matching lift tracks, mirror the
    /// workout to HealthKit (when enabled and finished live), and arm the
    /// next-morning knee check-in if the session included running.
    ///
    /// `startedAt` is the logger's ephemeral session-clock origin (view-open
    /// time). The Health workout is written only when that origin falls on the
    /// session's own day — a session resumed and banked days later is a
    /// backfill, and a made-up duration is worse than no sample.
    @discardableResult
    static func finish(_ session: WorkoutSession, context: ModelContext, startedAt: Date? = nil) -> SessionSummary {
        // Idempotence backstop (mirrors web completeSession): finishing twice
        // would duplicate milestones and double-advance tracks/programs.
        guard !session.isCompleted else { return SessionSummary(lines: [], milestones: []) }
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

            // Program-owned exercises advance via the program, never the standalone track.
            if entry.programRole == nil {
                advanceTrackIfNeeded(for: exercise.name, context: context)
            }
        }

        if session.programName != nil {
            advanceProgram(session, context: context, events: &allEvents)
        }

        if session.includesRunning {
            NotificationService.scheduleKneeCheckIn(afterSessionOn: session.date)
        }

        // Mirror to Health only when the session was finished live on its own
        // day — a session resumed days later would otherwise produce a bogus
        // seconds-long workout dated today (sessionStart is view-open time).
        if let start = startedAt,
           Calendar.current.isDate(start, inSameDayAs: session.date),
           healthKitEnabled(context) {
            let end = Date()
            Task { await HealthKitService.shared.saveStrengthWorkout(start: start, end: end) }
        }

        do {
            try context.save()
        } catch {
            // Keep the session retryable: with the flag left set, a retry
            // would no-op through the idempotence guard without persisting.
            session.isCompleted = false
        }
        return SessionSummary(lines: lines, milestones: allEvents)
    }

    private static func healthKitEnabled(_ context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<AppSettings>()
        return (try? context.fetch(descriptor).first?.healthKitEnabled) ?? false
    }

    // MARK: - Program day/week/cycle advancement (mirrors web advanceProgram)

    private static func cyclePerf(_ entry: SessionExercise) -> CycleLiftPerformance {
        let w = entry.workingSets
        let presReps = entry.plannedReps ?? (w.map(\.reps).max() ?? 0)
        let top = w.max { $0.weightLb < $1.weightLb }
        return CycleLiftPerformance(
            prescribedSets: entry.plannedSets ?? w.count,
            prescribedReps: presReps,
            completedSets: w.filter { $0.reps >= presReps }.count,
            anyStoppedEarly: w.contains { $0.flags.contains(.stoppedEarly) },
            anyDroppedLoad: w.contains { $0.autoregReason != nil },
            grindyOrWobbleSets: w.filter { $0.flags.contains(.grindy) || $0.flags.contains(.wobble) }.count,
            topSetWeightLb: top?.weightLb ?? 0,
            topSetReps: top?.reps ?? 0
        )
    }

    private static func accPerf(_ entry: SessionExercise) -> AccessoryPerformance {
        let w = entry.workingSets
        return AccessoryPerformance(
            completedSets: w.count,
            minRepsAchieved: w.map(\.reps).min() ?? 0,
            anyStoppedEarly: w.contains { $0.flags.contains(.stoppedEarly) }
        )
    }

    private static func advanceProgram(_ session: WorkoutSession, context: ModelContext, events: inout [PREvent]) {
        guard let name = session.programName else { return }
        let descriptor = FetchDescriptor<Program>(predicate: #Predicate { $0.name == name })
        guard let program = try? context.fetch(descriptor).first else { return }
        let dayIndex = session.programDayIndex ?? 0
        guard let day = program.days.first(where: { $0.order == dayIndex }) else { return }
        let week = session.programWeek ?? program.currentWeek

        // Accessories: double progression, every bank.
        for acc in day.accessories {
            if let entry = session.exercises.first(where: { $0.programRole == "accessory" && $0.exercise?.name == acc.exerciseName }) {
                acc.apply(ProgramProgression.advanceAccessory(acc.coreState, perf: accPerf(entry)))
            }
        }

        // Cycle lifts: grade at the week-3 Peak, stash pending; apply at rollover.
        if week == 3 {
            for lift in day.lifts {
                if let entry = session.exercises.first(where: { $0.exercise?.name == lift.exerciseName && $0.programRole == lift.role.rawValue }) {
                    let result = ProgramProgression.advanceCycleLift(lift.coreState, perf: cyclePerf(entry), focus: program.focus, roundingLb: program.roundingLb)
                    lift.pendingBaseWeightLb = result.state.baseWeightLb
                    lift.pendingEstimatedMaxLb = result.state.estimatedMaxLb
                    lift.pendingStallCount = result.state.stallCount
                    lift.pendingLastIncrementLb = result.state.lastIncrementLb
                    lift.pendingNote = result.note
                }
            }
        }

        let lastDay = dayIndex == program.days.count - 1
        program.nextDayIndex = (dayIndex + 1) % Swift.max(1, program.days.count)
        guard lastDay else { return }

        if program.currentWeek < 4 {
            program.currentWeek += 1
            return
        }

        // Rollover at the deload week's last day.
        for d in program.days {
            for lift in d.lifts {
                if let pendingBase = lift.pendingBaseWeightLb {
                    lift.baseWeightLb = pendingBase
                    lift.estimatedMaxLb = lift.pendingEstimatedMaxLb ?? lift.estimatedMaxLb
                    lift.stallCount = lift.pendingStallCount ?? lift.stallCount
                    lift.lastIncrementLb = lift.pendingLastIncrementLb ?? 0
                    if let note = lift.pendingNote {
                        let label = "\(lift.exerciseName): \(note)"
                        context.insert(Milestone(date: session.date, exerciseName: lift.exerciseName, kind: .programNote, label: label))
                        events.append(PREvent(kind: .programNote, exercise: lift.exerciseName, label: label))
                    }
                    lift.pendingBaseWeightLb = nil
                    lift.pendingEstimatedMaxLb = nil
                    lift.pendingStallCount = nil
                    lift.pendingLastIncrementLb = nil
                    lift.pendingNote = nil
                } else {
                    // Peak never banked → treat as a stall.
                    lift.stallCount += 1
                    lift.lastIncrementLb = 0
                    if lift.stallCount >= ProgramProgression.stallLimit {
                        let old = lift.baseWeightLb
                        lift.baseWeightLb = Weight.round(old * ProgramProgression.deloadRebuildFraction, to: program.roundingLb)
                        lift.stallCount = 0
                        let label = "\(lift.exerciseName): skipped peak — deloaded \(Weight.trim(old))→\(Weight.trim(lift.baseWeightLb)) lb."
                        context.insert(Milestone(date: session.date, exerciseName: lift.exerciseName, kind: .programNote, label: label))
                        events.append(PREvent(kind: .programNote, exercise: lift.exerciseName, label: label))
                    }
                }
            }
        }
        program.cycleNumber += 1
        program.currentWeek = 1
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
