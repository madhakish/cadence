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

    /// The save failed and everything staged was rolled back — the session is
    /// still open and Bank can simply be tapped again.
    struct SaveFailure: LocalizedError {
        let underlying: Error
        var errorDescription: String? {
            "Nothing was banked — the save failed, so the session is still open. Try again. (\(underlying.localizedDescription))"
        }
    }

    /// Close out a session: detect PRs against all prior completed sessions,
    /// persist milestones, advance any matching lift tracks, mirror the
    /// workout to HealthKit (when enabled and finished live), and arm the
    /// next-morning knee check-in if the session included running.
    ///
    /// Atomic (mirrors the web's single IndexedDB completion transaction): all
    /// mutations are staged, then committed in one save. A failed save rolls
    /// everything back — session flag, milestones, tracks, program — throws
    /// SaveFailure, and runs NO side effects, so a retry can't duplicate
    /// milestones, progression, HealthKit workouts, or notifications.
    ///
    /// `startedAt` is the logger's ephemeral session-clock origin (view-open
    /// time). The Health workout is written only when that origin falls on the
    /// session's own day — a session resumed and banked days later is a
    /// backfill, and a made-up duration is worse than no sample.
    @discardableResult
    static func finish(_ session: WorkoutSession, context: ModelContext, startedAt: Date? = nil) throws -> SessionSummary {
        // Idempotence backstop (mirrors web completeSession): finishing twice
        // would duplicate milestones and double-advance tracks/programs.
        guard !session.isCompleted else { return SessionSummary(lines: [], milestones: []) }

        // Checkpoint the logged sets BEFORE staging anything: a rollback on a
        // failed commit then discards only the completion mutations, never the
        // user's logged work. If even the checkpoint can't save, the store is
        // already failing — bail out now, with nothing staged and nothing to
        // roll back, so the guarantee holds unconditionally.
        do {
            try context.save()
        } catch {
            throw SaveFailure(underlying: error)
        }

        // Freeze the legacy fallback while the session is still open. Without
        // this, flipping isCompleted first would make every status-less set in
        // a pre-v2 open session appear performed.
        for entry in session.exercises {
            for set in entry.sets where SetStatus(rawValue: set.statusRaw) == nil {
                set.status = .planned
            }
        }
        session.isCompleted = true
        let unitDisplay = (try? context.fetch(FetchDescriptor<AppSettings>()).first?.unitDisplay) ?? .lbPrimary

        var lines: [SessionSummary.LiftLine] = []
        var allEvents: [PREvent] = []

        for entry in session.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            let working = entry.workingSets.map { SetSample(weightLb: $0.weightLb, reps: $0.reps) }
            guard !working.isEmpty else { continue }

            if let top = entry.topSet {
                lines.append(SessionSummary.LiftLine(
                    exerciseName: exercise.name,
                    topSetLabel: "\(unitDisplay.format(lb: top.weightLb)) × \(top.reps)",
                    volumeLb: entry.workingVolumeLb
                ))
            }

            let history: (sets: [SetSample], volumes: [Double], schemes: Set<String>)
            do { history = try priorHistory(for: exercise.name, before: session.date, context: context) }
            catch { context.rollback(); throw SaveFailure(underlying: error) }
            let events = PRDetection.evaluate(
                exercise: exercise.name,
                sessionSets: working,
                historySets: history.sets,
                historyVolumes: history.volumes,
                historySchemes: history.schemes,
                formatWeight: { unitDisplay.format(lb: $0) }
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
                do { try advanceTrackIfNeeded(for: exercise.name, context: context) }
                catch { context.rollback(); throw SaveFailure(underlying: error) }
            }
        }

        if (session.programID != nil || session.programName != nil) && session.hasCompletedWork {
            do { try advanceProgram(session, context: context, unitDisplay: unitDisplay, events: &allEvents) }
            catch { context.rollback(); throw SaveFailure(underlying: error) }
        }

        // Commit the staged batch through the core boundary: save, or roll
        // everything back to the checkpoint and rethrow. Side effects run
        // strictly AFTER this line — a failed save must leave no trace.
        do {
            try CompletionPersistence.commit(
                save: { try context.save() },
                rollback: { context.rollback() }
            )
        } catch {
            throw SaveFailure(underlying: error)
        }

        if session.includesRunning {
            NotificationService.scheduleKneeCheckIn(afterSessionOn: session.date)
        }

        // Mirror to Health only when the session was finished live on its own
        // day — a session resumed days later would otherwise produce a bogus
        // seconds-long workout dated today (sessionStart is view-open time).
        if let start = startedAt,
           Calendar.current.isDate(start, inSameDayAs: session.date),
           session.hasCompletedWork,
           healthKitEnabled(context) {
            let end = Date()
            Task { await HealthKitService.shared.saveStrengthWorkout(start: start, end: end) }
        }

        return SessionSummary(lines: lines, milestones: allEvents)
    }

    private static func healthKitEnabled(_ context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<AppSettings>()
        return (try? context.fetch(descriptor).first?.healthKitEnabled) ?? false
    }

    // MARK: - Program day/week/cycle advancement (mirrors web advanceProgram)

    private static func cyclePerf(_ entry: SessionExercise, roundingLb: Double) -> CycleLiftPerformance {
        let w = entry.workingSets
        let presReps = entry.plannedReps ?? (w.map(\.reps).max() ?? 0)
        let top = w.max { $0.weightLb < $1.weightLb }
        return CycleLiftPerformance(
            prescribedSets: entry.plannedSets ?? w.count,
            prescribedReps: presReps,
            completedSets: w.filter { $0.reps >= presReps }.count,
            anyStoppedEarly: w.contains { $0.flags.contains(.stoppedEarly) },
            anyDroppedLoad: w.contains { $0.autoregReason != nil },
            anyBelowPlanLoad: ProgramProgression.belowPlanWork(
                weightsLb: w.map(\.weightLb), plannedLb: entry.plannedWeightLb,
                prescribedSets: entry.plannedSets ?? w.count, roundingLb: roundingLb
            ),
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

    private static func advanceProgram(_ session: WorkoutSession, context: ModelContext,
                                       unitDisplay: UnitDisplay, events: inout [PREvent]) throws {
        let programs = try context.fetch(FetchDescriptor<Program>())
        guard let program = session.programID.flatMap({ id in programs.first { $0.id == id } })
                ?? programs.first(where: { $0.name == session.programName }) else { return }
        let dayIndex = session.programDayIndex ?? 0
        guard let day = program.days.first(where: { $0.order == dayIndex }) else { return }
        let week = session.programWeek ?? program.currentWeek

        // Duplicate/stale guard (mirrors web advanceProgram): the tag captured
        // at creation must still match the program's live position, or this
        // bank must not move the schedule again. Untagged legacy fields fall
        // back to the current value (they can't disagree).
        let tagCycle = session.programCycleNumber ?? program.cycleNumber
        guard ProgramProgression.sessionTagCurrent(
            tagCycle: tagCycle, tagWeek: week, tagDayIndex: dayIndex,
            cycleNumber: program.cycleNumber, currentWeek: program.currentWeek,
            nextDayIndex: program.nextDayIndex
        ) else {
            let label = "\(program.name): banked a session from cycle \(tagCycle) week \(week) day \(dayIndex + 1), but the program has moved on — kept as history, schedule not advanced twice."
            context.insert(Milestone(date: session.date, exerciseName: nil, kind: .programNote, label: label))
            events.append(PREvent(kind: .programNote, exercise: program.name, label: label))
            return
        }

        // Accessories: double progression, every bank.
        for acc in day.accessories {
            if let entry = session.exercises.first(where: {
                $0.programRole == "accessory" && $0.exercise?.name == acc.exerciseName && !$0.workingSets.isEmpty
            }) {
                acc.apply(ProgramProgression.advanceAccessory(acc.coreState, perf: accPerf(entry)))
            }
        }

        // Cycle lifts: grade at the week-3 Peak, stash pending; apply at rollover.
        if week == 3 {
            for lift in day.lifts {
                if let entry = session.exercises.first(where: {
                    $0.exercise?.name == lift.exerciseName && $0.programRole == lift.role.rawValue && !$0.workingSets.isEmpty
                }) {
                    let result = ProgramProgression.advanceCycleLift(lift.coreState, perf: cyclePerf(entry, roundingLb: program.roundingLb), focus: program.focus, roundingLb: program.roundingLb)
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
                    let oldBase = lift.baseWeightLb
                    lift.baseWeightLb = pendingBase
                    lift.estimatedMaxLb = lift.pendingEstimatedMaxLb ?? lift.estimatedMaxLb
                    lift.stallCount = lift.pendingStallCount ?? lift.stallCount
                    lift.lastIncrementLb = lift.pendingLastIncrementLb ?? 0
                    if let note = lift.pendingNote {
                        let presented = note.hasPrefix("Two cycles without a clean peak")
                            ? "Two cycles without a clean peak — deloaded \(unitDisplay.format(lb: oldBase))→\(unitDisplay.format(lb: pendingBase)) to rebuild."
                            : note
                        let label = "\(lift.exerciseName): \(presented)"
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
                        let label = "\(lift.exerciseName): skipped peak — deloaded \(unitDisplay.format(lb: old))→\(unitDisplay.format(lb: lift.baseWeightLb))."
                        context.insert(Milestone(date: session.date, exerciseName: lift.exerciseName, kind: .programNote, label: label))
                        events.append(PREvent(kind: .programNote, exercise: lift.exerciseName, label: label))
                    }
                }
                // A cycle-scoped swap ends with the cycle (mirrors web).
                if let original = lift.revertToExerciseName {
                    let label = "\(original): cycle swap over — slot reverts from \(lift.exerciseName) for the new cycle."
                    lift.exerciseName = original
                    lift.revertToExerciseName = nil
                    context.insert(Milestone(date: session.date, exerciseName: original, kind: .programNote, label: label))
                    events.append(PREvent(kind: .programNote, exercise: original, label: label))
                }
            }
            for acc in d.accessories {
                if let original = acc.revertToExerciseName {
                    let label = "\(original): cycle swap over — slot reverts from \(acc.exerciseName) for the new cycle."
                    acc.exerciseName = original
                    acc.revertToExerciseName = nil
                    context.insert(Milestone(date: session.date, exerciseName: original, kind: .programNote, label: label))
                    events.append(PREvent(kind: .programNote, exercise: original, label: label))
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
    ) throws -> (sets: [SetSample], volumes: [Double], schemes: Set<String>) {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.isCompleted && $0.date < date }
        )
        let sessions = try context.fetch(descriptor)

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

    private static func advanceTrackIfNeeded(for exerciseName: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<LiftTrack>(
            predicate: #Predicate { $0.exerciseName == exerciseName }
        )
        guard let track = try context.fetch(descriptor).first else { return }
        track.completeSession()
    }
}
