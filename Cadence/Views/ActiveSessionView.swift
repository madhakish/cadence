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

    @Environment(\.scenePhase) private var scenePhase
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
    @State private var showEarlierExercises = false
    /// The brief "logged" receipt that takes the Done slot after a completion.
    /// Presentation only: the verdict is already saved when it appears.
    @State private var stamp: LoggedStamp?
    /// The hold whose timer is open from the bottom bar's Start hold.
    @State private var holdSet: SetEntry?

    private var currentOrFirst: SessionExercise? {
        currentEntry
            ?? session.orderedExercises.first { $0.orderedSets.contains { $0.status == .planned } }
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
    /// Whether the root stopwatch is timing THIS session. Another workout's
    /// clock must never be reported — or stopped — from here.
    private var isTimingThisSession: Bool { workoutClock.isTracking(sessionID: session.id) }

    /// Begin timing. The one place a workout starts, so opening the logger to
    /// read the plan never logs elapsed time nobody trained.
    private func startWorkout() {
        workoutClock.begin(for: session,
                           currentLift: currentOrFirst?.exercise?.name ?? "",
                           defaultRestSeconds: currentRestSeconds,
                           currentSet: currentProjection)
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
    /// What the Lock Screen shows as the set you're on — the same focus rule
    /// this screen draws, published whenever it changes.
    private var currentProjection: CurrentSetProjection? {
        WorkoutCommandService.projection(for: session, focus: currentOrFirst)
    }

    /// The set the bottom bar's Done logs: the focused lift's current set, by
    /// the same first-unresolved rule the hero and the Lock Screen draw. Holds
    /// and conditioning keep their own start/log flow in the row, so a big
    /// button never logs a plank nobody timed or a ruck with no distance.
    private var doneTarget: (set: SetEntry, entry: SessionExercise)? {
        guard let entry = currentOrFirst, let type = entry.exercise?.type,
              type != .timed, type != .conditioning else { return nil }
        let sets = entry.orderedSets
        let states = sets.map { SetLifecycle.PresentationState(isWarmup: $0.isWarmup, status: $0.status) }
        return SetLifecycle.currentPresentationIndex(states).map { (sets[$0], entry) }
    }

    private var doneAction: SessionDoneAction? {
        guard let target = doneTarget else { return nil }
        let (set, entry) = target
        let words = SetWords(set: set, in: entry)
        return SessionDoneAction(
            position: words.position,
            spoken: words.spoken,
            perform: { resolve(set, in: entry, as: .completed) },
            skip: { resolve(set, in: entry, as: .skipped) }
        )
    }

    /// A timed set's thumb-zone action is starting its hold timer; the timer
    /// logs the attempt through the same writer when it ends.
    private var holdAction: SessionHoldAction? {
        guard let entry = currentOrFirst, entry.exercise?.type == .timed else { return nil }
        let sets = entry.orderedSets
        let states = sets.map { SetLifecycle.PresentationState(isWarmup: $0.isWarmup, status: $0.status) }
        guard let index = SetLifecycle.currentPresentationIndex(states) else { return nil }
        let set = sets[index]
        return SessionHoldAction(name: entry.exercise?.name ?? "hold", perform: { holdSet = set })
    }

    /// Done and Skip go through the one status writer, exactly like a
    /// marker's menu and the Lock Screen; only what follows is decided here.
    private func resolve(_ set: SetEntry, in entry: SessionExercise, as status: SetStatus) {
        let previous = set.status
        guard previous == .planned else { return }
        do {
            try WorkoutCommandService.setStatus(status, of: set, context: context)
        } catch {
            PersistenceErrorCenter.shared.report(error, operation: status == .completed ? "Completing the set" : "Skipping the set", context: context)
            return
        }
        followVerdict(on: set, in: entry, previous: previous, status: status)
    }

    /// What follows any verdict on this screen — Done, the row's status
    /// control, or the hold timer: move focus, arm rest by the shared rule,
    /// and say "logged" once.
    private func followVerdict(on set: SetEntry, in entry: SessionExercise, previous: SetStatus, status: SetStatus) {
        if status == .planned { currentEntry = entry } else { focusAfterResolving(entry) }
        // A verdict changes the current set even when focus stays on the
        // same lift; the Lock Screen face must follow every time (#200).
        pushActivityContext()
        // The same decision the Lock Screen's commands make: a new completion
        // with auto-start on and no rest running arms the rest.
        let decision = WorkoutCommandService.decision(
            after: previous, status: status, set: set, entry: entry, session: session,
            settings: settingsList.first, restRunning: restTimer.isRunning
        )
        if let seconds = decision.restSeconds {
            restTimer.start(seconds: seconds, exerciseName: nextRestExerciseName(after: entry))
        }
        if status == .completed, previous != .completed {
            let words = SetWords(set: set, in: entry)
            // An instant swap, not a crossfade: the receipt is the stamp, and
            // a fade let the outgoing Done ghost through it.
            stamp = LoggedStamp(text: "\(words.title) logged · \(words.work)")
            UIAccessibility.post(notification: .announcement, argument: "\(words.title) logged, \(words.spoken)")
        } else if stamp != nil {
            stamp = nil
        }
    }

    var body: some View {
        List {
            if session.tfhPolicyID != nil { TFHEvidenceView(session: session) }
            // Preserve the authored exercise order. Work already passed stays
            // represented above the current lift as one compact disclosure,
            // rather than moving the current lift ahead of exercises 1...N.
            earlierExerciseSections
            focusedExerciseSection
            remainingExerciseSections

            // One supporting section for the session itself: where it is
            // happening, adding a lift, and notes. Progress rides as the
            // focused lift's footer, so nothing competes with the dominant
            // block above it (#185).
            Section("Session") {
                // With no lift to carry it as a footer, progress and the date
                // still have a home (mirrors the web session card).
                if currentOrFirst == nil {
                    Text(sessionProgressLine)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("session-progress")
                }
                gymPicker
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                TextField("Session notes", text: Bindable(session).notes, axis: .vertical)
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
                .primaryActionStyle()
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .themeListBackground()
        .accessibilityIdentifier("active-session-screen")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SessionBottomBar(
                sessionStart: isTimingThisSession ? workoutClock.startDate : nil,
                pausedAt: workoutClock.pausedAt,
                restLabel: nextRestExerciseName(after: currentOrFirst),
                restSeconds: currentRestSeconds,
                done: doneAction,
                hold: holdAction,
                stamp: stamp?.text,
                onStart: startWorkout
            )
        }
        .sheet(item: $holdSet) { set in
            HoldTimerSheet(set: set, exerciseName: set.sessionExercise?.exercise?.name ?? "Hold") { previous, status in
                if let entry = set.sessionExercise {
                    followVerdict(on: set, in: entry, previous: previous, status: status)
                }
            }
        }
        // The receipt is short and owns nothing: it lapses on its own, and a
        // newer verdict replaces it (cancelling this wait).
        .task(id: stamp?.id) {
            guard stamp != nil, (try? await Task.sleep(for: .seconds(2.4))) != nil else { return }
            stamp = nil
        }
        .sensoryFeedback(.success, trigger: stamp?.id) { _, new in
            new != nil && (settingsList.first?.haptics ?? true)
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
                                          defaultRestSeconds: currentRestSeconds,
                                          currentSet: currentProjection)
        }
        // Keep the activity's elapsed face and its quick-rest default honest.
        // Watch the derived VALUES, not the entry's identity: swapping the
        // exercise in place or editing its rest stepper changes the lift
        // name / default rest without changing which SessionExercise is current.
        .onChange(of: currentOrFirst?.exercise?.name) { pushActivityContext() }
        .onChange(of: currentRestSeconds) { pushActivityContext() }
        // A set may have been completed from the Lock Screen while this screen
        // was in the background: the record is already saved, so only the
        // remembered focus can be stale. Drop it when its exercise has no
        // planned work left (the derived fallback then picks the right one)
        // and republish the face.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            workoutClock.synchronize()
            if let entry = currentEntry, !entry.orderedSets.contains(where: { $0.status == .planned }) {
                // The same rule the logger and the Lock Screen commands use:
                // advance through authored order from the finished lift.
                focusAfterResolving(entry)
            }
            pushActivityContext()
        }
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
            ExercisePickerSheet(equipmentPolicy: sessionProgram?.equipmentPolicy ?? .any) { exercise in
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
    private var gymPicker: some View {
        if !gyms.isEmpty {
                Picker("Training at", selection: Binding(
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

    /// Supporting fact for the focused lift's footer: where the session is
    /// and how much work is left. Web twin: `.session-progress`.
    private var sessionProgressLine: String {
        "Exercise \(currentExerciseNumber) of \(session.orderedExercises.count) · \(totalWorkSetCount == 0 ? 0 : min(resolvedWorkSetCount + 1, totalWorkSetCount)) of \(totalWorkSetCount) work sets · \(session.date.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Extracted from `body` — the multi-argument section call plus the recall
    /// lookup pushed the List builder past the type-checker's budget.
    @ViewBuilder
    private var earlierExerciseSections: some View {
        let recall = recallLines()
        let focusedID = currentOrFirst?.persistentModelID
        let earlier = exercises(before: focusedID)

        if !earlier.isEmpty {
            if showEarlierExercises {
                ForEach(earlier) { entry in
                    exerciseSection(for: entry, emphasized: false, recall: recall)
                }
                Section {
                    Button("Collapse earlier exercises") {
                        showEarlierExercises = false
                    }
                    .accessibilityIdentifier("collapse-earlier-exercises")
                }
            } else {
                Section {
                    Button {
                        showEarlierExercises = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.good)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Earlier in session")
                                    .font(.subheadline.weight(.semibold))
                                Text(earlierExerciseSummary(earlier))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: Theme.bigTap - 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("expand-earlier-exercises")
                    .accessibilityHint("Shows exercises that remain in their authored positions before the current exercise")
                }
            }
        }
    }

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
        return ForEach(exercises(after: focusedID)) { entry in
            exerciseSection(for: entry, emphasized: false, recall: recall)
        }
    }

    private func exercises(before focusedID: PersistentIdentifier?) -> [SessionExercise] {
        guard let focusedID,
              let index = session.orderedExercises.firstIndex(where: { $0.persistentModelID == focusedID })
        else { return [] }
        return Array(session.orderedExercises.prefix(index))
    }

    private func exercises(after focusedID: PersistentIdentifier?) -> [SessionExercise] {
        guard let focusedID,
              let index = session.orderedExercises.firstIndex(where: { $0.persistentModelID == focusedID })
        else { return session.orderedExercises }
        return Array(session.orderedExercises.dropFirst(index + 1))
    }

    private func earlierExerciseSummary(_ entries: [SessionExercise]) -> String {
        entries.map { entry in
            let resolved = entry.plannedWorkingSets.filter { $0.status != .planned }.count
            let total = entry.plannedWorkingSets.count
            return "\(entry.exercise?.name ?? "Exercise") \(resolved)/\(total)"
        }
        .joined(separator: " · ")
    }

    private func exerciseSection(
        for entry: SessionExercise,
        emphasized: Bool,
        recall: [PersistentIdentifier: String]
    ) -> some View {
        ExerciseSection(
            entry: entry,
            emphasized: emphasized,
            sessionProgress: emphasized ? sessionProgressLine : nil,
            settings: settingsList.first,
            gym: gym,
            programFocus: sessionProgram?.focus,
            allExercises: allExercises.filter { sessionProgram?.equipmentPolicy.allows(exerciseType: $0.typeRaw) ?? true },
            lastTime: recallLine(for: entry, in: recall),
            adHocExposure: mostRecentTopExposure(for: entry),
            onDropLoad: { autoregEntry = entry },
            onWork: { currentEntry = $0; pushActivityContext() },
            onResolve: { focusAfterResolving($0); pushActivityContext() },
            onVerdict: { set, previous, status in
                followVerdict(on: set, in: entry, previous: previous, status: status)
            },
            restTargetName: { nextRestExerciseName(after: entry) },
            onRemove: { removeExercise(entry) },
            onMove: { moveExercise(entry, direction: $0) }
        )
    }

    /// A verdict resolves the current position, not merely the tapped row.
    /// Stay on this exercise while it still has planned work; after its final
    /// set, advance through authored order to the next exercise that can be
    /// performed. Undoing a verdict deliberately returns focus to that entry.
    private func focusAfterResolving(_ entry: SessionExercise) {
        let ordered = session.orderedExercises
        let resolvedIndex = ordered.firstIndex { $0.persistentModelID == entry.persistentModelID } ?? -1
        guard let next = SetLifecycle.focusAfterResolving(
            ordered.map { $0.orderedSets.map(\.status) }, resolvedIndex: resolvedIndex
        ) else { currentEntry = entry; return }
        currentEntry = ordered[next]
        restTimer.updateExerciseName(nextRestExerciseName(after: currentEntry))
        if next != resolvedIndex { showEarlierExercises = false }
    }

    private func nextRestExerciseName(after entry: SessionExercise?) -> String {
        let ordered = session.orderedExercises
        let index = ordered.firstIndex { $0.persistentModelID == entry?.persistentModelID } ?? -1
        guard let next = SetLifecycle.nextPendingExerciseIndex(
            ordered.map { $0.orderedSets.map(\.status) }, after: index
        ) else { return "" }
        return ordered[next].exercise?.name ?? ""
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
        let nextName = nextRestExerciseName(after: currentOrFirst)
        restTimer.updateExerciseName(nextName)
        workoutClock.updateContext(currentLift: nextName,
                                   defaultRestSeconds: currentRestSeconds,
                                   currentSet: currentProjection)
    }

    private func bankSession() {
        guard !banking else { return }
        banking = true
        do {
            summary = try SessionCompletion.finish(session, context: context,
                                                   healthTiming: workoutClock.healthTiming(for: session.id))
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

/// Compact "how long ago" for the last-session recall line.
private func agoLabel(_ date: Date) -> String {
    ProgramProgression.historyAgeLabel(exposureDate: date, asOf: .now, calendar: .current)
}

/// What the bottom bar's Done needs: the words for the set and the act.
private struct SessionDoneAction {
    let position: String    // "working set 2 of 3"
    let spoken: String      // "6 reps at 138.7 lb"
    let perform: () -> Void
    let skip: () -> Void
}

private struct SessionHoldAction {
    let name: String
    let perform: () -> Void
}

private struct LoggedStamp: Equatable {
    let id = UUID()
    let text: String
}

/// One set in words, from its own performed values — the same unit it was
/// entered in, the same basis suffix the row shows. Display only.
private struct SetWords {
    let title: String       // "Set 2" / "Warmup 1"
    let position: String
    let work: String
    let spoken: String

    init(set: SetEntry, in entry: SessionExercise) {
        let phase = entry.orderedSets.filter { $0.isWarmup == set.isWarmup }
        let ordinal = (phase.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
        title = set.isWarmup ? "Warmup \(ordinal)" : "Set \(ordinal)"
        position = "\(set.isWarmup ? "warmup" : "working set") \(ordinal) of \(phase.count)"
        let load: String
        if set.weightLb == 0 {
            load = "BW"
        } else {
            let value = set.enteredUnit == .kg ? Weight.kg(fromLb: set.weightLb) : set.weightLb
            load = "\(Weight.trim(value)) \(set.enteredUnit == .kg ? "kg" : "lb")\(set.loadBasis.shortSuffix)"
        }
        let side = set.isPerSide ? "/side" : ""
        // [INV-CARRY-LOGS-DISTANCE] A carry is yards under a load, not reps.
        if let yards = set.carryYards {
            work = "\(Weight.trim(yards)) yd\(side) × \(load)"
            spoken = "\(Weight.trim(yards)) yards\(set.isPerSide ? " per side" : "") at \(set.weightLb == 0 ? "bodyweight" : load)"
        } else {
            work = "\(set.reps)\(side) × \(load)"
            spoken = "\(set.reps) reps\(set.isPerSide ? " per side" : "") at \(set.weightLb == 0 ? "bodyweight" : load)"
        }
    }
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
    let solution: PlateSolution
    let requestedLb: Double?
    let style: PlateVisualStyle
    var theme: PlateThemeID = .custom
}

// MARK: - Exercise section

private struct ExerciseSection: View {
    @Environment(\.modelContext) private var context
    @Environment(RestTimer.self) private var restTimer

    @Bindable var entry: SessionExercise
    @State private var expandedLoadout: ExpandedLoadout?
    /// Only the actively worked exercise gets the full between-sets cockpit.
    /// Remaining exercises stay in authored order underneath it.
    let emphasized: Bool
    /// Session progress, shown as this section's footer for the focused lift
    /// only. Supporting information never gets its own card (#185).
    let sessionProgress: String?
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
    /// `recallEntry` exactly like `lastTime`. Precomputed by
    /// `ActiveSessionView` (which owns `completedSessions`/`recallEntry`); nil
    /// with no prior history. It may drive a default and its disclosure only
    /// when `usesAdHocFirstSetFallback` confirms the entry is truly unplanned
    /// and off-program.
    let adHocExposure: RecentTopExposure?
    let onDropLoad: () -> Void
    /// Marks this exercise as the one being actively worked (drives the bottom bar).
    let onWork: (SessionExercise) -> Void
    /// Recomputes the active position after a completed or skipped verdict.
    let onResolve: (SessionExercise) -> Void
    /// A set's status changed (already saved). The screen decides what
    /// follows — focus, rest, the "logged" receipt — the same way it does
    /// for the bottom bar's Done.
    let onVerdict: (_ set: SetEntry, _ previous: SetStatus, _ status: SetStatus) -> Void
    let restTargetName: () -> String
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
    /// programming tier and exact load basis, excluding shelved (SwapRules in
    /// CadenceCore — no more Walking Lunges → Back Squat or DB Press → Dips).
    private var alternatives: [Exercise] {
        guard let cur = entry.exercise else { return [] }
        return allExercises.filter {
            SwapRules.compatible(
                currentName: cur.name, currentCategory: cur.categoryRaw,
                currentLoadBasis: cur.loadBasis, currentGroup: cur.movementGroup,
                candidateName: $0.name, candidateCategory: $0.categoryRaw,
                candidateLoadBasis: $0.loadBasis, candidateGroup: $0.movementGroup,
                candidateShelved: $0.gateStatus == .shelved
            )
        }
    }

    private func swap(to newExercise: Exercise, scope: SwapScope) {
        // Recheck at Apply time: a set can be logged while the dialog is open.
        // This precedes all program, entry, set, and warmup mutations.
        guard SwapRules.canReplaceEntry(setStatuses: entry.sets.map(\.status)),
              alternatives.contains(where: { $0.id == newExercise.id }) else {
            PersistenceErrorCenter.shared.report(
                NSError(domain: "Cadence", code: 1,
                        userInfo: [NSLocalizedDescriptionKey:
                            "This exercise can no longer be swapped. Keep its logged sets and add the replacement as a separate exercise with its own load."]),
                operation: "Swapping the exercise", context: context
            )
            return
        }
        let oldName = entry.exercise?.name
        let oldType = entry.exercise?.typeRaw
        // Session scope leaves the program slot alone. Cycle/program scope
        // repoint the slot at the lift you're actually doing (completion
        // matches the durable slot ID, with name+role only for legacy
        // sessions). The slot keeps its progression state, which is why
        // substitutions must preserve the load basis.
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

    private func solvedPlateSolution(for set: SetEntry) -> PlateSolution {
        authoritativePlateSolution(
            targetLb: set.weightLb,
            fallbackUnit: set.enteredUnit,
            bar: effectiveBar,
            gym: gym,
            stationDenomination: entry.exercise?.stationDenomination
        )
    }
    private var complementaryEffortCue: String? {
        if entry.tfhAnchorData != nil { return "TFH · complete clean work; leave capacity for the rest of your training." }
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

    /// The set you're on: the first unresolved authored set, warmups
    /// included — the rule the Lock Screen and the Done bar share.
    private var currentSet: SetEntry? {
        let ordered = entry.orderedSets
        let states = ordered.map { SetLifecycle.PresentationState(isWarmup: $0.isWarmup, status: $0.status) }
        return SetLifecycle.currentPresentationIndex(states).map { ordered[$0] }
    }

    private var groups: [SetGroup] {
        SetGroup.grouping(entry.orderedSets, separately: entry.exercise?.type == .conditioning)
    }

    /// The set a box's loadout draws: the current set when it's in the box,
    /// else the box's next planned set, else its first.
    private func representative(of group: SetGroup) -> SetEntry {
        group.sets.first { $0.persistentModelID == currentSet?.persistentModelID }
            ?? group.sets.first { $0.status == .planned }
            ?? group.sets[0]
    }

    /// Role and phase as the name's eyebrow: "MAIN LIFT · R2 LOAD". The
    /// movement group is dropped; "Back Squat" already says squat.
    private var slotLine: String? {
        let parts = [entry.programRole.map { "\($0) lift" }, entry.truthfulPhaseLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ").uppercased()
    }
    private var restBinding: Binding<Int> {
        Binding(get: { entry.exercise?.defaultRestSeconds ?? 0 },
                set: {
                    entry.exercise?.defaultRestSeconds = $0
                    PersistenceErrorCenter.shared.save(context, operation: "Changing the rest timer")
                })
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
                onResolve(entry)
                restTimer.start(seconds: restSeconds, exerciseName: restTargetName())
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
            // The cockpit for the set you're on: where you are in the sets,
            // the numbers to lift, and the loaded bar. The full plan, one box
            // per prescription, sits below it.
            if emphasized, let current = currentSet {
                SetCockpit(
                    entry: entry,
                    current: current,
                    gym: gym,
                    bar: effectiveBar,
                    onStatusChange: onVerdict,
                    onRemove: { removeSet($0) }
                )
                .accessibilityIdentifier("current-exercise-\(entry.exercise?.name ?? "Exercise")")
                // Loadout visualization — plates for barbell lifts, the rack
                // number for dumbbell lifts. The loadout is the set's own
                // value, never a re-solve. Mirrors web.
                if entry.exercise?.type == .barbell && current.weightLb > 0 {
                    let set = current
                    let exactSolution = solvedPlateSolution(for: set)
                    let style: PlateVisualStyle = entry.exercise?.movementGroup == "olympic" ? .bumper : .steel
                    let theme = gym?.plateTheme ?? .custom
                    BarbellStageView(
                        solution: exactSolution,
                        unit: set.enteredUnit,
                        plateStyle: style,
                        plateTheme: theme,
                        onExpand: {
                            expandedLoadout = ExpandedLoadout(
                                solution: exactSolution,
                                requestedLb: set.targetWeightLb ?? entry.targetWeightLb,
                                style: style,
                                theme: theme
                            )
                        }
                    )
                    LoadoutSummaryView(
                        requestedLb: set.targetWeightLb ?? entry.targetWeightLb,
                        loadout: exactSolution.loadout,
                        plateStyle: style,
                        plateTheme: theme
                    )
                } else if entry.exercise?.type == .dumbbell && current.weightLb > 0 {
                    DumbbellView(weightLb: current.weightLb, unit: current.enteredUnit)
                }
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
            // The plan, one box per prescription: a 3×5 is one box with
            // three markers; a ramp of different warmups stays a box each.
            ForEach(groups) { group in
                let isActive = group.sets.contains { $0.persistentModelID == currentSet?.persistentModelID }
                let set = representative(of: group)
                let showLoadout = !(emphasized && isActive) && loadChanges(at: set)
                VStack(alignment: .leading, spacing: 8) {
                    SetGroupBox(
                        group: group,
                        entry: entry,
                        currentID: emphasized ? currentSet?.persistentModelID : nil,
                        showsHoldStart: !emphasized,
                        restSeconds: restSeconds,
                        display: settings?.unitDisplay ?? .lbPrimary,
                        gym: gym,
                        bar: effectiveBar,
                        onStatusChange: onVerdict,
                        onRemove: { removeSet($0) }
                    )
                    .accessibilityIdentifier(emphasized && isActive ? "active-set-group" : "set-group")
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
                    if showLoadout, entry.exercise?.type == .barbell && set.weightLb > 0 {
                        let exactSolution = solvedPlateSolution(for: set)
                        let style: PlateVisualStyle = entry.exercise?.movementGroup == "olympic" ? .bumper : .steel
                        let theme = gym?.plateTheme ?? .custom
                        BarbellView(
                            solution: exactSolution,
                            plateStyle: style,
                            plateTheme: theme,
                            presentation: .compactSide,
                            emphasis: isActive ? .current : .muted
                        )
                    } else if showLoadout, entry.exercise?.type == .dumbbell && set.weightLb > 0 {
                        DumbbellView(weightLb: set.weightLb, unit: set.enteredUnit)
                    }
                }
                .opacity(group.sets[0].isWarmup && !isActive ? 0.68
                         : (group.sets.allSatisfy { $0.status == .completed } ? 0.72 : 1))
            }
            if let lastTime {
                Text("Previous · \(lastTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            DurationEditorButton(title: "Rest override", seconds: restBinding,
                                 zeroLabel: "Use default from Settings")
            Text("Effective rest: \(RestDuration.label(restSeconds)). Changes apply to this exercise everywhere; a running timer is unchanged.")
                .font(.footnote).foregroundStyle(.secondary)

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
                        // Color.primary, not the hierarchical `.primary`: in a
                        // section header the latter resolves to the header's
                        // own gray, which made the lift you're on look disabled.
                        VStack(alignment: .leading, spacing: 2) {
                            if emphasized, let slotLine {
                                Text(slotLine)
                                    .font(.footnote.weight(.heavy))
                                    .tracking(0.8)
                                    .foregroundStyle(Theme.forgedSteel)
                            }
                            Text(exercise.name)
                                .font(emphasized ? .largeTitle.weight(.heavy) : .headline)
                                .fontWidth(emphasized ? .condensed : .standard)
                                .foregroundStyle(Color.primary)
                                .multilineTextAlignment(.leading)
                        }
                        // The header stays pinned while the list scrolls; at
                        // the largest sizes an uncapped large title would
                        // cover the very set it names.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
                if !emphasized, let phaseLabel = entry.truthfulPhaseLabel {
                    Text(phaseLabel).foregroundStyle(Theme.accent)
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
                        .disabled(!SwapRules.canReplaceEntry(setStatuses: entry.sets.map(\.status)))
                        if !SwapRules.canReplaceEntry(setStatuses: entry.sets.map(\.status)) {
                            Text("Sets already logged. Add a separate exercise to change movements.")
                        }
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
                        // House tap target; the glyph alone audits as too small (#61).
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
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
                        Text("Just this session leaves the program unchanged. Cycle swaps revert at the next rollover; program swaps rename the slot for good. Check the starting weight for the new exercise before logging sets.")
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let sessionProgress {
                    Text(sessionProgress)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .accessibilityIdentifier("session-progress")
                }
                if let site = entry.exercise?.watchSite {
                    Text("Watch: \(site.rawValue.lowercased()) — \(site.watchNote)")
                }
            }
        }
        .sheet(item: $expandedLoadout) { detail in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        BarbellInspectionView(solution: detail.solution, plateStyle: detail.style, plateTheme: detail.theme)
                        LoadoutSummaryView(
                            requestedLb: detail.requestedLb,
                            loadout: detail.solution.loadout,
                            plateStyle: detail.style,
                            plateTheme: detail.theme
                        )
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

    /// [INV-CARRY-LOGS-DISTANCE] The distance a new carry set starts with:
    /// the previous set's, or the default when this is the first. A previous
    /// set logged as reps keeps the entry on reps. nil for everything else.
    private static func startingCarryMiles(entry: SessionExercise, last: SetEntry?) -> Double? {
        guard let name = entry.exercise?.name, CardioFormat.logsCarryDistance(exerciseName: name) else { return nil }
        guard let last else { return CardioFormat.miles(fromYards: CardioFormat.carryDefaultYards) }
        return (last.distanceMiles ?? 0) > 0 ? last.distanceMiles : nil
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
        let carryMiles = Self.startingCarryMiles(entry: entry, last: last)
        let set = SetEntry(
            order: entry.sets.count,
            weightLb: isTimed ? carryLb : (last?.weightLb ?? entry.plannedWeightLb ?? firstSetDefaultLb()),
            reps: isTimed || carryMiles != nil ? 1 : (last?.reps ?? entry.plannedReps ?? 5),
            isPerSide: entry.exercise?.isUnilateral ?? false,
            enteredUnit: last?.enteredUnit ?? settings?.unitDisplay.primaryUnit ?? .lb,
            durationSeconds: isTimed ? (last?.durationSeconds ?? 30) : nil,
            distanceMiles: carryMiles,
            loadBasis: last?.loadBasis ?? entry.exercise?.loadBasis,
            implementCount: last?.resolvedImplementCount ?? entry.exercise?.resolvedImplementCount ?? 1,
            targetWeightLb: last?.targetWeightLb ?? entry.targetWeightLb,
            plannedWeightLb: last?.weightLb ?? entry.plannedWeightLb,
            plannedReps: isTimed || carryMiles != nil ? 1 : (last?.reps ?? entry.plannedReps ?? 5),
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
        let usesHistory = ProgramProgression.usesAdHocFirstSetFallback(
            programRole: entry.programRole,
            programSlotID: entry.programSlotID,
            plannedWeightLb: entry.plannedWeightLb
        )
        let suggestedLb = usesHistory
            ? (ProgramProgression.suggestedAdHocFirstSetTarget(
                fromLastTopExposure: adHocExposure
            )?.weightLb ?? catalogLb)
            : catalogLb
        return exercise.type == .barbell ? max(suggestedLb, effectiveBar.lb) : suggestedLb
    }

    /// Where the history-based suggestion prefilled into this entry's first
    /// working set came from, so the UI can disclose it instead of leaving a
    /// history-derived number unexplained. Nil for program/explicit plans and
    /// whenever there is no prior exposure (the catalog default applied
    /// silently, as before).
    private var firstSetProvenance: String? {
        guard ProgramProgression.usesAdHocFirstSetFallback(
                programRole: entry.programRole,
                programSlotID: entry.programSlotID,
                plannedWeightLb: entry.plannedWeightLb
              ),
              let exposure = adHocExposure,
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
    let existing = entry.orderedSets.filter(\.isWarmup)
    // Work already COMPLETED earlier in the session on this movement with
    // this implement trims the ramp below it (issue #64) — but only while
    // every warmup here is still planned: once one is resolved the ramp is
    // the lifter's record and only its weights refresh. Mirrors web.
    let priorWorkLb: Double? = {
        guard !existing.contains(where: { $0.status != .planned }), let session = entry.session else { return nil }
        return WarmupRamp.priorWorkLb(order: entry.order, movementGroup: exercise.movementGroup,
                                      exerciseType: exercise.typeRaw, in: sessionWork(session))
    }()
    var desired: [WarmupSet]
    if exercise.type == .barbell {
        desired = ProgramSession.achievableWarmups(
            WarmupRamp.ramp(workingLb: workingLb, barLb: bar.lb,
                            roundingLb: ProgramEngine.defaultRoundingLb,
                            includeEmptyBar: ProgramSession.includesEmptyBarWarmup(for: exercise),
                            priorWorkLb: priorWorkLb),
            workingLb: workingLb, gym: gym, bar: bar, exercise: exercise)
    } else if exercise.type == .dumbbell && entry.programRole == LiftRole.main.rawValue {
        desired = WarmupRamp.dumbbellRamp(workingLb: workingLb,
                                          roundingLb: ProgramEngine.loadStep(
                                            programRoundingLb: ProgramEngine.defaultRoundingLb,
                                            exerciseType: exercise.typeRaw))
    } else {
        return
    }
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

/// What each entry has already lifted, in the shape `WarmupRamp.priorWorkLb`
/// reads: completed working loads only — planned and skipped sets, and
/// warmups, prepared nobody. Mirrors web `sessionWork`.
private func sessionWork(_ session: WorkoutSession) -> [WarmupRamp.SessionWork] {
    session.orderedExercises.map { entry in
        WarmupRamp.SessionWork(order: entry.order,
                               movementGroup: entry.exercise?.movementGroup ?? "",
                               exerciseType: entry.exercise?.typeRaw ?? "",
                               completedWorkLbs: entry.workingSets.map(\.weightLb))
    }
}

// MARK: - Set row

private struct SetRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    var onStatusChange: (_ previous: SetStatus, _ current: SetStatus) -> Void
    var onRemove: () -> Void

    @State private var showDetail = false
    @State private var showHoldTimer = false

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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
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
                            Text("× \(repsOrDistance)")
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
                        if !isCardio && !isTimed, set.carryYards == nil,
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

            if isTimed && set.status == .planned {
                Button { showHoldTimer = true } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.callout.bold()).frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Start \(exercise?.name ?? "hold") timer")
                .accessibilityIdentifier("start-hold-timer")
            }
            SetVerdictControl(set: set, allowsQuality: !isCardio && !isTimed, onStatusChange: onStatusChange)
        }
        .padding(isCurrent ? 12 : 0)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.accent.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.accent.opacity(0.55)))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Theme.edge)
                            .frame(height: 0.5)
                            .padding(.horizontal, Theme.cornerRadius)
                    }
            }
        }
        .sheet(isPresented: $showHoldTimer) {
            HoldTimerSheet(set: set, exerciseName: exercise?.name ?? "Hold", onStatusChange: onStatusChange)
        }
        .sheet(isPresented: $showDetail) {
            SetEditor(set: set, entry: entry, exercise: exercise, gym: gym, bar: bar,
                      targetLb: targetLb, onDelete: onRemove)
        }
    }

    /// [INV-CARRY-LOGS-DISTANCE] "40 yd" for a distance carry — the row
    /// then reads "50 lb each × 40 yd" — and the rep count otherwise.
    private var repsOrDistance: String {
        if let yards = set.carryYards {
            return CardioFormat.carryDistanceLabel(yards: yards, isPerSide: set.isPerSide)
        }
        return "\(set.reps)\(set.isPerSide ? "/side" : "")"
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

/// "Edit sets": the plan one set per row — load, reps, status — for fixing
/// several at once, like a 3×5 that went 5, 5, 4 at a lighter third set.
/// Each row is the full set row: tap for its editor, the status control for
/// complete/skip/quality, swipe to delete.
private struct SetPlanEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: SessionExercise
    let gym: Gym?
    let bar: Bar
    let currentID: PersistentIdentifier?
    let onStatusChange: (_ set: SetEntry, _ previous: SetStatus, _ current: SetStatus) -> Void
    let onRemove: (SetEntry) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(entry.orderedSets) { set in
                    SetRow(set: set, entry: entry, exercise: entry.exercise, gym: gym, bar: bar,
                           isCurrent: set.persistentModelID == currentID, compact: false,
                           targetLb: set.plannedWeightLb ?? entry.plannedWeightLb,
                           onStatusChange: { onStatusChange(set, $0, $1) },
                           onRemove: { onRemove(set) })
                }
                .onDelete { offsets in
                    let ordered = entry.orderedSets
                    for index in offsets.sorted(by: >) { onRemove(ordered[index]) }
                }
            }
            .listStyle(.plain)
            .themeListBackground()
            .accessibilityIdentifier("set-plan-editor")
            .navigationTitle(entry.exercise?.name ?? "Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if PersistenceErrorCenter.shared.save(context, operation: "Saving the sets") { dismiss() }
                    }
                }
            }
        }
    }
}

/// The one-set editor, chosen by what the set records: distance/time for
/// conditioning, hold time for timed work, load/reps/flags for everything
/// else. Opened from a set's marker on the working screen and from its row
/// in the per-set plan editor.
private struct SetEditor: View {
    let set: SetEntry
    let entry: SessionExercise
    let exercise: Exercise?
    let gym: Gym?
    let bar: Bar
    let targetLb: Double?
    let onDelete: () -> Void

    var body: some View {
        if exercise?.type == .conditioning {
            CardioSetSheet(set: set, exerciseName: exercise?.name ?? "", onDelete: onDelete)
                .presentationDetents([.medium, .large])
        } else if exercise?.type == .timed {
            TimedSetSheet(set: set, onDelete: onDelete)
                .presentationDetents([.medium])
        } else {
            SetDetailSheet(set: set, entry: entry, exercise: exercise, gym: gym, bar: bar,
                           targetLb: targetLb, onDelete: onDelete)
                .presentationDetents([.large])
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
    var onStatusChange: (_ previous: SetStatus, _ current: SetStatus) -> Void

    var body: some View {
        Menu {
            SetVerdictMenu(set: set, allowsQuality: allowsQuality, onStatusChange: onStatusChange)
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
        SetVerdictMenu.apply(status, to: set, context: context, onStatusChange: onStatusChange)
    }

    private func statusLabel(_ status: SetStatus) -> String { SetVerdictMenu.statusLabel(status) }
    private func statusIcon(_ status: SetStatus) -> String { SetVerdictMenu.statusIcon(status) }
    private func statusColor(_ status: SetStatus) -> Color {
        switch status { case .planned: return .secondary; case .completed: return Theme.good; case .skipped: return .secondary }
    }
}

/// Status, quality and reps-in-reserve for one set: the long-press menu of
/// the row's status control and of the set's marker on the working screen.
private struct SetVerdictMenu: View {
    @Environment(\.modelContext) private var context
    @Bindable var set: SetEntry
    let allowsQuality: Bool
    var onStatusChange: (_ previous: SetStatus, _ current: SetStatus) -> Void

    var body: some View {
        Section("Status") {
            ForEach(SetStatus.allCases, id: \.self) { status in
                Button {
                    Self.apply(status, to: set, context: context, onStatusChange: onStatusChange)
                } label: {
                    Label(Self.statusLabel(status), systemImage: Self.statusIcon(status))
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
    }

    private func save() { PersistenceErrorCenter.shared.save(context, operation: "Changing the set verdict") }

    /// The one mutation path — shared with the Lock Screen's commands — then
    /// the caller decides what follows.
    static func apply(_ status: SetStatus, to set: SetEntry, context: ModelContext,
                      onStatusChange: (SetStatus, SetStatus) -> Void) {
        let previous = set.status
        guard previous != status else { return }
        do {
            try WorkoutCommandService.setStatus(status, of: set, context: context)
        } catch {
            PersistenceErrorCenter.shared.report(error, operation: "Changing the set verdict", context: context)
            return
        }
        onStatusChange(previous, status)
    }

    static func statusLabel(_ status: SetStatus) -> String {
        switch status { case .planned: return "Planned"; case .completed: return "Completed"; case .skipped: return "Skipped" }
    }
    static func statusIcon(_ status: SetStatus) -> String {
        switch status { case .planned: return "circle"; case .completed: return "checkmark.circle.fill"; case .skipped: return "minus.circle.fill" }
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
    /// [INV-CARRY-LOGS-DISTANCE] Yards for a distance-carry set, captured
    /// once on open; nil keeps the reps editor (a carry logged as reps too).
    @State private var yards: Double?
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
                        BarbellView(
                            solution: authoritativePlateSolution(
                                targetLb: lb,
                                fallbackUnit: unit,
                                bar: bar,
                                gym: gym,
                                stationDenomination: exercise?.stationDenomination
                            ),
                            plateStyle: exercise?.movementGroup == "olympic" ? .bumper : .steel,
                            plateTheme: gym?.plateTheme ?? .custom
                        )
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
                    if let carried = yards {
                        Stepper("Distance: \(CardioFormat.carryDistanceLabel(yards: carried, isPerSide: isPerSide))",
                                value: Binding(get: { carried }, set: { yards = $0 }),
                                in: CardioFormat.carryYardsStep...2000, step: CardioFormat.carryYardsStep)
                    } else {
                        Stepper("Reps: \(reps)", value: $reps, in: 0...100)
                    }
                    Toggle("Warmup", isOn: $isWarmup)
                    Toggle("Per side", isOn: $isPerSide)
                    Toggle("Stopped early", isOn: $stoppedEarly)
                    if canApplyToRemaining {
                        Toggle(yards == nil ? "Apply reps to remaining planned sets" : "Apply distance to remaining planned sets",
                               isOn: $applyRepsToRemaining)
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
                yards = set.carryYards
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
        if let yards { set.distanceMiles = CardioFormat.miles(fromYards: yards) }
        if !isWarmup {
            let remaining = entry.plannedWorkingSets.filter { $0 !== set && $0.status == .planned }
            if applyWeightToRemaining {
                for target in remaining { target.weightLb = lb; target.enteredUnit = unit }
            }
            if applyRepsToRemaining {
                for target in remaining {
                    if yards == nil { target.reps = reps }
                    else if target.carryYards != nil { target.distanceMiles = set.distanceMiles }
                }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// At accessibility sizes the utility row sheds words, not meaning: the
    /// labels still reach VoiceOver; the thumb zone stays Done's.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editingRest = false
    @State private var restAtOpen = 0
    /// nil until the workout is explicitly started — opening the logger to
    /// read the plan must not display a running clock.
    let sessionStart: Date?
    let pausedAt: Date?
    let restLabel: String
    let restSeconds: Int
    /// The set the thumb logs next; nil for holds, conditioning, or nothing left.
    let done: SessionDoneAction?
    /// A timed set's Start hold, in the same slot.
    let hold: SessionHoldAction?
    /// The short "logged" receipt, while it lasts.
    let stamp: String?
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            // A tall progress bar during rest so the countdown reads at a glance.
            ProgressView(value: restTimer.isRunning ? min(1, 1 - restTimer.progress) : 0)
                .tint(Theme.accent)
                .scaleEffect(x: 1, y: restTimer.isRunning ? 2 : 1, anchor: .top)
                .animation(reduceMotion ? nil : .easeOut(duration: Theme.shortMotion), value: restTimer.isRunning)

            // Utility row: the workout clock (or the explicit start) and the
            // manual rest. Steel, not accent — they're rarely the next thing.
            HStack(spacing: 10) {
                clock
                Spacer(minLength: 4)
                if restTimer.isRunning {
                    if !restTimer.exerciseName.isEmpty {
                        Text("Next · \(restTimer.exerciseName)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                } else {
                    restButton
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, primarySlotIsEmpty ? 10 : 6)

            // The primary slot, in the thumb zone. One thing lives here at a
            // time: the receipt for the set just logged, the rest countdown,
            // or Done for the set you're on.
            Group {
                if let stamp {
                    stampView(stamp)
                } else if restTimer.isRunning {
                    restSlot
                } else if let done {
                    HStack(spacing: 10) {
                        doneButton(done)
                        skipButton(done)
                    }
                } else if let hold {
                    Button(action: hold.perform) {
                        Label("Start hold", systemImage: "play.fill")
                            .font(.title2.weight(.black))
                            .fontWidth(.condensed)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: Theme.bigTap - 14)
                    }
                    .primaryActionStyle()
                    .accessibilityLabel("Start \(hold.name) timer")
                    .accessibilityIdentifier("start-hold-timer")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, primarySlotIsEmpty ? 0 : 10)
        }
        // Opaque, not bar material: whatever scrolls under the thumb zone
        // (an orange "-0.3 lb", a blue plate) must not tint Done or Rest.
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-bottom-bar")
        .sheet(isPresented: $editingRest) {
            DurationEditor(title: "Remaining rest", seconds: restAtOpen, zeroLabel: "End rest") {
                restTimer.setRemaining(seconds: $0)
            }
        }
    }

    private var primarySlotIsEmpty: Bool { stamp == nil && !restTimer.isRunning && done == nil && hold == nil }

    @ViewBuilder
    private var clock: some View {
        if let sessionStart {
            // Session stopwatch, with an icon so it reads as a running clock.
            TimelineView(.periodic(from: sessionStart, by: 1)) { timeline in
                Label(elapsedLabel(at: pausedAt ?? timeline.date),
                      systemImage: pausedAt == nil ? "stopwatch" : "pause.fill")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else {
            // Starting the clock is explicit and optional: sets log without
            // it. With Done on screen it is a secondary control; with nothing
            // else to do it keeps the primary treatment.
            Button(action: onStart) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "play.fill")
                    } else {
                        Label("Start workout", systemImage: "play.fill")
                    }
                }
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minHeight: 32)
            }
            .accessibilityLabel("Start workout")
            .modifier(SecondaryUnlessAlone(alone: done == nil && hold == nil))
            .accessibilityHint("Begins the workout clock for this session")
        }
    }

    private var restButton: some View {
        Button {
            restTimer.start(seconds: restSeconds, exerciseName: restLabel)
        } label: {
            Label(dynamicTypeSize.isAccessibilitySize ? mmss(restSeconds) : "Rest \(mmss(restSeconds))", systemImage: "timer")
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(minHeight: 32)
        }
        .accessibilityLabel("Rest \(mmss(restSeconds))")
        .modifier(SecondaryUnlessAlone(alone: done == nil && hold == nil))
    }

    private func doneButton(_ done: SessionDoneAction) -> some View {
        Button(action: done.perform) {
            Label("Done", systemImage: "checkmark")
                .font(.title2.weight(.black))
                .fontWidth(.condensed)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: Theme.bigTap - 14)
                .contentShape(Rectangle())
        }
        .primaryActionStyle()
        .layoutPriority(1)
        .accessibilityIdentifier("done-set")
        .accessibilityLabel("Done, \(done.position)")
        .accessibilityValue(done.spoken)
        .accessibilityHint("Logs the set as shown. Tap the numbers above first if reps or load changed.")
    }

    private func skipButton(_ done: SessionDoneAction) -> some View {
        Button(action: done.skip) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "forward.end.fill")
                } else {
                    Text("Skip")
                }
            }
                .font(.headline.weight(.heavy))
                .fontWidth(.condensed)
                .lineLimit(1)
                .frame(minWidth: 64, minHeight: Theme.bigTap - 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: Theme.cornerRadius))
        .tint(Color.primary)
        .accessibilityIdentifier("skip-set")
        .accessibilityLabel("Skip \(done.position)")
        .accessibilityHint("Marks the set skipped. It stays in the log as skipped, not completed.")
    }

    /// The set just logged, stamped in steel where Done was. It holds no
    /// action, so a double tap on Done can't log the next set by accident;
    /// undo is the set's marker (touch and hold), as for any verdict.
    private func stampView(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.title3.weight(.heavy).monospacedDigit())
            .fontWidth(.condensed)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: Theme.bigTap, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.hairline))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("set-logged-stamp")
    }

    /// Rest owns the thumb zone while it runs: a countdown big enough to read
    /// from the bench, tap to set it exactly, and the existing adjustments.
    private var restSlot: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                countdown
                Spacer(minLength: 4)
                restControls
            }
            VStack(alignment: .leading, spacing: 6) {
                countdown
                restControls
            }
        }
        .frame(minHeight: Theme.bigTap)
    }

    private var countdown: some View {
        Button {
            restAtOpen = max(0, Int(restTimer.remaining.rounded()))
            editingRest = true
        } label: {
            Text(restTimer.display)
                .font(.largeTitle.weight(.black).monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit remaining rest")
        .accessibilityValue(restTimer.display)
    }

    private var restControls: some View {
        HStack(spacing: 8) {
            Button {
                restTimer.isPaused ? restTimer.resume() : restTimer.pause()
            } label: { Image(systemName: restTimer.isPaused ? "play.fill" : "pause.fill").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel(restTimer.isPaused ? "Resume rest" : "Pause rest")
            Button { restTimer.add(seconds: -60) } label: { Image(systemName: "gobackward.60").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Subtract one minute")
            Button { restTimer.add(seconds: 60) } label: { Image(systemName: "goforward.60").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Add one minute")
            Button {
                restTimer.stop()
            } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Skip rest")
        }
        .buttonStyle(.bordered)
        .tint(Color.primary)
    }

    private func elapsedLabel(at date: Date) -> String {
        mmss(max(0, Int(date.timeIntervalSince(sessionStart ?? date))))
    }
}

/// Accent is for the next act. A bar control that isn't it (Start workout,
/// manual rest while Done is on screen) wears steel instead.
private struct SecondaryUnlessAlone: ViewModifier {
    let alone: Bool
    func body(content: Content) -> some View {
        if alone {
            content.primaryActionStyle()
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: Theme.cornerRadius))
                .tint(Color.primary)
        }
    }
}

// MARK: - Exercise picker

private struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var equipmentPolicy: EquipmentPolicy = .any
    let onPick: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            // The library browser with a selection closure (issue #63):
            // search, Movement and Equipment filters, Recent, and the
            // collapsed category groups — one surface for every picker.
            ExerciseBrowser(equipmentPolicy: equipmentPolicy) { exercise in
                onPick(exercise)
                dismiss()
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Summary

private struct SessionSummarySheet: View {
    @Query private var settingsList: [AppSettings]
    @State private var healthResult: HealthWorkoutSaveResult?
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
                if summary.healthExport != nil || summary.healthExportNotice != nil {
                    Section("Apple Health") {
                        if let message = healthResult?.message ?? summary.healthExportNotice {
                            Text(message)
                        } else {
                            Label("Saving workout to Apple Health…", systemImage: "heart")
                                .accessibilityLabel("Session saved in Cadence. Saving workout to Apple Health.")
                        }
                    }
                }
                if let timing = summary.ruckStepTiming {
                    RuckStepsSection(timing: timing)
                } else if summary.ruckStepTimingUnavailable {
                    Section("Measured steps") {
                        Text("Steps aren't available because this session has no reliable captured timing. Your ruck is saved in Cadence.")
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
            .task {
                if let task = summary.healthExport { healthResult = await task.value }
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

/// The focused exercise's set track: one segment per working set, the current
/// one carrying the accent, resolved ones quieter. Web twin: `.set-track`.
/// Consecutive sets that share one prescription: same kind (warmup/work),
/// block, planned load and reps (or hold), basis and unit. A 3×5 is one box,
/// a ramp of three different warmups is three. Presentation only: every set
/// stays its own record with its own ID, order, status and performed values,
/// and keys use the PLANNED numbers so an edited set 3 stays in its box
/// instead of quietly splitting the plan.
private struct SetGroup: Identifiable {
    let sets: [SetEntry]
    var id: PersistentIdentifier { sets[0].persistentModelID }

    struct Key: Equatable {
        let isWarmup: Bool
        let block: String
        let loadLb: Double
        let reps: Int
        let seconds: Int?
        let yards: Double?
        let isPerSide: Bool
        let basis: String
        let unit: String
    }

    static func key(_ set: SetEntry) -> Key {
        Key(isWarmup: set.isWarmup, block: set.prescriptionBlockRaw,
            loadLb: set.plannedWeightLb ?? set.weightLb, reps: set.plannedReps ?? set.reps,
            seconds: set.plannedDurationSeconds ?? set.durationSeconds, yards: set.carryYards,
            isPerSide: set.isPerSide, basis: set.loadBasisRaw, unit: set.enteredUnitRaw)
    }

    var key: Key { Self.key(sets[0]) }

    /// Conditioning sets each log their own distance and time, so they never
    /// share a box.
    static func grouping(_ ordered: [SetEntry], separately: Bool) -> [SetGroup] {
        var runs: [[SetEntry]] = []
        for set in ordered {
            if !separately, let last = runs.last?.last, key(last) == key(set) {
                runs[runs.count - 1].append(set)
            } else {
                runs.append([set])
            }
        }
        return runs.map(SetGroup.init)
    }

    /// "Warmup", "Working sets", "Back-off", … — the kind, in words.
    var kind: String {
        let first = sets[0]
        if first.isWarmup { return first.prescriptionBlock == .primer ? "Primer" : "Warmup" }
        switch first.prescriptionBlock {
        case .topSingle: return "Top single"
        case .ramp: return "Ramp"
        case .backoff: return "Back-off"
        case .amrap: return "AMRAP"
        default: return sets.count == 1 ? "Working set" : "Working sets"
        }
    }
}

/// Load in the set's entered unit, the other unit only when the lifter asked
/// for both (Settings › Units & loading). "BW" for bodyweight.
private func loadWords(lb: Double, set: SetEntry, display: UnitDisplay, withUnit: Bool = true) -> (primary: String, secondary: String?) {
    guard lb > 0 else { return ("BW", nil) }
    let kg = Weight.kg(fromLb: lb)
    let primary = set.enteredUnit == .kg
        ? Weight.trim(kg) + (withUnit ? " kg" : "")
        : Weight.trim(lb) + (withUnit ? " lb" : "")
    guard display == .both else { return (primary, nil) }
    let secondary = set.enteredUnit == .kg ? "\(Weight.trim(lb)) lb" : "\(Weight.trim(kg)) kg"
    return (primary, secondary)
}

/// One set's circle: current filled accent with its number, done filled
/// steel with a chalk check, skipped dashed and struck, planned a steel
/// outline with its number. Tap opens the set's
/// editor; touch and hold for status, quality and reps in reserve.
private struct SetMarker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var set: SetEntry
    let number: Int
    let total: Int
    let isCurrent: Bool
    let allowsQuality: Bool
    /// The set's own numbers when they differ from the box's prescription.
    let deviation: String?
    let spoken: String
    let size: CGFloat
    let onEdit: () -> Void
    let onStatusChange: (_ previous: SetStatus, _ current: SetStatus) -> Void
    @State private var stamped = false

    var body: some View {
        VStack(spacing: 3) {
            Menu {
                SetVerdictMenu(set: set, allowsQuality: allowsQuality, onStatusChange: onStatusChange)
            } label: {
                face
            } primaryAction: {
                onEdit()
            }
            .tint(Color.primary)
            .accessibilityLabel("\(set.isWarmup ? "Warmup" : "Set") \(number) of \(total), \(stateWord)")
            .accessibilityValue(spoken)
            .accessibilityHint("Opens this set's editor. Touch and hold for status, quality, and reps in reserve.")
            .accessibilityIdentifier("set-marker")
            if let deviation {
                Text(deviation)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .fontWidth(.condensed)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: set.status) { old, new in
            guard new == .completed, old != .completed, !reduceMotion else { return }
            withAnimation(.spring(duration: 0.18, bounce: 0.45)) { stamped = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.easeOut(duration: 0.2)) { stamped = false }
            }
        }
    }

    private var stateWord: String {
        if isCurrent { return "current" }
        switch set.status {
        case .completed: return "done"
        case .skipped: return "skipped"
        case .planned: return "planned"
        }
    }

    private var face: some View {
        let shape = Circle()
        return ZStack {
            switch (isCurrent, set.status) {
            case (true, _):
                shape.fill(Theme.accent)
                Text("\(number)").foregroundStyle(Theme.onAccent)
            case (false, .completed):
                shape.fill(Color.primary.opacity(0.22))
                Image(systemName: "checkmark").foregroundStyle(Color.primary)
            case (false, .skipped):
                shape.stroke(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Path { path in
                    path.move(to: CGPoint(x: size * 0.22, y: size * 0.78))
                    path.addLine(to: CGPoint(x: size * 0.78, y: size * 0.22))
                }
                .stroke(Color.primary.opacity(0.6), lineWidth: 1.5)
            case (false, .planned):
                shape.stroke(Color.primary.opacity(0.35), lineWidth: 1.5)
                Text("\(number)").foregroundStyle(Color.secondary)
            }
        }
        .font(.title3.weight(.heavy).monospacedDigit())
        .fontWidth(.condensed)
        .frame(width: size, height: size)
        .scaleEffect(stamped ? 1.14 : 1)
        .contentShape(Rectangle())
    }
}

/// A set's own numbers when they differ from `key` — a manual edit is never
/// hidden behind the planned figures. Nil when they match.
private func deviationWords(_ set: SetEntry, from key: SetGroup.Key, type: ExerciseType?) -> String? {
    if type == .conditioning { return nil }
    if type == .timed {
        guard let seconds = set.durationSeconds, seconds != key.seconds else { return nil }
        return CardioFormat.durationLabel(seconds: seconds)
    }
    let repsDiffer = set.carryYards == nil && set.reps != key.reps
    let loadDiffers = abs(set.weightLb - key.loadLb) > 0.001
    guard repsDiffer || loadDiffers else { return nil }
    let load = loadWords(lb: set.weightLb, set: set, display: .lbPrimary, withUnit: false).primary
    return "\(set.reps) × \(load)"
}

/// One set in words for VoiceOver: "6 reps at 138.7 lb".
private func spokenWords(_ set: SetEntry, type: ExerciseType?) -> String {
    if type == .conditioning {
        return CardioFormat.setLabel(distanceMiles: set.distanceMiles, durationSeconds: set.durationSeconds,
                                     inclinePercent: set.inclinePercent, loadLb: set.weightLb, flights: set.flights)
    }
    if type == .timed { return "\(CardioFormat.durationLabel(seconds: set.durationSeconds ?? 0)) hold" }
    let load = set.weightLb == 0 ? "bodyweight" : loadWords(lb: set.weightLb, set: set, display: .lbPrimary).primary
    if let yards = set.carryYards { return "\(Weight.trim(yards)) yards at \(load)" }
    return "\(set.reps) reps at \(load)"
}

/// The set you're on: a circle per set in its phase, "SET 2 OF 3" under
/// them, then the numbers to lift. Tap the numbers or a circle to edit that
/// one set; touch and hold a circle for status, quality and reps in reserve.
private struct SetCockpit: View {
    let entry: SessionExercise
    let current: SetEntry
    let gym: Gym?
    let bar: Bar
    let onStatusChange: (_ set: SetEntry, _ previous: SetStatus, _ current: SetStatus) -> Void
    let onRemove: (SetEntry) -> Void
    @ScaledMetric(relativeTo: .body) private var scaledMarker: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 64
    @State private var editingSet: SetEntry?

    private var type: ExerciseType? { entry.exercise?.type }
    private var phase: [SetEntry] { entry.orderedSets.filter { $0.isWarmup == current.isWarmup } }
    private var ordinal: Int { (phase.firstIndex { $0.persistentModelID == current.persistentModelID } ?? 0) + 1 }
    private var markerSize: CGFloat { min(max(scaledMarker, 40), 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: markerSize, maximum: markerSize + 24), spacing: 10, alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                ForEach(Array(phase.enumerated()), id: \.element.persistentModelID) { index, set in
                    SetMarker(
                        set: set,
                        number: index + 1,
                        total: phase.count,
                        isCurrent: set.persistentModelID == current.persistentModelID,
                        allowsQuality: type != .timed && type != .conditioning,
                        deviation: deviationWords(set, from: SetGroup.key(set), type: type),
                        spoken: spokenWords(set, type: type),
                        size: markerSize,
                        onEdit: { editingSet = set },
                        onStatusChange: { onStatusChange(set, $0, $1) }
                    )
                }
            }
            Text("\(current.isWarmup ? "WARMUP" : "SET") \(ordinal) OF \(phase.count)")
                .font(.footnote.weight(.heavy).monospacedDigit())
                .tracking(0.8)
                .foregroundStyle(.secondary)
            figure
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .sheet(item: $editingSet) { set in
            SetEditor(set: set, entry: entry, exercise: entry.exercise, gym: gym, bar: bar,
                      targetLb: set.plannedWeightLb ?? entry.plannedWeightLb, onDelete: { onRemove(set) })
        }
    }

    @ViewBuilder
    private var figure: some View {
        if type == .timed {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CardioFormat.durationLabel(seconds: current.durationSeconds ?? 0))
                    .font(.system(size: min(figureSize, 120), weight: .black).width(.condensed).monospacedDigit())
                Text("hold")
                    .font(.title.weight(.heavy))
                    .fontWidth(.condensed)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentShape(Rectangle())
            .onTapGesture { editingSet = current }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Adjust hold time") { editingSet = current }
        } else if type == .conditioning {
            Button { editingSet = current } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spokenWords(current, type: type))
                        .font(.title.weight(.heavy).monospacedDigit())
                        .fontWidth(.condensed)
                        .foregroundStyle(Color.primary)
                    Text("Tap to log distance and time")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            // The numbers you're about to lift — the set's own values, which
            // is the prescription unless you changed this set.
            CurrentSetHero(set: current)
                .contentShape(Rectangle())
                .onTapGesture { editingSet = current }
                .accessibilityAction(named: "Adjust reps or load") { editingSet = current }
        }
    }
}

/// One prescription, stated once, with a marker per set across the top.
/// Per-set rows live in the editor ("Edit sets"), not here.
private struct SetGroupBox: View {
    let group: SetGroup
    let entry: SessionExercise
    /// The focused lift's current set; nil for a lift you're not on.
    let currentID: PersistentIdentifier?
    /// The focused lift starts its hold from the cockpit; other lifts' boxes
    /// keep the button.
    let showsHoldStart: Bool
    let restSeconds: Int
    let display: UnitDisplay
    let gym: Gym?
    let bar: Bar
    let onStatusChange: (_ set: SetEntry, _ previous: SetStatus, _ current: SetStatus) -> Void
    let onRemove: (SetEntry) -> Void
    @ScaledMetric(relativeTo: .body) private var scaledMarker: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Each box presents its own sheets. Modifiers on a List Section land on
    // every row, and a dozen rows sharing one binding present nothing.
    @State private var editingSet: SetEntry?
    @State private var editingPlan = false
    @State private var holdSet: SetEntry?

    private func onEdit(_ set: SetEntry) { editingSet = set }

    private var type: ExerciseType? { entry.exercise?.type }
    private var isTimed: Bool { type == .timed }
    private var isCardio: Bool { type == .conditioning }
    private var current: SetEntry? { group.sets.first { $0.persistentModelID == currentID } }
    private var markerSize: CGFloat { min(max(scaledMarker, 44), 64) }
    private var phase: [SetEntry] { entry.orderedSets.filter { $0.isWarmup == group.sets[0].isWarmup } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                // A row of markers; a long plan (10×10) wraps instead.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) { markers }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: markerSize, maximum: markerSize + 28), spacing: 10, alignment: .leading)],
                              alignment: .leading, spacing: 8) { markers }
                }
                Spacer(minLength: 8)
                Button("Edit sets") { editingPlan = true }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(Color.primary)
                    .frame(minHeight: 44)
                    .fixedSize()
                    .accessibilityHint("Lists every set of this exercise to change load, reps, or status one set at a time")
            }
            prescription
            if showsHoldStart, isTimed, let current, current.status == .planned {
                Button { holdSet = current } label: {
                    Label("Start hold", systemImage: "play.fill")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .primaryActionStyle()
                .accessibilityLabel("Start \(entry.exercise?.name ?? "hold") timer")
                .accessibilityIdentifier("start-hold-timer")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius)
            .stroke(Color.primary.opacity(0.16), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
        .sheet(item: $editingSet) { set in
            SetEditor(set: set, entry: entry, exercise: entry.exercise, gym: gym, bar: bar,
                      targetLb: set.plannedWeightLb ?? entry.plannedWeightLb, onDelete: { onRemove(set) })
        }
        .sheet(item: $holdSet) { set in
            HoldTimerSheet(set: set, exerciseName: entry.exercise?.name ?? "Hold",
                           onStatusChange: { onStatusChange(set, $0, $1) })
        }
        .sheet(isPresented: $editingPlan) {
            SetPlanEditor(entry: entry, gym: gym, bar: bar, currentID: currentID,
                          onStatusChange: onStatusChange, onRemove: onRemove)
        }
    }

    private func ordinal(_ set: SetEntry) -> Int {
        (phase.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
    }

    private var markers: some View {
        ForEach(group.sets) { set in
            SetMarker(
                set: set,
                number: ordinal(set),
                total: phase.count,
                isCurrent: set.persistentModelID == currentID,
                allowsQuality: !isCardio && !isTimed,
                deviation: deviation(set),
                spoken: spoken(set),
                size: markerSize,
                onEdit: { onEdit(set) },
                onStatusChange: { onStatusChange(set, $0, $1) }
            )
        }
    }

    /// The prescription once — kind, sets × reps (or hold), load, rest — on
    /// one line, stacked at accessibility sizes rather than truncated.
    private var prescription: some View {
        let first = group.sets[0]
        let key = group.key
        let load = loadWords(lb: key.loadLb, set: first, display: display)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        return layout {
            Text(group.kind.uppercased())
                .font(.footnote.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            if isCardio {
                Text(CardioFormat.setLabel(distanceMiles: first.distanceMiles, durationSeconds: first.durationSeconds,
                                           inclinePercent: first.inclinePercent, loadLb: first.weightLb, flights: first.flights))
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .fontWidth(.condensed)
            } else {
                Text(workWords(key))
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .fontWidth(.condensed)
                if !isTimed || key.loadLb > 0 {
                    Text(load.primary + first.loadBasis.shortSuffix)
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .fontWidth(.condensed)
                    if let secondary = load.secondary {
                        Text(secondary)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !first.isWarmup, restSeconds > 0, !isCardio {
                Text("· rest \(mmss(restSeconds))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    private func workWords(_ key: SetGroup.Key) -> String {
        let side = key.isPerSide ? "/side" : ""
        let each: String
        if isTimed { each = CardioFormat.durationLabel(seconds: key.seconds ?? 0) }
        else if let yards = key.yards { each = "\(Weight.trim(yards)) yd\(side)" }
        else { each = "\(key.reps)\(side)" }
        if group.sets.count > 1 { return "\(group.sets.count) × \(each)" }
        if isTimed { return "\(each) hold" }
        return key.yards == nil ? "\(each) reps" : each
    }

    private func deviation(_ set: SetEntry) -> String? { deviationWords(set, from: group.key, type: type) }
    private func spoken(_ set: SetEntry) -> String { spokenWords(set, type: type) }

    private var summary: String {
        let done = group.sets.filter { $0.status == .completed }.count
        let key = group.key
        let load = key.loadLb == 0 ? "bodyweight" : loadWords(lb: key.loadLb, set: group.sets[0], display: .lbPrimary).primary
        let work: String
        if isCardio { work = spoken(group.sets[0]) }
        else if isTimed { work = "\(group.sets.count) by \(CardioFormat.durationLabel(seconds: key.seconds ?? 0)) hold" }
        else { work = "\(group.sets.count) by \(key.yards.map { "\(Weight.trim($0)) yards" } ?? "\(key.reps)") at \(load)" }
        return "\(group.kind), \(work), \(done) of \(group.sets.count) done"
    }
}

/// The numbers to lift: the load giant, its unit, then "× reps" in steel,
/// the other unit small beneath. The set's own values in the unit it was
/// entered in. Web twin: `.current-set-hero`.
private struct CurrentSetHero: View {
    let set: SetEntry
    /// The dominant numeral keeps its proportion and still follows Dynamic
    /// Type. Condensed width buys the size without widening "138.7".
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 76
    @ScaledMetric(relativeTo: .largeTitle) private var unitSize: CGFloat = 40

    private var loadNumber: String {
        guard set.weightLb > 0 else { return "BW" }
        return Weight.trim(set.enteredUnit == .kg ? Weight.kg(fromLb: set.weightLb) : set.weightLb)
    }
    private var unit: String { self.set.weightLb > 0 ? (set.enteredUnit == .kg ? "kg" : "lb") : "" }
    private var otherUnit: String? {
        guard set.weightLb > 0 else { return nil }
        return set.enteredUnit == .kg ? "\(Weight.trim(set.weightLb)) lb" : "\(Weight.trim(Weight.kg(fromLb: set.weightLb))) kg"
    }
    /// [INV-CARRY-LOGS-DISTANCE] A distance carry states its yards.
    private var work: String {
        let side = set.isPerSide ? "/side" : ""
        if let yards = set.carryYards { return "× \(Weight.trim(yards)) yd\(side)" }
        return "× \(set.reps)\(side)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { load; reps }
                VStack(alignment: .leading, spacing: 0) { load; reps }
            }
            HStack(spacing: 8) {
                if let otherUnit { Text(otherUnit) }
                // The basis on the number itself: "50 lb each". Without it a
                // per-hand load reads as the total.
                if set.loadBasis != .totalBar, set.weightLb > 0 { Text("Set load · \(set.loadBasis.label)") }
                if set.prescriptionBlock == .amrap {
                    Text("AMRAP — \(set.plannedReps ?? set.reps)+ reps").foregroundStyle(Theme.accent)
                }
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(set.weightLb > 0
            ? "Set load \(LoadSemantics.heroLoadLabel(weightLb: set.weightLb, basis: set.loadBasis)), \(spokenWork)"
            : "Bodyweight, \(spokenWork)")
        .accessibilityHint("Opens this set's editor")
        .accessibilityIdentifier("current-set-hero")
    }

    private var spokenWork: String {
        if let yards = set.carryYards { return "\(Weight.trim(yards)) yards" }
        return "\(set.reps) reps\(set.isPerSide ? " per side" : "")"
    }

    private var load: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            // Scales with Dynamic Type up to a ceiling: past ~130 pt the
            // numeral only pushes the bar and Done off the screen.
            Text(loadNumber)
                .font(.system(size: min(numeralSize, 130), weight: .black).width(.condensed).monospacedDigit())
            if !unit.isEmpty {
                Text(unit + set.loadBasis.shortSuffix)
                    .font(.system(size: unitSize, weight: .heavy).width(.condensed))
            }
        }
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var reps: some View {
        Text(work)
            .font(.system(size: unitSize * 1.1, weight: .heavy).width(.condensed).monospacedDigit())
            .foregroundStyle(Theme.forgedSteel)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
