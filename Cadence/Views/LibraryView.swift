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
        let term = ExerciseSearch.preparedTerm(search)
        return exercises.filter { $0.matchesSearch(preparedTerm: term) }
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
    /// Present only when this pane is opened from the live logger. The pane
    /// then shows the resolved prescription and exact bar context instead of
    /// pretending the catalog knows today's work.
    var sessionEntry: SessionExercise? = nil
    var sessionGym: Gym? = nil
    var sessionProgramFocus: TrainingFocus? = nil
    @Query private var programs: [Program]
    @Query private var settingsList: [AppSettings]
    @Query private var gyms: [Gym]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted },
           sort: \WorkoutSession.date, order: .reverse)
    private var completed: [WorkoutSession]

    @State private var showAnatomy = true
    @State private var showProgramming = false
    @State private var showSetup = false
    @State private var showStatus = false
    @State private var showExpandedContextBar = false

    private var profile: AnatomyData.Profile? {
        AnatomyData.muscleProfile(name: exercise.name, movementGroup: exercise.movementGroup)
    }

    private var contextualSet: SetEntry? {
        guard let sessionEntry else { return nil }
        return sessionEntry.orderedSets.first { !$0.isWarmup && $0.status == .planned }
            ?? sessionEntry.orderedSets.last { !$0.isWarmup && $0.status == .completed }
            ?? sessionEntry.orderedSets.first
    }

    private var contextualBar: Bar {
        sessionEntry?.barID.map { Bar.by(id: $0) } ?? sessionGym?.defaultBar ?? .bar45lb
    }

    private var contextualSolution: PlateSolution? {
        guard exercise.type == .barbell, let set = contextualSet, set.weightLb > 0 else { return nil }
        return authoritativePlateSolution(
            targetLb: set.weightLb,
            fallbackUnit: set.enteredUnit,
            bar: contextualBar,
            gym: sessionGym,
            stationDenomination: exercise.stationDenomination
        )
    }

    private var contextualEffortCue: String? {
        guard let entry = sessionEntry,
              let role = entry.programRole.flatMap(LiftRole.init(rawValue:)),
              let style = PrescriptionStyle(rawValue: entry.prescriptionStyleRaw)
        else { return nil }
        guard style != .automatic || sessionProgramFocus != nil else { return nil }
        return ProgramEngine.complementaryEffortCue(
            role: role,
            prescriptionStyle: style,
            movementGroup: exercise.movementGroup,
            focus: sessionProgramFocus ?? .strength
        )
    }

    private var contextualTrainingRelationship: String? {
        guard let role = sessionEntry?.programRole.flatMap(LiftRole.init(rawValue:)) else { return nil }
        let relationship = role == .complementary ? "Complementary lift" : "Main lift"
        guard let sessionProgramFocus else { return relationship }
        return "\(relationship) · \(sessionProgramFocus.rawValue.capitalized) focus"
    }

    private struct CycleMembership: Identifiable {
        let program: Program
        let day: ProgramDay
        let lift: ProgramLift
        var id: String { "\(program.id):\(lift.id)" }
    }

    /// One traversal produces both the membership labels and the cycle rows —
    /// two properties walking the same programs→days→lifts filter is how the
    /// name-matching rule drifts. Mirrors web exerciseInsight's single loop.
    private var membershipData: (labels: [String], cycle: [CycleMembership]) {
        var labels: [String] = []
        var cycle: [CycleMembership] = []
        for program in programs {
            for day in program.orderedDays {
                for lift in day.orderedLifts where lift.exerciseName == exercise.name {
                    labels.append("\(program.name) · \(day.name) (\(lift.roleRaw))")
                    cycle.append(CycleMembership(program: program, day: day, lift: lift))
                }
                for accessory in day.accessories where accessory.exerciseName == exercise.name {
                    labels.append("\(program.name) · \(day.name) (accessory)")
                }
            }
        }
        return (labels, cycle)
    }

    private var defaultGym: Gym? { gyms.first(where: \.isDefault) ?? gyms.first }

    /// The shared preview pipeline; base, fallback sets, and the gym are
    /// phase-invariant, so the caller computes them once per membership
    /// instead of once per rotation row.
    private func cyclePlan(
        _ item: CycleMembership, phase: CyclePhase,
        planningBase: Double, addedVolumeSets: Int, gym: Gym?
    ) -> SessionPlan {
        ProgramSession.previewPlan(
            for: item.lift, exercise: exercise, program: item.program,
            phase: phase, planningBase: planningBase,
            addedVolumeSets: addedVolumeSets, gym: gym
        ).snapped
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
            return "\(s.date.formatted(date: .abbreviated, time: .omitted)) — \(settingsList.unitDisplay.format(lb: top.weightLb)) × \(top.reps)\(program)"
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
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Text(exercise.category.rawValue.uppercased())
                        Text(exercise.type.rawValue.uppercased())
                        if !exercise.movementGroup.isEmpty {
                            Text(exercise.movementGroup.replacingOccurrences(of: "_", with: " ").uppercased())
                        }
                    }
                    .font(.caption2.bold())
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                    if let set = contextualSet {
                        Text("CURRENT PRESCRIPTION")
                            .font(.caption.bold())
                            .tracking(0.8)
                            .foregroundStyle(Theme.accent)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(set.weightLb > 0 ? settingsList.unitDisplay.format(lb: set.weightLb) : "Bodyweight")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .monospacedDigit()
                            if exercise.type != .timed && exercise.type != .conditioning {
                                Text("× \(set.reps)")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Text(set.status == .planned ? "Next set" : "Most recent set")
                            if let entry = sessionEntry {
                                Text("· \(entry.plannedWorkingSets.filter { $0.status == .completed }.count)/\(entry.plannedWorkingSets.count) complete")
                            }
                            Text("· rest \(mmss(smartRestSeconds(for: exercise, role: sessionEntry?.programRole, settings: settingsList.first)))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let contextualTrainingRelationship {
                            Text(contextualTrainingRelationship)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("training-focus-context")
                        }
                        if let contextualEffortCue {
                            Text(contextualEffortCue)
                                .font(.callout.bold())
                                .foregroundStyle(Theme.accent)
                        }
                        if let contextualSolution {
                            let style: PlateVisualStyle = exercise.movementGroup == "olympic" ? .bumper : .steel
                            BarbellStageView(
                                solution: contextualSolution,
                                unit: set.enteredUnit,
                                plateStyle: style,
                                onExpand: { showExpandedContextBar = true }
                            )
                            LoadoutSummaryView(
                                requestedLb: set.targetWeightLb ?? sessionEntry?.targetWeightLb,
                                loadout: contextualSolution.loadout
                            )
                        }
                    }
                }
            }

            if let profile {
                Section {
                    DisclosureGroup(isExpanded: $showAnatomy) {
                        AnatomyFigureView(profile: profile)
                            .frame(maxWidth: 620)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Muscles worked").font(.headline)
                            Text(profile.primary.map { AnatomyData.muscleNames[$0] ?? $0 }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
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

            // One binding, one traversal: the computed property re-walks
            // programs→days→lifts on every access, and this body needs the
            // result four times.
            let data = membershipData
            let gym = defaultGym

            Section {
                DisclosureGroup(isExpanded: $showProgramming) {
                    if data.labels.isEmpty {
                        Text("Not currently used in a program.").foregroundStyle(.secondary)
                    } else {
                        Text("PROGRAM MEMBERSHIP")
                            .font(.caption.bold())
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        ForEach(data.labels, id: \.self) { Text($0) }
                    }

                    ForEach(data.cycle) { item in
                        // Base and fallback sets are phase-invariant: once
                        // per membership row, not once per rotation line.
                        let planningBase = ProgramSession.planningBase(
                            for: item.lift, exercise: exercise,
                            program: item.program, sessions: completed
                        )
                        let addedVolumeSets = ProgramSession.volumeFallbackSets(
                            for: item.lift, program: item.program
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(item.program.name) · \(item.day.name)")
                                .font(.subheadline.bold())
                            ForEach(CyclePhase.allCases, id: \.rawValue) { phase in
                                let plan = cyclePlan(item, phase: phase, planningBase: planningBase,
                                                     addedVolumeSets: addedVolumeSets, gym: gym)
                                let phaseLabel = ProgramEngine.slotPhaseLabel(
                                    rotation: phase.rawValue,
                                    role: item.lift.role,
                                    prescriptionStyle: item.lift.prescription,
                                    movementGroup: exercise.movementGroup,
                                    focus: item.program.focus
                                ) ?? "R\(phase.rawValue)"
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(phaseLabel).font(.caption.bold())
                                        Text(ProgramEngine.rotationContextLabel(
                                            rotation: phase.rawValue,
                                            currentRotation: item.program.currentWeek
                                        ))
                                            .font(.caption2)
                                            .foregroundStyle(
                                                phase.rawValue == item.program.currentWeek
                                                    ? Theme.accent : .secondary
                                            )
                                    }
                                    Spacer()
                                    Text(plan.weightLb > 0 ? settingsList.unitDisplay.format(lb: plan.weightLb) : "Bodyweight")
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text("\(plan.sets)×\(plan.reps)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Programming context").font(.headline)
                        Text(data.labels.isEmpty ? "No program assignment" : "\(data.labels.count) assignment\(data.labels.count == 1 ? "" : "s") · rotation details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showSetup) {
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
                    if exercise.type == .barbell {
                    // The station this lift lives at can stock a single plate
                    // denomination — a kg-only deadlift platform beside lb
                    // squat racks. The preference rides the exercise the same
                    // way its rest default does; prescriptions, warmups, and
                    // the plate hint all solve against the station's plates.
                        Picker("Station plates", selection: Binding(
                            get: { exercise.stationDenomination },
                            set: { exercise.stationDenomination = $0 }
                        )) {
                            Text("Gym inventory").tag(WeightUnit?.none)
                            Text("lb only").tag(WeightUnit?.some(.lb))
                            Text("kg only").tag(WeightUnit?.some(.kg))
                        }
                    }
                    Picker("Watch site", selection: Binding(
                        get: { exercise.watchSite },
                        set: { exercise.watchSite = $0 }
                    )) {
                        Text("None").tag(BodySite?.none)
                        ForEach(BodySite.allCases) { site in
                            Text(site.rawValue).tag(BodySite?.some(site))
                        }
                    }
                    TextField("Notes", text: $exercise.notes, axis: .vertical)
                        .lineLimit(2...6)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exercise setup").font(.headline)
                        Text("Classification, loading, rest and watch site")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showStatus) {
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
                            Stepper("Test load: \(settingsList.unitDisplay.format(lb: exercise.reEntryTestWeightLb))",
                                    value: $exercise.reEntryTestWeightLb, in: 0...1000, step: 5)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Availability & re-entry").font(.headline)
                        Text(exercise.gateStatus.name)
                            .font(.caption)
                            .foregroundStyle(exercise.gateStatus == .shelved ? Theme.hardStop : .secondary)
                    }
                }
            } footer: {
                if exercise.gateStatus == .shelved {
                    Text("Stays in the library and out of new programs until its user-defined re-entry criteria pass.")
                }
            }

        }
        .listStyle(.plain)
        .accessibilityIdentifier("exercise-detail-screen")
        .navigationTitle(exercise.name)
        .saveChangesOnDisappear(context, operation: "Saving the exercise")
        .sheet(isPresented: $showExpandedContextBar) {
            if let solution = contextualSolution {
                NavigationStack {
                    ScrollView {
                        let style: PlateVisualStyle = exercise.movementGroup == "olympic" ? .bumper : .steel
                        VStack(alignment: .leading, spacing: 18) {
                            ScrollView(.horizontal, showsIndicators: true) {
                                BarbellView(
                                    solution: solution,
                                    plateStyle: style,
                                    presentation: .fullBar
                                )
                                .frame(
                                    width: max(
                                        360,
                                        BarbellView.minimumLegibleWidth(for: solution.loadout, style: style)
                                    ),
                                    height: 180
                                )
                                .padding(.horizontal)
                            }
                            LoadoutSummaryView(
                                requestedLb: contextualSet?.targetWeightLb ?? sessionEntry?.targetWeightLb,
                                loadout: solution.loadout
                            )
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                    .navigationTitle(exercise.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExpandedContextBar = false }
                        }
                    }
                }
            }
        }
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
                        exercise.id = UUID().uuidString
                        context.insert(exercise)
                        if PersistenceErrorCenter.shared.save(context, operation: "Adding the exercise") { dismiss() }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
