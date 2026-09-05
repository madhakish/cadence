import SwiftUI
import SwiftData
import CadenceCore

/// The logger. Pre-filled from the plan; everything editable in place.
/// Autoregulation is one tap. Rest is manual by default — armed from the Rest
/// buttons or the sticky bottom bar (session clock + countdown); it only
/// auto-arms after a set when the auto-start setting is on. Mirrors the web
/// logger (web/app/js/views/session.js).
struct ActiveSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimer.self) private var restTimer
    @Environment(WorkoutClock.self) private var workoutClock
    @Query private var settingsList: [AppSettings]
    @Query private var gyms: [Gym]
    @Query private var programs: [Program]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Bindable var session: WorkoutSession
    @State private var showExercisePicker = false
    @State private var confirmDiscard = false
    @State private var autoregEntry: SessionExercise?
    @State private var summary: SessionSummary?
    @State private var currentEntry: SessionExercise?   // the exercise you're actively working
    @State private var banking = false                  // double-tap on Bank it would run completion twice
    @State private var showBankError = false            // failed save: everything rolled back, Bank stays retryable
    @State private var bankErrorMessage = ""
    @State private var showIncompleteBankConfirmation = false

    private var currentOrFirst: SessionExercise? {
        currentEntry
            ?? session.orderedExercises.first { $0.plannedWorkingSets.contains { $0.status == .planned } }
            ?? session.orderedExercises.first
    }
    private var gym: Gym? {
        gyms.first { $0.id == session.gymID }
            ?? gyms.first { $0.name == session.gymName }
            ?? gyms.first { $0.isDefault }
            ?? gyms.first
    }
    private var sessionProgram: Program? {
        programs.matching(sessionProgramID: session.programID, name: session.programName)
    }
    private var unfinishedSetCount: Int {
        session.orderedExercises.flatMap(\.plannedWorkingSets).filter { $0.status == .planned }.count
    }
    private var completedSetCount: Int {
        session.orderedExercises.flatMap(\.plannedWorkingSets).filter { $0.status == .completed }.count
    }
    private var totalWorkSetCount: Int { session.orderedExercises.flatMap(\.plannedWorkingSets).count }
    /// Position, not achievement: a skipped set is resolved and moves the
    /// workout forward, so the ordinal must count it or skipping every set
    /// would read "1 of N" forever. Mirrors web session.js.
    private var resolvedWorkSetCount: Int {
        session.orderedExercises.flatMap(\.plannedWorkingSets).filter { $0.status != .planned }.count
    }
    private var currentExerciseNumber: Int {
        guard let currentOrFirst,
              let index = session.orderedExercises.firstIndex(where: { $0.persistentModelID == currentOrFirst.persistentModelID })
        else { return session.orderedExercises.isEmpty ? 0 : 1 }
        return index + 1
    }
    private var workoutName: String {
        return session.programDayIndex.flatMap { index in
            sessionProgram?.day(order: index)?.name
        } ?? session.programName ?? "Workout"
    }
    /// The stopwatch origin lives in WorkoutClock (root-scoped), so it survives
    /// leaving this screen — and, via the Live Activity, app relaunch.
    /// The real start, or nil when this session was opened but never started.
    private var sessionStart: Date? { isTimingThisSession ? workoutClock.startDate : nil }
    /// Whether the root stopwatch is timing THIS session. Another workout's
    /// clock must never be reported — or stopped — from here.
    private var isTimingThisSession: Bool { workoutClock.isTracking(sessionID: session.id) }

    /// Begin timing. The one place a workout starts, so opening the logger to
    /// read the plan never logs elapsed time nobody trained.
    private func startWorkout() {
        workoutClock.begin(for: session,
                           currentLift: currentOrFirst?.exercise?.name ?? "",
                           defaultRestSeconds: currentRestSeconds)
    }

    /// Names the cost of discarding. A session started by mistake has nothing
    /// logged and can go without ceremony; one with real work says so.
    private var discardPrompt: String {
        let performed = session.exercises.flatMap(\.workingSets).count
        return performed == 0
            ? "Discard this session? Nothing has been logged."
            : "Discard this session and lose \(performed) logged set\(performed == 1 ? "" : "s")?"
    }

    private var currentRestSeconds: Int {
        smartRestSeconds(for: currentOrFirst?.exercise, role: currentOrFirst?.programRole, settings: settingsList.first)
    }

    var body: some View {
        List {
            // The focused exercise is deliberately first. Between sets, the
            // phone must answer load / plates / set / next action before it
            // spends vertical space on venue or session metadata.
            focusedExerciseSection

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SESSION PROGRESS")
                        .font(.caption.bold())
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text("Exercise \(currentExerciseNumber) of \(session.orderedExercises.count) · \(totalWorkSetCount == 0 ? 0 : min(resolvedWorkSetCount + 1, totalWorkSetCount)) of \(totalWorkSetCount) work sets")
                        .font(.headline.monospacedDigit())
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            trainingAtSection
            remainingExerciseSections

            Section {
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
            }

            Section("Session notes") {
                TextField("Notes", text: Bindable(session).notes, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section {
                Button {
                    if unfinishedSetCount > 0 { showIncompleteBankConfirmation = true }
                    else { bankSession() }
                } label: {
                    Text(Copy.sessionDone)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.bigTap - 16)
                }
                .disabled(banking)
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .accessibilityIdentifier("active-session-screen")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SessionBottomBar(
                sessionStart: isTimingThisSession ? workoutClock.startDate : nil,
                pausedAt: workoutClock.pausedAt,
                restLabel: currentOrFirst?.exercise?.name ?? "",
                restSeconds: currentRestSeconds,
                onStart: startWorkout
            )
        }
        // The logger has its own persistent bottom bar. Keyboard safe-area
        // state can otherwise strand that bar at the keyboard's former top
        // edge after editing a set, even after the keyboard has disappeared.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: settingsList.first?.haptics, initial: true) { _, on in restTimer.hapticsEnabled = on ?? true }
        .onAppear {
            // Opening the logger is NOT starting the workout. Only continue a
            // clock already running for this session (including one adopted
            // after a cold start); starting is an explicit act.
            workoutClock.resumeIfTracking(for: session,
                                          currentLift: currentOrFirst?.exercise?.name ?? "",
                                          defaultRestSeconds: currentRestSeconds)
        }
        // Keep the activity's elapsed face and its quick-rest default honest.
        // Watch the derived VALUES, not the entry's identity: swapping the
        // exercise in place or editing its rest stepper changes the lift
        // name / default rest without changing which SessionExercise is current.
        .onChange(of: currentOrFirst?.exercise?.name) { pushActivityContext() }
        .onChange(of: currentRestSeconds) { pushActivityContext() }
        .navigationTitle(workoutName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't bank the session", isPresented: $showBankError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bankErrorMessage)
        }
        .confirmationDialog(
            "Bank an incomplete session?",
            isPresented: $showIncompleteBankConfirmation,
            titleVisibility: .visible
        ) {
            Button("Bank completed work") { bankSession() }
            Button("Keep logging", role: .cancel) {}
        } message: {
            Text("\(completedSetCount) completed; \(unfinishedSetCount) planned set\(unfinishedSetCount == 1 ? " is" : "s are") still unfinished. Only completed sets will count toward volume, PRs, and progression.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // Navigation only. Leaving the logger must not mutate either
                // timer; pause/end remain explicit workout-clock controls.
                Button {
                    if PersistenceErrorCenter.shared.save(context, operation: "Saving the open session") { dismiss() }
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .accessibilityHint("Returns to Today while the workout and rest timers keep running")
            }
            // Workout clock controls: pause/resume/reset the stopwatch, or end
            // the workout outright (Live Activity + timers) without banking —
            // previously the only way to stop the clock was Bank it.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if isTimingThisSession {
                        if workoutClock.isPaused {
                            Button { workoutClock.resume() } label: { Label("Resume clock", systemImage: "play") }
                        } else {
                            Button { workoutClock.pause() } label: { Label("Pause clock", systemImage: "pause") }
                        }
                        Button { workoutClock.reset() } label: { Label("Restart clock at 0:00", systemImage: "arrow.counterclockwise") }
                        Divider()
                        // The undo for starting by accident: back to not
                        // started, with the plan and any logged work intact.
                        Button(role: .destructive) {
                            restTimer.stop()
                            workoutClock.end()
                        } label: { Label("Reset to not started", systemImage: "stop.circle") }
                    } else {
                        Button { startWorkout() } label: { Label("Start workout", systemImage: "play.fill") }
                    }
                    Divider()
                    Divider()
                    // The way OUT of a session you never want to keep. Without
                    // this the only exits were Back (leaves it open), Stop
                    // workout clock (stops the clock, leaves it open), and
                    // Bank it (commits it) — so a session started by mistake
                    // could not be got rid of from inside it at all, and the
                    // only discard anywhere was an unlabelled swipe on Today.
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: { Label("Discard session", systemImage: "trash") }
                } label: {
                    Image(systemName: !isTimingThisSession ? "play.circle"
                          : (workoutClock.isPaused ? "pause.circle" : "stopwatch"))
                }
                .accessibilityLabel("Workout and session controls")
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet { exercise in
                addExercise(exercise)
            }
        }
        // Deleting logged work is not something to do on a mis-tap, so the
        // confirmation says exactly how much would be lost.
        .confirmationDialog(discardPrompt, isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard session", role: .destructive) {
                // The rest timer is root-scoped and unowned: stop it unless
                // the clock says it belongs to ANOTHER running workout —
                // discarding a stray session must not kill that workout's
                // rest countdown.
                if !workoutClock.isRunning || workoutClock.isTracking(sessionID: session.id) {
                    restTimer.stop()
                }
                // Scoped teardown: ends the clock only if this session owns
                // it, else drops just this session's durable record and any
                // orphaned activity it left behind.
                workoutClock.release(sessionID: session.id)
                context.delete(session)
                if PersistenceErrorCenter.shared.save(context, operation: "Discarding the session") { dismiss() }
            }
            Button("Keep session", role: .cancel) {}
        } message: {
            Text("The program schedule and your completed history are unchanged.")
        }
        .confirmationDialog("Dropping load — why?", isPresented: Binding(
            get: { autoregEntry != nil },
            set: { if !$0 { autoregEntry = nil } }
        ), titleVisibility: .visible) {
            ForEach(AutoregReason.allCases, id: \.self) { reason in
                Button(reason.rawValue.capitalized) {
                    if let entry = autoregEntry { dropLoad(entry, reason: reason) }
                }
            }
        }
        .sheet(item: Binding(
            get: { summary.map(SummaryBox.init) },
            set: { _ in summary = nil }
        )) { box in
            SessionSummarySheet(summary: box.summary) {
                summary = nil
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var trainingAtSection: some View {
        if !gyms.isEmpty {
            Section("Training at") {
                Picker("Gym", selection: Binding(
                    get: { gym?.id ?? "" },
                    set: { id in
                        guard let selected = gyms.first(where: { $0.id == id }) else { return }
                        // Entries still tracking the OUTGOING gym's default
                        // bar follow the explicit switch (restamp + warmup
                        // resync); a manually chosen bar, an entry with
                        // logged sets, or a legacy nil entry keeps its
                        // record — the nil-only resync went dead the moment
                        // creation started stamping every barbell entry.
                        // Mirrors the web session gym select.
                        let previousBarID = gym?.defaultBar.id
                        session.gymID = selected.id
                        session.gymName = selected.name
                        for entry in session.exercises {
                            // Completed WORK freezes the bar record (the
                            // prescription was performed on it); a tapped
                            // warmup alone must not pin a wrong-gym bar for
                            // the rest of the session. A HAND-PICKED bar
                            // (barIDIsManual) never follows the switch, even
                            // when it equals the outgoing default — that
                            // ambiguity is exactly what the V10 bit resolves.
                            let hasCompletedWork = entry.sets.contains { !$0.isWarmup && $0.status == .completed }
                            if entry.barID != nil, entry.barID == previousBarID,
                               !entry.barIDIsManual, !hasCompletedWork {
                                entry.barID = selected.defaultBar.id
                            }
                            if entry.barID == nil
                                || (entry.barID == selected.defaultBar.id && !entry.barIDIsManual) {
                                synchronizeWarmups(entry, bar: selected.defaultBar, gym: selected,
                                                   enteredUnit: settingsList.first?.unitDisplay.primaryUnit ?? .lb,
                                                   context: context)
                            }
                        }
                        PersistenceErrorCenter.shared.save(context, operation: "Changing the session gym")
                    }
                )) {
                    ForEach(gyms) { option in Text(option.name).tag(option.id) }
                }
            }
        }
    }

    /// Extracted from `body` — the multi-argument section call plus the recall
    /// lookup pushed the List builder past the type-checker's budget.
    private var focusedExerciseSection: some View {
        let recall = recallLines()
        let focusedID = currentOrFirst?.persistentModelID
        return ForEach(session.orderedExercises.filter { $0.persistentModelID == focusedID }) { entry in
            exerciseSection(for: entry, emphasized: true, recall: recall)
        }
    }

    private var remainingExerciseSections: some View {
        let recall = recallLines()
        let focusedID = currentOrFirst?.persistentModelID
        return ForEach(session.orderedExercises.filter { $0.persistentModelID != focusedID }) { entry in
            exerciseSection(for: entry, emphasized: false, recall: recall)
        }
    }

    private func exerciseSection(
        for entry: SessionExercise,
        emphasized: Bool,
        recall: [PersistentIdentifier: String]
    ) -> some View {
        ExerciseSection(
            entry: entry,
            emphasized: emphasized,
            settings: settingsList.first,
            gym: gym,
            programFocus: sessionProgram?.focus,
            allExercises: allExercises,
            lastTime: recallLine(for: entry, in: recall),
            adHocExposure: mostRecentTopExposure(for: entry),
            onDropLoad: { autoregEntry = entry },
            onWork: { currentEntry = $0 },
            onRemove: { removeExercise(entry) },
            onMove: { moveExercise(entry, direction: $0) }
        )
    }

    private func recallLine(
        for entry: SessionExercise,
        in recall: [PersistentIdentifier: String]
    ) -> String? {
        recall[entry.persistentModelID]
    }

    /// Drop an exercise from this session (session-only — the program slot is
    /// untouched, like a swap). If it was the actively-worked lift, clear that
    /// so the bottom bar falls back to the first remaining exercise.
    private func removeExercise(_ entry: SessionExercise) {
        if currentEntry?.persistentModelID == entry.persistentModelID { currentEntry = nil }
        context.delete(entry)
        PersistenceErrorCenter.shared.save(context, operation: "Removing the exercise")
    }

    /// Reorder within THIS session only — the program day's authored order is
    /// untouched, like removal and session-scoped swaps. Renumbers the whole
    /// ordered list so duplicate or gapped order values (imports, removals)
    /// cannot make a move silently no-op. Mirrors web moveExercise.
    private func moveExercise(_ entry: SessionExercise, direction: Int) {
        var ordered = session.orderedExercises
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) else { return }
        let target = index + direction
        guard target >= 0, target < ordered.count else { return }
        ordered.swapAt(index, target)
        for (position, item) in ordered.enumerated() { item.order = position }
        PersistenceErrorCenter.shared.save(context, operation: "Reordering the exercises")
    }

    private func pushActivityContext() {
        workoutClock.updateContext(currentLift: currentOrFirst?.exercise?.name ?? "",
                                   defaultRestSeconds: currentRestSeconds)
    }

    private func bankSession() {
        guard !banking else { return }
        banking = true
        do {
            summary = try SessionCompletion.finish(session, context: context, startedAt: sessionStart)
            // Same scoping as discard: banking a leftover session opened over
            // another running workout must not stop that workout's clock,
            // erase its durable record, or kill its rest countdown.
            if !workoutClock.isRunning || workoutClock.isTracking(sessionID: session.id) {
                restTimer.stop()
            }
            workoutClock.release(sessionID: session.id)
        } catch {
            banking = false
            bankErrorMessage = error.localizedDescription
            showBankError = true
        }
    }

    /// Program entries recall the exact slot that prescribed them. The same
    /// exercise on another day or in another role is a different exposure;
    /// slotless exercises retain generic exercise-history recall.
    private func recallLines() -> [PersistentIdentifier: String] {
        let wanted = session.orderedExercises.filter { $0.exercise != nil }
        var lines: [PersistentIdentifier: String] = [:]
        guard !wanted.isEmpty else { return lines }
        for past in completedSessions where past.persistentModelID != session.persistentModelID {
            for current in wanted where lines[current.persistentModelID] == nil {
                guard let entry = recallEntry(
                    for: current, in: past
                ), let exercise = entry.exercise else { continue }
                let recalledSets: [SetEntry]
                if current.programRole != nil {
                    let prescribed = entry.orderedSets.filter {
                        !$0.isWarmup
                            && $0.prescriptionBlock.countsAsProgramInstruction
                    }
                    recalledSets = Array(prescribed.prefix(entry.plannedSets ?? prescribed.count))
                        .filter { $0.status == .completed }
                } else {
                    recalledSets = entry.workingSets
                }
                guard let top = recalledSets.max(by: { $0.weightLb < $1.weightLb }) else { continue }
                let prefix = recallPrefix(for: current)
                if exercise.type == .timed {
                    let longest = recalledSets.compactMap(\.durationSeconds).max() ?? 0
                    let when = past.date.formatted(date: .abbreviated, time: .omitted)
                    lines[current.persistentModelID] = "\(prefix): \(CardioFormat.durationLabel(seconds: longest)) · \(when) (\(agoLabel(past.date)))"
                    continue
                }
                let weight = top.weightLb == 0 ? "BW" : settingsList.unitDisplay.format(lb: top.weightLb)
                let when = past.date.formatted(date: .abbreviated, time: .omitted)
                lines[current.persistentModelID] = "\(prefix): \(weight)×\(top.reps) · \(when) (\(agoLabel(past.date)))"
            }
            if lines.count == wanted.count { break }
        }
        return lines
    }

    private func recallEntry(
        for current: SessionExercise,
        in pastSession: WorkoutSession
    ) -> SessionExercise? {
        guard let exerciseName = current.exercise?.name else { return nil }
        guard let role = current.programRole else {
            return pastSession.exercises.first {
                $0.exercise?.name == exerciseName && $0.programRole == nil
            }
        }
        let sameProgram = (session.programID != nil && session.programID == pastSession.programID)
            || (pastSession.programID == nil && session.programName == pastSession.programName)
        guard sameProgram, session.programDayIndex == pastSession.programDayIndex else { return nil }
        // Slot ID AND role, like web programmedEntry: a slot whose role was
        // re-authored between cycles is a different exposure, and recalling
        // the old role's numbers would grade today against the wrong tier.
        if let slotID = current.programSlotID,
           let exact = pastSession.exercises.first(where: {
               $0.programSlotID == slotID && $0.programRole == role
           }) {
            return exact
        }
        let lineage = pastSession.exercises.filter {
            $0.exercise?.name == exerciseName && $0.programRole == role
        }
        return lineage.count == 1 ? lineage[0] : nil
    }

    private func recallPrefix(for entry: SessionExercise) -> String {
        guard let role = entry.programRole else { return "Last" }
        let program = programs.matching(sessionProgramID: session.programID, name: session.programName)
        let day = session.programDayIndex.flatMap { index in
            program?.day(order: index)?.name
        }
        return ["Last", role, day].compactMap { $0 }.joined(separator: " ")
    }

    /// The lifter's most recent completed top-weight set for this exact
    /// entry, scoped exactly like `recallEntry`/`lastTime`: slotless
    /// exercises match by name and role alone, so a program slot's history
    /// never leaks into an off-program suggestion or vice versa. Lives here
    /// (not on `ExerciseSection`) because it needs
    /// `completedSessions`/`session`/`recallEntry`, which only this view has.
    private func mostRecentTopExposure(for entry: SessionExercise) -> RecentTopExposure? {
        guard entry.exercise != nil else { return nil }
        for past in completedSessions where past.persistentModelID != session.persistentModelID {
            guard let recalled = recallEntry(for: entry, in: past),
                  let top = recalled.workingSets.max(by: { $0.weightLb < $1.weightLb }) else { continue }
            return RecentTopExposure(
                weightLb: top.weightLb, reps: top.reps, loadBasis: top.loadBasis,
                quality: top.quality?.rawValue, rir: top.rir?.rawValue, date: past.date
            )
        }
        return nil
    }

    private func addExercise(_ exercise: Exercise) {
        let entry = SessionExercise(order: session.exercises.count, exercise: exercise)
        entry.exerciseID = exercise.id
        entry.stampBarID(for: exercise, bar: gym?.defaultBar ?? .bar45lb)
        context.insert(entry)
        session.exercises.append(entry)
        PersistenceErrorCenter.shared.save(context, operation: "Adding the exercise")
    }

    /// One tap mid-session: apply the shared drop plan (core parity) — only
    /// not-yet-performed sets are touched, each dropped from its own weight.
    private func dropLoad(_ entry: SessionExercise, reason: AutoregReason) {
        let ordered = entry.orderedSets
        let bar = entry.barID.map { Bar.by(id: $0) } ?? gym?.defaultBar ?? .bar45lb
        // The configured drop derives from the MAIN work set — ramp/backoff
        // blocks at lighter loads must not anchor it. With no planned work
        // set left, fixedDrop stays nil and the generic percentage drop in
        // dropLoadPlan takes over.
        let firstPlannedWork = ordered.first {
            !$0.isWarmup && $0.status == .planned && $0.prescriptionBlock.countsAsPrescribedWork
        }
        let fixedDrop = firstPlannedWork.flatMap { current in
            entry.fallbackWeightLb.map { max(0, current.weightLb - $0) }
        }
        let plan = ProgramEngine.dropLoadPlan(
            sets: ordered.map { (weightLb: $0.weightLb, isWarmup: $0.isWarmup, isFlagged: $0.status != .planned) },
            roundingLb: ProgramEngine.loadStep(
                programRoundingLb: 5,
                exerciseType: entry.exercise?.typeRaw
            ),
            barLb: entry.exercise?.type == .barbell ? bar.lb : 0,
            dropIncrementLb: fixedDrop
        )
        guard !plan.isEmpty else { return }
        for target in plan {
            let set = ordered[target.index]
            set.weightLb = ProgramSession.fallbackWeight(
                from: set.weightLb,
                exercise: entry.exercise,
                gym: gym,
                bar: bar,
                roundingLb: ProgramEngine.loadStep(programRoundingLb: 5, exerciseType: entry.exercise?.typeRaw),
                dropIncrementLb: fixedDrop ?? 0
            )
            set.autoregReason = reason
        }
        let top = plan.map { ordered[$0.index].weightLb }.max() ?? 0
        entry.notes += (entry.notes.isEmpty ? "" : " ") + "Dropped to \(settingsList.unitDisplay.format(lb: top)) — \(reason.rawValue)."
        PersistenceErrorCenter.shared.save(context, operation: "Dropping the load")
    }
}

/// Smart per-exercise rest via the shared CadenceCore precedence (per-exercise
/// rest → program role → movementGroup bucket); no exercise → accessory bucket.
func smartRestSeconds(for exercise: Exercise?, role: String? = nil, settings: AppSettings?) -> Int {
    let config = settings?.restConfig ?? .standard
    guard let ex = exercise else { return config.accessorySeconds }
    return RestDefaults.seconds(category: ex.categoryRaw, movementGroup: ex.movementGroup, role: role,
                                config: config,
                                exerciseDefaultRest: ex.defaultRestSeconds)
}

/// Compact "how long ago" for the last-session recall line.
private func agoLabel(_ date: Date) -> String {
    let days = max(0, Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0)
    if days == 0 { return "today" }
    if days == 1 { return "yesterday" }
    if days < 14 { return "\(days)d ago" }
    if days < 70 { return "\(days / 7)w ago" }
    return "\(days / 30)mo ago"
}

/// Identifiable wrapper so the summary sheet can drive off .sheet(item:).
private struct SummaryBox: Identifiable {
    let id = UUID()
    let summary: SessionSummary
}

/// Immutable snapshot for the expanded bar sheet. Keeping the exact loadout
/// here prevents the sheet from re-solving against a gym edited underneath it.
private struct ExpandedLoadout: Identifiable {
    let id = UUID()
    let loadout: Loadout
    let requestedLb: Double?
    let unit: WeightUnit
    let style: PlateVisualStyle
}

// MARK: - Exercise section

private struct ExerciseSection: View {
    @Environment(\.modelContext) private var context
    @Environment(RestTimer.self) private var restTimer

    @Bindable var entry: SessionExercise
    @State private var showAllSets = false
    @State private var expandedLoadout: ExpandedLoadout?
    /// Only the actively worked exercise gets the full between-sets cockpit.
    /// Remaining exercises stay in authored order underneath it.
    let emphasized: Bool
    // Passed down from ActiveSessionView (which already queries them) — a
    // per-section @Query would register one redundant fetch per exercise.
    let settings: AppSettings?
    let gym: Gym?
    /// Automatic prescriptions are focus-dependent. A missing originating
    /// program is unknown evidence, so its automatic cue stays silent.
    let programFocus: TrainingFocus?
    let allExercises: [Exercise]
    /// Previous-performance context, or nil for a first-ever lift.
    let lastTime: String?
    /// This entry's most recent completed top-of-session exposure, scoped by
    /// `recallEntry` exactly like `lastTime` (program-slot matching for a
    /// programmed entry, name+role matching for an off-program one).
    /// Precomputed by `ActiveSessionView` (which owns
    /// `completedSessions`/`recallEntry`); nil with no prior history. Drives
    /// both the first-set default weight and its provenance disclosure.
    let adHocExposure: RecentTopExposure?
    let onDropLoad: () -> Void
    /// Marks this exercise as the one being actively worked (drives the bottom bar).
    let onWork: (SessionExercise) -> Void
    /// Remove this exercise from the session. Unlike a swap, removal leaves no
    /// performed entry carrying the program slot identity.
    let onRemove: () -> Void
    /// Move this exercise one position up (-1) or down (+1) in THIS session's
    /// order. Session-only, like removal — the program day is untouched.
    let onMove: (Int) -> Void

    /// How long a swap outlives this session (issue 20). Session-only is the
    /// default: the program's exercise name is untouched, while today's entry
    /// keeps the stable slot identity and its prescribed work grades that slot.
    /// Cycle renames the slot and reverts it at the next rollover; program
    /// renames it for good.
    enum SwapScope { case session, cycle, program }

    /// Same-movement-pattern lifts you can swap in, constrained to the same
    /// programming tier and loadability, excluding shelved (SwapRules in
    /// CadenceCore — no more Walking Lunges → Back Squat or DB Press → Dips).
    private var alternatives: [Exercise] {
        guard let cur = entry.exercise else { return [] }
        return allExercises.filter {
            SwapRules.compatible(
                currentName: cur.name, currentCategory: cur.categoryRaw,
                currentLoadBasis: cur.loadBasis, currentGroup: cur.movementGroup,
                candidateName: $0.name, candidateCategory: $0.categoryRaw,
                candidateLoadBasis: $0.loadBasis, candidateGroup: $0.movementGroup,
                candidateShelved: $0.isShelved
            )
        }
    }

    private func swap(to newExercise: Exercise, scope: SwapScope) {
        let oldName = entry.exercise?.name
        let oldType = entry.exercise?.typeRaw
        // Session scope leaves the program slot alone. Cycle/program scope
        // repoint the slot at the lift you're actually doing (completion
        // matches the durable slot ID, with name+role only for legacy
        // sessions); the slot keeps its
        // progression state as the starting load — candidates train the same
        // pattern at the same tier, so base/e1RM remain the best prior.
        if scope != .session {
            guard let role = entry.programRole, let session = entry.session,
                  let dayIndex = entry.session?.programDayIndex else {
                PersistenceErrorCenter.shared.report(
                    NSError(domain: "Cadence", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "This session has no durable program linkage."]),
                    operation: "Changing the program exercise", context: context
                )
                return
            }
            let program: Program
            do {
                guard let found = try fetchProgram(id: session.programID, named: session.programName) else {
                    throw NSError(domain: "Cadence", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "The originating program no longer exists."])
                }
                program = found
            } catch {
                PersistenceErrorCenter.shared.report(error, operation: "Loading the program for the swap", context: context)
                return
            }
            guard let day = program.day(order: dayIndex) else {
                PersistenceErrorCenter.shared.report(
                    NSError(domain: "Cadence", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "The program day for this session no longer exists."]),
                    operation: "Loading the program for the swap", context: context
                )
                return
            }
            if role == "accessory" {
                if let acc = entry.programSlotID.flatMap({ id in day.accessories.first { $0.id == id } })
                    ?? day.accessories.first(where: { $0.exerciseName == oldName }) {
                    // Cycle: remember the original once (re-swapping mid-cycle
                    // keeps the FIRST original). Program: any pending revert dies.
                    if scope == .cycle { acc.revertToExerciseName = acc.revertToExerciseName ?? oldName }
                    else { acc.revertToExerciseName = nil }
                    acc.exerciseName = newExercise.name
                }
            } else if let lift = entry.programSlotID.flatMap({ id in day.lifts.first { $0.id == id } })
                ?? day.lifts.first(where: { $0.exerciseName == oldName && $0.roleRaw == role }) {
                if scope == .cycle { lift.revertToExerciseName = lift.revertToExerciseName ?? oldName }
                else { lift.revertToExerciseName = nil }
                lift.exerciseName = newExercise.name
            }
        }
        entry.exercise = newExercise
        // The swap is an entry mutation like creation: a barbell substitute
        // must carry a bar record (keep an existing pick, else stamp the gym
        // default) and a non-barbell substitute must not keep a stale one —
        // an unstamped swapped entry is exactly the legacy-nil row the
        // gym-change resync would keep reinterpreting. One spelling: the
        // stamp helper owns the rule; only "keep an existing pick" is local.
        if entry.barID == nil || newExercise.type != .barbell {
            entry.stampBarID(for: newExercise, bar: gym?.defaultBar ?? .bar45lb)
        }
        entry.sets.forEach { set in
            set.isPerSide = newExercise.isUnilateral
            if set.status == .planned {
                set.loadBasis = newExercise.loadBasis
                set.implementCount = newExercise.resolvedImplementCount
            }
        }
        reconcileWarmups(oldType: oldType, newExercise: newExercise)
        if PersistenceErrorCenter.shared.save(context, operation: "Swapping the exercise") { onWork(entry) }
    }

    /// Equipment-changing swaps invalidate the warmup ramp: a non-barbell
    /// substitute drops the barbell ramp; a barbell substitute for a lift that
    /// had none gains one. Working sets are never touched — the prescription
    /// stands and any logged work is the user's record.
    private func reconcileWarmups(oldType: String?, newExercise: Exercise) {
        guard oldType != newExercise.typeRaw else { return }
        let warmups = entry.sets.filter(\.isWarmup)
        let supportsRamp = newExercise.type == .barbell
            || (newExercise.type == .dumbbell && entry.programRole == LiftRole.main.rawValue)
        if !supportsRamp {
            for set in warmups { context.delete(set) }
            entry.sets.removeAll(where: \.isWarmup)
            // Renumber the survivors: addSet() assigns order = sets.count, so
            // leftover gaps (3,4,5) would collide with the next added set.
            for (i, set) in entry.orderedSets.enumerated() { set.order = i }
        } else {
            synchronizeWarmups(entry, bar: effectiveBar, gym: gym,
                               rebuildingForNewEquipment: true,
                               enteredUnit: settings?.unitDisplay.primaryUnit ?? .lb,
                               context: context)
        }
    }

    private func fetchProgram(id: String?, named name: String?) throws -> Program? {
        try context.fetch(FetchDescriptor<Program>())
            .matching(sessionProgramID: id, name: name)
    }

    /// A nil override follows the selected gym's default. Explicit choices are
    /// stored on the session exercise so they survive navigation and relaunch.
    private var effectiveBar: Bar { entry.barID.map { Bar.by(id: $0) } ?? gym?.defaultBar ?? .bar45lb }

    /// A picked swap for a program slot, awaiting its scope (issue 20).
    /// Standalone entries skip the dialog — with no slot, session-only is the
    /// only meaning a swap can have.
    @State private var pendingSwap: Exercise?
    /// The lift-info sheet's subject (the entry's own exercise, opened from
    /// the header name).
    @State private var liftInfo: Exercise?

    private var restSeconds: Int { smartRestSeconds(for: entry.exercise, role: entry.programRole, settings: settings) }

    private func solvedLoadout(for set: SetEntry) -> Loadout {
        authoritativePlateSolution(
            targetLb: set.weightLb,
            fallbackUnit: set.enteredUnit,
            bar: effectiveBar,
            gym: gym,
            stationDenomination: entry.exercise?.stationDenomination
        ).loadout
    }
    private var complementaryEffortCue: String? {
        guard let role = entry.programRole.flatMap(LiftRole.init(rawValue:)),
              let style = PrescriptionStyle(rawValue: entry.prescriptionStyleRaw) else { return nil }
        guard style != .automatic || programFocus != nil else { return nil }
        return ProgramEngine.complementaryEffortCue(
            role: role,
            prescriptionStyle: style,
            movementGroup: entry.exercise?.movementGroup,
            focus: programFocus ?? .strength
        )
    }
    private var restBinding: Binding<Int> {
        Binding(get: { restSeconds },
                set: {
                    entry.exercise?.defaultRestSeconds = $0
                    PersistenceErrorCenter.shared.save(context, operation: "Changing the rest timer")
                })
    }
    // Stepper floor: writing 0 clears the override, and the stepper displays
    // the EFFECTIVE rest — so 0 is only offered where clearing lands on 0
    // (conditioning, or a bucket the user zeroed); elsewhere a decrement to 0
    // would snap the display up to the movement default. Same role + config as
    // the effective rest (mirrors web editRest's floor).
    private var restFloor: Int {
        guard let ex = entry.exercise else { return 15 }
        return RestDefaults.seconds(category: ex.categoryRaw, movementGroup: ex.movementGroup, role: entry.programRole,
                                    config: settings?.restConfig ?? .standard) == 0 ? 0 : 15
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String, iconOnly: Bool) -> some View {
        if iconOnly {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        } else {
            // fixedSize keeps ViewThatFits honest: a row that would have to
            // wrap its titles mid-word reports "doesn't fit" instead.
            Label(title, systemImage: systemImage).lineLimit(1).fixedSize()
        }
    }

    private func setActionButtons(iconOnly: Bool) -> some View {
        HStack {
            Button {
                onWork(entry)
                addSet()
            } label: {
                actionLabel("Set", systemImage: "plus", iconOnly: iconOnly)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add set")

            Button {
                onWork(entry)
                if let last = entry.orderedSets.last(where: { !$0.isWarmup }) ?? entry.orderedSets.last {
                    removeSet(last)
                }
            } label: {
                actionLabel("Set", systemImage: "minus", iconOnly: iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(entry.sets.isEmpty)
            .accessibilityLabel("Remove set")

            Button {
                onWork(entry)
                restTimer.start(seconds: restSeconds, exerciseName: entry.exercise?.name ?? "")
            } label: {
                actionLabel("Rest", systemImage: "timer", iconOnly: iconOnly)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Start rest timer")

            Spacer()

            Button {
                onDropLoad()
            } label: {
                actionLabel("Dropping load", systemImage: "arrow.down.right", iconOnly: iconOnly)
            }
            .buttonStyle(.bordered)
            .tint(Theme.warn)
            .accessibilityLabel("Dropping load")
        }
    }

    var body: some View {
        Section {
            if emphasized, let exercise = entry.exercise {
                HStack(spacing: 8) {
                    Text(exercise.movementGroup.replacingOccurrences(of: "_", with: " ").uppercased())
                    if let role = entry.programRole {
                        Text(role.uppercased())
                    }
                    if let phase = entry.truthfulPhaseLabel {
                        Text(phase.uppercased()).foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption2.bold())
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            if let complementaryEffortCue {
                Text(complementaryEffortCue)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .accessibilityLabel("Effort target: \(complementaryEffortCue)")
            }
            ForEach(entry.orderedSets) { set in
                // The set you're ON — the first WORKING set with no verdict
                // yet. Warmups sit quiet (and often go unflagged, so they must
                // not hold the rail hostage).
                let isCurrent = entry.orderedSets.first { !$0.isWarmup && $0.status == .planned }?.persistentModelID == set.persistentModelID
                let showLoadout = showAllSets || isCurrent || loadChanges(at: set)
                VStack(alignment: .leading, spacing: 4) {
                    if emphasized && isCurrent {
                        Text("CURRENT SET · NEXT ACTION")
                            .font(.caption.bold())
                            .tracking(0.8)
                            .foregroundStyle(Theme.accent)
                    }
                    SetRow(set: set, entry: entry, exercise: entry.exercise, gym: gym, bar: effectiveBar, isCurrent: isCurrent,
                           compact: !showAllSets && !isCurrent,
                           targetLb: set.plannedWeightLb ?? entry.plannedWeightLb, onLogged: {
                        onWork(entry)
                        // Auto-start only if the user opted in (manual is the
                        // default), and never restart a countdown already running.
                        if settings?.autoStartRest == true && !restTimer.isRunning {
                            restTimer.start(seconds: set.isWarmup ? 60 : restSeconds,
                                            exerciseName: entry.exercise?.name ?? "")
                        }
                    }, onRemove: { removeSet(set) })
                    // Discloses where the first working set's ad-hoc history
                    // suggestion came from — only for that set, and only when
                    // a suggestion actually shaped it (never the silent
                    // catalog-default fallback).
                    if !set.isWarmup,
                       entry.orderedSets.first(where: { !$0.isWarmup })?.persistentModelID == set.persistentModelID,
                       let firstSetProvenance {
                        Text(firstSetProvenance)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Loadout visualization — plates for barbell lifts, the
                    // rack number for dumbbell lifts. Mirrors web.
                    if showLoadout, entry.exercise?.type == .barbell && set.weightLb > 0 {
                        let exactLoadout = solvedLoadout(for: set)
                        if emphasized && isCurrent {
                            ScrollView(.horizontal, showsIndicators: true) {
                                BarbellView(weightLb: set.weightLb, unit: set.enteredUnit,
                                            bar: effectiveBar, gym: gym,
                                            targetWeightLb: set.targetWeightLb ?? entry.targetWeightLb,
                                            loadout: exactLoadout,
                                            stationDenomination: entry.exercise?.stationDenomination,
                                            plateStyle: entry.exercise?.movementGroup == "olympic" ? .bumper : .steel,
                                            presentation: .fullBar)
                                .frame(width: 420, height: 132)
                            }
                            .accessibilityLabel("Loaded bar diagram; scroll horizontally if needed")
                        } else {
                            BarbellView(weightLb: set.weightLb, unit: set.enteredUnit,
                                        bar: effectiveBar, gym: gym,
                                        targetWeightLb: set.targetWeightLb ?? entry.targetWeightLb,
                                        loadout: exactLoadout,
                                        stationDenomination: entry.exercise?.stationDenomination,
                                        plateStyle: entry.exercise?.movementGroup == "olympic" ? .bumper : .steel,
                                        presentation: .compactSide)
                        }
                        if emphasized && isCurrent {
                            LoadoutSummaryView(
                                requestedLb: set.targetWeightLb ?? entry.targetWeightLb,
                                loadout: exactLoadout
                            )
                            Button("Inspect loaded bar", systemImage: "arrow.up.left.and.arrow.down.right") {
                                expandedLoadout = ExpandedLoadout(
                                    loadout: exactLoadout,
                                    requestedLb: set.targetWeightLb ?? entry.targetWeightLb,
                                    unit: set.enteredUnit,
                                    style: entry.exercise?.movementGroup == "olympic" ? .bumper : .steel
                                )
                            }
                            .font(.caption.bold())
                            .frame(minHeight: 44)
                        }
                    } else if showLoadout, entry.exercise?.type == .dumbbell && set.weightLb > 0 {
                        DumbbellView(weightLb: set.weightLb, unit: set.enteredUnit)
                    }
                }
                .opacity(set.isWarmup ? 0.68 : (set.status == .completed ? 0.72 : 1))
            }
            .onDelete { offsets in
                let ordered = entry.orderedSets
                for index in offsets.sorted(by: >) { removeSet(ordered[index], save: false) }
                PersistenceErrorCenter.shared.save(context, operation: "Deleting the set")
            }

            if entry.orderedSets.count > 1 {
                Button(showAllSets ? "Focus current set" : "Show all sets") {
                    showAllSets.toggle()
                }
                .font(.caption.bold())
            }

            // The row must never solve a tight fit by wrapping label text
            // character-by-character; when the full labels don't fit (larger
            // Dynamic Type), fall back to icons with accessibility labels.
            ViewThatFits(in: .horizontal) {
                setActionButtons(iconOnly: false)
                setActionButtons(iconOnly: true)
            }

            if entry.exercise?.type == .barbell {
                Picker("Bar", selection: Binding(
                    get: { effectiveBar },
                    set: {
                        entry.barID = $0.id
                        // A hand-picked bar is a decision: it never follows a
                        // mid-session gym switch, even when it happens to
                        // equal a gym's default.
                        entry.barIDIsManual = true
                        synchronizeWarmups(entry, bar: $0, gym: gym,
                                           enteredUnit: settings?.unitDisplay.primaryUnit ?? .lb,
                                           context: context)
                        PersistenceErrorCenter.shared.save(context, operation: "Changing the exercise bar")
                    }
                )) {
                    ForEach(Bar.all) { Text($0.label).tag($0) }
                }
                .font(.caption)
            }

            Stepper("Rest between sets: \(mmss(restSeconds))", value: restBinding, in: restFloor...600, step: 15)
                .font(.caption)
            // The stepper shows the EFFECTIVE rest, so its floor can't offer
            // 0 ("Default") without the display snapping to the bucket value —
            // clearing an override back to bucket-driven is an explicit action
            // instead, offered only while an override exists.
            if (entry.exercise?.defaultRestSeconds ?? 0) > 0 {
                Button("Reset rest to default") {
                    entry.exercise?.defaultRestSeconds = 0
                    PersistenceErrorCenter.shared.save(context, operation: "Resetting the rest timer")
                }
                .font(.caption)
            }
        } header: {
            HStack {
                // The name is the door to the lift itself — muscles figure,
                // history, settings — mid-workout, same as the preview and
                // program editor. A sheet, not a header NavigationLink: sheet
                // presentation from this header is proven (the Menu and the
                // swap dialog already present here), dismissing lands exactly
                // where logging left off, and the entry's own relationship is
                // the identity — no by-name re-resolution that could dead-end
                // at "Not in the library" for a lift the session still holds.
                if let exercise = entry.exercise {
                    Button {
                        liftInfo = exercise
                    } label: {
                        Text(exercise.name)
                            .font(emphasized ? .title2.bold() : .headline)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exercise-info-\(exercise.name)")
                    .accessibilityHint("Shows muscles worked, history, and exercise settings")
                    .sheet(item: $liftInfo) { exercise in
                        NavigationStack {
                            ExerciseDetailView(
                                exercise: exercise,
                                sessionEntry: entry,
                                sessionGym: gym,
                                sessionProgramFocus: programFocus
                            )
                        }
                    }
                } else {
                    Text("Exercise")
                }
                if let phaseLabel = entry.truthfulPhaseLabel {
                    Text(phaseLabel).foregroundStyle(Theme.accent)
                }
                if let lastTime {
                    Text(lastTime).textCase(nil)
                }
                if entry.exercise?.isShelved == true {
                    Text(Copy.shelved).foregroundStyle(Theme.hardStop)
                }
                Spacer()
                Menu {
                    if !alternatives.isEmpty {
                        Menu {
                            ForEach(alternatives) { alt in
                                Button(alt.name) {
                                    if entry.programRole != nil { pendingSwap = alt }
                                    else { swap(to: alt, scope: .session) }
                                }
                            }
                        } label: { Label("Swap exercise", systemImage: "arrow.left.arrow.right") }
                    }
                    // Session-only reorder (issue #64): a complementary lift
                    // pulled forward today does not edit the program day.
                    Button { onMove(-1) } label: { Label("Move up", systemImage: "arrow.up") }
                    Button { onMove(1) } label: { Label("Move down", systemImage: "arrow.down") }
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove from session", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Exercise options")
                if !alternatives.isEmpty {
                    // Retain the confirmation dialog anchor for scoped swaps.
                    Color.clear.frame(width: 0, height: 0)
                    .confirmationDialog(
                        "Swap to \(pendingSwap?.name ?? "")?",
                        isPresented: Binding(get: { pendingSwap != nil },
                                             set: { if !$0 { pendingSwap = nil } }),
                        titleVisibility: .visible,
                        presenting: pendingSwap
                    ) { alt in
                        Button("Just this session") { swap(to: alt, scope: .session) }
                        Button("For the rest of this cycle") { swap(to: alt, scope: .cycle) }
                        Button("For the whole program") { swap(to: alt, scope: .program) }
                        Button("Cancel", role: .cancel) {}
                    } message: { _ in
                        Text("Just this session leaves the program unchanged. Cycle swaps revert at the next rollover; program swaps rename the slot for good.")
                    }
                }
            }
        } footer: {
            if let site = entry.exercise?.watchSite {
                Text("Watch: \(site.rawValue.lowercased()) — \(site.watchNote)")
            }
        }
        .sheet(item: $expandedLoadout) { detail in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ScrollView(.horizontal, showsIndicators: true) {
                            BarbellView(
                                weightLb: detail.loadout.totalLb,
                                unit: detail.unit,
                                bar: detail.loadout.bar,
                                gym: gym,
                                loadout: detail.loadout,
                                plateStyle: detail.style,
                                presentation: .fullBar
                            )
                            .frame(width: 620, height: 180)
                            .padding(.horizontal)
                        }
                        LoadoutSummaryView(requestedLb: detail.requestedLb, loadout: detail.loadout)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .navigationTitle(entry.exercise?.name ?? "Loaded bar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { expandedLoadout = nil }
                    }
                }
            }
        }
    }

    private func loadChanges(at set: SetEntry) -> Bool {
        let ordered = entry.orderedSets
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == set.persistentModelID }), index > 0 else {
            return false
        }
        let previous = ordered[index - 1]
        return abs(previous.weightLb - set.weightLb) > 0.001
            || previous.loadBasis != set.loadBasis
            || previous.resolvedImplementCount != set.resolvedImplementCount
    }

    /// [INV-RUCK-CARRIES-ITS-LOAD] What a new duration-based set starts loaded
    /// with. Unloaded conditioning and timed holds carry nothing; a ruck or
    /// sled inherits the previous leg's load, or opens at the movement's
    /// default. A previous leg deliberately set to zero stays zero.
    private static func startingCarryLoadLb(entry: SessionExercise, last: SetEntry?) -> Double {
        guard entry.exercise?.type == .conditioning,
              let name = entry.exercise?.name,
              CardioFormat.carriesLoad(exerciseName: name) else { return 0 }
        if let last { return last.weightLb }
        return CardioFormat.defaultLoadLb(exerciseName: name) ?? 0
    }

    private func addSet() {
        let last = entry.orderedSets.last
        let isTimed = entry.exercise?.type == .timed || entry.exercise?.type == .conditioning
        // [INV-RUCK-CARRIES-ITS-LOAD] Duration-based work is unloaded EXCEPT a
        // loaded carry, which is born wearing its pack and carries that weight
        // to the next leg. Defaulting later — on first edit — cannot work: a
        // conditioning set is created with a planned duration, so there is no
        // moment afterwards when it is distinguishable from one the lifter
        // deliberately set to zero.
        let carryLb = Self.startingCarryLoadLb(entry: entry, last: last)
        let set = SetEntry(
            order: entry.sets.count,
            weightLb: isTimed ? carryLb : (last?.weightLb ?? entry.plannedWeightLb ?? firstSetDefaultLb()),
            reps: isTimed ? 1 : (last?.reps ?? entry.plannedReps ?? 5),
            isPerSide: entry.exercise?.isUnilateral ?? false,
            enteredUnit: last?.enteredUnit ?? settings?.unitDisplay.primaryUnit ?? .lb,
            durationSeconds: isTimed ? (last?.durationSeconds ?? 30) : nil,
            loadBasis: last?.loadBasis ?? entry.exercise?.loadBasis,
            implementCount: last?.resolvedImplementCount ?? entry.exercise?.resolvedImplementCount ?? 1,
            targetWeightLb: last?.targetWeightLb ?? entry.targetWeightLb,
            plannedWeightLb: last?.weightLb ?? entry.plannedWeightLb,
            plannedReps: isTimed ? 1 : (last?.reps ?? entry.plannedReps ?? 5),
            plannedDurationSeconds: isTimed ? (last?.durationSeconds ?? 30) : nil,
            prescriptionBlock: entry.exercise?.type == .conditioning ? .conditioning : .work
        )
        context.insert(set)
        entry.sets.append(set)
        PersistenceErrorCenter.shared.save(context, operation: "Adding the set")
    }

    private func removeSet(_ set: SetEntry, save: Bool = true) {
        entry.sets.removeAll { $0 === set }
        context.delete(set)
        for (index, remaining) in entry.orderedSets.enumerated() { remaining.order = index }
        if save { PersistenceErrorCenter.shared.save(context, operation: "Deleting the set") }
    }

    /// The first set of an exercise added mid-session, with no plan and no
    /// predecessor to inherit from. The old default was a literal 45 — the
    /// empty bar — which prescribed phantom load to everything else: a
    /// bodyweight GHD sit-up was born asking for 45 lb. When the lifter has
    /// already performed this off-program exercise, their own last top-of-
    /// session exposure (`adHocExposure`, precomputed by `ActiveSessionView`)
    /// is a far better starting point than the generic catalog — the
    /// conservative bootstrap catalog only applies when there is no such
    /// history. A barbell movement is floored at the bar actually in hand
    /// either way: the catalog's light recommendations assume a lighter bar,
    /// and a total-bar set cannot weigh less than its own bar.
    private func firstSetDefaultLb() -> Double {
        guard let exercise = entry.exercise else { return 0 }
        let catalogLb = ProgrammingDefaultsData.recommendation(
            exerciseName: exercise.name,
            slotCategory: exercise.categoryRaw,
            exerciseType: exercise.typeRaw
        ).weightLb
        let suggestedLb = ProgramProgression.suggestedAdHocFirstSetTarget(
            fromLastTopExposure: adHocExposure
        )?.weightLb ?? catalogLb
        return exercise.type == .barbell ? max(suggestedLb, effectiveBar.lb) : suggestedLb
    }

    /// Where the history-based suggestion prefilled into this entry's first
    /// working set came from, so the UI can disclose it instead of leaving a
    /// history-derived number unexplained. Nil whenever there is no prior
    /// exposure (the catalog default applied silently, as before).
    private var firstSetProvenance: String? {
        guard let exposure = adHocExposure,
              ProgramProgression.suggestedAdHocFirstSetTarget(fromLastTopExposure: exposure) != nil
        else { return nil }
        return ProgramProgression.historyProvenanceLabel(exposureDate: exposure.date, asOf: .now)
    }
}

/// Keep the editable prescription and its equipment illustration on the same
/// bar context without discarding status/quality already logged on matching
/// warmup rows.
private func synchronizeWarmups(_ entry: SessionExercise, workingLb overrideWorkingLb: Double? = nil,
                                bar: Bar, gym: Gym?, rebuildingForNewEquipment: Bool = false,
                                enteredUnit: WeightUnit, context: ModelContext) {
    guard let exercise = entry.exercise,
          let workingLb = overrideWorkingLb ?? entry.plannedWeightLb
            ?? entry.orderedSets.first(where: { !$0.isWarmup })?.weightLb,
          workingLb > 0 else { return }
    var desired: [WarmupSet]
    if exercise.type == .barbell {
        desired = ProgramSession.achievableWarmups(
            WarmupRamp.ramp(workingLb: workingLb, barLb: bar.lb,
                            roundingLb: ProgramEngine.defaultRoundingLb,
                            includeEmptyBar: ProgramSession.includesEmptyBarWarmup(for: exercise)),
            workingLb: workingLb, gym: gym, bar: bar, exercise: exercise)
    } else if exercise.type == .dumbbell && entry.programRole == LiftRole.main.rawValue {
        desired = WarmupRamp.dumbbellRamp(workingLb: workingLb,
                                          roundingLb: ProgramEngine.loadStep(
                                            programRoundingLb: ProgramEngine.defaultRoundingLb,
                                            exerciseType: exercise.typeRaw))
    } else {
        return
    }
    let existing = entry.orderedSets.filter(\.isWarmup)
    // A programmed entry was built under a resolved warmup policy — full
    // ramp, two bridging sets for a complementary lift, or none — possibly
    // refined by the user's own row edits. Resync refreshes the warmup
    // WEIGHTS for the new bar/gym/working weight without changing how many
    // warmups the plan owns (suffix keeps the steps nearest the working
    // weight); it must never re-inflate a deliberately short — or deliberately
    // EMPTY — ramp: a programmed entry with zero warmups keeps zero, matching
    // web. Manually added exercises still grow a full ramp as before.
    //
    // An EQUIPMENT-changing swap is the exception: the old ramp described a
    // different implement, so its length carries no intent about the new one,
    // and a lift that had no ramp at all (a machine or band slot) must be able
    // to gain one when it becomes a barbell.
    if entry.programRole != nil, !rebuildingForNewEquipment {
        desired = Array(desired.suffix(existing.count))
    }
    var rebuilt: [SetEntry] = []
    for (index, target) in desired.enumerated() {
        if index < existing.count {
            // Resync refreshes rows still PLANNED; a completed or skipped
            // warmup is the athlete's performed record and its weight/reps
            // are never reinterpreted against new equipment.
            if existing[index].status == .planned {
                existing[index].weightLb = target.weightLb
                existing[index].reps = target.reps
            }
            rebuilt.append(existing[index])
        } else {
            let set = SetEntry(order: index, weightLb: target.weightLb, reps: target.reps,
                               isWarmup: true, enteredUnit: enteredUnit,
                               loadBasis: exercise.loadBasis,
                               implementCount: exercise.resolvedImplementCount,
                               targetWeightLb: target.weightLb,
                               plannedWeightLb: target.weightLb,
                               plannedReps: target.reps,
                               prescriptionBlock: .warmup)
            context.insert(set)
            rebuilt.append(set)
        }
    }
    if existing.count > desired.count {
        // Only surplus PLANNED rows are dropped; performed rows survive the
        // shrink — deleting logged work is never a resync's job.
        for set in existing.dropFirst(desired.count) {
            if set.status == .planned { context.delete(set) } else { rebuilt.append(set) }
        }
    }
    let working = entry.orderedSets.filter { !$0.isWarmup }
    entry.sets = rebuilt + working
    for (index, set) in entry.sets.enumerated() { set.order = index }
}

// MARK: - Set row

private struct SetRow: View {
    @Bindable var set: SetEntry
    let entry: SessionExercise
    let exercise: Exercise?
    let gym: Gym?
    let bar: Bar
    /// The set you're ON (first with no verdict yet) — gets the accent rail.
    let isCurrent: Bool
    /// Completed/future rows retain every control but give the current set the cockpit.
    let compact: Bool
    /// The program/track weight this session recommends — the picker anchors here.
    let targetLb: Double?
    var onLogged: () -> Void
    var onRemove: () -> Void

    @State private var showDetail = false

    /// Steady-state cardio (Walk/Bike/Ruck…) logs distance/time/incline, not
    /// weight×reps. Keyed on the exercise TYPE — rep-based conditioning like
    /// burpees (category Conditioning, type bodyweight) keeps the lifting row.
    private var isCardio: Bool { exercise?.type == .conditioning }
    private var isTimed: Bool { exercise?.type == .timed }

    /// The affordance line names the fields the sheet will actually show, from
    /// the same rule the sheet uses, so the row never advertises one the sheet
    /// withholds — nor understates it, which is what a hand-written string did
    /// for a climb still holding a legacy distance.
    private var cardioHint: String {
        CardioFormat.fields(exerciseName: exercise?.name ?? "",
                            flights: set.flights,
                            distanceMiles: set.distanceMiles,
                            inclinePercent: set.inclinePercent).label
    }

    var body: some View {
        HStack(spacing: 12) {
            if isCurrent {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent)
                    .frame(width: 3, height: 34)
                    .accessibilityLabel("Current set")
            }
            Button {
                showDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrent ? "NOW" : (set.status == .completed ? "COMPLETED" : (set.status == .skipped ? "SKIPPED" : "UPCOMING")))
                        .font(.caption2.bold())
                        .tracking(0.7)
                        .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                    // Cardio uses the shared CadenceCore formatter; lifts show
                    // weight in the unit used for entry.
                    Text(isCardio
                         ? CardioFormat.setLabel(distanceMiles: set.distanceMiles,
                                                 durationSeconds: set.durationSeconds,
                                                 inclinePercent: set.inclinePercent,
                                                 loadLb: set.weightLb,
                                                 flights: set.flights)
                         : (isTimed ? CardioFormat.durationLabel(seconds: set.durationSeconds ?? 0) : weightLabel))
                        .font((isCurrent ? Font.title2 : (compact ? Font.callout : Font.title3)).bold().monospacedDigit())
                        .foregroundStyle(set.isWarmup ? .secondary : .primary)
                    HStack(spacing: 6) {
                        if !isCardio && !isTimed {
                            Text("× \(set.reps)\(set.isPerSide ? "/side" : "")")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else if isCardio {
                            Text("tap to log \(cardioHint)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("tap to adjust hold time")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if !isCardio && !isTimed,
                           let plannedWeight = set.plannedWeightLb,
                           let plannedReps = set.plannedReps,
                           abs(plannedWeight - set.weightLb) > 0.001 || plannedReps != set.reps {
                            let plannedLoad = set.enteredUnit == .kg
                                ? "\(Weight.trim(Weight.kg(fromLb: plannedWeight))) kg"
                                : "\(Weight.trim(plannedWeight)) lb"
                            Text("planned \(plannedLoad)×\(plannedReps)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if set.isWarmup {
                            Text(set.prescriptionBlock == .primer ? "primer" : "warmup")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else if set.prescriptionBlock == .topSingle {
                            Text("top single").font(.caption2).foregroundStyle(Theme.accent)
                        } else if set.prescriptionBlock == .ramp {
                            Text("ramp").font(.caption2).foregroundStyle(.secondary)
                        } else if set.prescriptionBlock == .backoff {
                            Text("back-off").font(.caption2).foregroundStyle(.secondary)
                        } else if set.prescriptionBlock == .amrap {
                            // The prescribed reps are a FLOOR on this set. Without
                            // saying so, 5/3/1's week 3 reads as a plain single and
                            // the "+" — the whole progression engine — never happens.
                            Text("AMRAP — \(set.plannedReps ?? set.reps)+ reps, stop when a rep turns grindy")
                                .font(.caption2).foregroundStyle(Theme.accent)
                        }
                        if let reason = set.autoregReason {
                            Text("↓ \(reason.rawValue)").font(.caption2).foregroundStyle(Theme.warn)
                        }
                        if set.bodyFlagSite != nil {
                            Image(systemName: "bolt.heart.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.hardStop)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            SetVerdictControl(set: set, allowsQuality: !isCardio && !isTimed, onCompleted: onLogged)
        }
        .padding(isCurrent ? 12 : 0)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.accent.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.accent.opacity(0.55)))
            }
        }
        .sheet(isPresented: $showDetail) {
            if isCardio {
                CardioSetSheet(set: set, exerciseName: exercise?.name ?? "", onDelete: onRemove)
                    .presentationDetents([.medium, .large])
            } else if isTimed {
                TimedSetSheet(set: set, onDelete: onRemove)
                    .presentationDetents([.medium])
            } else {
                SetDetailSheet(set: set, entry: entry, exercise: exercise, gym: gym, bar: bar,
                               targetLb: targetLb, onDelete: onRemove)
                    .presentationDetents([.large])
            }
        }
    }

    private var weightLabel: String {
        if set.weightLb == 0 { return "BW" }
        let suffix = set.loadBasis.shortSuffix
        switch set.enteredUnit {
        case .lb: return "\(Weight.trim(set.weightLb)) lb\(suffix)"
        case .kg: return "\(Weight.trim(Weight.kg(fromLb: set.weightLb))) kg\(suffix)"
        }
    }
}

// MARK: - Cardio set detail (distance / time / incline)

/// Conditioning-type work logs distance, time, speed, and incline.
/// [INV-CARDIO-SOLVES-THE-THIRD] Distance and speed are two views of one
/// relationship, so both are editable and whichever one the lifter is not
/// adjusting is the one that recomputes. Time is never overwritten. Only
/// distance and duration persist — speed stays derivable, so there is no third
/// stored value that can disagree with the two it came from.
/// Small deliberate steps for each field — content hoisted into plain
/// rows to stay inside the type-checker's budget (see CompileRegressionTests).
private struct CardioSetSheet: View {
    /// Which side is currently computed from the other two.
    private enum Derived { case speed, distance }
    /// The same idea against the climber's yardstick: either the pace is the
    /// readout, or the count is.
    private enum FlightDerived { case pace, flights }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: SetEntry
    let exerciseName: String
    let onDelete: () -> Void

    /// Distance is what gets stored, so it starts as the entered value and
    /// speed is the readout — the same way the sheet behaved before speed
    /// became editable.
    @State private var derived: Derived = .speed

    /// The count is what gets stored, so flights start as the entered value
    /// and the pace is the readout.
    @State private var flightDerived: FlightDerived = .pace

    /// [INV-STAIRS-COUNT-FLIGHTS] Which fields this sheet offers, captured
    /// ONCE when it opens.
    ///
    /// Deliberately state rather than a computed property: the rule reads the
    /// values being edited, so recomputing it would let a field delete itself
    /// mid-edit. Stepping a legacy climb's distance to zero would remove the
    /// distance and speed rows on the spot — and permanently, since reopening
    /// re-evaluates the same now-false condition — leaving no way to retype the
    /// number that had just been cleared.
    @State private var fields: CardioFormat.CardioFields

    init(set: SetEntry, exerciseName: String, onDelete: @escaping () -> Void) {
        self._set = Bindable(wrappedValue: set)
        self.exerciseName = exerciseName
        self.onDelete = onDelete
        self._fields = State(initialValue: CardioFormat.fields(
            exerciseName: exerciseName,
            flights: set.flights,
            distanceMiles: set.distanceMiles,
            inclinePercent: set.inclinePercent
        ))
    }

    private var carriesLoad: Bool { fields.load }
    private var carryLb: Double { self.set.weightLb }

    private var showsFlights: Bool { fields.flights }
    private var showsDistance: Bool { fields.distance }
    private var showsIncline: Bool { fields.incline }

    // `self.` keeps the parser from reading `set` as a setter declaration
    // (the type has a property named `set` — see CompileRegressionTests).
    private var miles: Double { self.set.distanceMiles ?? 0 }
    private var secs: Int { self.set.durationSeconds ?? 0 }
    private var incline: Double { self.set.inclinePercent ?? 0 }
    private var flights: Double { self.set.flights ?? 0 }
    private var mph: Double {
        CardioFormat.speedMph(distanceMiles: self.set.distanceMiles, durationSeconds: self.set.durationSeconds) ?? 0
    }
    private var flightPace: Double {
        CardioFormat.flightPace(flights: self.set.flights, durationSeconds: self.set.durationSeconds) ?? 0
    }

    /// Typing a distance makes speed the readout again.
    private func applyDistance(_ value: Double) {
        set.distanceMiles = value > 0 ? value : nil
        derived = .speed
    }

    /// Setting a pace computes the distance it covers in the logged time —
    /// the treadmill case, where the belt reports no distance until it stops.
    private func applySpeed(_ value: Double) {
        derived = .distance
        // With no time logged there is nothing to solve against. Assigning the
        // nil would delete a distance the lifter already has, so leave it.
        guard let solved = CardioFormat.distanceMiles(speedMph: value, durationSeconds: set.durationSeconds)
        else { return }
        set.distanceMiles = solved
    }

    /// Typing a count makes the pace the readout again.
    private func applyFlights(_ value: Double) {
        set.flights = value > 0 ? value : nil
        flightDerived = .pace
    }

    /// Setting a pace computes the count it reaches in the logged time — the
    /// planned case, "twenty minutes at eight floors a minute".
    private func applyFlightPace(_ value: Double) {
        // With no time logged there is nothing to solve against. Assigning the
        // nil would delete a count the lifter already has, so leave it — and
        // leave the derived side alone too, because a footer claiming the count
        // is calculated from a pace nothing stored would simply be untrue.
        guard let solved = CardioFormat.flights(pacePerMinute: value, durationSeconds: set.durationSeconds)
        else { return }
        set.flights = solved
        flightDerived = .flights
    }

    /// Changing the time holds whichever side the lifter last set. If they
    /// entered a pace, a longer walk means more distance at that same pace;
    /// if they entered a distance, it means a slower one. Flights follow the
    /// same rule against their own pace.
    private func applyDuration(_ value: Int) {
        let keptSpeed = CardioFormat.speedMph(distanceMiles: set.distanceMiles, durationSeconds: set.durationSeconds)
        let keptPace = CardioFormat.flightPace(flights: set.flights, durationSeconds: set.durationSeconds)
        set.durationSeconds = value > 0 ? value : nil
        if derived == .distance, let keptSpeed,
           let solved = CardioFormat.distanceMiles(speedMph: keptSpeed, durationSeconds: set.durationSeconds) {
            set.distanceMiles = solved
        }
        if flightDerived == .flights, let keptPace,
           let solved = CardioFormat.flights(pacePerMinute: keptPace, durationSeconds: set.durationSeconds) {
            set.flights = solved
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    flightCountRow
                    distanceRows
                    Stepper("Time: \(secs > 0 ? CardioFormat.durationLabel(seconds: secs) : "—")",
                            value: Binding(get: { secs }, set: { applyDuration($0) }),
                            in: 0...36000, step: 60)
                    speedRow
                    flightPaceRow
                    inclineRow
                    carryLoadRow
                } header: {
                    Text(sectionHeader)
                } footer: {
                    Text(sectionFooter)
                }
                Section {
                    Button("Delete set", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Log conditioning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if PersistenceErrorCenter.shared.save(context, operation: "Saving the conditioning set") { dismiss() }
                    }
                }
            }
        }
    }

    /// Names only the fields this sheet is actually showing — the same list the
    /// rows are built from, so the two cannot drift.
    private var sectionHeader: String { fields.headerLabel }

    /// Which value is the readout rather than the entry, so the lifter can see
    /// which number the other two are driving.
    private var sectionFooter: String {
        if showsFlights && !showsDistance {
            return flightDerived == .flights
                ? "Flights are calculated from pace and time."
                : "Pace is calculated from flights and time."
        }
        return derived == .distance
            ? "Distance is calculated from speed and time."
            : "Speed is calculated from distance and time."
    }

    /// [INV-STAIRS-COUNT-FLIGHTS] Whole steps: a console reports floors as a
    /// count, and nobody climbs a third of one on purpose. A count solved from
    /// a pace still keeps its decimal — the stepper is the entry, not the store.
    @ViewBuilder
    private var flightCountRow: some View {
        if showsFlights {
            Stepper("Flights: \(flights > 0 ? CardioFormat.flightsLabel(flights) : "—")",
                    value: Binding(get: { flights }, set: { applyFlights($0) }),
                    in: 0...2000, step: 1)
            flightsTypeRow
        }
    }

    /// Direct entry for the number on the console. A twenty-minute climb is a
    /// three-figure count, and reaching it one tap at a time is not a thing
    /// anyone does mid-workout — the stepper is for nudging, this is for
    /// logging. Mirrors `distanceTypeRow`, which exists for the same reason.
    private var flightsTypeRow: some View {
        HStack {
            Text("Type flights").foregroundStyle(.secondary)
            Spacer()
            TextField("flights", text: Binding(
                get: { flights == 0 ? "" : Weight.trim(flights, decimals: 1) },
                set: {
                    if let v = Double($0.replacingOccurrences(of: ",", with: ".")), v > 0 { applyFlights(v) }
                    else if $0.isEmpty { applyFlights(0) }
                }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var flightPaceRow: some View {
        if showsFlights {
            Stepper("Pace: \(flightPace > 0 ? "\(Weight.trim(flightPace)) fl/min" : "—")",
                    value: Binding(get: { flightPace }, set: { applyFlightPace($0) }),
                    in: 0...60, step: 0.5)
        }
    }

    @ViewBuilder
    private var distanceRows: some View {
        if showsDistance {
            Stepper("Distance: \(miles > 0 ? "\(Weight.trim(miles, decimals: 2)) mi" : "—")",
                    value: Binding(get: { miles }, set: { applyDistance($0) }),
                    in: 0...100, step: 0.25)
            distanceTypeRow
        }
    }

    @ViewBuilder
    private var speedRow: some View {
        if showsDistance {
            Stepper("Speed: \(mph > 0 ? "\(Weight.trim(mph)) mph" : "—")",
                    value: Binding(get: { mph }, set: { applySpeed($0) }),
                    in: 0...20, step: 0.1)
        }
    }

    /// A climber's grade is the machine, not a setting, so it gets no incline
    /// row unless a legacy set already carries one.
    @ViewBuilder
    private var inclineRow: some View {
        if showsIncline {
            Stepper("Incline: \(incline > 0 ? "\(Weight.trim(incline))%" : "—")",
                    value: Binding(get: { incline }, set: { set.inclinePercent = $0 > 0 ? $0 : nil }),
                    in: 0...30, step: 0.5)
        }
    }

    /// [INV-RUCK-CARRIES-ITS-LOAD] A ruck is a walk with a pack on. Unloaded
    /// cardio gets no load row at all. Hoisted out of the Form body to keep the
    /// section inside the type-checker's budget (see CompileRegressionTests).
    @ViewBuilder
    private var carryLoadRow: some View {
        if carriesLoad {
            Stepper("Load: \(carryLb > 0 ? "\(Weight.trim(carryLb)) lb" : "—")",
                    value: Binding(get: { carryLb }, set: { set.weightLb = max(0, $0) }),
                    in: 0...200, step: CardioFormat.loadIncrementLb)
        }
    }

    /// Exact distance entry for values the 0.25 steps don't land.
    private var distanceTypeRow: some View {
        HStack {
            Text("Type distance").foregroundStyle(.secondary)
            Spacer()
            TextField("miles", text: Binding(
                get: { miles == 0 ? "" : Weight.trim(miles, decimals: 2) },
                set: {
                    if let v = Double($0.replacingOccurrences(of: ",", with: ".")), v > 0 { applyDistance(v) }
                    else if $0.isEmpty { applyDistance(0) }
                }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
        }
        .font(.callout)
    }
}

/// Timed holds (planks, hollow holds) have a first-class duration instead of
/// masquerading as one repetition. The program pre-fills the target, so the
/// normal path remains a single completion tap.
private struct TimedSetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: SetEntry
    let onDelete: () -> Void

    private var seconds: Int { self.set.durationSeconds ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hold time") {
                    Stepper(
                        CardioFormat.durationLabel(seconds: seconds),
                        value: Binding(get: { seconds }, set: { set.durationSeconds = max($0, 5) }),
                        in: 5...1800,
                        step: 5
                    )
                }
                Section {
                    Button("Delete set", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Log timed set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if PersistenceErrorCenter.shared.save(context, operation: "Saving the timed set") { dismiss() }
                    }
                }
            }
        }
    }
}

/// Normal logging is one tap: planned → completed (and a second tap undoes).
/// Long-press exposes the exceptional states and quality flags, keeping the
/// powerful record model without making every ordinary set an interrogation.
private struct SetVerdictControl: View {
    @Environment(\.modelContext) private var context
    @Bindable var set: SetEntry
    let allowsQuality: Bool
    var onCompleted: () -> Void

    var body: some View {
        Menu {
            Section("Status") {
            ForEach(SetStatus.allCases, id: \.self) { status in
                Button {
                    apply(status)
                } label: {
                    Label(statusLabel(status), systemImage: statusIcon(status))
                }
            }
            }
            if allowsQuality {
                Section("Quality — only when notable") {
                    Button("Not graded") { set.quality = nil; save() }
                    Button("Clean") { set.quality = .clean; save() }
                    Button("Grindy") { set.quality = .grindy; save() }
                    Button("Wobble") { set.quality = .wobble; save() }
                }
                // Separate section, deliberately: a set can be clean at 3+ reps
                // in reserve or clean at 1, and those say different things.
                Section("Reps in reserve") {
                    Button("Not graded") { set.rir = nil; save() }
                    ForEach(SetFlag.allCases.filter(\.isRIR), id: \.self) { value in
                        Button(value.name) { set.rir = value; save() }
                    }
                }
            }
        } label: {
            // One labelling pattern with the web logger (issue #61): the
            // glyph, with the graded verdicts spelled out in WORDS underneath
            // — never a bare G/W badge, and reps-in-reserve is visible too,
            // not menu-only. The caption is part of the control, so it
            // survives any compact row treatment.
            VStack(spacing: 1) {
                Image(systemName: statusIcon(set.status))
                    .font(.title3)
                if let caption = verdictCaption {
                    Text(caption)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
                .frame(width: 48, height: 48)
                .background(statusColor(set.status).opacity(set.status == .planned ? 0.12 : 0.30),
                            in: RoundedRectangle(cornerRadius: 8))
        } primaryAction: {
            apply(set.status == .completed ? .planned : .completed)
        }
        .accessibilityLabel("Set status")
        .accessibilityValue(accessibilityVerdict)
        .accessibilityHint("Tap to complete or undo. Touch and hold for skipped, quality, and reps-in-reserve options.")
    }

    /// The graded verdicts in words — "grindy", "2 left", or both. Nil when
    /// nothing notable is graded, so the ordinary tap-to-complete flow stays
    /// visually quiet.
    private var verdictCaption: String? {
        var parts: [String] = []
        if let quality = set.quality, quality != .clean { parts.append(quality == .grindy ? "grindy" : "wobble") }
        if let rir = set.rir { parts.append(rir.name.lowercased()) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityVerdict: String {
        var parts = [statusLabel(set.status)]
        if let quality = set.quality { parts.append("quality \(quality.name.lowercased())") }
        if let rir = set.rir { parts.append("reps in reserve \(rir.name.lowercased())") }
        return parts.joined(separator: ", ")
    }

    private func apply(_ status: SetStatus) {
        let wasCompleted = set.status == .completed
        set.status = status
        if status == .completed && !wasCompleted { onCompleted() }
        save()
    }

    private func save() { PersistenceErrorCenter.shared.save(context, operation: "Changing the set verdict") }

    private func statusLabel(_ status: SetStatus) -> String {
        switch status { case .planned: return "Planned"; case .completed: return "Completed"; case .skipped: return "Skipped" }
    }
    private func statusIcon(_ status: SetStatus) -> String {
        switch status { case .planned: return "circle"; case .completed: return "checkmark.circle.fill"; case .skipped: return "minus.circle.fill" }
    }
    private func statusColor(_ status: SetStatus) -> Color {
        switch status { case .planned: return .secondary; case .completed: return Theme.good; case .skipped: return .secondary }
    }
}

// MARK: - Set detail (weight/reps/unit/body flag)

private struct SetDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: SetEntry
    let entry: SessionExercise
    let exercise: Exercise?
    let gym: Gym?
    let bar: Bar
    let targetLb: Double?
    let onDelete: () -> Void

    // Edited live (canonical pounds) so the plate graphic tracks every tap;
    // committed on Done. Starts at the set's weight, which the program/track
    // pre-fills to this session's recommendation.
    @State private var lb: Double = 0
    @State private var unit: WeightUnit = .lb
    @State private var reps: Int = 0
    @State private var isWarmup = false
    @State private var isPerSide = false
    @State private var stoppedEarly = false
    @State private var bodySite: BodySite?
    @State private var bodyNote = ""
    @State private var applyWeightToRemaining = false
    @State private var applyRepsToRemaining = true
    @State private var confirmMisload = false

    private var isBarbell: Bool { exercise?.type == .barbell }

    /// One tap = one plate change per side: 2× the smallest plate available at
    /// the gym in the current unit (barbell); a sensible fixed step otherwise.
    private var stepLb: Double {
        if isBarbell, let gym {
            let plates = gym.availablePlates.filter { $0.unit == unit }.map(\.value)
            if let smallest = plates.min() { return Weight.toLb(smallest * 2, from: unit) }
        }
        return unit == .kg ? Weight.toLb(2.5, from: .kg) : 5
    }

    private var displayValue: Double { unit == .lb ? lb : Weight.kg(fromLb: lb) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Big readout with plate ± on either side.
                    HStack {
                        Button { adjust(-1) } label: { Image(systemName: "minus").font(.title2) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Decrease weight")
                        Spacer()
                        VStack(spacing: 0) {
                            Text(lb == 0 ? "BW" : Weight.trim(displayValue))
                                .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                            Text(lb == 0 ? "bodyweight" : unit.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { adjust(1) } label: { Image(systemName: "plus").font(.title2) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Increase weight")
                    }

                    if isBarbell && lb > 0 {
                        BarbellView(weightLb: lb, unit: unit, bar: bar, gym: gym,
                                    stationDenomination: exercise?.stationDenomination,
                                    plateStyle: exercise?.movementGroup == "olympic" ? .bumper : .steel)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if exercise?.type == .dumbbell && lb > 0 {
                        DumbbellView(weightLb: lb, unit: unit)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Picker("", selection: Binding(get: { unit }, set: { setUnit($0) })) {
                        Text("lb").tag(WeightUnit.lb)
                        Text("kg").tag(WeightUnit.kg)
                    }
                    .pickerStyle(.segmented)

                    if let targetLb, targetLb > 0, abs(targetLb - lb) > 0.01 {
                        Button {
                            lb = targetLb
                        } label: {
                            Label("Session target: \(Weight.trim(unit == .lb ? targetLb : Weight.kg(fromLb: targetLb))) \(unit.rawValue)",
                                  systemImage: "scope")
                                .font(.callout)
                        }
                    }

                    // Type an exact value if the steps don't land it.
                    HStack {
                        Text("Type").foregroundStyle(.secondary)
                        Spacer()
                        TextField("weight", text: Binding(
                            get: { lb == 0 ? "" : Weight.trim(displayValue, decimals: 2) },
                            set: { if let v = Double($0.replacingOccurrences(of: ",", with: ".")) { lb = Weight.toLb(v, from: unit) } else if $0.isEmpty { lb = 0 } }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    }
                    .font(.callout)
                } header: {
                    Text("Weight — 0 = bodyweight")
                }

                Section {
                    Stepper("Reps: \(reps)", value: $reps, in: 0...100)
                    Toggle("Warmup", isOn: $isWarmup)
                    Toggle("Per side", isOn: $isPerSide)
                    Toggle("Stopped early", isOn: $stoppedEarly)
                    if canApplyToRemaining {
                        Toggle("Apply reps to remaining planned sets", isOn: $applyRepsToRemaining)
                        Toggle("Apply weight to remaining planned sets", isOn: $applyWeightToRemaining)
                    }
                }

                Section("Body flag") {
                    Picker("Site", selection: $bodySite) {
                        Text("None").tag(BodySite?.none)
                        ForEach(BodySite.allCases) { site in
                            Text(site.rawValue).tag(BodySite?.some(site))
                        }
                    }
                    if bodySite != nil {
                        TextField("What did it feel like?", text: $bodyNote)
                    }
                }

                Section {
                    Button("Delete set", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .navigationTitle("Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if isLargePlanDifference { confirmMisload = true }
                        else { saveAndDismiss() }
                    }
                }
            }
            .onAppear {
                unit = set.enteredUnit
                lb = set.weightLb
                reps = set.reps
                isWarmup = set.isWarmup
                isPerSide = set.isPerSide
                stoppedEarly = set.flags.contains(.stoppedEarly)
                bodySite = set.bodyFlagSite
                bodyNote = set.bodyFlagNote ?? ""
                // Both propagations start OFF. Opening a set to add a body
                // flag or fix a typo must not silently rewrite every later
                // set — per-set rep targets are deliberate work, and there is
                // no undo once they are gone.
                applyRepsToRemaining = false
                applyWeightToRemaining = false
            }
            .alert("Confirm the loaded weight", isPresented: $confirmMisload) {
                Button("Use \(Weight.trim(displayValue)) \(unit.rawValue)") { saveAndDismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                if let targetLb {
                    Text("This differs from the planned load by \(Weight.trim(abs(lb - targetLb))) lb. Confirm the plates before logging it.")
                }
            }
        }
    }

    private func adjust(_ dir: Double) {
        lb = max(0, lb + dir * stepLb)
    }

    private func setUnit(_ newUnit: WeightUnit) {
        unit = newUnit // lb is canonical, so the readout just re-renders in the new unit
    }

    private var canApplyToRemaining: Bool {
        !isWarmup && entry.plannedWorkingSets.contains {
            $0 !== set && $0.status == .planned
        }
    }

    private var isLargePlanDifference: Bool {
        guard let targetLb, targetLb > 0, lb > 0 else { return false }
        return abs(lb - targetLb) > 6
    }

    private func saveAndDismiss() {
        commitDraft()
        if PersistenceErrorCenter.shared.save(context, operation: "Saving the set") { dismiss() }
    }

    /// Commit actual values without rewriting the immutable per-set plan
    /// snapshot. Reps and load propagate independently, so changing a rep
    /// target cannot reset a deliberate weight adjustment (or vice versa).
    /// Completed/skipped rows are never rewritten.
    private func commitDraft() {
        set.weightLb = lb
        set.enteredUnit = unit
        set.reps = reps
        if !isWarmup {
            let remaining = entry.plannedWorkingSets.filter { $0 !== set && $0.status == .planned }
            if applyWeightToRemaining {
                for target in remaining { target.weightLb = lb; target.enteredUnit = unit }
            }
            if applyRepsToRemaining {
                for target in remaining { target.reps = reps }
            }
        }
        set.isWarmup = isWarmup
        set.isPerSide = isPerSide
        var flags = set.flags.filter { $0 != .stoppedEarly }
        if stoppedEarly { flags.append(.stoppedEarly) }
        set.flags = flags
        set.bodyFlagSite = bodySite
        set.bodyFlagNote = bodySite == nil || bodyNote.isEmpty ? nil : bodyNote

        if applyWeightToRemaining && !isWarmup {
            // Keep generated targets intact, but warm up for the load that will
            // actually be used across the remaining work sets.
            synchronizeWarmups(entry, workingLb: lb, bar: bar, gym: gym,
                               enteredUnit: unit, context: context)
        }
    }
}

// MARK: - Sticky bottom bar (session clock + rest)

/// Mirrors the web logger's #session-bar: session stopwatch on the left; while
/// resting, the countdown with +1:00 / Skip and a progress fill; when idle, a
/// Rest button for the lift you're working.
private struct SessionBottomBar: View {
    @Environment(RestTimer.self) private var restTimer
    /// nil until the workout is explicitly started — opening the logger to
    /// read the plan must not display a running clock.
    let sessionStart: Date?
    let pausedAt: Date?
    let restLabel: String
    let restSeconds: Int
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            // A tall progress bar during rest so the countdown reads at a glance.
            ProgressView(value: restTimer.isRunning ? min(1, 1 - restTimer.progress) : 0)
                .tint(Theme.accent)
                .scaleEffect(x: 1, y: restTimer.isRunning ? 2 : 1, anchor: .top)
                .animation(.default, value: restTimer.isRunning)

            // While resting the bar carries the countdown + FOUR controls —
            // text everywhere here must be single-line (scaling down before
            // truncating) or narrow phones wrap the digits mid-string.
            HStack(spacing: 10) {
                // Session stopwatch — always visible, with an icon so it reads
                // as a running clock.
                if let sessionStart {
                    TimelineView(.periodic(from: sessionStart, by: 1)) { timeline in
                        Label(elapsedLabel(at: pausedAt ?? timeline.date),
                              systemImage: pausedAt == nil ? "stopwatch" : "pause.fill")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    Button(action: onStart) {
                        Label("Start workout", systemImage: "play.fill")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Begins the workout clock for this session")
                }

                Spacer(minLength: 4)

                if restTimer.isRunning {
                    VStack(alignment: .trailing, spacing: 0) {
                        if !restTimer.exerciseName.isEmpty {
                            Text("resting · \(restTimer.exerciseName)")
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Text(restTimer.display)
                            .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .layoutPriority(1) // the countdown is the point — buttons shrink first
                    }
                    Group {
                        Button {
                            restTimer.isPaused ? restTimer.resume() : restTimer.pause()
                        } label: { Image(systemName: restTimer.isPaused ? "play.fill" : "pause.fill") }
                            .accessibilityLabel(restTimer.isPaused ? "Resume rest" : "Pause rest")
                        Button { restTimer.add(seconds: -60) } label: { Image(systemName: "gobackward.60") }
                            .accessibilityLabel("Subtract one minute")
                        Button { restTimer.add(seconds: 60) } label: { Image(systemName: "goforward.60") }
                            .accessibilityLabel("Add one minute")
                        Button {
                            restTimer.stop()
                        } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Skip rest")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        restTimer.start(seconds: restSeconds, exerciseName: restLabel)
                    } label: {
                        Label("Rest \(mmss(restSeconds))", systemImage: "timer")
                            .font(.body.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func elapsedLabel(at date: Date) -> String {
        mmss(max(0, Int(date.timeIntervalSince(sessionStart ?? date))))
    }
}

// MARK: - Exercise picker

private struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var typeFilter: ExerciseType?
    @State private var detailExercise: Exercise?
    let onPick: (Exercise) -> Void

    private var visible: [Exercise] {
        let pool = typeFilter.map { filter in exercises.filter { $0.type == filter } } ?? exercises
        guard !search.isEmpty else { return pool }
        let term = ExerciseSearch.preparedTerm(search)
        return pool.filter { $0.matchesSearch(preparedTerm: term) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Equipment filter (issue #63): the catalog is too long for
                // one flat list; search stays available above at all times.
                Section {
                    ExerciseTypeFilterRow(typeFilter: $typeFilter)
                }
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    let inCategory = visible.filter { $0.category == category }
                    if !inCategory.isEmpty {
                    Section(category.rawValue) {
                        ForEach(inCategory) { exercise in
                            HStack {
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(exercise.name).foregroundStyle(.primary)
                                    if exercise.isShelved {
                                        Text(Copy.shelved)
                                            .font(.caption)
                                            .foregroundStyle(Theme.hardStop)
                                    }
                                    Spacer()
                                }
                            }
                            // Detail preview OVER the picker (issue #66): the
                            // sheet keeps the search text and active filter, so
                            // inspecting never restarts the hunt.
                            Button {
                                detailExercise = exercise
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Theme.accent)
                            }
                            .accessibilityLabel("\(exercise.name) — muscles, history, and settings")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    }
                }
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Exercise, movement, or equipment")
            .sheet(item: $detailExercise) { exercise in
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                }
            }
        }
    }
}

/// Horizontal equipment-filter chips shared by the pickers. A second tap on
/// the active chip clears the filter, mirroring the web picker.
struct ExerciseTypeFilterRow: View {
    @Binding var typeFilter: ExerciseType?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(nil, label: "All")
                ForEach(ExerciseType.allCases, id: \.self) { type in
                    chip(type, label: type.rawValue)
                }
            }
        }
    }

    private func chip(_ type: ExerciseType?, label: String) -> some View {
        let active = typeFilter == type
        return Button(label) {
            typeFilter = (type != nil && active) ? nil : type
        }
        .font(.caption.bold())
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? Theme.accent.opacity(0.25) : Color(.tertiarySystemFill),
                    in: Capsule())
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Summary

private struct SessionSummarySheet: View {
    @Query private var settingsList: [AppSettings]
    let summary: SessionSummary
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    ForEach(summary.lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.exerciseName).font(.headline)
                            Text(line.volumeLb > 0
                                 ? "Top: \(line.topSetLabel) · Volume: \(settingsList.unitDisplay.format(lb: line.volumeLb))"
                                 : line.topSetLabel)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !summary.coachingNotes.isEmpty {
                    Section("Coach") {
                        ForEach(summary.coachingNotes, id: \.self) { note in
                            Text(note)
                        }
                    }
                }
                if !summary.milestones.isEmpty {
                    Section("Milestones") {
                        ForEach(summary.milestones, id: \.label) { event in
                            Label(event.label, systemImage: "flag.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .navigationTitle(Copy.sessionDone)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}
