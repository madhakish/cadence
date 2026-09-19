import SwiftUI
import SwiftData
import CadenceCore

/// The one exercise-finding surface (issue #63). Search first, then two
/// composable filters, then a compact Recent group, then the categories as
/// collapsed groups that state their counts — nobody scrolls the whole
/// catalog to find one lift. A filter reveals only the groups with matches,
/// opened; clearing it returns every group, collapsed, except the ones the
/// user opened themselves. Shelved lifts stay visible — with their badge — so
/// coming back to them is a decision, not an accident, unless the caller asks
/// for programmable exercises only.
///
/// Without `onSelect` a row navigates to the exercise's detail (the library).
/// With it a row selects, and the ⓘ opens the detail OVER the browser, so the
/// search text and active filters survive the inspection — picking after
/// reading never restarts the hunt. Every picker is this view plus a
/// selection closure; nothing else. Web twin: `exerciseBrowser` in
/// views/settings.js.
struct ExerciseBrowser: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]
    @State private var search = ""
    @State private var movementFilter: MovementPattern?
    @State private var typeFilter: ExerciseType?
    @State private var openedCategories: Set<ExerciseCategory> = []
    @State private var detailExercise: Exercise?
    @State private var showNewExercise = false
    var equipmentPolicy: EquipmentPolicy = .any
    var availableOnly = false
    var onSelect: ((Exercise) -> Void)? = nil

    private var isFiltering: Bool {
        !search.isEmpty || movementFilter != nil || typeFilter != nil
    }

    private var visibleExercises: [Exercise] {
        let term = search.isEmpty ? nil : ExerciseSearch.preparedTerm(search)
        return exercises.filter { exercise in
            if !equipmentPolicy.allows(exerciseType: exercise.typeRaw) { return false }
            if availableOnly, !exercise.isAvailableForProgramming { return false }
            if let term, !exercise.matchesSearch(preparedTerm: term) { return false }
            if !ExerciseSearch.matchesMovement(movementFilter, primary: exercise.movementPattern,
                                               secondary: exercise.secondaryMovementPattern) { return false }
            if let typeFilter, exercise.type != typeFilter { return false }
            return true
        }
    }

    /// Recent lifts resolved against the visible list, so the same search,
    /// filters, policy, and availability apply to them. The session walk is
    /// lazy: only as many sessions as the cap needs are touched per pass.
    private func recentExercises(in visible: [Exercise]) -> [Exercise] {
        let names = ExerciseSearch.recentNames(sessionsNewestFirst: completedSessions.lazy.map { session in
            session.orderedExercises.compactMap { $0.exercise?.name }
        })
        return names.compactMap { name in visible.first { $0.name == name } }
    }

    /// While filtering, a group is open exactly when it has matches; the
    /// user's own toggles are remembered only for the unfiltered list.
    private func isExpanded(_ category: ExerciseCategory, hasMatches: Bool) -> Binding<Bool> {
        Binding(
            get: { isFiltering ? hasMatches : openedCategories.contains(category) },
            set: { open in
                guard !isFiltering else { return }
                if open { openedCategories.insert(category) } else { openedCategories.remove(category) }
            }
        )
    }

    private func clearFilters() {
        search = ""
        movementFilter = nil
        typeFilter = nil
    }

    var body: some View {
        let visible = visibleExercises
        List {
            Section {
                Picker("Movement", selection: $movementFilter) {
                    Text("All movements").tag(MovementPattern?.none)
                    ForEach(MovementPattern.allCases, id: \.self) { pattern in
                        Text(pattern.name).tag(MovementPattern?.some(pattern))
                    }
                }
                Picker("Equipment", selection: $typeFilter) {
                    Text("All equipment").tag(ExerciseType?.none)
                    ForEach(ExerciseType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(ExerciseType?.some(type))
                    }
                }
                if isFiltering, !visible.isEmpty {
                    Button("Clear filters") { clearFilters() }
                }
            }
            if visible.isEmpty {
                // The empty state says how to widen the hunt, with both ways
                // out beside it — the same copy on web.
                Section {
                    Text(Copy.noExercisesMatch).foregroundStyle(.secondary)
                    if isFiltering {
                        Button("Clear filters") { clearFilters() }
                    }
                    Button("New exercise") { showNewExercise = true }
                }
            } else {
                let recent = recentExercises(in: visible)
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent) { exercise in row(exercise) }
                    }
                }
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    let inCategory = visible.filter { $0.category == category }
                    if !isFiltering || !inCategory.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: isExpanded(category, hasMatches: !inCategory.isEmpty)) {
                                ForEach(inCategory) { exercise in row(exercise) }
                            } label: {
                                HStack {
                                    Text(category.rawValue).font(.headline)
                                    Spacer()
                                    Text("\(inCategory.count)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Name, equipment or movement")
        .sheet(item: $detailExercise) { exercise in
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
            }
        }
        .sheet(isPresented: $showNewExercise) { NewExerciseView() }
    }

    @ViewBuilder
    private func row(_ exercise: Exercise) -> some View {
        if let onSelect {
            HStack {
                Button {
                    onSelect(exercise)
                } label: {
                    LibraryRow(exercise: exercise).foregroundStyle(.primary)
                }
                // Detail preview OVER the browser (issue #66): the sheet keeps
                // the search text and active filters, so inspecting never
                // restarts the hunt.
                Button {
                    detailExercise = exercise
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("\(exercise.name) — muscles, history, and settings")
            }
            .buttonStyle(.borderless)
        } else {
            NavigationLink {
                ExerciseDetailView(exercise: exercise)
            } label: {
                LibraryRow(exercise: exercise)
            }
        }
    }
}

struct LibraryRow: View {
    let exercise: Exercise

    var body: some View {
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
                    .background(Theme.hardStop.opacity(0.25), in: RoundedRectangle(cornerRadius: 2))
                    .foregroundStyle(Theme.hardStop)
            }
            if exercise.isUnilateral {
                Text("per side").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
