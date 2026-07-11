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
    @Query private var settingsList: [AppSettings]
    @Query private var gyms: [Gym]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @Bindable var session: WorkoutSession
    @State private var showExercisePicker = false
    @State private var autoregEntry: SessionExercise?
    @State private var summary: SessionSummary?
    @State private var sessionStart = Date()            // session stopwatch origin (ephemeral)
    @State private var currentEntry: SessionExercise?   // the exercise you're actively working
    @State private var banking = false                  // double-tap on Bank it would run completion twice

    private var currentOrFirst: SessionExercise? { currentEntry ?? session.orderedExercises.first }
    private var gym: Gym? { gyms.first { $0.isDefault } ?? gyms.first }

    var body: some View {
        List {
            ForEach(session.orderedExercises) { entry in
                ExerciseSection(
                    entry: entry,
                    settings: settingsList.first,
                    gym: gym,
                    allExercises: allExercises,
                    onDropLoad: { autoregEntry = entry },
                    onWork: { currentEntry = $0 }
                )
            }

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
                    guard !banking else { return }
                    banking = true
                    summary = SessionCompletion.finish(session, context: context, startedAt: sessionStart)
                    restTimer.stop() // the workout is over; don't fire "Rest over" for a banked session
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
                restLabel: currentOrFirst?.exercise?.name ?? "",
                restSeconds: smartRestSeconds(for: currentOrFirst?.exercise, role: currentOrFirst?.programRole, settings: settingsList.first)
            )
        }
        .onChange(of: settingsList.first?.haptics, initial: true) { _, on in restTimer.hapticsEnabled = on ?? true }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Later") { dismiss() }
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

    private func addExercise(_ exercise: Exercise) {
        let entry = SessionExercise(order: session.exercises.count, exercise: exercise)
        entry.session = session
        context.insert(entry)
        session.exercises.append(entry)
        try? context.save()
    }

    /// One tap mid-session: apply the shared drop plan (core parity) — only
    /// not-yet-performed sets are touched, each dropped from its own weight.
    private func dropLoad(_ entry: SessionExercise, reason: AutoregReason) {
        let ordered = entry.orderedSets
        let plan = ProgramEngine.dropLoadPlan(
            sets: ordered.map { (weightLb: $0.weightLb, isWarmup: $0.isWarmup, isFlagged: !$0.flags.isEmpty) }
        )
        guard !plan.isEmpty else { return }
        for (i, target) in plan.enumerated() {
            ordered[target.index].weightLb = target.weightLb
            if i == 0 { ordered[target.index].autoregReason = reason }
        }
        let top = plan.map(\.weightLb).max() ?? 0
        entry.notes += (entry.notes.isEmpty ? "" : " ") + "Dropped to \(Weight.trim(top)) — \(reason.rawValue)."
        try? context.save()
    }
}

/// Smart per-exercise rest by category/movement (shared CadenceCore logic);
/// accessories fall back to the accessory setting, then 90s.
private func smartRestSeconds(for exercise: Exercise?, role: String? = nil, settings: AppSettings?) -> Int {
    guard let ex = exercise else { return 90 }
    return RestDefaults.seconds(category: ex.categoryRaw, name: ex.name, role: role,
                                config: settings?.restConfig ?? .standard,
                                exerciseDefaultRest: ex.defaultRestSeconds)
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
    let onDropLoad: () -> Void
    /// Marks this exercise as the one being actively worked (drives the bottom bar).
    let onWork: (SessionExercise) -> Void

    /// Same-movement-pattern lifts you can swap in (all presses, squat/hinge
    /// variants, the oly lifts). Empty group ⇒ no swaps offered.
    private var alternatives: [Exercise] {
        guard let g = entry.exercise?.movementGroup, !g.isEmpty else { return [] }
        return allExercises.filter { $0.movementGroup == g && $0.name != entry.exercise?.name }
    }

    private func swap(to newExercise: Exercise) {
        let oldName = entry.exercise?.name
        // If this section fills a program slot, repoint the slot at the lift
        // you're actually doing. Completion matches program lifts/accessories
        // by name+role, so without this the swapped lift wouldn't be graded and
        // the original would be treated as a missed peak (false stall/deload) at
        // rollover. The slot keeps its progression state as the starting load.
        if let role = entry.programRole, let name = entry.session?.programName,
           let program = fetchProgram(named: name),
           let day = program.days.first(where: { $0.order == (entry.session?.programDayIndex ?? 0) }) {
            if role == "accessory" {
                day.accessories.first { $0.exerciseName == oldName }?.exerciseName = newExercise.name
            } else {
                day.lifts.first { $0.exerciseName == oldName && $0.roleRaw == role }?.exerciseName = newExercise.name
            }
        }
        entry.exercise = newExercise
        entry.sets.forEach { $0.isPerSide = newExercise.isUnilateral }
        try? context.save()
        onWork(entry)
    }

    private func fetchProgram(named name: String) -> Program? {
        let n = name // hoist: #Predicate can't read a captured property
        return (try? context.fetch(FetchDescriptor<Program>(predicate: #Predicate { $0.name == n })))?.first
    }

    /// Ephemeral bar choice for this exercise (mirrors the web logger's
    /// per-exercise bar select, which is equally sticky once touched). Starts
    /// out tracking the gym's default bar; a pick — including re-picking the
    /// default, a value-identical Bar — pins it for this screen's lifetime.
    @State private var pickedBar: Bar?
    private var effectiveBar: Bar { pickedBar ?? gym?.defaultBar ?? .bar45lb }

    private var restSeconds: Int { smartRestSeconds(for: entry.exercise, role: entry.programRole, settings: settings) }
    private var restBinding: Binding<Int> {
        Binding(get: { restSeconds },
                set: { entry.exercise?.defaultRestSeconds = $0; try? context.save() })
    }
    // Stepper floor: writing 0 clears the override, and the stepper displays
    // the EFFECTIVE rest — so 0 is only offered where clearing lands on 0
    // (conditioning, or a bucket the user zeroed); elsewhere a decrement to 0
    // would snap the display up to the movement default. Same role + config as
    // the effective rest (mirrors web editRest's floor).
    private var restFloor: Int {
        guard let ex = entry.exercise else { return 15 }
        return RestDefaults.seconds(category: ex.categoryRaw, name: ex.name, role: entry.programRole,
                                    config: settings?.restConfig ?? .standard) == 0 ? 0 : 15
    }

    var body: some View {
        Section {
            ForEach(entry.orderedSets) { set in
                VStack(alignment: .leading, spacing: 4) {
                    SetRow(set: set, exercise: entry.exercise, gym: gym, bar: effectiveBar,
                           targetLb: entry.plannedWeightLb, onLogged: {
                        onWork(entry)
                        // Auto-start only if the user opted in (manual is the
                        // default), and never restart a countdown already running.
                        if settings?.autoStartRest == true && !restTimer.isRunning {
                            restTimer.start(seconds: set.isWarmup ? 60 : restSeconds,
                                            exerciseName: entry.exercise?.name ?? "")
                        }
                    })
                    // Barbell plate visualization (barbell lifts only) — mirrors web.
                    if entry.exercise?.type == .barbell && set.weightLb > 0 {
                        BarbellView(weightLb: set.weightLb, unit: set.enteredUnit, bar: effectiveBar, gym: gym)
                    }
                }
            }
            .onDelete { offsets in
                let ordered = entry.orderedSets
                for index in offsets { context.delete(ordered[index]) }
                try? context.save()
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
                Picker("Bar", selection: Binding(get: { effectiveBar }, set: { pickedBar = $0 })) {
                    ForEach(Bar.all) { Text($0.label).tag($0) }
                }
                .font(.caption)
            }

            Stepper("Rest between sets: \(mmss(restSeconds))", value: restBinding, in: restFloor...600, step: 15)
                .font(.caption)
        } header: {
            HStack {
                Text(entry.exercise?.name ?? "Exercise")
                if let phase = entry.phase {
                    Text(phase.label).foregroundStyle(Theme.accent)
                }
                if entry.exercise?.isShelved == true {
                    Text(Copy.shelved).foregroundStyle(Theme.hardStop)
                }
                Spacer()
                if !alternatives.isEmpty {
                    Menu {
                        ForEach(alternatives) { alt in
                            Button(alt.name) { swap(to: alt) }
                        }
                    } label: {
                        Label("Swap", systemImage: "arrow.left.arrow.right")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Theme.accent)
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
        let set = SetEntry(
            order: entry.sets.count,
            weightLb: last?.weightLb ?? entry.plannedWeightLb ?? 45,
            reps: last?.reps ?? entry.plannedReps ?? 5,
            isPerSide: entry.exercise?.isUnilateral ?? false
        )
        set.sessionExercise = entry
        context.insert(set)
        entry.sets.append(set)
        try? context.save()
    }
}

// MARK: - Set row

private struct SetRow: View {
    @Bindable var set: SetEntry
    let exercise: Exercise?
    let gym: Gym?
    let bar: Bar
    /// The program/track weight this session recommends — the picker anchors here.
    let targetLb: Double?
    var onLogged: () -> Void

    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 12) {
            // Weight, shown in the unit it was entered in.
            Button {
                showDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weightLabel)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(set.isWarmup ? .secondary : .primary)
                    HStack(spacing: 6) {
                        Text("× \(set.reps)\(set.isPerSide ? "/side" : "")")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if set.isWarmup {
                            Text("warmup").font(.caption2).foregroundStyle(.secondary)
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

            // Quality flags: one thumb-tap each.
            ForEach([SetFlag.clean, .grindy, .wobble], id: \.self) { flag in
                FlagToggle(set: set, flag: flag, onLogged: onLogged)
            }
        }
        .sheet(isPresented: $showDetail) {
            SetDetailSheet(set: set, exercise: exercise, gym: gym, bar: bar, targetLb: targetLb)
                .presentationDetents([.large])
        }
    }

    private var weightLabel: String {
        if set.weightLb == 0 { return "BW" }
        switch set.enteredUnit {
        case .lb: return "\(Weight.trim(set.weightLb)) lb"
        case .kg: return "\(Weight.trim(Weight.kg(fromLb: set.weightLb))) kg"
        }
    }
}

private struct FlagToggle: View {
    @Bindable var set: SetEntry
    let flag: SetFlag
    var onLogged: () -> Void

    // `self.` keeps the parser from reading `set` as a setter declaration
    private var isOn: Bool { self.set.flags.contains(flag) }

    var body: some View {
        Button {
            var flags = set.flags
            if isOn {
                flags.removeAll { $0 == flag }
            } else {
                flags.append(flag)
                onLogged() // first flag = set done → arm rest timer
            }
            set.flags = flags
        } label: {
            Text(symbol)
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(isOn ? color.opacity(0.35) : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch flag {
        case .clean: return "✓"
        case .grindy: return "G"
        case .wobble: return "W"
        case .stoppedEarly: return "■"
        }
    }

    private var color: Color {
        switch flag {
        case .clean: return Theme.good
        case .grindy: return Theme.warn
        case .wobble: return Theme.warn
        case .stoppedEarly: return Theme.hardStop
        }
    }
}

// MARK: - Set detail (weight/reps/unit/body flag)

private struct SetDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: SetEntry
    let exercise: Exercise?
    let gym: Gym?
    let bar: Bar
    let targetLb: Double?

    // Edited live (canonical pounds) so the plate graphic tracks every tap;
    // committed on Done. Starts at the set's weight, which the program/track
    // pre-fills to this session's recommendation.
    @State private var lb: Double = 0
    @State private var unit: WeightUnit = .lb

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
                    Stepper("Reps: \(set.reps)", value: Bindable(set).reps, in: 0...100)
                    Toggle("Warmup", isOn: Bindable(set).isWarmup)
                    Toggle("Per side", isOn: Bindable(set).isPerSide)
                    Toggle("Stopped early", isOn: Binding(
                        get: { set.flags.contains(.stoppedEarly) },
                        set: { on in
                            var flags = set.flags
                            flags.removeAll { $0 == .stoppedEarly }
                            if on { flags.append(.stoppedEarly) }
                            set.flags = flags
                        }
                    ))
                }

                Section("Body flag") {
                    Picker("Site", selection: Bindable(set).bodyFlagSite) {
                        Text("None").tag(BodySite?.none)
                        ForEach(BodySite.allCases) { site in
                            Text(site.rawValue).tag(BodySite?.some(site))
                        }
                    }
                    if set.bodyFlagSite != nil {
                        TextField("What did it feel like?", text: Binding(
                            get: { set.bodyFlagNote ?? "" },
                            set: { set.bodyFlagNote = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }
            }
            .navigationTitle("Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        set.weightLb = lb       // stored canonically in lb
                        set.enteredUnit = unit
                        dismiss()
                    }
                }
            }
            .onAppear {
                unit = set.enteredUnit
                lb = set.weightLb
            }
        }
    }

    private func adjust(_ dir: Double) {
        lb = max(0, lb + dir * stepLb)
    }

    private func setUnit(_ newUnit: WeightUnit) {
        unit = newUnit // lb is canonical, so the readout just re-renders in the new unit
    }
}

// MARK: - Sticky bottom bar (session clock + rest)

/// Mirrors the web logger's #session-bar: session stopwatch on the left; while
/// resting, the countdown with +1:00 / Skip and a progress fill; when idle, a
/// Rest button for the lift you're working.
private struct SessionBottomBar: View {
    @Environment(RestTimer.self) private var restTimer
    let sessionStart: Date
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

            HStack(spacing: 12) {
                // Session stopwatch — always visible, with an icon so it reads
                // as a running clock.
                TimelineView(.periodic(from: sessionStart, by: 1)) { timeline in
                    Label(elapsedLabel(at: timeline.date), systemImage: "stopwatch")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if restTimer.isRunning {
                    VStack(alignment: .trailing, spacing: 0) {
                        if !restTimer.exerciseName.isEmpty {
                            Text("resting · \(restTimer.exerciseName)")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(restTimer.display)
                            .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                    Button {
                        restTimer.isPaused ? restTimer.resume() : restTimer.pause()
                    } label: { Image(systemName: restTimer.isPaused ? "play.fill" : "pause.fill") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(restTimer.isPaused ? "Resume rest" : "Pause rest")
                    Button("+1:00") { restTimer.add(seconds: 60) }
                        .buttonStyle(.bordered)
                    Button {
                        restTimer.stop()
                    } label: { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Skip rest")
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
    let onPick: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(exercises.filter { $0.category == category }) { exercise in
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
        }
    }
}

// MARK: - Summary

private struct SessionSummarySheet: View {
    let summary: SessionSummary
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    ForEach(summary.lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.exerciseName).font(.headline)
                            Text("Top: \(line.topSetLabel) · Volume: \(Weight.trim(line.volumeLb)) lb")
                                .font(.callout)
                                .foregroundStyle(.secondary)
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
