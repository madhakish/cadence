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
        if isProgramSession && hasCompletedProgramInstruction(in: session) {
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
            // Distance from the conditioning work actually performed. Without
            // it the mirrored workout carries a duration and nothing else,
            // which is all Health showed before. `workingSets` is already
            // completed-and-non-warmup, so a set left planned or skipped is not
            // claimed as ground covered.
            //
            // Bucketed per exercise, never from the session's overall modality:
            // a strength day that ends with a walk classifies as
            // `.crossTraining`, which maps to no distance type at all, so
            // deriving it from the whole session would drop the walk's miles —
            // and that mixed shape is the ordinary case, not the edge one.
            var milesByBasis: [DistanceBasis: Double] = [:]
            for entry in session.exercises {
                guard let exercise = entry.exercise, exercise.type == .conditioning else { continue }
                let kind = CompletedExerciseKind(name: exercise.name, type: exercise.typeRaw,
                                                 category: exercise.categoryRaw)
                guard let basis = WorkoutClassification.distanceBasis(for: kind) else { continue }
                let miles = entry.workingSets.compactMap(\.distanceMiles).reduce(0, +)
                if miles > 0 { milesByBasis[basis, default: 0] += miles }
            }
            Task {
                await HealthKitService.shared.saveWorkout(
                    start: start, end: end, modality: modality, milesByBasis: milesByBasis
                )
            }
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

    /// The set rows created with the session are the prescription. User-added
    /// rows are appended after them and remain history-only bonus work.
    private static func prescribedWork(_ entry: SessionExercise) -> [SetEntry] {
        let candidates = entry.orderedSets.filter {
            !$0.isWarmup && $0.prescriptionBlock.countsAsPrescribedWork
        }
        return Array(candidates.prefix(entry.plannedSets ?? candidates.count))
            .filter { $0.status == .completed }
    }

    private static func hasCompletedProgramInstruction(in session: WorkoutSession) -> Bool {
        session.exercises.contains { entry in
            guard entry.programSlotID != nil || entry.programRole != nil else { return false }
            let candidates = entry.orderedSets.filter {
                !$0.isWarmup && $0.prescriptionBlock.countsAsProgramInstruction
            }
            return candidates.prefix(entry.plannedSets ?? candidates.count)
                .contains { $0.status == .completed }
        }
    }

    private static func completedProgramInstructionsMatch(
        _ session: WorkoutSession,
        day: ProgramDay
    ) -> Bool {
        let completed = session.exercises.filter { entry in
            guard entry.programSlotID != nil || entry.programRole != nil else { return false }
            let candidates = entry.orderedSets.filter {
                !$0.isWarmup && $0.prescriptionBlock.countsAsProgramInstruction
            }
            return candidates.prefix(entry.plannedSets ?? candidates.count)
                .contains { $0.status == .completed }
        }
        guard !completed.isEmpty else { return false }
        return completed.allSatisfy { entry in
            guard let role = entry.programRole else { return false }
            if role == LiftRole.main.rawValue || role == LiftRole.complementary.rawValue {
                if let slotID = entry.programSlotID {
                    return day.lifts.contains { $0.id == slotID && $0.role.rawValue == role }
                }
                let matches = day.lifts.filter {
                    $0.role.rawValue == role && $0.exerciseName == entry.exercise?.name
                }
                return matches.count == 1
            }
            if role == "accessory" {
                if let slotID = entry.programSlotID {
                    return day.accessories.contains { $0.id == slotID }
                }
                return day.accessories.filter { $0.exerciseName == entry.exercise?.name }.count == 1
            }
            return false
        }
    }

    private static func programmedEntry(
        for slotID: String,
        exerciseName: String,
        role: String,
        in session: WorkoutSession
    ) -> SessionExercise? {
        if let exact = session.exercises.first(where: {
            $0.programSlotID == slotID && $0.programRole == role
        }) {
            return exact
        }
        let lineage = session.exercises.filter {
            $0.programRole == role && $0.exercise?.name == exerciseName
        }
        return lineage.count == 1 ? lineage[0] : nil
    }

    private static func cyclePerf(_ entry: SessionExercise, roundingLb: Double) -> CycleLiftPerformance {
        // A primer and optional top single are observable preparation/practice.
        // Only the prescribed work block can earn the cycle progression.
        let w = prescribedWork(entry)
        let presReps = entry.plannedReps ?? (w.map(\.reps).max() ?? 0)
        // The cycle's strength sample, not simply the heaviest set — see
        // ProgramProgression.strengthSampleIndex. Heaviest-first discarded the
        // extra reps of an AMRAP taken at the top weight.
        let top = ProgramProgression.strengthSampleIndex(
            weightsLb: w.map(\.weightLb), reps: w.map(\.reps)
        ).map { w[$0] }
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
        let w = prescribedWork(entry)
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

    /// Complete rotations banked for this program since its most recent deload
    /// rotation. A program that has never deloaded returns every rotation it
    /// has run, which is exactly right — it has accumulated all of them.
    ///
    /// Rotations, not sessions: a session count means something different on
    /// every split, and the floor it feeds has to mean the same thing on all of
    /// them. Ordered by `completedAt ?? date` to match the web mirror and
    /// `CoachingService`, so a backdated session cannot make one client cut the
    /// cycle short while the other does not.
    private static func rotationsSinceLastDeload(
        _ sessions: [WorkoutSession], program: Program
    ) -> Int {
        let mine = sessions.filter {
            $0.isCompleted && ($0.programID == program.id || $0.programName == program.name)
        }.sorted { ($0.completedAt ?? $0.date) < ($1.completedAt ?? $1.date) }
        var lastDeloadIndex = -1
        for (index, session) in mine.enumerated() where session.programWeek == ProgramProgression.deloadWeek {
            lastDeloadIndex = index
        }
        let after = mine.dropFirst(lastDeloadIndex + 1)
        return Set(after.map { RotationKey(
            cycleNumber: $0.programCycleNumber ?? 0, week: $0.programWeek ?? 0
        ) }).count
    }

    private struct RotationKey: Hashable { let cycleNumber: Int; let week: Int }

    /// Readiness-triggered deload. The schedule normally walks 1 → 2 → 3 → 4;
    /// a second consecutive red rotation means this cycle is not worth
    /// finishing, so it goes straight to the deload instead. Returns the
    /// rotation being cut short, or nil to advance normally. Mirrors the web
    /// `earlyDeloadDecision`.
    ///
    /// The session that just closed this rotation is already marked completed
    /// on the context, so the fetch below sees it — but it has not been saved,
    /// which is why the filtering happens in memory rather than in a predicate.
    private static func earlyDeloadWeek(
        program: Program, context: ModelContext
    ) throws -> Int? {
        // Structural guard first: building the coaching report is not free, and
        // from rotation 3 the schedule advances into the deload by itself.
        guard program.currentWeek >= 1,
              program.currentWeek < ProgramProgression.deloadWeek - 1 else { return nil }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let report = CoachingService.report(
            program: program,
            sessions: sessions,
            exercises: try context.fetch(FetchDescriptor<Exercise>()),
            checkIns: try context.fetch(FetchDescriptor<CheckIn>())
        )
        // Verified rotations only — an as-run rotation is complete by
        // construction, so trusting one would launder an unknown into a deload.
        let verified = report.rotations.filter { $0.isComplete && !$0.judgedAsRun }
        let decided = ProgramProgression.shouldDeloadEarly(
            currentWeek: program.currentWeek,
            readiness: verified.last?.readiness ?? .unknown,
            previousReadiness: verified.dropLast().last?.readiness ?? .unknown,
            rotationsSinceLastDeload: rotationsSinceLastDeload(sessions, program: program)
        )
        return decided ? program.currentWeek : nil
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
        guard completedProgramInstructionsMatch(session, day: day) else {
            let label = "\(program.name): banked work from an older version of day \(dayIndex + 1) — kept as history, current schedule unchanged."
            context.insert(Milestone(date: session.date, exerciseName: nil, kind: .programNote, label: label))
            events.append(PREvent(kind: .programNote, exercise: program.name, label: label))
            return
        }

        // Accessories: double progression, every bank.
        for acc in day.accessories {
            if let entry = programmedEntry(
                for: acc.id, exerciseName: acc.exerciseName,
                role: "accessory", in: session
            ), !prescribedWork(entry).isEmpty {
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
            guard let entry = programmedEntry(
                for: lift.id, exerciseName: lift.exerciseName,
                role: lift.role.rawValue, in: session
            ), !prescribedWork(entry).isEmpty else { continue }
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

        // Methodology slots on session-to-session linear progression: novice
        // fives and the Texas day slots advance their own base after every
        // banked exposure instead of waiting for a Peak grade. A day that
        // repeats the same lift+style is still ONE exposure — only the first
        // slot advances (twin sync carries the rest), so duplicates can never
        // double-progress.
        var advancedLinearSlots = Set<String>()
        for lift in day.lifts where lift.prescription.advancesPerExposure && lift.prescription != .doubleProgression {
            let exposureKey = "\(lift.exerciseName)|\(lift.prescription.rawValue)"
            guard !advancedLinearSlots.contains(exposureKey) else { continue }
            // Slot-scoped matching and completed-work gating share the same
            // helpers as the week-3 grading loop — mirrored 1:1 with web.
            guard let entry = programmedEntry(
                for: lift.id, exerciseName: lift.exerciseName,
                role: lift.role.rawValue, in: session
            ), !prescribedWork(entry).isEmpty else { continue }
            advancedLinearSlots.insert(exposureKey)
            let loadStep = ProgramEngine.loadStep(
                programRoundingLb: program.roundingLb,
                exerciseType: entry.exercise?.typeRaw
            )
            let rule = ProgramProgression.linearRule(for: lift.prescription,
                                                     movementGroup: entry.exercise?.movementGroup)
            let priorBase = lift.baseWeightLb
            let priorMax = lift.estimatedMaxLb
            let result = ProgramProgression.advanceLinearLift(
                lift.coreState, perf: cyclePerf(entry, roundingLb: loadStep),
                rule: rule, roundingLb: loadStep
            )
            lift.baseWeightLb = result.state.baseWeightLb
            lift.estimatedMaxLb = result.state.estimatedMaxLb
            lift.stallCount = result.state.stallCount
            lift.lastIncrementLb = result.state.lastIncrementLb
            // Non-success outcomes surface their explanation — a silent hold
            // would read as a broken app, and a deload must always say why.
            if result.grade != .success, let note = result.note {
                let label = "\(lift.exerciseName): \(note)"
                context.insert(Milestone(date: session.date, exerciseName: lift.exerciseName, kind: .programNote, label: label))
                events.append(PREvent(kind: .programNote, exercise: lift.exerciseName, label: label))
            }
            // Repeated slots of the same lift and style (novice squat on Day
            // A and Day B, Texas A/B day pairs) share ONE progression: mirror
            // the advanced state into every twin so "weight every session"
            // holds across alternating days instead of each slot advancing
            // every other exposure. Only twins still in lockstep (same base
            // before this advance) are synchronized — a deliberately diverged
            // or manually edited twin keeps its own base — and a hand-edited
            // estimated 1RM on a twin survives the sync the same way; edits
            // must never disappear.
            for twinDay in program.days {
                for twin in twinDay.lifts where twin.id != lift.id
                    && twin.exerciseName == lift.exerciseName
                    && twin.prescription == lift.prescription
                    && abs(twin.baseWeightLb - priorBase) < 0.001 {
                    if abs(twin.estimatedMaxLb - priorMax) < 0.001 {
                        twin.estimatedMaxLb = lift.estimatedMaxLb
                    }
                    twin.baseWeightLb = lift.baseWeightLb
                    twin.stallCount = lift.stallCount
                    twin.lastIncrementLb = lift.lastIncrementLb
                }
            }
        }

        // A clean, completed top-single becomes the next peak projection's
        // explicit anchor. Adjusted or quality-flagged singles do not.
        for lift in day.lifts where lift.peakSingleEnabled {
            guard let entry = programmedEntry(
                for: lift.id, exerciseName: lift.exerciseName,
                role: lift.role.rawValue, in: session
            ) else { continue }
            if let single = entry.orderedSets.first(where: {
                $0.prescriptionBlock == .topSingle && $0.reps >= 1
                    && $0.status == .completed
                    && $0.autoregReason == nil && $0.quality != .grindy && $0.quality != .wobble
                    && $0.bodyFlagSite == nil
            }) {
                lift.lastPeakSingleLb = max(lift.lastPeakSingleLb, single.weightLb)
            }
        }

        // Outside the graded rotation the cycle does not advance, but the work
        // still happened, and a set taken past its prescription is the best
        // estimate available. Observation only: it can raise the estimate,
        // never lower it, because a submaximal prescription is not evidence of
        // a smaller max. This is what a capped AMRAP on the load rotation feeds.
        if week != ProgramProgression.gradedWeek {
            for lift in day.lifts where !lift.prescription.advancesPerExposure {
                guard let entry = programmedEntry(
                    for: lift.id, exerciseName: lift.exerciseName,
                    role: lift.role.rawValue, in: session
                ) else { continue }
                let loadStep = ProgramEngine.loadStep(programRoundingLb: program.roundingLb,
                                                      exerciseType: entry.exercise?.typeRaw)
                let perf = cyclePerf(entry, roundingLb: loadStep)
                guard perf.topSetWeightLb > 0, perf.topSetReps >= 1 else { continue }
                lift.estimatedMaxLb = ProgramProgression.observedMax(
                    prior: lift.estimatedMaxLb,
                    sample: ProgramProgression.epleyE1RM(
                        weightLb: perf.topSetWeightLb, reps: perf.topSetReps
                    )
                )
            }
        }

        // Cycle lifts: grade at the week-3 Peak, stash pending; apply at rollover.
        if week == ProgramProgression.gradedWeek {
            for lift in day.lifts where !lift.prescription.advancesPerExposure {
                if let entry = programmedEntry(
                    for: lift.id, exerciseName: lift.exerciseName,
                    role: lift.role.rawValue, in: session
                ), !prescribedWork(entry).isEmpty {
                    let loadStep = ProgramEngine.loadStep(programRoundingLb: program.roundingLb,
                                                          exerciseType: entry.exercise?.typeRaw)
                    let result = ProgramProgression.advanceProgramLift(
                        lift.coreState,
                        perf: cyclePerf(entry, roundingLb: loadStep),
                        focus: program.focus,
                        style: lift.prescription,
                        movementGroup: entry.exercise?.movementGroup,
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

        // Walk day ORDER values, not array positions — `orderedDays` also
        // drops the relationship aliases that a raw `days.count` would inflate.
        let advance = ProgramProgression.scheduleAdvance(
            dayOrders: program.orderedDays.map(\.order), bankedDayOrder: dayIndex
        )
        program.nextDayIndex = advance.nextDayOrder
        guard advance.isLastDay else { return }

        if program.currentWeek < ProgramProgression.deloadWeek {
            if let earlyWeek = try earlyDeloadWeek(program: program, context: context) {
                // Write the hold through the same pending group a real peak
                // grade uses, so the rollover applies it on its existing path
                // and never reaches the skipped-peak stall branch. A slot that
                // already carries a grade keeps it — this only speaks for
                // cycles whose peak never ran.
                for programDay in program.days {
                    for lift in programDay.lifts
                    where !lift.prescription.advancesPerExposure && lift.pendingBaseWeightLb == nil {
                        let hold = ProgramProgression.recoveryDeloadHold(lift.coreState, atWeek: earlyWeek)
                        lift.pendingBaseWeightLb = hold.state.baseWeightLb
                        lift.pendingEstimatedMaxLb = hold.state.estimatedMaxLb
                        lift.pendingStallCount = hold.state.stallCount
                        lift.pendingLastIncrementLb = hold.state.lastIncrementLb
                        lift.pendingNote = hold.note
                    }
                }
                program.currentWeek = ProgramProgression.deloadWeek
                let label = "\(program.name): two red rotations in a row — going straight to the deload. Main-lift bases hold."
                context.insert(Milestone(date: session.date, exerciseName: nil, kind: .programNote, label: label))
                events.append(PREvent(kind: .programNote, exercise: program.name, label: label))
                return
            }
            program.currentWeek += 1
            return
        }

        // Rollover at the deload week's last day.
        for d in program.days {
            for lift in d.lifts {
                if lift.prescription.advancesPerExposure {
                    // Per-exposure slots (rep windows, novice fives, Texas
                    // days) advance after every banked session and do not
                    // participate in Peak grading or skipped-Peak stalls.
                    // Clear any stale pending left by a style edit after a
                    // grade — it must never apply months later.
                    lift.pendingBaseWeightLb = nil
                    lift.pendingEstimatedMaxLb = nil
                    lift.pendingStallCount = nil
                    lift.pendingLastIncrementLb = nil
                    lift.pendingNote = nil
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
                } else if !lift.prescription.buildsOwnSessionShape {
                    // Wave-family slots: a peak never banked is a stall toward
                    // the 10% rebuild. The methodology cycle styles (5/3/1,
                    // max/dynamic effort) define their own miss rules and
                    // simply hold when the graded week was skipped — a
                    // skipped week is not missed reps.
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
                } else {
                    // Methodology cycle styles hold on a skipped graded week,
                    // but the increment record must not keep advertising a
                    // bump that never happened this cycle.
                    lift.lastIncrementLb = 0
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
                !$0.workingSets.filter { $0.prescriptionBlock.countsAsPrescribedWork }.isEmpty
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
