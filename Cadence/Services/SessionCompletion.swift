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
    let coachingNotes: [String]
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
        guard !session.isCompleted else { return SessionSummary(lines: [], milestones: [], coachingNotes: []) }

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
        session.completedAt = .now
        let unitDisplay = (try? context.fetch(FetchDescriptor<AppSettings>()).first?.unitDisplay) ?? .lbPrimary

        var lines: [SessionSummary.LiftLine] = []
        var allEvents: [PREvent] = []

        for entry in session.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            let working = entry.workingSets.map(sample)
            guard !working.isEmpty else { continue }

            if exercise.type == .timed {
                let durations = entry.workingSets.compactMap(\.durationSeconds)
                if let longest = durations.max() {
                    lines.append(SessionSummary.LiftLine(
                        exerciseName: exercise.name,
                        topSetLabel: "\(durations.count) × \(CardioFormat.durationLabel(seconds: longest))",
                        volumeLb: 0
                    ))
                }
                continue // duration work is not a weight/repetition PR or lift track
            }
            if exercise.type == .conditioning { continue }

            if let top = entry.topSet {
                lines.append(SessionSummary.LiftLine(
                    exerciseName: exercise.name,
                    topSetLabel: top.loadBasis == .bodyweight
                        ? "\(top.reps) reps"
                        : "\(unitDisplay.format(lb: top.weightLb))\(top.loadBasis.shortSuffix) × \(top.reps)",
                    volumeLb: entry.workingVolumeLb
                ))
            }

            let history: (sets: [SetSample], volumes: [Double], schemes: Set<String>)
            do { history = try priorHistory(for: exercise.name, basis: working[0].loadBasis,
                                            before: session.date, context: context) }
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

        }

        // Grade standalone tracks from all occurrences together. Actual reps,
        // actual load, stopped/adjusted sets, and the original prescription
        // snapshots determine whether the lift advances. A duplicated exercise
        // is still one exposure and therefore advances at most once.
        let heldStandaloneTracks: [String]
        do { heldStandaloneTracks = try advanceStandaloneTracks(in: session, context: context) }
        catch { context.rollback(); throw SaveFailure(underlying: error) }

        let isProgramSession = session.programID != nil || session.programName != nil
        if isProgramSession && session.hasCompletedWork {
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
            let completedKinds = session.exercises.compactMap { entry -> CompletedExerciseKind? in
                guard !entry.workingSets.isEmpty, let exercise = entry.exercise else { return nil }
                return CompletedExerciseKind(name: exercise.name, type: exercise.typeRaw,
                                             category: exercise.categoryRaw)
            }
            let modality = WorkoutClassification.classify(completedKinds)
            Task { await HealthKitService.shared.saveWorkout(start: start, end: end, modality: modality) }
        }

        let allPlannedWork = session.exercises.flatMap(\.plannedWorkingSets)
        let completedSets = allPlannedWork.filter { $0.status == .completed }
        let skippedSets = allPlannedWork.filter { $0.status == .skipped }
        let plannedSets = allPlannedWork.filter { $0.status == .planned }
        let adjusted = completedSets.contains {
            $0.autoregReason != nil || $0.flags.contains(.stoppedEarly) || $0.quality == .grindy || $0.quality == .wobble
        }
        var coachingNotes: [String] = []
        if !plannedSets.isEmpty || !skippedSets.isEmpty {
            coachingNotes.append("Modified session — \(completedSets.count) sets completed; unfinished or skipped sets were not credited as performed.")
        } else if adjusted {
            coachingNotes.append("Completed with adjustments — progression was graded from the work actually logged.")
        } else if !completedSets.isEmpty {
            coachingNotes.append("Completed as planned — progression advanced from the banked work.")
        }
        if !heldStandaloneTracks.isEmpty {
            coachingNotes.append("Held progression for \(heldStandaloneTracks.sorted().joined(separator: ", ")) — actual work was saved, but the original prescription was not fully met.")
        }
        if isProgramSession,
           let programs = try? context.fetch(FetchDescriptor<Program>()),
           let program = session.programID.flatMap({ id in programs.first { $0.id == id } })
                ?? programs.first(where: { $0.name == session.programName }),
           let nextDay = program.orderedDays.first(where: { $0.order == program.nextDayIndex }) ?? program.orderedDays.first {
            let phase = CyclePhase(rawValue: program.currentWeek) ?? .volume
            coachingNotes.append("Next: \(nextDay.name) · R\(program.currentWeek) \(phase.name).")
        }
        return SessionSummary(lines: lines, milestones: allEvents, coachingNotes: coachingNotes)
    }

    private static func healthKitEnabled(_ context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<AppSettings>()
        return (try? context.fetch(descriptor).first?.healthKitEnabled) ?? false
    }

    private static func sample(_ set: SetEntry) -> SetSample {
        SetSample(weightLb: set.weightLb, reps: set.reps, isPerSide: set.isPerSide,
                  loadBasis: set.loadBasis, implementCount: set.resolvedImplementCount)
    }

    // MARK: - Program day/week/cycle advancement (mirrors web advanceProgram)

    private static func cyclePerf(_ entry: SessionExercise, roundingLb: Double) -> CycleLiftPerformance {
        // A primer and optional top single are observable preparation/practice.
        // Only the prescribed work block can earn the cycle progression.
        let w = entry.workingSets.filter { $0.prescriptionBlock == .work }
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

    private static func accPerf(_ entry: SessionExercise, roundingLb: Double) -> AccessoryPerformance {
        let w = entry.workingSets.filter { $0.prescriptionBlock == .work }
        return AccessoryPerformance(
            completedSets: w.count,
            minRepsAchieved: w.map(\.reps).min() ?? 0,
            anyStoppedEarly: w.contains { $0.flags.contains(.stoppedEarly) },
            performedAtPlannedLoad: w.allSatisfy {
                !ProgramProgression.belowPlanLoad(
                    actualLb: $0.weightLb,
                    plannedLb: $0.plannedWeightLb ?? entry.plannedWeightLb,
                    roundingLb: roundingLb
                )
            },
            grindyOrWobbleSets: w.filter { $0.quality == .grindy || $0.quality == .wobble }.count,
            bodyFlagSets: w.filter { $0.bodyFlagSite != nil }.count
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
        let exerciseTypeByName = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Exercise>()).map { ($0.name, $0.typeRaw) }
        )

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
                ($0.programSlotID == acc.id || ($0.programSlotID == nil && $0.programRole == "accessory" && $0.exercise?.name == acc.exerciseName))
                    && !$0.workingSets.isEmpty
            }) {
                let exerciseType = exerciseTypeByName[acc.exerciseName]
                if exerciseType == ExerciseType.conditioning.rawValue {
                    continue
                }
                // A temporary red-readiness cut deliberately banks less work;
                // it is a hold, not a failed double-progression exposure.
                if (entry.plannedSets ?? acc.sets) < acc.sets { continue }
                if exerciseType == ExerciseType.timed.rawValue {
                    let completed = entry.workingSets.filter { $0.status == .completed }
                    if completed.count >= acc.sets,
                       completed.allSatisfy({ ($0.durationSeconds ?? 0) >= acc.targetSeconds }),
                       !completed.contains(where: { $0.flags.contains(.stoppedEarly) }) {
                        acc.targetSeconds += acc.durationStepSeconds
                    }
                } else {
                    let loadStep = ProgramEngine.loadStep(
                        programRoundingLb: program.roundingLb,
                        exerciseType: entry.exercise?.typeRaw
                    )
                    acc.apply(ProgramProgression.advanceAccessory(
                        acc.coreState,
                        perf: accPerf(entry, roundingLb: loadStep)
                    ))
                }
            }
        }

        // DB lifts and other coarse implements can opt into the same earned
        // rep-window progression as accessories. It advances after each
        // exposure, independent of the four-phase calendar.
        for lift in day.lifts where lift.prescription == .doubleProgression {
            guard let entry = session.exercises.first(where: {
                ($0.programSlotID == lift.id || ($0.programSlotID == nil && $0.exercise?.name == lift.exerciseName))
                    && !$0.workingSets.isEmpty
            }) else { continue }
            let loadStep = ProgramEngine.loadStep(
                programRoundingLb: program.roundingLb,
                exerciseType: entry.exercise?.typeRaw
            )
            let prior = AccessoryState(
                sets: max(1, lift.doubleProgressionSets),
                minReps: max(1, lift.minimumReps),
                maxReps: max(lift.minimumReps, lift.maximumReps),
                currentReps: max(lift.minimumReps, lift.currentReps),
                weightLb: lift.baseWeightLb,
                incrementLb: loadStep,
                stallCount: lift.stallCount
            )
            let next = ProgramProgression.advanceAccessory(
                prior,
                perf: accPerf(entry, roundingLb: loadStep)
            )
            lift.baseWeightLb = next.weightLb
            lift.currentReps = next.currentReps
            lift.stallCount = next.stallCount
            lift.lastIncrementLb = next.weightLb - prior.weightLb
        }

        // A clean, completed top-single becomes the next peak projection's
        // explicit anchor. Adjusted or quality-flagged singles do not.
        for lift in day.lifts where lift.peakSingleEnabled {
            guard let entry = session.exercises.first(where: { $0.programSlotID == lift.id }) else { continue }
            if let single = entry.workingSets.first(where: {
                $0.prescriptionBlock == .topSingle && $0.reps >= 1
                    && $0.autoregReason == nil && $0.quality != .grindy && $0.quality != .wobble
                    && $0.bodyFlagSite == nil
            }) {
                lift.lastPeakSingleLb = max(lift.lastPeakSingleLb, single.weightLb)
            }
        }

        // Cycle lifts: grade at the week-3 Peak, stash pending; apply at rollover.
        if week == 3 {
            for lift in day.lifts where lift.prescription != .doubleProgression {
                if let entry = session.exercises.first(where: {
                    ($0.programSlotID == lift.id || ($0.programSlotID == nil && $0.exercise?.name == lift.exerciseName && $0.programRole == lift.role.rawValue))
                        && !$0.workingSets.isEmpty
                }) {
                    let loadStep = ProgramEngine.loadStep(programRoundingLb: program.roundingLb,
                                                          exerciseType: entry.exercise?.typeRaw)
                    let result = ProgramProgression.advanceCycleLift(
                        lift.coreState,
                        perf: cyclePerf(entry, roundingLb: loadStep),
                        focus: program.focus,
                        roundingLb: loadStep
                    )
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
                if lift.prescription == .doubleProgression {
                    // Rep-window slots advance after every exposure and do not
                    // participate in Peak grading or skipped-Peak stalls.
                } else if let pendingBase = lift.pendingBaseWeightLb {
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
                        let loadStep = ProgramEngine.loadStep(programRoundingLb: program.roundingLb,
                                                              exerciseType: exerciseTypeByName[lift.exerciseName])
                        lift.baseWeightLb = Weight.round(old * ProgramProgression.deloadRebuildFraction, to: loadStep)
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
        basis: LoadBasis,
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

    private static func advanceStandaloneTracks(in session: WorkoutSession, context: ModelContext) throws -> [String] {
        let candidates = session.exercises.filter { entry in
            guard entry.programRole == nil, let exercise = entry.exercise else { return false }
            return exercise.type != .timed && exercise.type != .conditioning
        }
        let grouped = Dictionary(grouping: candidates) { $0.exercise?.name ?? "" }
        let tracks = try context.fetch(FetchDescriptor<LiftTrack>())
        var held: [String] = []

        for (exerciseName, entries) in grouped where !exerciseName.isEmpty {
            guard let track = tracks.first(where: { $0.exerciseName == exerciseName }) else { continue }
            let performedEntries = entries.filter {
                !$0.workingSets.filter { $0.prescriptionBlock == .work }.isEmpty
            }
            guard !performedEntries.isEmpty else { continue }

            // An untouched duplicate occurrence is part of the prescription and
            // must hold the exposure rather than disappearing from the grade.
            let allOccurrencesPerformed = performedEntries.count == entries.count
            let performances = performedEntries.map { cyclePerf($0, roundingLb: track.roundingLb) }
            let advance = allOccurrencesPerformed
                && ProgramProgression.earnsStandaloneTrackAdvance(performances)
            track.completeSession(advance: advance)
            if !advance { held.append(exerciseName) }
        }
        return held
    }
}
