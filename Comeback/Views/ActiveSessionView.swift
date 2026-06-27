import SwiftUI
import SwiftData
import ComebackCore

/// The logger. Pre-filled from the plan; everything editable in place.
/// Autoregulation is one tap. Rest timer arms itself after each working set.
struct ActiveSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimer.self) private var restTimer

    @Bindable var session: WorkoutSession
    @State private var showExercisePicker = false
    @State private var autoregEntry: SessionExercise?
    @State private var summary: SessionSummary?

    var body: some View {
        List {
            if restTimer.isRunning {
                Section {
                    RestTimerBar()
                }
            }

            ForEach(session.orderedExercises) { entry in
                ExerciseSection(
                    entry: entry,
                    onDropLoad: { autoregEntry = entry }
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
                    summary = SessionCompletion.finish(session, context: context)
                } label: {
                    Text(Copy.sessionDone)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.bigTap - 16)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
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

    /// One tap mid-session: recalc remaining sets, log the reason.
    private func dropLoad(_ entry: SessionExercise, reason: AutoregReason) {
        let remaining = entry.workingSets.suffix(from: completedCount(entry))
        guard let current = remaining.first?.weightLb else { return }
        let dropped = ProgramEngine.droppedLoad(from: current)
        for (i, set) in remaining.enumerated() {
            set.weightLb = dropped
            if i == 0 { set.autoregReason = reason }
        }
        entry.notes += (entry.notes.isEmpty ? "" : " ") + "Dropped to \(Weight.trim(dropped)) — \(reason.rawValue)."
        try? context.save()
    }

    /// Heuristic: sets with any flag set are "done"; otherwise assume the
    /// drop applies from the first unflagged working set onward.
    private func completedCount(_ entry: SessionExercise) -> Int {
        entry.workingSets.prefix { !$0.flags.isEmpty }.count
    }
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
    @Query private var settingsList: [AppSettings]

    @Bindable var entry: SessionExercise
    let onDropLoad: () -> Void

    // Per-exercise rest, falling back to the global main/accessory defaults.
    private var restSeconds: Int {
        guard let ex = entry.exercise else { return 90 }
        if ex.defaultRestSeconds > 0 { return ex.defaultRestSeconds }
        let s = settingsList.first
        return ex.category == .main ? (s?.mainLiftRestSeconds ?? 300) : (s?.accessoryRestSeconds ?? 90)
    }
    private var restBinding: Binding<Int> {
        Binding(get: { restSeconds }, set: { entry.exercise?.defaultRestSeconds = $0 })
    }
    private func timeLabel(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    var body: some View {
        Section {
            ForEach(entry.orderedSets) { set in
                SetRow(set: set, onLogged: {
                    restTimer.start(seconds: set.isWarmup ? 60 : restSeconds,
                                    exerciseName: entry.exercise?.name ?? "")
                })
            }
            .onDelete { offsets in
                let ordered = entry.orderedSets
                for index in offsets { context.delete(ordered[index]) }
                try? context.save()
            }

            HStack {
                Button {
                    addSet()
                } label: {
                    Label("Set", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
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

            Stepper("Rest between sets: \(timeLabel(restSeconds))", value: restBinding, in: 0...600, step: 15)
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
            SetDetailSheet(set: set)
                .presentationDetents([.medium])
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

    @State private var weightText = ""
    @State private var unit: WeightUnit = .lb

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold())
                        Picker("", selection: $unit) {
                            Text("lb").tag(WeightUnit.lb)
                            Text("kg").tag(WeightUnit.kg)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                    }
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
                        commitWeight()
                        dismiss()
                    }
                }
            }
            .onAppear {
                unit = set.enteredUnit
                let display = unit == .lb ? set.weightLb : Weight.kg(fromLb: set.weightLb)
                weightText = Weight.trim(display, decimals: 2)
            }
        }
    }

    private func commitWeight() {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) else { return }
        set.weightLb = Weight.toLb(value, from: unit) // stored canonically in lb
        set.enteredUnit = unit
    }
}

// MARK: - Rest timer bar

struct RestTimerBar: View {
    @Environment(RestTimer.self) private var restTimer

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if !restTimer.exerciseName.isEmpty {
                    Text("Resting · \(restTimer.exerciseName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(restTimer.display)
                    .font(.system(size: 32, weight: .heavy, design: .rounded).monospacedDigit())
            }
            Spacer()
            Button("+30s") { restTimer.add(seconds: 30) }
                .buttonStyle(.bordered)
            Button("Skip") { restTimer.stop() }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            ProgressView(value: 1 - restTimer.progress)
                .tint(Theme.accent)
        }
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
