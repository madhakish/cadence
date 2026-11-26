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

// MARK: Forge styling (#177)

/// The watch's palette: the asset accent (oxide red) means "now / act" and
/// nothing else; data reads in white; structure is steel.
private enum Forge {
    /// Labels for structure: set position, units, captions. Bright enough to
    /// read at arm's length, which "secondary" gray on black is not.
    static let steel = Color(white: 0.68)
    /// Fill of a control that is not the act: +30 s, Not a set, tags.
    static let plate = Color(white: 0.19)
}

/// Load, reps and time: SF condensed at black weight with tabular digits,
/// scaled with Dynamic Type, shrinking to fit rather than truncating a load.
/// The figure gets first claim on a screen's height (`layoutPriority`);
/// without it a stack hands it the same share as a Spacer and it shrinks to
/// a whisper, which is the opposite of the point.
private struct Figure: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(_ size: CGFloat) { _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle) }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .black).width(.condensed).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .layoutPriority(1)
    }
}

private extension View {
    func figure(_ size: CGFloat) -> some View { modifier(Figure(size)) }

    /// Exercise names: condensed heavy, primary, two lines at most.
    func exerciseName() -> some View {
        font(.headline.weight(.heavy).width(.condensed))
            .lineLimit(2).minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
    }

    /// Small structural captions ("Set 1 of 2", "Rest"): steel, not tiny gray.
    func caption() -> some View {
        font(.footnote.weight(.bold).width(.condensed)).foregroundStyle(Forge.steel)
    }
}

/// A flat, square-shouldered control. `.act` is the one accent fill on a
/// screen; `.steel` is everything else; `.danger` is steel with an accent label.
struct SlabButtonStyle: ButtonStyle {
    enum Kind { case act, steel, danger }
    var kind: Kind
    var height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        SlabLabel(configuration: configuration, kind: kind, baseHeight: height)
    }
}

private struct SlabLabel: View {
    let configuration: ButtonStyleConfiguration
    let kind: SlabButtonStyle.Kind
    @ScaledMetric private var height: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    init(configuration: ButtonStyleConfiguration, kind: SlabButtonStyle.Kind, baseHeight: CGFloat) {
        self.configuration = configuration
        self.kind = kind
        _height = ScaledMetric(wrappedValue: baseHeight, relativeTo: .headline)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        configuration.label
            .font(.headline.weight(.heavy).width(.condensed))
            .lineLimit(1)
            .minimumScaleFactor(0.7)  // large text shrinks a label rather than cutting it off
            .foregroundStyle(kind == .act ? Color.black : kind == .danger ? Color.accentColor : Color.white)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(shape.fill(kind == .act ? Color.accentColor : Forge.plate))
            .contentShape(shape)
            // Pressed and disabled are instant opacity changes: nothing moves,
            // so there is nothing for Reduce Motion to take away.
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == SlabButtonStyle {
    /// The screen's act: Done, Start, Confirm. At least the system's large
    /// control height (47 pt on a 42 mm watch), so a chalked thumb finds it.
    static var act: SlabButtonStyle { SlabButtonStyle(kind: .act, height: 48) }
    static func steel(height: CGFloat = 48) -> SlabButtonStyle { SlabButtonStyle(kind: .steel, height: height) }
    static var danger: SlabButtonStyle { SlabButtonStyle(kind: .danger, height: 48) }
}

/// "185 lb × 5": the one number read with a bar on your back. Figures in
/// white, the unit and the × in steel, as one Text so it scales as a unit.
struct LoadFigure: View {
    let load: String  // `WatchSessionModel.display`, "185 lb" or "84 kg"
    let reps: Int
    @ScaledMetric private var scaled: CGFloat

    init(load: String, reps: Int, size: CGFloat = 50) {
        self.load = load
        self.reps = reps
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        let split = load.lastIndex(of: " ")
        let number = split.map { String(load[..<$0]) } ?? load
        let unit = split.map { String(load[load.index(after: $0)...]) } ?? ""
        let big = Font.system(size: scaled, weight: .black).width(.condensed).monospacedDigit()
        let small = Font.system(size: scaled * 0.5, weight: .heavy).width(.condensed)
        Text("\(Text(number).font(big))\(Text(" \(unit) ×").font(small).foregroundStyle(Forge.steel))\(Text(" \(reps)").font(big))")
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .accessibilityLabel("\(load) × \(reps)")
    }
}

// MARK: Screens

struct StartView: View {
    @EnvironmentObject private var model: WatchSessionModel
    @EnvironmentObject private var motion: MotionRecorder

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.plan?.activeSessionID != nil {
                    Text("A session is open on your iPhone")
                        .font(.headline.weight(.heavy).width(.condensed)).multilineTextAlignment(.center)
                    Button("Continue") { model.join() }
                        .buttonStyle(.act)
                } else if let next = model.plan?.next {
                    VStack(spacing: 2) {
                        Text(next.title)
                            .font(.title3.weight(.black).width(.condensed))
                            .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                        Text("\(next.exercises.count) exercises").caption()
                    }
                    if model.plan?.isStale(now: Date()) == true {
                        Label("Plan may be out of date", systemImage: "exclamationmark.triangle")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                    }
                    Button("Start") { model.start() }
                        .buttonStyle(.act)
                        .accessibilityIdentifier("start")
                        .accessibilityHint("Starts \(next.title) on your watch")
                } else {
                    Text("Open Cadence on your iPhone")
                        .font(.headline.weight(.heavy).width(.condensed)).multilineTextAlignment(.center)
                    Text("Your next program day appears here once the phone has planned it.")
                        .font(.footnote).foregroundStyle(Forge.steel).multilineTextAlignment(.center)
                }
                Toggle("Record wrist motion", isOn: $motion.isEnabled)
                    .font(.footnote)
                    .padding(.top, 8)
                    .accessibilityHint("Recordings help Cadence learn to count your reps. They go to your iPhone only.")
                Toggle("Confirm detected sets", isOn: $model.confirmBeforeLogging)
                    .font(.footnote)
                    .accessibilityHint("When on, a set your watch detects waits for you to confirm it instead of logging itself.")
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
                .font(.footnote.weight(.bold).width(.condensed).monospacedDigit()).foregroundStyle(.red)
                .accessibilityLabel("Heart rate \(bpm) beats per minute")
        }
    }
}

struct SetView: View {
    @EnvironmentObject private var model: WatchSessionModel
    @State private var reps = 0.0
    @State private var editingLoad = false

    var body: some View {
        if let proposed = model.proposedSet {
            ProposalCard(exercise: proposed.exercise, set: proposed.set)
        } else if let exercise = model.currentExercise, let set = model.currentSet, WatchSessionModel.isTimed(set) {
            TimedSetView(exercise: exercise, set: set)
        } else if let exercise = model.currentExercise, let set = model.currentSet {
            let index = (exercise.sets.firstIndex { $0.id == set.id } ?? 0) + 1
            VStack(spacing: 2) {
                HStack {
                    Text(set.isWarmup ? "Warmup" : "Set \(index) of \(exercise.sets.count)")
                        .caption()
                        .accessibilityIdentifier("setPosition")
                    Spacer()
                    HeartRateBadge()
                }
                Text(exercise.catalog.name).exerciseName()
                Spacer(minLength: 0)
                Button { editingLoad = true } label: {
                    LoadFigure(load: model.display(model.load(for: set)), reps: Int(reps))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityIdentifier("load")
                .accessibilityHint("Adjust the load. Turn the Digital Crown to change reps.")
                Spacer(minLength: 0)
                Button("Done") { model.complete(set, reps: Int(reps), weightLb: model.load(for: set)) }
                    .buttonStyle(.act)
                    .accessibilityIdentifier("done")
                Button("Skip", role: .destructive) { model.skip(set) }
                    .accessibilityIdentifier("skipSet")
                    .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Forge.steel)
            }
            // The page's bottom inset is height the load figure needs on 42 mm.
            .ignoresSafeArea(.container, edges: .bottom)
            .focusable()
            .digitalCrownRotation($reps, from: 0, through: 50, by: 1, sensitivity: .low,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
            .onAppear { load(set) }
            .onChange(of: set.id) { _, _ in load(set) }
            .sheet(isPresented: $editingLoad) {
                LoadAdjuster(weightLb: Binding(get: { model.load(for: set) }, set: { model.adjustLoad(set.id, to: $0) }))
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark").font(.title.weight(.black))
                Text("All planned sets are logged").exerciseName()
                Text("Swipe down to end the workout").caption()
            }
        }
    }

    private func load(_ set: SyncSessionView.Set) {
        reps = Double(set.reps)
    }
}

struct LoadAdjuster: View {
    @Binding var weightLb: Double
    @EnvironmentObject private var model: WatchSessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosingReason = false

    var body: some View {
        VStack(spacing: 6) {
            Text(model.display(weightLb)).figure(44)
                // The sheet squeezes a shrinkable Text to a sliver; hold its
                // height and let only a too-wide load scale down.
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("−5") { weightLb = max(0, weightLb - 5) }
                    .buttonStyle(.steel(height: 44))
                Button("+5") { weightLb += 5 }
                    .buttonStyle(.steel(height: 44))
            }
            Button("Done") { dismiss() }.buttonStyle(.act)
                .accessibilityIdentifier("loadDone")
            Button("Drop load…") { choosingReason = true }
                .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Forge.steel)
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

/// The first screen is the clock and the two things you do to it. Everything
/// else (a detected set, effort tags, the next set) waits below the fold, with
/// its top edge peeking so it's clear there is more.
struct RestView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    HStack {
                        Text("Rest").caption().accessibilityIdentifier("restTitle")
                        Spacer()
                        HeartRateBadge()
                    }
                    Spacer(minLength: 0)
                    if let rest = model.view?.rest {
                        let end = Date(timeIntervalSince1970: rest.endEpoch)
                        Group {
                            if rest.paused {
                                Text(Duration.seconds(rest.pausedRemaining).formatted(.time(pattern: .minuteSecond)))
                            } else {
                                Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                            }
                        }
                        .figure(76)
                        .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Button("+30 s") { model.addRest(30) }
                            .buttonStyle(.steel())
                        Button("Skip") { model.endRest() }
                            .buttonStyle(.act)
                            .accessibilityIdentifier("skipRest")
                    }
                }
                .containerRelativeFrame(.vertical)

                ProposalBanner()
                if let reps = model.autoLoggedReps, let setID = model.lastLoggedSetID {
                    Button("\(reps) reps · Edit") { model.reopen(setID); model.endRest() }
                        .buttonStyle(.steel())
                        .accessibilityIdentifier("autoLogged")
                        .accessibilityHint("Logged from your wrist motion. Tap to correct it.")
                }
                if let setID = model.lastLoggedSetID {
                    EffortTags(setID: setID)
                    Button("Edit last set") { model.reopen(setID); model.endRest() }
                        .buttonStyle(.steel(height: 40))
                }
                if let next = model.currentSet, let exercise = model.currentExercise {
                    VStack(spacing: 0) {
                        Text("Next").caption()
                        Text(exercise.catalog.name).exerciseName()
                        LoadFigure(load: model.display(model.load(for: next)), reps: next.reps, size: 26)
                    }
                    .accessibilityElement(children: .combine)
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

    /// Square-shouldered, steel until chosen; only a chosen tag takes the accent.
    private func tagButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(SlabButtonStyle(kind: selected ? .act : .steel, height: 34))
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise.catalog.name)
                        .font(.headline.weight(.heavy).width(.condensed)).lineLimit(1)
                    Text("\(done) of \(exercise.sets.count) sets")
                        .font(.footnote.weight(.semibold).width(.condensed).monospacedDigit())
                        .foregroundStyle(Forge.steel)
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
                .buttonStyle(.danger)
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
        VStack(spacing: 4) {
            Text("Logged").caption()
            Text(summary.sets == 1 ? "1 working set" : "\(summary.sets) working sets")
                .font(.title3.weight(.black).width(.condensed).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityIdentifier("summarySets")
            Text(model.display(summary.volumeLb) + " volume")
                .font(.headline.weight(.heavy).width(.condensed).monospacedDigit())
            Text(Duration.seconds(summary.duration).formatted(.time(pattern: .hourMinute)))
                .font(.headline.weight(.heavy).width(.condensed).monospacedDigit()).foregroundStyle(Forge.steel)
            Text("Saved to your iPhone when it's in reach.")
                .font(.footnote).foregroundStyle(Forge.steel)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
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
        VStack(spacing: 4) {
            HStack {
                Text(target.map { "Target \(Duration.seconds($0).formatted(.time(pattern: .minuteSecond)))" } ?? "Timed")
                    .caption()
                Spacer()
                HeartRateBadge()
            }
            Text(exercise.catalog.name).exerciseName()
            Spacer(minLength: 0)
            if let startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let elapsed = (stoppedAt ?? context.date).timeIntervalSince(startedAt)
                    Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                        .figure(50)
                }
                .layoutPriority(1)
            }
            Spacer(minLength: 0)
            if startedAt == nil {
                Button("Start") { startedAt = Date() }
                    .buttonStyle(.act)
                    .accessibilityIdentifier("startTimer")
            } else if stoppedAt == nil {
                Button("Stop") { stoppedAt = Date() }
                    .buttonStyle(.act)
            } else if let startedAt, let stoppedAt {
                Button("Done") {
                    model.complete(set, reps: set.reps, weightLb: set.weightLb,
                                   durationSeconds: Int(stoppedAt.timeIntervalSince(startedAt).rounded()))
                    self.startedAt = nil
                    self.stoppedAt = nil
                }
                .buttonStyle(.act)
            }
            Button("Skip", role: .destructive) { model.skip(set) }
                .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Forge.steel)
        }
        .onChange(of: set.id) { _, _ in
            startedAt = nil
            stoppedAt = nil
        }
    }
}

/// Tap-to-confirm (design section 10) on the rest screen: rest started at
/// detection, and the detected set waits here until the owner confirms it.
struct ProposalBanner: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        if let proposal = model.proposal {
            VStack(spacing: 4) {
                Text("Detected \(proposal.reps) reps").exerciseName()
                ProposalActions(reps: proposal.reps)
            }
            .padding(.vertical, 4)
        }
    }
}

/// Tap-to-confirm on the set screen (#359): once a set is detected, its own
/// Done is redundant, so the proposal takes the set's controls. The card has
/// the set screen's rows, so it fits wherever that screen does (40 mm too)
/// without scrolling, which keeps the crown on the reps.
struct ProposalCard: View {
    let exercise: SyncSessionView.Exercise
    let set: SyncSessionView.Set
    @EnvironmentObject private var model: WatchSessionModel
    @State private var editingLoad = false

    var body: some View {
        let index = (exercise.sets.firstIndex { $0.id == set.id } ?? 0) + 1
        let reps = model.proposal?.reps ?? set.reps
        VStack(spacing: 2) {
            HStack {
                Text(set.isWarmup ? "Detected warmup" : "Detected set \(index) of \(exercise.sets.count)").caption()
                Spacer()
                HeartRateBadge()
            }
            Text(exercise.catalog.name).exerciseName()
            Spacer(minLength: 0)
            Button { editingLoad = true } label: {
                LoadFigure(load: model.display(model.load(for: set)), reps: reps)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityIdentifier("load")
            .accessibilityHint("Adjust the load. Turn the Digital Crown to correct the detected reps.")
            Spacer(minLength: 0)
            ProposalActions(reps: reps)
            Button("Skip", role: .destructive) { model.skip(set) }
                .accessibilityIdentifier("skipSet")
                .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Forge.steel)
        }
        .ignoresSafeArea(.container, edges: .bottom)  // as on the set screen
        .focusable()
        .digitalCrownRotation(Binding(get: { Double(reps) }, set: { model.adjustProposal(reps: Int($0)) }),
                              from: 0, through: 50, by: 1, sensitivity: .low,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .sheet(isPresented: $editingLoad) {
            LoadAdjuster(weightLb: Binding(get: { model.load(for: set) }, set: { model.adjustLoad(set.id, to: $0) }))
        }
    }
}

/// Confirm and Not a set, the same on the rest screen and the set screen.
struct ProposalActions: View {
    let reps: Int
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        HStack(spacing: 6) {
            Button("Confirm") { model.confirmProposal() }
                .buttonStyle(.act)
                .accessibilityIdentifier("confirmDetected")
                .accessibilityHint("Logs the set with \(reps) reps.")
            Button("Not a set") { model.dismissProposal() }
                .buttonStyle(.steel())
                .accessibilityIdentifier("dismissDetected")
                .accessibilityHint("Nothing is logged; the set stays planned.")
        }
    }
}
