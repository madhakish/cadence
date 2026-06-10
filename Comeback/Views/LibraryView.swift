import SwiftUI
import SwiftData

/// The exercise library. Shelved lifts stay visible — with the re-entry
/// test spelled out — so coming back to them is a decision, not an accident.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    var body: some View {
        List {
            ForEach(ExerciseCategory.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(exercises.filter { $0.category == category }) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            HStack {
                                Text(exercise.name)
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
    }
}

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: Binding(
                    get: { exercise.type },
                    set: { exercise.type = $0 }
                )) {
                    ForEach(ExerciseType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Unilateral (log per side)", isOn: $exercise.isUnilateral)
                Stepper(
                    "Rest: \(exercise.defaultRestSeconds / 60):\(String(format: "%02d", exercise.defaultRestSeconds % 60))",
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
                Toggle("Shelved", isOn: $exercise.isShelved)
                if exercise.isShelved {
                    TextField("Re-entry test", text: $exercise.shelvedNote, axis: .vertical)
                        .lineLimit(2...5)
                }
            } header: {
                Text("Status")
            } footer: {
                if exercise.isShelved {
                    Text("Stays in the library, out of the program, until the re-entry test passes.")
                }
            }

            Section("Notes") {
                TextField("Notes", text: $exercise.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle(exercise.name)
    }
}
