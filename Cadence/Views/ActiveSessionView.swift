import SwiftUI
import SwiftData
import CadenceCore

/// The logger. Pre-filled from the plan; everything editable in place.
/// Autoregulation is one tap. Rest is manual by default — armed from the Rest
/// buttons or the sticky bottom bar (session clock + countdown); it only
/// auto-arms after a set when the auto-start setting is on. Mirrors the web
/// logger (web/js/views/session.js).
struct ActiveSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimer.self) private var restTimer
    @Environment(WorkoutClock.self) private var workoutClock
    @Query private var settingsList: [AppSettings]
    @Query private var gyms: [Gym]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Bindable var session: WorkoutSession
    @State private var showExercisePicker = false
    @State private var autoregEntry: SessionExercise?
    @State private var summary: SessionSummary?
    @State private var currentEntry: SessionExercise?   // the exercise you're actively working
    @State private var banking = false                  // double-tap on Bank it would run completion twice
    @State private var showBankError = false            // failed save: everything rolled back, Bank stays retryable
    @State private var bankErrorMessage = ""
    @State private var showIncompleteBankConfirmation = false

    private var currentOrFirst: SessionExercise? { currentEntry ?? session.orderedExercises.first }
    private var gym: Gym? {
        gyms.first { $0.id == session.gymID }
            ?? gyms.first { $0.name == session.gymName }
            ?? gyms.first { $0.isDefault }
            ?? gyms.first
    }
    private var unfinishedSetCount: Int {
        session.orderedExercises.flatMap(\.plannedWorkingSets).filter { $0.status == .planned }.count
    }
    private var completedSetCount: Int {
        session.orderedExercises.flatMap(\.plannedWorkingSets).filter { $0.status == .completed }.count
    }
    /// The stopwatch origin lives in WorkoutClock (root-scoped), so it survives
    /// leaving this screen — and, via the Live Activity, app relaunch.
    private var sessionStart: Date { workoutClock.startDate ?? .now }
    private var currentRestSeconds: Int {
        smartRestSeconds(for: currentOrFirst?.exercise, role: currentOrFirst?.programRole, settings: settingsList.first)
    }

    var body: some View {
        List {
            trainingAtSection
            exerciseSections

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SessionBottomBar(
                sessionStart: sessionStart,
                pausedAt: workoutClock.pausedAt,
                restLabel: currentOrFirst?.exercise?.name ?? "",
                restSeconds: currentRestSeconds
            )
        }
        .onChange(of: settingsList.first?.haptics, initial: true) { _, on in restTimer.hapticsEnabled = on ?? true }
        .onAppear {
            // Start (or continue) the workout stopwatch + Live Activity.
            workoutClock.begin(for: session,
                               currentLift: currentOrFirst?.exercise?.name ?? "",
                               defaultRestSeconds: currentRestSeconds)
        }
        // Keep the activity's elapsed face and its quick-rest default honest.
        // Watch the derived VALUES, not the entry's identity: swapping the
        // exercise in place or editing its rest stepper changes the lift
        // name / default rest without changing which SessionExercise is current.
        .onChange(of: currentOrFirst?.exercise?.name) { pushActivityContext() }
        .onChange(of: currentRestSeconds) { pushActivityContext() }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
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
                Button("Later") {
                    if PersistenceErrorCenter.shared.save(context, operation: "Saving the open session") { dismiss() }
                }
            }
            // Workout clock controls: pause/resume/reset the stopwatch, or end
            // the workout outright (Live Activity + timers) without banking —
            // previously the only way to stop the clock was Bank it.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if workoutClock.isPaused {
                        Button { workoutClock.resume() } label: { Label("Resume clock", systemImage: "play") }
                    } else {
                        Button { workoutClock.pause() } label: { Label("Pause clock", systemImage: "pause") }
                    }
                    Button { workoutClock.reset() } label: { Label("Reset clock", systemImage: "arrow.counterclockwise") }
                    Divider()
                    Button(role: .destructive) {
                        restTimer.stop()
                        workoutClock.end()
                    } label: { Label("End workout", systemImage: "stop.circle") }
                } label: {
                    Image(systemName: workoutClock.isPaused ? "pause.circle" : "stopwatch")
                }
                .accessibilityLabel("Workout clock controls")
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet { exercise in
                addExercise(exercise)
            }
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
                        session.gymID = selected.id
                        session.gymName = selected.name
                        for entry in session.exercises where entry.barID == nil {
                            synchronizeWarmups(entry, bar: selected.defaultBar, gym: selected,
                                               enteredUnit: settingsList.first?.unitDisplay.primaryUnit ?? .lb,
                                               context: context)
                        }
                        PersistenceErrorCenter.shared.save(context, operation: "Changing the session gym")
                    }
                )) {
                    ForEach(gyms) { option in Text(option.name).tag(option.id) }
                }
            }
        }
    }

    /// Extracted from `body` — the seven-argument section call plus the recall
    /// lookup pushed the List builder past the type-checker's budget.
    private var exerciseSections: some View {
        let recall = recallLines()
        return ForEach(session.orderedExercises) { entry in
            ExerciseSection(
                entry: entry,
                settings: settingsList.first,
                gym: gym,
                allExercises: allExercises,
                lastTime: recallLine(for: entry, in: recall),
                onDropLoad: { autoregEntry = entry },
                onWork: { currentEntry = $0 },
                onRemove: { removeExercise(entry) }
            )
        }
    }

    private func recallLine(for entry: SessionExercise, in recall: [String: String]) -> String? {
        guard let name = entry.exercise?.name else { return nil }
        return recall[name]
    }

    /// Drop an exercise from this session (session-only — the program slot is
    /// untouched, like a swap). If it was the actively-worked lift, clear that
    /// so the bottom bar falls back to the first remaining exercise.
    private func removeExercise(_ entry: SessionExercise) {
        if currentEntry?.persistentModelID == entry.persistentModelID { currentEntry = nil }
        context.delete(entry)
        PersistenceErrorCenter.shared.save(context, operation: "Removing the exercise")
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
            restTimer.stop()
            workoutClock.end()
        } catch {
            banking = false
            bankErrorMessage = error.localizedDescription
            showBankError = true
        }
    }

    /// Compact previous-performance context per lift in THIS session, searched
    /// across ALL history (not just this
    /// program), so a lift you swapped away from months ago still tells you
    /// where you left off. One newest-first pass over history, stopping as
    /// soon as every lift on today's card has an answer.
    private func recallLines() -> [String: String] {
        var wanted = Set(session.orderedExercises.compactMap { $0.exercise?.name })
        var lines: [String: String] = [:]
        guard !wanted.isEmpty else { return lines }
        for past in completedSessions where past.persistentModelID != session.persistentModelID {
            for entry in past.exercises {
                guard let exercise = entry.exercise, wanted.contains(exercise.name),
                      let top = entry.topSet else { continue }
                let name = exercise.name
                if exercise.type == .timed {
                    let longest = past.exercises.filter { $0.exercise?.name == name }
                        .flatMap(\.workingSets).compactMap(\.durationSeconds).max() ?? 0
                    let when = past.date.formatted(date: .abbreviated, time: .omitted)
                    lines[name] = "Last: \(CardioFormat.durationLabel(seconds: longest)) · \(when) (\(agoLabel(past.date)))"
                    wanted.remove(name)
                    continue
                }
                let better = past.exercises.filter { $0.exercise?.name == name }.compactMap(\.topSet)
                    .max { $0.weightLb < $1.weightLb } ?? top
                let weight = better.weightLb == 0 ? "BW" : (settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: better.weightLb)
                let when = past.date.formatted(date: .abbreviated, time: .omitted)
                lines[name] = "Last: \(weight)×\(better.reps) · \(when) (\(agoLabel(past.date)))"
                wanted.remove(name)
            }
            if wanted.isEmpty { break }
        }
        return lines
    }

    private func addExercise(_ exercise: Exercise) {
        let entry = SessionExercise(order: session.exercises.count, exercise: exercise)
        context.insert(entry)
        session.exercises.append(entry)
        PersistenceErrorCenter.shared.save(context, operation: "Adding the exercise")
    }

    /// One tap mid-session: apply the shared drop plan (core parity) — only
    /// not-yet-performed sets are touched, each dropped from its own weight.
    private func dropLoad(_ entry: SessionExercise, reason: AutoregReason) {
        let ordered = entry.orderedSets
        let bar = entry.barID.map { Bar.by(id: $0) } ?? gym?.defaultBar ?? .bar45lb
        // The configured drop derives from the MAIN work set. Ramp/backoff
        // blocks can precede or trail it at lighter loads (5/3/1, max effort),
        // so match the work block, not just the first non-warmup set.
        let firstPlannedWork = ordered.first { !$0.isWarmup && $0.status == .planned && $0.prescriptionBlock == .work }
            ?? ordered.first { !$0.isWarmup && $0.status == .planned }
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
        entry.notes += (entry.notes.isEmpty ? "" : " ") + "Dropped to \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: top)) — \(reason.rawValue)."
        PersistenceErrorCenter.shared.save(context, operation: "Dropping the load")
    }
}

/// Smart per-exercise rest via the shared CadenceCore precedence (per-exercise
/// rest → program role → movementGroup bucket); no exercise → accessory bucket.
private func smartRestSeconds(for exercise: Exercise?, role: String? = nil, settings: AppSettings?) -> Int {
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

// MARK: - Exercise section

private struct ExerciseSection: View {
    @Environment(\.modelContext) private var context
    @Environment(RestTimer.self) private var restTimer

    @Bindable var entry: SessionExercise
    // Passed down from ActiveSessionView (which already queries them) — a
    // per-section @Query would register one redundant fetch per exercise.
    let settings: AppSettings?
    let gym: Gym?
    let allExercises: [Exercise]
    /// Previous-performance context, or nil for a first-ever lift.
    let lastTime: String?
    let onDropLoad: () -> Void
    /// Marks this exercise as the one being actively worked (drives the bottom bar).
    let onWork: (SessionExercise) -> Void
    /// Remove this exercise from the session (session-only, like a swap — the
    /// program slot is untouched and just isn't performed today).
    let onRemove: () -> Void

    /// How long a swap outlives this session (issue 20). Session-only is the
    /// default: the program slot is untouched and simply isn't performed today
    /// (on a peak day the existing skipped-peak rule applies — the honest
    /// grade for substituted work). Cycle renames the slot and reverts it at
    /// the next rollover; program renames it for good.
    enum SwapScope { case session, cycle, program }

    /// Same-movement-pattern lifts you can swap in, constrained to the same
    /// programming tier and loadability, excluding shelved (SwapRules in
    /// CadenceCore — no more Walking Lunges → Back Squat or DB Press → Dips).
    private var alternatives: [Exercise] {
        guard let cur = entry.exercise else { return [] }
        return allExercises.filter {
            SwapRules.compatible(
                currentName: cur.name, currentCategory: cur.categoryRaw,
                currentType: cur.typeRaw, currentGroup: cur.movementGroup,
                candidateName: $0.name, candidateCategory: $0.categoryRaw,
                candidateType: $0.typeRaw, candidateGroup: $0.movementGroup,
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
            guard let day = program.days.first(where: { $0.order == dayIndex }) else {
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
                               enteredUnit: settings?.unitDisplay.primaryUnit ?? .lb,
                               context: context)
        }
    }

    private func fetchProgram(id: String?, named name: String?) throws -> Program? {
        let programs = try context.fetch(FetchDescriptor<Program>())
        return id.flatMap { stableID in programs.first { $0.id == stableID } }
            ?? programs.first { $0.name == name }
    }

    /// A nil override follows the selected gym's default. Explicit choices are
    /// stored on the session exercise so they survive navigation and relaunch.
    private var effectiveBar: Bar { entry.barID.map { Bar.by(id: $0) } ?? gym?.defaultBar ?? .bar45lb }

    /// A picked swap for a program slot, awaiting its scope (issue 20).
    /// Standalone entries skip the dialog — with no slot, session-only is the
    /// only meaning a swap can have.
    @State private var pendingSwap: Exercise?

    private var restSeconds: Int { smartRestSeconds(for: entry.exercise, role: entry.programRole, settings: settings) }
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

    var body: some View {
        Section {
            ForEach(entry.orderedSets) { set in
                // The set you're ON — the first WORKING set with no verdict
                // yet. Warmups sit quiet (and often go unflagged, so they must
                // not hold the rail hostage).
                let isCurrent = entry.orderedSets.first { !$0.isWarmup && $0.status == .planned }?.persistentModelID == set.persistentModelID
                VStack(alignment: .leading, spacing: 4) {
                    SetRow(set: set, entry: entry, exercise: entry.exercise, gym: gym, bar: effectiveBar, isCurrent: isCurrent,
                           targetLb: set.plannedWeightLb ?? entry.plannedWeightLb, onLogged: {
                        onWork(entry)
                        // Auto-start only if the user opted in (manual is the
                        // default), and never restart a countdown already running.
                        if settings?.autoStartRest == true && !restTimer.isRunning {
                            restTimer.start(seconds: set.isWarmup ? 60 : restSeconds,
                                            exerciseName: entry.exercise?.name ?? "")
                        }
                    }, onRemove: { removeSet(set) })
                    // Loadout visualization — plates for barbell lifts, the
                    // rack number for dumbbell lifts. Mirrors web.
                    if entry.exercise?.type == .barbell && set.weightLb > 0 {
                        BarbellView(weightLb: set.weightLb, unit: set.enteredUnit,
                                    bar: effectiveBar, gym: gym,
                                    targetWeightLb: set.targetWeightLb ?? entry.targetWeightLb)
                    } else if entry.exercise?.type == .dumbbell && set.weightLb > 0 {
                        DumbbellView(weightLb: set.weightLb, unit: set.enteredUnit)
                    }
                }
            }
            .onDelete { offsets in
                let ordered = entry.orderedSets
                for index in offsets.sorted(by: >) { removeSet(ordered[index], save: false) }
                PersistenceErrorCenter.shared.save(context, operation: "Deleting the set")
            }

            HStack {
                Button {
                    onWork(entry)
                    addSet()
                } label: {
                    Label("Set", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    onWork(entry)
                    if let last = entry.orderedSets.last(where: { !$0.isWarmup }) ?? entry.orderedSets.last {
                        removeSet(last)
                    }
                } label: {
                    Label("Set", systemImage: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(entry.sets.isEmpty)

                Button {
                    onWork(entry)
                    restTimer.start(seconds: restSeconds, exerciseName: entry.exercise?.name ?? "")
                } label: {
                    Label("Rest", systemImage: "timer")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    onDropLoad()
                } label: {
                    Label("Dropping load", systemImage: "arrow.down.right")
                }
                .buttonStyle(.bordered)
                .tint(Theme.warn)
            }

            if entry.exercise?.type == .barbell {
                Picker("Bar", selection: Binding(
                    get: { effectiveBar },
                    set: {
                        entry.barID = $0.id
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
                Text(entry.exercise?.name ?? "Exercise")
                if let phase = entry.phase {
                    Text(phase.label).foregroundStyle(Theme.accent)
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
    }

    private func addSet() {
        let last = entry.orderedSets.last
        let isTimed = entry.exercise?.type == .timed || entry.exercise?.type == .conditioning
        let set = SetEntry(
            order: entry.sets.count,
            weightLb: isTimed ? 0 : (last?.weightLb ?? entry.plannedWeightLb ?? 45),
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
}

/// Keep the editable prescription and its equipment illustration on the same
/// bar context without discarding status/quality already logged on matching
/// warmup rows.
private func synchronizeWarmups(_ entry: SessionExercise, workingLb overrideWorkingLb: Double? = nil,
                                bar: Bar, gym: Gym?,
                                enteredUnit: WeightUnit, context: ModelContext) {
    guard let exercise = entry.exercise,
          let workingLb = overrideWorkingLb ?? entry.plannedWeightLb
            ?? entry.orderedSets.first(where: { !$0.isWarmup })?.weightLb,
          workingLb > 0 else { return }
    let desired: [WarmupSet]
    if exercise.type == .barbell {
        desired = ProgramSession.achievableWarmups(
            WarmupRamp.ramp(workingLb: workingLb, barLb: bar.lb,
                            roundingLb: ProgramEngine.defaultRoundingLb),
            workingLb: workingLb, gym: gym, bar: bar)
    } else if exercise.type == .dumbbell && entry.programRole == LiftRole.main.rawValue {
        desired = WarmupRamp.dumbbellRamp(workingLb: workingLb,
                                          roundingLb: ProgramEngine.loadStep(
                                            programRoundingLb: ProgramEngine.defaultRoundingLb,
                                            exerciseType: exercise.typeRaw))
    } else {
        return
    }
    let existing = entry.orderedSets.filter(\.isWarmup)
    var rebuilt: [SetEntry] = []
    for (index, target) in desired.enumerated() {
        if index < existing.count {
            existing[index].weightLb = target.weightLb
            existing[index].reps = target.reps
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
        for set in existing.dropFirst(desired.count) { context.delete(set) }
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
                    // Cardio uses the shared CadenceCore formatter; lifts show
                    // weight in the unit used for entry.
                    Text(isCardio
                         ? CardioFormat.setLabel(distanceMiles: set.distanceMiles,
                                                 durationSeconds: set.durationSeconds,
                                                 inclinePercent: set.inclinePercent)
                         : (isTimed ? CardioFormat.durationLabel(seconds: set.durationSeconds ?? 0) : weightLabel))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(set.isWarmup ? .secondary : .primary)
                    HStack(spacing: 6) {
                        if !isCardio && !isTimed {
                            Text("× \(set.reps)\(set.isPerSide ? "/side" : "")")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else if isCardio {
                            Text("tap to log distance · time · incline")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("tap to adjust hold time")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
        .sheet(isPresented: $showDetail) {
            if isCardio {
                CardioSetSheet(set: set, onDelete: onRemove)
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

/// Conditioning-type work logs distance, time, and incline; speed falls out.
/// Small deliberate steps for each field — content hoisted into plain
/// rows to stay inside the type-checker's budget (see CompileRegressionTests).
private struct CardioSetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: SetEntry
    let onDelete: () -> Void

    // `self.` keeps the parser from reading `set` as a setter declaration
    // (the type has a property named `set` — see CompileRegressionTests).
    private var miles: Double { self.set.distanceMiles ?? 0 }
    private var secs: Int { self.set.durationSeconds ?? 0 }
    private var incline: Double { self.set.inclinePercent ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Distance: \(miles > 0 ? "\(Weight.trim(miles, decimals: 2)) mi" : "—")",
                            value: Binding(get: { miles }, set: { set.distanceMiles = $0 > 0 ? $0 : nil }),
                            in: 0...100, step: 0.25)
                    distanceTypeRow
                    Stepper("Time: \(secs > 0 ? CardioFormat.durationLabel(seconds: secs) : "—")",
                            value: Binding(get: { secs }, set: { set.durationSeconds = $0 > 0 ? $0 : nil }),
                            in: 0...36000, step: 60)
                    Stepper("Incline: \(incline > 0 ? "\(Weight.trim(incline))%" : "—")",
                            value: Binding(get: { incline }, set: { set.inclinePercent = $0 > 0 ? $0 : nil }),
                            in: 0...30, step: 0.5)
                } header: {
                    Text("Distance · time · incline")
                } footer: {
                    if let mph = CardioFormat.speedMph(distanceMiles: set.distanceMiles, durationSeconds: set.durationSeconds) {
                        Text("Speed: \(Weight.trim(mph)) mph")
                    }
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

    /// Exact distance entry for values the 0.25 steps don't land.
    private var distanceTypeRow: some View {
        HStack {
            Text("Type distance").foregroundStyle(.secondary)
            Spacer()
            TextField("miles", text: Binding(
                get: { miles == 0 ? "" : Weight.trim(miles, decimals: 2) },
                set: {
                    if let v = Double($0.replacingOccurrences(of: ",", with: ".")), v > 0 { set.distanceMiles = v }
                    else if $0.isEmpty { set.distanceMiles = nil }
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
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: statusIcon(set.status))
                    .font(.title3)
                if let quality = set.quality, quality != .clean {
                    Text(quality == .grindy ? "G" : "W")
                        .font(.caption2.bold())
                        .padding(2)
                        .background(Theme.warn, in: Circle())
                        .foregroundStyle(.black)
                        .offset(x: 6, y: -6)
                }
            }
                .frame(width: 48, height: 48)
                .background(statusColor(set.status).opacity(set.status == .planned ? 0.12 : 0.30),
                            in: RoundedRectangle(cornerRadius: 8))
        } primaryAction: {
            apply(set.status == .completed ? .planned : .completed)
        }
        .accessibilityLabel("Set status")
        .accessibilityValue(statusLabel(set.status))
        .accessibilityHint("Tap to complete or undo. Touch and hold for skipped and quality options.")
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
                        BarbellView(weightLb: lb, unit: unit, bar: bar, gym: gym)
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
                applyRepsToRemaining = !set.isWarmup && set.status == .planned
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
    let sessionStart: Date
    let pausedAt: Date?
    let restLabel: String
    let restSeconds: Int

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
                TimelineView(.periodic(from: sessionStart, by: 1)) { timeline in
                    Label(elapsedLabel(at: pausedAt ?? timeline.date),
                          systemImage: pausedAt == nil ? "stopwatch" : "pause.fill")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        mmss(max(0, Int(date.timeIntervalSince(sessionStart))))
    }
}

// MARK: - Exercise picker

private struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    let onPick: (Exercise) -> Void

    private var visible: [Exercise] {
        search.isEmpty ? exercises : exercises.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.movementGroup.localizedCaseInsensitiveContains(search)
                || $0.typeRaw.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(visible.filter { $0.category == category }) { exercise in
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
                        }
                    }
                }
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Exercise, movement, or equipment")
        }
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
                                 ? "Top: \(line.topSetLabel) · Volume: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: line.volumeLb))"
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
