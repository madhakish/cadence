import SwiftUI
import SwiftData
import CadenceCore

struct TFHProgramView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @Query private var sessions: [WorkoutSession]
    let program: Program
    @State private var draft: TFHProgramPolicy?
    @State private var error: String?

    private var slots: [(id: String, name: String)] {
        program.orderedDays.flatMap { $0.orderedLifts.map { ($0.id, $0.exerciseName) }
            + $0.orderedAccessories.map { ($0.id, $0.exerciseName) } }
    }
    var body: some View {
        Form {
            Section {
                Text("TFH · Strength for everything else")
                    .font(.headline)
                Text("Three build rotations, then 2–3 light sessions. Leave about 1–3 days between recovery sessions. Each rotation compares with the same rotation in prior cycles.")
                Text("Review every starting load. Dumbbell loads are per implement; bodyweight is zero added load. Timed and conditioning slots keep their authored practice targets.")
                if program.tfhPolicyData != nil {
                    Text("Saving starts a new evidence cohort. Existing sessions and their targets remain in history.")
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let draft {
                Section("Recovery days · choose 2 or 3") {
                    ForEach(program.orderedDays) { day in
                        Toggle(day.name, isOn: Binding(get: { self.draft?.recoveryDayOrders.contains(day.order) == true }, set: { on in
                            self.draft?.recoveryDayOrders.removeAll { $0 == day.order }
                            if on { self.draft?.recoveryDayOrders.append(day.order) }
                            self.draft?.recoveryDayOrders.sort()
                        }))
                    }
                }
                ForEach(slots, id: \.id) { slot in
                    if let anchor = draft.anchors[slot.id] {
                        TFHAnchorEditor(name: slot.name, anchor: Binding(
                            get: { self.draft?.anchors[slot.id] ?? anchor },
                            set: { self.draft?.anchors[slot.id] = $0 }
                        ))
                    }
                }
                Section {
                    Button("Use TFH from cycle \(draft.startCycle)") {
                        do {
                            try TFHProgramService.activate(draft, program: program, exercises: exercises, context: context)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(!draft.isValid)
                }
            }
        }
        .navigationTitle("TFH method")
        .task {
            do { draft = try TFHProgramService.draft(program, exercises: exercises, sessions: sessions) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct TFHAnchorEditor: View {
    let name: String
    @Binding var anchor: TFHAnchor
    var body: some View {
        Section(name) {
            HStack {
                Text("Starting load (lb)")
                TextField("lb", value: $anchor.weightLb, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .disabled(anchor.loadBasis == .bodyweight)
            }
            Text("\(anchor.loadBasis.rawValue) · \(anchor.implementCount) implement(s)\(anchor.isPerSide ? " · reps per side" : "")")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("Sets: \(anchor.reps.count)", value: Binding(get: { anchor.reps.count }, set: {
                anchor.reps = Array(repeating: anchor.reps.first ?? anchor.minReps, count: $0)
            }), in: 1...10)
            Stepper("Starting reps: \(anchor.reps.first ?? 0)", value: Binding(get: { anchor.reps.first ?? 1 }, set: { value in
                anchor.reps = anchor.reps.map { _ in value }
            }), in: 1...30)
            Stepper("Minimum reps: \(anchor.minReps)", value: $anchor.minReps, in: 1...30)
            Stepper("Maximum reps: \(anchor.maxReps)", value: $anchor.maxReps, in: 1...50)
            HStack {
                Text("Smallest available step (lb)")
                TextField("lb", value: $anchor.incrementLb, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Picker("Purpose", selection: $anchor.intent) {
                Text("Develop").tag(TFHIntent.develop)
                Text("Maintain").tag(TFHIntent.maintain)
                Text("Practice").tag(TFHIntent.practice)
            }
            Toggle("Optional R3 final-set benchmark", isOn: $anchor.benchmarkEnabled)
                .disabled(anchor.intent != .develop)
            Text("A benchmark stops when another clean rep is no longer possible. Pain, an interruption, or a chosen rep cap is not a capacity test. Skip it whenever it competes with other training.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TFHEvidenceView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: WorkoutSession
    var body: some View {
        Section("TFH evidence · optional") {
            TextField("Comparison conditions (setup, support, bodyweight)", text: Binding(
                get: { session.tfhContext ?? "" },
                set: { session.tfhContext = $0.isEmpty ? nil : String($0.prefix(500)) }
            ))
            Text("Use the same description only when conditions are comparable. Missing conditions or benchmark evidence leaves capacity unassessed.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Completed, unflagged work felt clean") {
                for set in session.exercises.flatMap(\.workingSets)
                    where set.quality == nil && !set.flags.contains(.stoppedEarly) && set.bodyFlagSite == nil {
                    set.quality = .clean
                }
                PersistenceErrorCenter.shared.save(context, operation: "Recording TFH set quality")
            }
            ForEach(session.orderedExercises) { entry in
                ForEach(entry.orderedSets.filter { $0.tfhBenchmarkData != nil }) { set in
                    TFHBenchmarkEditor(set: set, name: entry.exercise?.name ?? "Final set")
                }
            }
        }
        .saveChangesOnDisappear(context, operation: "Saving TFH context")
    }
}

private struct TFHBenchmarkEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var set: SetEntry
    let name: String
    @State private var result = TFHBenchmarkResult()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(name) · optional final-set benchmark").font(.caption.bold())
            Picker("Why you stopped", selection: $result.stopReason) {
                Text("Not recorded").tag(TFHBenchmarkStop?.none)
                Text("Technical limit").tag(TFHBenchmarkStop?.some(.technicalLimit))
                Text("Rep cap").tag(TFHBenchmarkStop?.some(.repCap))
                Text("Pain").tag(TFHBenchmarkStop?.some(.pain))
                Text("Interrupted").tag(TFHBenchmarkStop?.some(.interrupted))
                Text("Chose to stop").tag(TFHBenchmarkStop?.some(.voluntary))
            }
            HStack {
                Text("Actual rest before this set (seconds)")
                TextField("Unknown", value: $result.restSeconds, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Record benchmark context") {
                do {
                    guard result.isValid else { throw TFHProgramService.Failure.invalid("Rest must be 1–3600 seconds.") }
                    set.tfhBenchmarkData = try TFHProgramService.encode(result)
                    PersistenceErrorCenter.shared.save(context, operation: "Recording TFH benchmark")
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
        .onAppear {
            do { result = try TFHProgramService.decode(TFHBenchmarkResult.self, set.tfhBenchmarkData) ?? TFHBenchmarkResult() }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// Shared by Today, program overview, and the session preview. Individual rep
/// targets stay visible; 6/5/5 must never be mislabeled as 3×6.
struct TFHSlotPlanView: View {
    let program: Program
    let slotID: String
    let name: String
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]
    @Query private var gyms: [Gym]
    @Query private var settings: [AppSettings]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.subheadline.bold())
            switch result {
            case .success(let text): Text(text).font(.caption).foregroundStyle(.secondary)
            case .failure(let error): Text(error.localizedDescription).font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private var result: Result<String, Error> {
        Result {
            guard let exercise = exercises.first(where: { $0.name == name }) else {
                throw TFHProgramService.Failure.invalid("\(name) is missing from the exercise library.")
            }
            guard let (_, plan) = try TFHProgramService.prescription(program, slotID: slotID, sessions: sessions) else {
                guard let slot = program.days.flatMap(\.accessories).first(where: { $0.id == slotID }),
                      let policy = try TFHProgramService.policy(program) else {
                    throw TFHProgramService.Failure.invalid("\(name) needs an authored practice target.")
                }
                let next = try TFHProgramService.position(program, policy: policy, sessions: sessions)
                let target = try TFHSession.practice(exercise: exercise, weight: slot.weightLb, sets: slot.sets,
                                                      seconds: slot.targetSeconds, rotation: next.rotation)
                return "TFH · \(settings.unitDisplay.format(lb: target.weightLb)) · \(target.sets) × \(target.seconds)s · \(next.rotation == 4 ? "light recovery" : "authored practice")"
            }
            let load = TFHSession.achieved(plan, exercise: exercise, program: program,
                                           gym: gyms.first { $0.isDefault } ?? gyms.first)
            let label = plan.reps.map(String.init).joined(separator: "/")
            return "TFH · \(settings.unitDisplay.format(lb: load)) · \(label) reps\(plan.benchmark ? " · last set optional AMRAP" : "")\n\(plan.reason)"
        }
    }
}
