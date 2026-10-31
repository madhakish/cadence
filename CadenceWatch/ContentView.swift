import CadenceCore
import SwiftUI

/// Routes between the watch's screens (design #339, section 7): Start, the
/// running session, and the summary after ending.
struct ContentView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        if model.isRunning {
            SessionView()
        } else if let summary = model.summary {
            SummaryView(summary: summary)
        } else {
            StartView()
        }
    }
}

struct StartView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.plan?.activeSessionID != nil {
                    Text("A session is open on your iPhone")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Continue") { model.join() }
                        .buttonStyle(.borderedProminent)
                } else if let next = model.plan?.next {
                    Text(next.title).font(.headline).multilineTextAlignment(.center)
                    Text("\(next.exercises.count) exercises").font(.footnote).foregroundStyle(.secondary)
                    if model.plan?.isStale(now: Date()) == true {
                        Label("Plan may be out of date", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Button("Start") { model.start() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("start")
                        .accessibilityHint("Starts \(next.title) on your watch")
                } else {
                    Text("Open Cadence on your iPhone")
                        .multilineTextAlignment(.center)
                    Text("Your next program day appears here once the phone has planned it.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct SessionView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        TabView {
            Group {
                if model.view?.rest != nil { RestView() } else { SetView() }
            }
            ExerciseListView()
            EndView()
        }
        .tabViewStyle(.verticalPage)
    }
}

struct HeartRateBadge: View {
    @EnvironmentObject private var recorder: WorkoutRecorder

    var body: some View {
        if let bpm = recorder.heartRate {
            Label("\(bpm)", systemImage: "heart.fill")
                .font(.caption2.monospacedDigit()).foregroundStyle(.red)
                .accessibilityLabel("Heart rate \(bpm) beats per minute")
        }
    }
}

struct SetView: View {
    @EnvironmentObject private var model: WatchSessionModel
    @State private var reps = 0.0
    @State private var weightLb = 0.0
    @State private var editingLoad = false

    var body: some View {
        if let exercise = model.currentExercise, let set = model.currentSet, WatchSessionModel.isTimed(set) {
            TimedSetView(exercise: exercise, set: set)
        } else if let exercise = model.currentExercise, let set = model.currentSet {
            let index = (exercise.sets.firstIndex { $0.id == set.id } ?? 0) + 1
            VStack(spacing: 6) {
                HStack {
                    Text(set.isWarmup ? "Warmup" : "Set \(index) of \(exercise.sets.count)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("setPosition")
                    Spacer()
                    HeartRateBadge()
                }
                Text(exercise.catalog.name).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                Button { editingLoad = true } label: {
                    Text("\(model.display(weightLb)) × \(Int(reps))")
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Adjust the load. Turn the Digital Crown to change reps.")
                Button("Done") { model.complete(set, reps: Int(reps), weightLb: weightLb) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("done")
                Button("Skip", role: .destructive) { model.skip(set) }
                    .accessibilityIdentifier("skipSet")
                    .font(.footnote).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .focusable()
            .digitalCrownRotation($reps, from: 0, through: 50, by: 1, sensitivity: .low,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
            .onAppear { load(set) }
            .onChange(of: set.id) { _, _ in load(set) }
            .sheet(isPresented: $editingLoad) { LoadAdjuster(weightLb: $weightLb) }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.green)
                Text("All planned sets are logged").multilineTextAlignment(.center)
                Text("Swipe down to end the workout").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func load(_ set: SyncSessionView.Set) {
        reps = Double(set.reps)
        weightLb = set.weightLb
    }
}

struct LoadAdjuster: View {
    @Binding var weightLb: Double
    @EnvironmentObject private var model: WatchSessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosingReason = false

    var body: some View {
        VStack(spacing: 8) {
            Text(model.display(weightLb)).font(.title2.monospacedDigit())
            HStack {
                Button("−5") { weightLb = max(0, weightLb - 5) }
                Button("+5") { weightLb += 5 }
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            Button("Drop load…") { choosingReason = true }
                .font(.footnote)
        }
        .confirmationDialog("Why drop the load?", isPresented: $choosingReason) {
            ForEach(AutoregReason.allCases, id: \.self) { reason in
                Button(reason.rawValue.capitalized) {
                    model.dropLoad(reason: reason)
                    dismiss()
                }
            }
        }
        .focusable()
        .digitalCrownRotation($weightLb, from: 0, through: 1000, by: 2.5, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
    }
}

struct RestView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack {
                    Text("Rest").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("restTitle")
                    Spacer()
                    HeartRateBadge()
                }
                if let rest = model.view?.rest {
                    let end = Date(timeIntervalSince1970: rest.endEpoch)
                    if rest.paused {
                        Text(Duration.seconds(rest.pausedRemaining).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    } else {
                        Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                            .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    }
                }
                HStack {
                    Button("+30 s") { model.addRest(30) }
                    Button("Skip") { model.endRest() }.accessibilityIdentifier("skipRest")
                }
                if let setID = model.lastLoggedSetID {
                    EffortTags(setID: setID)
                    Button("Edit last set") { model.reopen(setID); model.endRest() }
                        .font(.footnote)
                }
                if let next = model.currentSet, let exercise = model.currentExercise {
                    Text("Next: \(exercise.catalog.name) · \(model.display(next.weightLb)) × \(next.reps)")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
    }
}

/// Owner decision 8: two optional rows, one tap each, never blocking.
struct EffortTags: View {
    let setID: String
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        let flags = model.view?.exercises.flatMap(\.sets).first { $0.id == setID }?.flags ?? []
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach([("clean", "Clean"), ("grindy", "Grindy"), ("wobble", "Wobble")], id: \.0) { value, label in
                    tagButton(label, selected: flags.contains(value)) { model.tag(setID, quality: value, rir: nil) }
                        .accessibilityIdentifier("quality-\(value)")
                }
            }
            HStack(spacing: 4) {
                ForEach([("rir1", "1"), ("rir2", "2"), ("rir3plus", "3+")], id: \.0) { value, label in
                    tagButton(label, selected: flags.contains(value)) { model.tag(setID, quality: nil, rir: value) }
                        .accessibilityLabel("\(label) reps in reserve")
                }
            }
        }
    }

    private func tagButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption2)
            .buttonStyle(.bordered)
            .tint(selected ? .accentColor : .gray)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ExerciseListView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        List(model.view?.exercises ?? [], id: \.id) { exercise in
            let done = exercise.sets.filter { $0.status != .planned }.count
            Button {
                model.focusExerciseID = exercise.id
            } label: {
                VStack(alignment: .leading) {
                    Text(exercise.catalog.name).lineLimit(1)
                    Text("\(done) of \(exercise.sets.count) sets").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityHint("Jump to this exercise")
        }
    }
}

struct EndView: View {
    @EnvironmentObject private var model: WatchSessionModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 10) {
            Button("End workout", role: .destructive) { confirming = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("endWorkout")
                .disabled(model.isEnding)
            if model.isEnding { ProgressView() }
        }
        .confirmationDialog("End this workout?", isPresented: $confirming) {
            Button("End now", role: .destructive) { Task { await model.end() } }
            Button("Keep going", role: .cancel) {}
        }
    }
}

struct SummaryView: View {
    let summary: WatchSessionModel.Summary
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill").font(.title).foregroundStyle(.green)
            Text(summary.sets == 1 ? "1 working set" : "\(summary.sets) working sets").font(.headline)
                .accessibilityIdentifier("summarySets")
            Text(model.display(summary.volumeLb) + " volume").font(.footnote)
            Text(Duration.seconds(summary.duration).formatted(.time(pattern: .hourMinute)))
                .font(.footnote).foregroundStyle(.secondary)
            Text("Saved to your iPhone when it's in reach.").font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Holds by a hold timer; carries and conditioning by duration (owner
/// decision 11). The timer runs on the watch; Done logs the elapsed time.
struct TimedSetView: View {
    let exercise: SyncSessionView.Exercise
    let set: SyncSessionView.Set
    @EnvironmentObject private var model: WatchSessionModel
    @State private var startedAt: Date?
    @State private var stoppedAt: Date?

    private var target: Int? { self.set.created.plannedDurationSeconds ?? self.set.durationSeconds }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(target.map { "Target \(Duration.seconds($0).formatted(.time(pattern: .minuteSecond)))" } ?? "Timed")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                HeartRateBadge()
            }
            Text(exercise.catalog.name).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            if let startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let elapsed = (stoppedAt ?? context.date).timeIntervalSince(startedAt)
                    Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 36, weight: .semibold).monospacedDigit())
                }
            }
            if startedAt == nil {
                Button("Start") { startedAt = Date() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("startTimer")
            } else if stoppedAt == nil {
                Button("Stop") { stoppedAt = Date() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else if let startedAt, let stoppedAt {
                Button("Done") {
                    model.complete(set, reps: set.reps, weightLb: set.weightLb,
                                   durationSeconds: Int(stoppedAt.timeIntervalSince(startedAt).rounded()))
                    self.startedAt = nil
                    self.stoppedAt = nil
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Button("Skip", role: .destructive) { model.skip(set) }
                .font(.footnote).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .onChange(of: set.id) { _, _ in
            startedAt = nil
            stoppedAt = nil
        }
    }
}
