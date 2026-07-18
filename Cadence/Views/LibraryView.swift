import SwiftUI
import SwiftData
import CadenceCore

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

    /// "Jun 7, 2026 — 245 lb × 3 · Upper/Lower 4-Day", from the newest
    /// completed session containing this exercise.
    private var lastDoneLabel: String {
        for s in completed {
            guard let entry = s.exercises.first(where: { $0.exercise?.name == exercise.name }),
                  let top = entry.workingSets.max(by: { $0.weightLb < $1.weightLb }) else { continue }
            let program = s.programName.map { " · \($0)" } ?? ""
            return "\(s.date.formatted(date: .abbreviated, time: .omitted)) — \(Weight.trim(top.weightLb)) lb × \(top.reps)\(program)"
        }
        return "Not yet"
    }

    /// Top-set weight per session, oldest→newest, capped to the last 24.
    private var topSetSeries: [Double] {
        var recent: [Double] = []
        for s in completed {
            guard let entry = s.exercises.first(where: { $0.exercise?.name == exercise.name }),
                  let top = entry.workingSets.max(by: { $0.weightLb < $1.weightLb }) else { continue }
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
                if topSetSeries.count >= 2 {
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
                Picker("Type", selection: Binding(
                    get: { exercise.type },
                    set: { exercise.type = $0 }
                )) {
                    ForEach(ExerciseType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Unilateral (log per side)", isOn: $exercise.isUnilateral)
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
        .saveChangesOnDisappear(context, operation: "Saving the exercise")
    }
}
