import SwiftUI
import SwiftData
import CadenceCore

/// The exercise library. Shelved lifts stay visible — with the re-entry
/// test spelled out — so coming back to them is a decision, not an accident.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showNewExercise = false

    private var visibleExercises: [Exercise] {
        guard !search.isEmpty else { return exercises }
        return exercises.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.movementGroup.localizedCaseInsensitiveContains(search)
                || $0.movementPattern.name.localizedCaseInsensitiveContains(search)
                || $0.typeRaw.localizedCaseInsensitiveContains(search)
                || $0.aliases.contains(where: { $0.localizedCaseInsensitiveContains(search) })
                || $0.strategyTags.contains(where: { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        List {
            ForEach(ExerciseCategory.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(visibleExercises.filter { $0.category == category }) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                    Text("\(exercise.movementPattern.name) · \(exercise.typeRaw) · \(exercise.loadBasis.label)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if exercise.isShelved {
                                    Text(Copy.shelved)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.hardStop.opacity(0.25), in: Capsule())
                                        .foregroundStyle(Theme.hardStop)
                                }
                                if exercise.isUnilateral {
                                    Text("per side").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Exercise, movement, or equipment")
        .toolbar {
            Button { showNewExercise = true } label: {
                Label("New exercise", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showNewExercise) { NewExerciseView() }
    }
}

/// Detail by name, for callers that hold only an exercise name (program
/// editor rows). Falls back gracefully if the name left the library.
struct ExerciseDetailByNameView: View {
    let name: String
    @Query private var exercises: [Exercise]

    var body: some View {
        if let exercise = exercises.first(where: { $0.name == name }) {
            ExerciseDetailView(exercise: exercise)
        } else {
            ContentUnavailableView("Not in the library", systemImage: "questionmark.circle",
                                   description: Text(name))
        }
    }
}

struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var exercise: Exercise
    @Query private var programs: [Program]
    @Query private var settingsList: [AppSettings]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted },
           sort: \WorkoutSession.date, order: .reverse)
    private var completed: [WorkoutSession]

    private var profile: AnatomyData.Profile? {
        AnatomyData.muscleProfile(name: exercise.name, movementGroup: exercise.movementGroup)
    }

    /// "Program · Day (role)" for every slot this exercise fills.
    private var memberships: [String] {
        var out: [String] = []
        for p in programs {
            for d in p.orderedDays {
                for l in d.orderedLifts where l.exerciseName == exercise.name {
                    out.append("\(p.name) · \(d.name) (\(l.roleRaw))")
                }
                for a in d.accessories where a.exerciseName == exercise.name {
                    out.append("\(p.name) · \(d.name) (accessory)")
                }
            }
        }
        return out
    }

    /// Compact previous-performance context from the newest completed session
    /// containing this exercise.
    private var lastDoneLabel: String {
        for s in completed {
            let matching = s.exercises.filter { $0.exercise?.name == exercise.name }
            if exercise.type == .timed,
               let longest = matching.flatMap(\.workingSets).compactMap(\.durationSeconds).max() {
                let program = s.programName.map { " · \($0)" } ?? ""
                return "\(s.date.formatted(date: .abbreviated, time: .omitted)) — \(CardioFormat.durationLabel(seconds: longest))\(program)"
            }
            guard let top = matching.flatMap(\.workingSets).max(by: { $0.weightLb < $1.weightLb }) else { continue }
            let program = s.programName.map { " · \($0)" } ?? ""
            return "\(s.date.formatted(date: .abbreviated, time: .omitted)) — \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: top.weightLb)) × \(top.reps)\(program)"
        }
        return "Not yet"
    }

    /// Top-set weight per session, oldest→newest, capped to the last 24.
    private var topSetSeries: [Double] {
        var recent: [Double] = []
        for s in completed {
            let matching = s.exercises.filter { $0.exercise?.name == exercise.name }
            guard let top = matching.flatMap(\.workingSets).max(by: { $0.weightLb < $1.weightLb }) else { continue }
            recent.append(top.weightLb)
            if recent.count == 24 { break }
        }
        return recent.reversed()
    }

    var body: some View {
        Form {
            if let profile {
                Section("Muscles — primary in red, supporting in blue") {
                    AnatomyFigureView(profile: profile)
                        .frame(maxWidth: 300)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    Text(AnatomyData.blurb(profile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("History") {
                LabeledContent("Last done") {
                    Text(lastDoneLabel).multilineTextAlignment(.trailing)
                }
                if exercise.type != .timed && topSetSeries.count >= 2 {
                    LabeledContent("Top set, last \(topSetSeries.count)") {
                        SparklineView(values: topSetSeries)
                            .frame(width: 132, height: 30)
                    }
                }
            }

            Section("In programs") {
                if memberships.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(memberships, id: \.self) { Text($0) }
                }
            }

            Section {
                Picker("Category", selection: Binding(
                    get: { exercise.category },
                    set: { exercise.category = $0 }
                )) {
                    ForEach(ExerciseCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Type", selection: Binding(
                    get: { exercise.type },
                    set: { exercise.type = $0 }
                )) {
                    ForEach(ExerciseType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Movement group", text: $exercise.movementGroup)
                    .textInputAutocapitalization(.never)
                Picker("Movement pattern", selection: Binding(
                    get: { exercise.movementPattern },
                    set: { exercise.movementPattern = $0 }
                )) {
                    ForEach(MovementPattern.allCases, id: \.self) { pattern in
                        Text(pattern.name).tag(pattern)
                    }
                }
                TextField("Aliases, comma-separated", text: Binding(
                    get: { exercise.aliases.joined(separator: ", ") },
                    set: { exercise.aliases = Self.splitList($0) }
                ))
                TextField("Strategy tags, comma-separated", text: Binding(
                    get: { exercise.strategyTags.joined(separator: ", ") },
                    set: { exercise.strategyTags = Self.splitList($0) }
                ))
                Toggle("Unilateral (log per side)", isOn: $exercise.isUnilateral)
                Picker("Load means", selection: Binding(
                    get: { exercise.loadBasis },
                    set: { exercise.loadBasis = $0 }
                )) {
                    ForEach(LoadBasis.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if exercise.loadBasis == .perImplement {
                    Stepper("Implements used: \(exercise.resolvedImplementCount)", value: Binding(
                        get: { exercise.resolvedImplementCount },
                        set: { exercise.implementCount = $0 }
                    ), in: 1...4)
                }
                // 0 = no rest of its own → the timer falls to the configurable
                // rest buckets in Settings; any value set here wins everywhere.
                Stepper(
                    exercise.defaultRestSeconds == 0
                        ? "Rest: default (Settings)"
                        : "Rest: \(exercise.defaultRestSeconds / 60):\(String(format: "%02d", exercise.defaultRestSeconds % 60))",
                    value: $exercise.defaultRestSeconds, in: 0...600, step: 15
                )
            }

            Section("Watch site") {
                Picker("Body site", selection: Binding(
                    get: { exercise.watchSite },
                    set: { exercise.watchSite = $0 }
                )) {
                    Text("None").tag(BodySite?.none)
                    ForEach(BodySite.allCases) { site in
                        Text(site.rawValue).tag(BodySite?.some(site))
                    }
                }
            }

            Section {
                Picker("Gate", selection: Binding(
                    get: { exercise.gateStatus },
                    set: { exercise.gateStatus = $0 }
                )) {
                    ForEach(ExerciseGateStatus.allCases, id: \.self) { status in
                        Text(status.name).tag(status)
                    }
                }
                if exercise.gateStatus != .open {
                    Picker("Site", selection: Binding(
                        get: { exercise.gateSite },
                        set: { exercise.gateSite = $0 }
                    )) {
                        Text("None").tag(BodySite?.none)
                        ForEach(BodySite.allCases) { site in Text(site.rawValue).tag(BodySite?.some(site)) }
                    }
                    TextField("Coach note", text: $exercise.shelvedNote, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Re-entry criteria — one per line", text: Binding(
                        get: { exercise.reEntryCriteria.joined(separator: "\n") },
                        set: { exercise.reEntryCriteria = Self.splitLines($0) }
                    ), axis: .vertical)
                    ForEach(exercise.reEntryCriteria, id: \.self) { criterion in
                        Toggle(criterion, isOn: Binding(
                            get: { exercise.completedReEntryCriteria.contains(criterion) },
                            set: { complete in
                                if complete, !exercise.completedReEntryCriteria.contains(criterion) {
                                    exercise.completedReEntryCriteria.append(criterion)
                                } else if !complete {
                                    exercise.completedReEntryCriteria.removeAll { $0 == criterion }
                                }
                                if exercise.reEntryCriteriaComplete { exercise.gateStatus = .reEntry }
                            }
                        ))
                    }
                    if exercise.reEntryCriteriaComplete || exercise.gateStatus == .reEntry {
                        Stepper("Test: \(exercise.reEntryTestSets) × \(exercise.reEntryTestReps)",
                                value: $exercise.reEntryTestSets, in: 1...8)
                        Stepper("Test reps: \(exercise.reEntryTestReps)",
                                value: $exercise.reEntryTestReps, in: 1...12)
                        Stepper("Test load: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: exercise.reEntryTestWeightLb))",
                                value: $exercise.reEntryTestWeightLb, in: 0...1000, step: 5)
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                if exercise.gateStatus == .shelved {
                    Text("Stays in the library and out of new programs until its user-defined re-entry criteria pass.")
                }
            }

            Section("Notes") {
                TextField("Notes", text: $exercise.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle(exercise.name)
        .saveChangesOnDisappear(context, operation: "Saving the exercise")
    }

    private static func splitList(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

private struct NewExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]

    @State private var name = ""
    @State private var category: ExerciseCategory = .accessory
    @State private var type: ExerciseType = .dumbbell
    @State private var movementGroup = ""
    @State private var movementPattern: MovementPattern = .unknown
    @State private var isUnilateral = false
    @State private var notes = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !trimmedName.isEmpty && !exercises.contains { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Type", selection: $type) {
                        ForEach(ExerciseType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Movement group (press, pull, squat…)", text: $movementGroup)
                        .textInputAutocapitalization(.never)
                    Picker("Movement pattern", selection: $movementPattern) {
                        ForEach(MovementPattern.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    Toggle("Unilateral (log per side)", isOn: $isUnilateral)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if !trimmedName.isEmpty && !canSave {
                    Section { Text("An exercise with this name already exists.").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let exercise = Exercise(name: trimmedName, category: category, type: type,
                                                movementGroup: movementGroup.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                                movementPattern: movementPattern == .unknown ? nil : movementPattern,
                                                isUnilateral: isUnilateral, notes: notes)
                        context.insert(exercise)
                        if PersistenceErrorCenter.shared.save(context, operation: "Adding the exercise") { dismiss() }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
