import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Sessions, milestones, and per-lift progression charts.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    /// The block the rotations matrix is scoped to; empty falls back to the
    /// active program.
    @State private var rotationProgramID = ""
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted },
           sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Milestone.date, order: .reverse) private var milestones: [Milestone]
    @Query private var settingsList: [AppSettings]
    @Query private var programs: [Program]
    @Query private var exercises: [Exercise]
    @Query private var checkIns: [CheckIn]
    @Query(sort: \TrainingInterval.startDate, order: .reverse)
    private var trainingIntervals: [TrainingInterval]

    @State private var view: ViewMode = .rotations
    @State private var rotationDetail: String?
    @State private var activityPendingDeletion: WorkoutSession?

    enum ViewMode: String, CaseIterable {
        case list = "Log"
        case rotations = "Rotations"
        case charts = "Charts"
        case milestones = "Milestones"
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("View", selection: $view) {
                    ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch view {
                case .list: sessionList
                case .rotations: rotationList
                case .charts: ProgressionChartsView()
                case .milestones: milestoneList
                }
            }
            .accessibilityIdentifier("history-screen")
            .navigationTitle("History")
            .alert("Rotation details", isPresented: Binding(
                get: { rotationDetail != nil }, set: { if !$0 { rotationDetail = nil } }
            )) {
                Button("OK") { rotationDetail = nil }
            } message: {
                Text(rotationDetail ?? "")
            }
            .confirmationDialog(
                "Delete this activity?",
                isPresented: Binding(
                    get: { activityPendingDeletion != nil },
                    set: { if !$0 { activityPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete activity", role: .destructive) {
                    guard let session = activityPendingDeletion else { return }
                    activityPendingDeletion = nil
                    context.delete(session)
                    PersistenceErrorCenter.shared.save(context, operation: "Deleting ad-hoc work")
                }
                Button("Cancel", role: .cancel) { activityPendingDeletion = nil }
            } message: {
                Text("This removes the banked activity from history. Training cycles and workout records are unchanged.")
            }
        }
    }

    private var rotationList: some View {
        List {
            // An explicit choice, not "whatever drives Today" (epic #155
            // Stage 5): switching the active program must not rewrite the
            // matrix the lifter is reading. Defaults to the active block.
            if programs.count > 1 {
                Picker("Program", selection: $rotationProgramID) {
                    ForEach(programs, id: \.id) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
            }
            if let program = programs.first(where: { $0.id == rotationProgramID })
                ?? programs.first(where: { $0.isActive }) ?? programs.first {
                let report = CoachingService.report(
                    program: program, sessions: sessions,
                    exercises: exercises, checkIns: checkIns,
                    intervals: trainingIntervals.map(\.snapshot)
                )
                Section("Rolling load") {
                    LabeledContent("14 days", value: rollingSummary(days: 14))
                    LabeledContent("28 days", value: rollingSummary(days: 28))
                    Text("Working sets and conditioning are separate; warm-ups are excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !report.rotations.isEmpty {
                    let rotations = Array(Set(report.rotations.map { $0.key.rotation })).sorted()
                    let cycles = Dictionary(grouping: report.rotations, by: { $0.key.cycleNumber })
                    Section("Cycle matrix") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                                GridRow {
                                    Text("Cycle").font(.caption.bold()).foregroundStyle(.secondary)
                                    ForEach(rotations, id: \.self) { Text("R\($0)").font(.caption.bold()) }
                                }
                                ForEach(cycles.keys.sorted(by: >), id: \.self) { cycle in
                                    GridRow {
                                        Text("\(cycle)").font(.headline.monospacedDigit())
                                        ForEach(rotations, id: \.self) { number in
                                            if let rotation = cycles[cycle]?.first(where: { $0.key.rotation == number }) {
                                                Button {
                                                    rotationDetail = rotationDetailText(rotation)
                                                } label: {
                                                    VStack(spacing: 3) {
                                                        Image(systemName: readinessIcon(rotation.readiness))
                                                            .foregroundStyle(readinessColor(rotation.readiness))
                                                        Text("\(rotation.completedWorkingSets)/\(rotation.plannedWorkingSets)")
                                                            .font(.caption2.monospacedDigit())
                                                        Text("\(Int(rotation.conditioningMinutes.rounded()))m")
                                                            .font(.caption2).foregroundStyle(.secondary)
                                                    }
                                                    .frame(minWidth: 54, minHeight: 54)
                                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Cycle \(cycle), rotation \(number), \(rotation.readiness.name), \(rotation.completedWorkingSets) of \(rotation.plannedWorkingSets) sets")
                                            } else {
                                                Color.clear.frame(width: 54, height: 54)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if report.rotations.isEmpty {
                    Text("Complete a full program rotation to establish the first baseline.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("No program", systemImage: "list.bullet.clipboard",
                                       description: Text("Create a program to group training by rotation."))
            }
        }
    }

    private func rollingSummary(days: Int) -> String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let recent = sessions.filter { $0.date >= cutoff }
        let work = recent.flatMap(\.exercises).flatMap(\.workingSets).filter {
            guard let exercise = $0.sessionExercise?.exercise else { return true }
            return !exercise.movementPattern.isConditioning
        }.count
        let seconds = recent.flatMap(\.exercises).filter { $0.exercise?.movementPattern.isConditioning == true }
            .flatMap(\.workingSets).compactMap(\.durationSeconds).reduce(0, +)
        return "\(work) work sets · \(seconds / 60) min conditioning"
    }

    private func readinessIcon(_ state: ReadinessState) -> String {
        switch state {
        case .green: return "circle.fill"
        case .yellow: return "circle.lefthalf.filled"
        case .red: return "exclamationmark.octagon.fill"
        case .unknown: return "circle.dotted"
        }
    }

    private func readinessColor(_ state: ReadinessState) -> Color {
        switch state {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .unknown: return .gray
        }
    }

    private func rotationDetailText(_ rotation: RotationAssessment) -> String {
        let reasons = rotation.reasons.isEmpty ? "No recommendation reasons recorded." : rotation.reasons.joined(separator: "\n")
        return "Cycle \(rotation.key.cycleNumber) · Rotation \(rotation.key.rotation)\n\n"
            + "Readiness: \(rotation.readiness.name)\n"
            + "Completed/planned: \(rotation.completedWorkingSets)/\(rotation.plannedWorkingSets) work sets\n"
            + "Conditioning: \(Int(rotation.conditioningMinutes.rounded())) min\n\n\(reasons)"
    }

    /// The log interleaves banked sessions with declared intervals — a break
    /// the lifter chose is part of the training story, not a hole in it
    /// (INV-INTERVAL-IS-NOT-A-GAP). Mirrors web history.js.
    private enum HistoryRow: Identifiable {
        case session(WorkoutSession)
        case interval(TrainingInterval)
        var id: String {
            switch self {
            case .session(let session): return "s-\(session.id)"
            case .interval(let interval): return "i-\(interval.id)"
            }
        }
        var date: Date {
            switch self {
            case .session(let session): return session.date
            case .interval(let interval): return interval.startDate
            }
        }
    }

    private func intervalRow(_ interval: TrainingInterval) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(interval.kind.name, systemImage: "calendar.badge.minus")
                .font(.callout.bold())
                .foregroundStyle(.secondary)
            Text(intervalRangeLabel(interval))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !interval.note.isEmpty {
                Text(interval.note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func intervalRangeLabel(_ interval: TrainingInterval) -> String {
        let start = interval.startDate.formatted(date: .abbreviated, time: .omitted)
        let end = interval.endDate.formatted(date: .abbreviated, time: .omitted)
        return start == end ? start : "\(start) – \(end)"
    }

    private var sessionList: some View {
        // Session volume relative to the biggest on record — the thin bar under
        // each row makes trends scannable while scrolling.
        let maxVolume = max(1, sessions.map(volumeOf).max() ?? 1)
        return List {
            if !currentYearActivities.isEmpty {
                Section("Ad-hoc work · \(Calendar.current.component(.year, from: .now))") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { activityYearStats }
                        VStack(alignment: .leading, spacing: 10) { activityYearStats }
                    }
                    Text("Off-program physical work. Reported separately from lifting volume and training cycles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(monthGroups, id: \.0) { month, items in
                Section(month) {
                    ForEach(items) { row in
                        switch row {
                        case .interval(let interval):
                            intervalRow(interval)
                        case .session(let session):
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let detail = session.activityDetail {
                                    Text(detail.kind?.exerciseName ?? "Ad-hoc work")
                                        .font(.callout.bold())
                                    Text(activityRowLine(session))
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                        .lineLimit(2)
                                } else if let lead = leadLift(session) {
                                    HStack(spacing: 6) {
                                        Text(lead.name).font(.callout.bold())
                                        Text(lead.set)
                                            .font(.callout.bold().monospacedDigit())
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                let rest = session.activityDetail == nil ? restLine(session) : ""
                                if !rest.isEmpty {
                                    Text(rest)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                let vol = session.activityDetail == nil ? volumeOf(session) : 0
                                if vol > 0 {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color(.tertiarySystemFill))
                                            Capsule().fill(Theme.accent.opacity(0.75))
                                                .frame(width: max(4, geo.size.width * vol / maxVolume))
                                        }
                                    }
                                    .frame(height: 3)
                                    .padding(.top, 3)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if session.activityDetail != nil {
                                Button(role: .destructive) {
                                    activityPendingDeletion = session
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        }
                    }
                }
            }
            if sessions.isEmpty {
                Text(Copy.emptyHistory).foregroundStyle(.secondary)
            }
        }
    }

    private var currentYearActivities: [WorkoutSession] {
        let year = Calendar.current.component(.year, from: .now)
        return sessions.filter {
            $0.activityDetail != nil && Calendar.current.component(.year, from: $0.date) == year
        }
    }

    @ViewBuilder
    private var activityYearStats: some View {
        activityStat("\(currentYearActivities.count)", label: "sessions")
        let seconds = currentYearActivities.reduce(0) { $0 + activityDurationSeconds($1) }
        activityStat(durationLabel(seconds), label: "logged time")
        let cords = currentYearActivities.compactMap { $0.activityDetail?.cordVolume }.reduce(0, +)
        if cords > 0 {
            activityStat(Weight.trim(cords, decimals: 3), label: "cords")
        }
        let workload = currentYearActivities.compactMap { ActivitySession.workload(for: $0) }.reduce(0) {
            $0 + $1.arbitraryUnits
        }
        if workload > 0 {
            activityStat(Weight.trim(workload), label: "effort AU")
        }
    }

    private func activityStat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activitySet(_ session: WorkoutSession) -> SetEntry? {
        guard let kind = session.activityDetail?.kind else { return nil }
        let stableID = StableID.exerciseLegacyID(name: kind.exerciseName)
        return session.orderedExercises.first {
            $0.exerciseID == stableID || $0.exercise?.name == kind.exerciseName
        }?.orderedSets.first
    }

    private func activityDurationSeconds(_ session: WorkoutSession) -> Int {
        session.orderedExercises.flatMap(\.workingSets).compactMap(\.durationSeconds).reduce(0, +)
    }

    private func durationLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private func activityRowLine(_ session: WorkoutSession) -> String {
        guard let detail = session.activityDetail else { return "" }
        var parts = [durationLabel(activityDurationSeconds(session))]
        if let rpe = detail.sessionRPE { parts.append("RPE \(Weight.trim(rpe))") }
        if let set = activitySet(session), set.weightLb > 0 {
            let value = set.enteredUnit == .kg ? Weight.kg(fromLb: set.weightLb) : set.weightLb
            parts.append("\(Weight.trim(value, decimals: 2)) \(set.enteredUnit.rawValue) maul")
        }
        if let cords = detail.cordVolume { parts.append("\(Weight.trim(cords, decimals: 3)) cords") }
        return parts.joined(separator: " · ")
    }

    private func volumeOf(_ session: WorkoutSession) -> Double {
        session.exercises.reduce(0) { $0 + $1.workingVolumeLb }
    }

    /// The heaviest lift of the day, emphasized; everything else rides in the sub line.
    private func leadLift(_ session: WorkoutSession) -> (name: String, set: String)? {
        let tops = session.orderedExercises.compactMap { entry -> (String, SetEntry)? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return (name, top)
        }
        guard let lead = tops.max(by: { $0.1.weightLb < $1.1.weightLb }) else { return nil }
        let w = lead.1.weightLb == 0 ? "BW" : settingsList.unitDisplay.format(lb: lead.1.weightLb)
        return (lead.0, "\(w)×\(lead.1.reps)")
    }

    private func restLine(_ session: WorkoutSession) -> String {
        let tops = session.orderedExercises.compactMap { entry -> (String, SetEntry)? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return (name, top)
        }
        guard let leadName = tops.max(by: { $0.1.weightLb < $1.1.weightLb })?.0 else { return "" }
        return tops.filter { $0.0 != leadName }
            .map { "\($0.0) \(settingsList.unitDisplay.format(lb: $0.1.weightLb))×\($0.1.reps)" }
            .joined(separator: " · ")
    }

    private var milestoneList: some View {
        List(milestones) { milestone in
            VStack(alignment: .leading, spacing: 2) {
                Label(milestone.label, systemImage: "flag.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text(milestone.date.formatted(date: .long, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var monthGroups: [(String, [HistoryRow])] {
        let rows = sessions.map(HistoryRow.session)
            + trainingIntervals.map(HistoryRow.interval)
        let groups = Dictionary(grouping: rows) {
            $0.date.formatted(.dateTime.year().month(.wide))
        }
        return groups
            .mapValues { $0.sorted { $0.date > $1.date } }
            .sorted { ($0.value.first?.date ?? .distantPast) > ($1.value.first?.date ?? .distantPast) }
    }

    private func sessionLine(_ session: WorkoutSession) -> String {
        session.orderedExercises.compactMap { entry -> String? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return "\(name) \(settingsList.unitDisplay.format(lb: top.weightLb))×\(top.reps)"
        }.joined(separator: " · ")
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]
    /// The post-correction milestone rebuild must exclude off-program spans
    /// exactly as bank time does, so it needs the same interval snapshots.
    @Query(sort: \TrainingInterval.startDate) private var correctionIntervals: [TrainingInterval]
    @AppStorage(HealthKitService.readEnabledKey) private var healthReadEnabled = false
    @State private var healthMiles: Double?
    @State private var healthEnergyKcal: Double?
    @State private var didCheckHealth = false
    /// Correction mode for a banked log: a set that never got its ✓ mid-workout
    /// or a weight banked at the stale plan can be fixed here. The corrected
    /// history is what charts, recalls, exports, and prior-best evidence read.
    /// It does NOT re-run the grading that fired at bank time — that result is
    /// already stashed in the lift's pending state — so a prescription built
    /// from the wrong base is fixed in the program editor, not here.
    @State private var isEditing = false
    /// Field text buffered per set while editing. Nothing touches the stored
    /// record until the drafts are committed (Done, or leaving the screen), so
    /// a half-typed number can never be banked by an autosave, and an
    /// untouched field is not an edit.
    @State private var setDrafts: [PersistentIdentifier: SetCorrectionDraft] = [:]
    @State private var showActivityEditor = false

    /// The conditioning sets this session actually performed. `workingSets` is
    /// already completed-and-non-warmup: a set left planned, or skipped after
    /// being edited, was not trained and must neither inflate the comparison
    /// nor be rewritten by adopting Health's number.
    private var conditioningSets: [SetEntry] {
        session.orderedExercises
            .filter { $0.exercise?.type == .conditioning }
            .flatMap(\.workingSets)
    }

    /// [INV-STAIRS-COUNT-FLIGHTS] Conditioning that measures ground covered —
    /// the sets a Health distance can honestly be compared against and written
    /// onto. A flight count is not a distance, and spreading miles across one
    /// would invent a measurement the machine never reported.
    ///
    /// Keyed on what each set HOLDS, not on the movement alone: a climb logged
    /// in miles before flights existed is still a logged distance, and dropping
    /// it here while `loggedMiles` still counted it would make the comparison
    /// and the rewrite disagree — every tap of "Use Health's…" would then move
    /// the total further from Health instead of onto it.
    private var distanceLoggingSets: [SetEntry] {
        conditioningSets.filter { set in
            if (set.flights ?? 0) > 0 { return false }
            if (set.distanceMiles ?? 0) > 0 { return true }
            // Nothing logged either way: only a movement that covers ground can
            // receive the whole-total fallback below.
            let name = set.sessionExercise?.exercise?.name ?? ""
            return !CardioFormat.climbsFlights(exerciseName: name)
        }
    }

    /// Everything this session logged as conditioning distance. Same basis as
    /// the rewrite, so adopting Health's number lands exactly on it.
    private var loggedMiles: Double? {
        let total = distanceLoggingSets.compactMap(\.distanceMiles).reduce(0, +)
        return total > 0 ? total : nil
    }

    private var healthVerdict: HealthComparison.Verdict {
        HealthComparison.compare(loggedMiles: loggedMiles, healthMiles: healthMiles)
    }

    private var completedWorkSets: [SetEntry] {
        session.orderedExercises
            .filter(isStrengthEntry)
            .flatMap(\.workingSets)
    }

    private var workingVolumeLb: Double {
        session.orderedExercises.reduce(0) { $0 + $1.workingVolumeLb }
    }

    private var durationLabel: String? {
        guard let end = session.completedAt, end > session.date else { return nil }
        let minutes = Int(end.timeIntervalSince(session.date) / 60)
        // The same one-day sanity bound the stopwatch record applies — one
        // constant, so the clock and this label cannot disagree about what a
        // plausible single-day session is.
        guard minutes > 0, minutes < Int(StopwatchRecovery.recordWindow / 60) else { return nil }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// The window to ask Health about: session creation to completion.
    ///
    /// Bounded to a single day, mirroring the guard the Health *write* path
    /// already applies in `SessionCompletion`. A session opened Monday and
    /// banked Thursday spans three days, and every unrelated walk or ride in
    /// that stretch would be fully contained in it — so it would pass the
    /// majority-overlap test, inflate the verdict, and be written into the log
    /// by the adopt button. When the window is not trustworthy there is no
    /// second opinion to offer.
    private var healthWindow: (start: Date, end: Date)? {
        guard let end = session.completedAt, end > session.date,
              Calendar.current.isDate(end, inSameDayAs: session.date) else { return nil }
        return (session.date, end)
    }

    private var unitDisplay: UnitDisplay { settingsList.unitDisplay }

    /// Strength and timed rows are correctable; conditioning is not, and a
    /// row whose library entry is gone falls back to its DATA — the same
    /// rule the read-only rendering uses.
    private func isCorrectable(_ entry: SessionExercise) -> Bool {
        isStrengthEntry(entry) || entry.exercise?.type == .timed
    }

    private func draftBinding(for set: SetEntry) -> Binding<SetCorrectionDraft> {
        Binding(get: { setDrafts[set.persistentModelID] ?? SetCorrectionDraft() },
                set: { setDrafts[set.persistentModelID] = $0 })
    }

    /// Apply every buffered draft through the shared correction rule, writing
    /// only fields that actually changed. The no-edit comparison happens HERE,
    /// against the untouched stored values — so a field still reading the
    /// stored value's display form (including a kg string whose round-trip
    /// would drift the canonical pounds) is not an edit, and the comparison
    /// basis can never move mid-typing because typing never touches the model.
    private func commitCorrections() {
        let unit = unitDisplay.primaryUnit
        var corrections: [(set: SetEntry, correction: SetLifecycle.SetCorrection)] = []
        for entry in session.orderedExercises where isCorrectable(entry) {
            for set in entry.orderedSets {
                guard let draft = setDrafts[set.persistentModelID] else { continue }
                var correction = SetLifecycle.SetCorrection(status: draft.status)
                if let text = draft.weightText, text != displayWeightText(set.weightLb, unit: unit) {
                    // The same comma-tolerant parse every entry surface uses —
                    // a decimal-comma keyboard types "92,5".
                    correction.weightLb = Double(text.replacingOccurrences(of: ",", with: "."))
                        .map { Weight.toLb($0, from: unit) }
                }
                if let text = draft.repsText, text != String(set.reps) {
                    correction.reps = Int(text)
                }
                if let text = draft.secondsText, text != (set.durationSeconds.map(String.init) ?? "") {
                    correction.durationSeconds = Int(text)
                }
                corrections.append((set: set, correction: correction))
            }
        }
        // Rebuild what the correction can deterministically rebuild — the PR
        // milestones of the touched lifts — and leave the banked grade alone
        // (epic #155 Stage 6). A failed rebuild must not swallow the
        // correction itself; the corrected sets are already applied.
        do {
            try SessionCorrectionService.applyAndRebuild(
                corrections, in: session, context: context,
                intervals: correctionIntervals.map(\.snapshot),
                formatWeight: { [unitDisplay] in unitDisplay.format(lb: $0) }
            )
        } catch {
            SessionCorrectionService.apply(corrections)
        }
    }

    var body: some View {
        List {
            if let activity = session.activityDetail {
                activitySections(activity)
            } else {
                sessionSummary
                if !session.notes.isEmpty {
                    Section("Notes") { Text(session.notes) }
                }
                healthSection
                ForEach(session.orderedExercises) { entry in
                    Section {
                        ForEach(entry.orderedSets) { set in
                        // Only strength and timed rows are correctable, keyed on
                        // the DATA when the library entry is gone (like the
                        // read-only rendering): a restored cardio record whose
                        // exercise was deleted must not grow a weight×reps
                        // editor over its distance. Conditioning corrections
                        // belong to the Health comparison flow above, which
                        // reconciles against a measurement instead of a memory.
                            if isEditing, isCorrectable(entry) {
                                HistorySetEditRow(set: set,
                                                  isTimed: entry.exercise?.type == .timed,
                                                  unitDisplay: unitDisplay,
                                                  draft: draftBinding(for: set))
                            } else {
                                HistorySetRow(set: set, type: entry.exercise?.type,
                                              unitDisplay: unitDisplay)
                            }
                        }
                        if !entry.notes.isEmpty {
                            Text(entry.notes).font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.exercise?.name ?? "Exercise")
                                if let phaseLabel = entry.truthfulPhaseLabel {
                                    Text(phaseLabel).foregroundStyle(Theme.accent)
                                }
                            }
                            Text(exerciseSummary(entry))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .onDisappear {
            // Leaving the screen commits like Done: what the fields show is
            // what banks. A read-only visit (no drafts) saves nothing.
            guard session.activityDetail == nil, isEditing, !setDrafts.isEmpty else { return }
            commitCorrections()
            if PersistenceErrorCenter.shared.save(context, operation: "Saving the workout corrections") {
                setDrafts = [:]
            }
        }
        .toolbar {
            if session.activityDetail != nil {
                Button("Edit") { showActivityEditor = true }
                    .accessibilityLabel("Edit this ad-hoc activity")
            } else if session.isCompleted {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        commitCorrections()
                        // A failed save rolls the context back; staying in edit
                        // mode with the drafts intact keeps the typed values on
                        // screen for a retry instead of dropping to read-only
                        // rows showing the reverted record.
                        if PersistenceErrorCenter.shared.save(context, operation: "Saving the workout corrections") {
                            setDrafts = [:]
                            isEditing = false
                        }
                    } else {
                        isEditing = true
                    }
                }
                .accessibilityLabel(isEditing ? "Finish editing this workout" : "Edit this workout's sets")
            }
        }
        .sheet(isPresented: $showActivityEditor) {
            ActivityQuickLogView(session: session, onDelete: { dismiss() })
        }
        .task {
            // One lookup per open, and only when there is something to compare
            // and a window to compare it over.
            guard session.activityDetail == nil,
                  !didCheckHealth, healthReadEnabled, let window = healthWindow else { return }
            didCheckHealth = true
            async let miles = HealthKitService.shared
                .conditioningDistanceMiles(start: window.start, end: window.end)
            async let energy = HealthKitService.shared
                .activeEnergyKilocalories(start: window.start, end: window.end)
            healthMiles = await miles
            healthEnergyKcal = await energy
        }
    }

    @ViewBuilder
    private func activitySections(_ detail: ActivityDetail) -> some View {
        let kind = detail.kind
        let durationSeconds = activityDurationSeconds
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("AD-HOC WORK · OFF PROGRAM")
                    .font(.caption.bold())
                    .tracking(0.9)
                    .foregroundStyle(Theme.accent)
                Text(kind?.exerciseName ?? "Ad-hoc work")
                    .font(.title2.bold())
                Text(session.date.formatted(date: .long, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(activityDurationLabel(durationSeconds))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .monospacedDigit()
                    if let rpe = detail.sessionRPE {
                        Text("RPE \(Weight.trim(rpe))")
                            .font(.title3.bold())
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        Section("Recorded facts") {
            if let set = activitySet, set.weightLb > 0 {
                let entered = set.enteredUnit == .kg ? Weight.kg(fromLb: set.weightLb) : set.weightLb
                LabeledContent("Maul", value: "\(Weight.trim(entered, decimals: 2)) \(set.enteredUnit.rawValue)")
            }
            if let rounds = detail.rounds { LabeledContent("Rounds", value: String(rounds)) }
            if let pieces = detail.splitPieces { LabeledContent("Split pieces", value: String(pieces)) }
            if let strikes = detail.estimatedStrikes { LabeledContent("Estimated strikes", value: String(strikes)) }
            if let cords = detail.cordVolume {
                LabeledContent("Cords split", value: Weight.trim(cords, decimals: 3))
            }
            if let workload = ActivitySession.workload(for: session) {
                LabeledContent("Session workload", value: "\(Weight.trim(workload.arbitraryUnits)) AU")
                Text("\(activityDurationLabel(durationSeconds)) × RPE \(Weight.trim(workload.sessionRPE)). This is relative effort, not lifting volume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if detail.sessionRPE == nil {
                Text("No effort workload calculated because session RPE was not recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !session.notes.isEmpty {
            Section("Notes") { Text(session.notes) }
        }

        Section {
            Text("This work shares the History timeline, but it never advances a program rotation, changes progression, sets a PR, or contributes barbell tonnage.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var activitySet: SetEntry? {
        guard let kind = session.activityDetail?.kind else { return nil }
        let stableID = StableID.exerciseLegacyID(name: kind.exerciseName)
        return session.orderedExercises.first {
            $0.exerciseID == stableID || $0.exercise?.name == kind.exerciseName
        }?.orderedSets.first
    }

    private var activityDurationSeconds: Int {
        session.orderedExercises.flatMap(\.workingSets).compactMap(\.durationSeconds).reduce(0, +)
    }

    private func activityDurationLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    private var sessionSummary: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.programName ?? "Standalone")
                        .font(.headline)
                    Text([
                        session.date.formatted(date: .abbreviated, time: .omitted),
                        session.gymName
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { summaryStats }
                    VStack(alignment: .leading, spacing: 8) { summaryStats }
                }
            }
        }
    }

    @ViewBuilder
    private var summaryStats: some View {
        summaryStat("\(completedWorkSets.count)", label: "work sets")
        summaryStat(workingVolumeLb > 0
                    ? unitDisplay.format(lb: workingVolumeLb)
                    : "—", label: "volume")
        if let durationLabel { summaryStat(durationLabel, label: "duration") }
    }

    private func summaryStat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exerciseSummary(_ entry: SessionExercise) -> String {
        let setName = isStrengthEntry(entry) ? "work set" : "completed set"
        var parts = ["\(entry.workingSets.count) \(setName)\(entry.workingSets.count == 1 ? "" : "s")"]
        if entry.exercise?.type != .conditioning, entry.exercise?.type != .timed,
           let top = entry.topSet {
            let load = top.weightLb == 0 ? "BW" : unitDisplay.format(lb: top.weightLb)
            parts.append("top \(load)×\(top.reps)")
        }
        if entry.workingVolumeLb > 0 {
            parts.append("\(unitDisplay.format(lb: entry.workingVolumeLb)) volume")
        }
        return parts.joined(separator: " · ")
    }

    private func isStrengthEntry(_ entry: SessionExercise) -> Bool {
        if let type = entry.exercise?.type {
            return type != .conditioning && type != .timed
        }
        return !entry.workingSets.contains {
            ($0.distanceMiles ?? 0) > 0 || ($0.flights ?? 0) > 0 || ($0.durationSeconds ?? 0) > 0
        }
    }

    /// [INV-HEALTH-IS-A-SECOND-OPINION] Both numbers, side by side, and an
    /// explicit tap to take Health's. Nothing here writes on its own, and a
    /// session with nothing in Health is silent rather than alarming.
    @ViewBuilder
    private var healthSection: some View {
        if healthReadEnabled, healthWindow != nil, showsHealthRow || healthEnergyKcal != nil {
            Section {
                if showsHealthRow {
                    Text(HealthComparison.label(healthVerdict))
                        .font(.callout)
                        .foregroundStyle(healthVerdict.isDiscrepancy ? Theme.warn : .secondary)
                    if let miles = adoptableMiles {
                        Button("Use Health's \(Weight.trim(miles, decimals: 2)) mi") {
                            adoptHealthDistance(miles)
                        }
                        .font(.callout)
                    }
                }
                // Read-only. Cadence has no heart rate and never writes an
                // energy figure of its own, so this is purely what Health
                // measured for the window.
                if let kcal = healthEnergyKcal {
                    LabeledContent("Energy", value: "\(Int(kcal.rounded())) kcal")
                        .font(.callout)
                }
            } header: {
                Text("Health")
            } footer: {
                Text("Your log stays the record. Adopting rewrites only this session's conditioning distance.")
            }
        }
    }

    /// Health's number is only offerable when there is a performed conditioning
    /// set to write it onto. Health finding a run for a session that logged no
    /// conditioning at all is worth reporting, but the button would be a no-op.
    private var adoptableMiles: Double? {
        guard !distanceLoggingSets.isEmpty else { return nil }
        return healthVerdict.adoptableMiles
    }

    /// Nothing to say, and an unworn watch, are both silence rather than a
    /// finding worth its own row.
    private var showsHealthRow: Bool {
        switch healthVerdict {
        case .neither, .onlyLogged: return false
        case .agree, .healthHigher, .loggedHigher, .onlyHealth: return true
        }
    }

    /// Both adoption paths round the same way, so a single-set session and a
    /// split one store comparably clean values.
    private static func roundedMiles(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// Write Health's number onto the single conditioning set, or spread it
    /// across several in proportion to what they already hold, so a two-leg
    /// walk keeps its shape instead of collapsing into the first set.
    private func adoptHealthDistance(_ miles: Double) {
        let sets = distanceLoggingSets
        guard !sets.isEmpty else { return }
        let existing = sets.compactMap(\.distanceMiles).reduce(0, +)
        if existing > 0 {
            for set in sets {
                guard let current = set.distanceMiles, current > 0 else { continue }
                set.distanceMiles = Self.roundedMiles(miles * (current / existing))
            }
        } else {
            sets.first?.distanceMiles = Self.roundedMiles(miles)
        }
        _ = PersistenceErrorCenter.shared.save(context, operation: "Adopting Health's distance")

        healthMiles = miles
    }

}

private struct HistorySetRow: View {
    let set: SetEntry
    let type: ExerciseType?
    let unitDisplay: UnitDisplay

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(actualLabel)
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(set.isWarmup ? .secondary : .primary)
                if let plannedLabel {
                    Text(plannedLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !set.flags.isEmpty {
                    Text(set.flags.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
                if let site = set.bodyFlagSite {
                    Label(site.rawValue + (set.bodyFlagNote.map { " — \($0)" } ?? ""),
                          systemImage: "bolt.heart.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.hardStop)
                }
            }
            Spacer(minLength: 4)
            Text(kindLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .tracking(0.35)
        }
        .accessibilityElement(children: .combine)
    }

    private var actualLabel: String {
        let performed: String
        if type == .conditioning {
            performed = CardioFormat.setLabel(distanceMiles: set.distanceMiles,
                                               durationSeconds: set.durationSeconds,
                                               inclinePercent: set.inclinePercent,
                                               loadLb: set.weightLb,
                                               flights: set.flights)
        } else if type == .timed {
            performed = CardioFormat.durationLabel(seconds: set.durationSeconds ?? 0)
        } else {
            let load = set.weightLb == 0 ? "BW" : unitDisplay.format(lb: set.weightLb)
            performed = "\(load) × \(set.reps)\(set.isPerSide ? "/side" : "")"
        }
        switch set.status {
        case .completed: return performed
        case .skipped: return "Skipped · \(performed)"
        case .planned: return "Not performed · \(performed)"
        }
    }

    private var plannedLabel: String? {
        if type == .timed, let planned = set.plannedDurationSeconds,
           planned != set.durationSeconds {
            return "Planned \(CardioFormat.durationLabel(seconds: planned))"
        }
        guard type != .conditioning, type != .timed else { return nil }
        let plannedWeight = set.plannedWeightLb ?? set.weightLb
        let plannedReps = set.plannedReps ?? set.reps
        guard abs(plannedWeight - set.weightLb) > 0.001 || plannedReps != set.reps else { return nil }
        let load = plannedWeight == 0 ? "BW" : unitDisplay.format(lb: plannedWeight)
        let earned = set.prescriptionBlock == .amrap ? "+" : ""
        return "Planned \(load) × \(plannedReps)\(earned)\(set.isPerSide ? "/side" : "")"
    }

    private var kindLabel: String {
        if set.isWarmup || set.prescriptionBlock == .warmup { return "Warm-up" }
        switch set.prescriptionBlock {
        case .warmup: return "Warm-up"
        case .primer: return "Primer"
        case .topSingle: return "Top single"
        case .ramp: return "Ramp"
        case .work: return "Work"
        case .amrap: return "AMRAP"
        case .backoff: return "Back-off"
        case .conditioning: return "Conditioning"
        }
    }

    private var statusIcon: String { statusIconName(self.set.status) }

    private var statusColor: Color {
        self.set.status == .completed ? Theme.good : .secondary
    }
}

/// The stored weight's display form in the entry unit — what an untouched
/// field reads, and what the no-edit comparison in `commitCorrections` uses.
private func displayWeightText(_ weightLb: Double, unit: WeightUnit) -> String {
    weightLb == 0 ? "" : Weight.trim(unit == .kg ? Weight.kg(fromLb: weightLb) : weightLb)
}

/// One glyph mapping for a set's status, shared by the read-only row and the
/// correction row.
private func statusIconName(_ status: SetStatus) -> String {
    switch status {
    case .completed: return "checkmark.circle.fill"
    case .skipped: return "minus.circle"
    case .planned: return "circle"
    }
}

/// Field text buffered for one set while correcting. `nil` means the field
/// was never touched — only touched fields can become corrections.
struct SetCorrectionDraft {
    var weightText: String?
    var repsText: String?
    var secondsText: String?
    var status: SetStatus?
}

/// One banked set in correction mode: cycle the status, retype the weight or
/// reps (or the hold for timed work). The row edits a DRAFT — the stored
/// record is untouched until `commitCorrections` applies every draft through
/// the shared `SetLifecycle.correctedSetValues` rule, so a half-typed number
/// is never written, an empty or garbage field keeps the stored value, and
/// nothing beyond the four performed fields is reachable. The weight edits in
/// the display's primary unit and stores canonical pounds, like every other
/// entry surface.
private struct HistorySetEditRow: View {
    let set: SetEntry
    let isTimed: Bool
    let unitDisplay: UnitDisplay
    @Binding var draft: SetCorrectionDraft

    private var unit: WeightUnit { unitDisplay.primaryUnit }
    private var effectiveStatus: SetStatus { draft.status ?? set.status }
    private var nextStatus: SetStatus { SetLifecycle.nextCorrectionStatus(effectiveStatus) }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                draft.status = nextStatus
            } label: {
                Image(systemName: statusIconName(effectiveStatus))
                    .font(.title3)
                    .foregroundStyle(effectiveStatus == .completed ? Theme.good : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Status: \(effectiveStatus.rawValue). Tap to mark \(nextStatus.rawValue)")
            if isTimed {
                editorField("Hold (seconds)",
                            text: draftField(\.secondsText,
                                             fallback: set.durationSeconds.map(String.init) ?? ""))
            } else {
                editorField("Weight (\(unit.rawValue))",
                            text: draftField(\.weightText,
                                             fallback: displayWeightText(set.weightLb, unit: unit)))
                Text("×").foregroundStyle(.secondary)
                editorField("Reps", text: draftField(\.repsText, fallback: String(set.reps)))
            }
            Spacer(minLength: 4)
            if set.isWarmup {
                Text("Warm-up").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func draftField(_ keyPath: WritableKeyPath<SetCorrectionDraft, String?>,
                            fallback: String) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? fallback },
                set: { draft[keyPath: keyPath] = $0 })
    }

    private func editorField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospacedDigit())
            .frame(maxWidth: 110)
            .accessibilityLabel(label)
    }
}

// MARK: - Progression charts

struct ProgressionChartsView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }, sort: \WorkoutSession.date)
    private var sessions: [WorkoutSession]
    @Query(filter: #Predicate<Exercise> { $0.categoryRaw == "Main" }, sort: \Exercise.name)
    private var mainLifts: [Exercise]
    @Query private var settingsList: [AppSettings]
    @Query private var programs: [Program]
    @Query(sort: \TrainingInterval.startDate)
    private var trainingIntervals: [TrainingInterval]

    // Defaults to the first main lift in the library on appear — no
    // hardcoded exercise name (the library is user data).
    @State private var selectedLift = ""
    /// Program is a FILTER over one global history, never a separate store
    /// (epic #155 Stage 5, INV-PROGRAM-IS-A-FILTER). All-time is the default;
    /// scoping narrows the same series, and which program drives Today can
    /// never change what history draws. Mirrors web `sessionInScope`.
    @State private var programScope = "all"
    @State private var plot: Plot = .progression
    @State private var metric: Metric = .topSet
    @State private var intent: ChartIntent = .mainProgression
    @State private var selectedDate: Date?
    /// Off by default: the chart's job is what happened, and a forecast is
    /// something the lifter asks for rather than something they are handed.
    @State private var horizon: TrendProjection.Horizon = .off

    enum Plot: String, CaseIterable {
        case progression = "Progression"
        case volume = "Volume"
        case repPRs = "Rep PRs"
    }

    enum Metric: String, CaseIterable {
        case topSet = "Working weight"
        case estimatedMax = "Est. 1RM"
        case all = "Weight + e1RM"
        /// Best completed working set's reps — the direct analogue of
        /// "heaviest set" for a lift whose load never changes.
        case reps = "Reps"
    }

    enum ChartIntent: String, CaseIterable {
        case mainProgression = "Main progression"
        case compareRoles = "Compare program roles"
        case compareRotations = "Compare like rotations"
    }

    /// A lift can hold a MAIN slot on one day and a COMPLEMENTARY slot on
    /// another at a much lighter base. Charting both as one line produced a
    /// sawtooth between two unrelated progressions.
    ///
    /// The third case is unprogrammed work. Inside a PROGRAM session, an entry
    /// with no role is extra work the lifter added — a few light squats on an
    /// upper day — and charting it as main dragged the progression line down to
    /// weights that were never a main effort. In a session with no program at
    /// all, an entry with no role IS the record for that lift, so it stays
    /// main. Mirrors web `chartRoleOf`.
    private enum ChartRole: String, CaseIterable {
        case main, complementary, extra
        static func of(_ entry: SessionExercise, in session: WorkoutSession) -> ChartRole {
            // An empty string is "no role", not a role: web stores empty as
            // falsy and old imports wrote "" for roleless entries, so treating
            // .some("") as programmed work would chart an unprogrammed
            // session's record as extra on this client only.
            switch entry.programRole?.isEmpty == true ? nil : entry.programRole {
            case LiftRole.complementary.rawValue: return .complementary
            case LiftRole.main.rawValue: return .main
            case .some: return .extra          // accessory, and anything added later
            case nil:
                let programmed = session.programID != nil || session.programName != nil
                return programmed ? .extra : .main
            }
        }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        /// "R1 Volume" … "R4 Deload", or "Untracked" for sessions without a
        /// cycle phase — the rotation-split series key.
        let rotation: String
        let role: ChartRole
        /// The line this point belongs to: metric and role together, so the
        /// combined view can draw weight and e1RM without them joining up.
        let series: String
    }

    private struct RepRecord: Identifiable {
        let reps: Int
        let weightLb: Double
        var id: Int { reps }
    }

    private var showComplementary: Bool { intent == .compareRoles }
    private var splitByRotation: Bool { intent == .compareRotations }
    private var visibleRoles: [ChartRole] { showComplementary ? [.main, .complementary] : [.main] }

    /// Load points (working weight and/or est. 1RM) for the visible roles.
    /// Volume is deliberately NOT a metric here — tonnage lives on its own
    /// plot (`volumeBars`), on its own zero-based scale.

    /// The block a session was logged under: its own id, with the recorded
    /// name as the legacy-only fallback (the ProgramResolution rule).
    private func programOf(_ session: WorkoutSession) -> Program? {
        if let id = session.programID { return programs.first { $0.id == id } }
        if let name = session.programName { return programs.first { $0.name == name } }
        return nil
    }

    private var scopedSessions: [WorkoutSession] {
        guard programScope != "all" else { return sessions }
        return sessions.filter { session in
            guard let program = programOf(session) else { return false }
            if programScope.hasPrefix("program:") {
                return program.id == String(programScope.dropFirst("program:".count))
            }
            if programScope.hasPrefix("style:") {
                return program.templateID == String(programScope.dropFirst("style:".count))
            }
            return true
        }
    }

    /// Only scopes this history can actually populate, so the picker never
    /// advertises an empty chart.
    private var programScopeOptions: [(value: String, label: String)] {
        var instances: [(String, String)] = []
        var styles: [String] = []
        for session in sessions {
            guard let program = programOf(session) else { continue }
            if !instances.contains(where: { $0.0 == program.id }) {
                instances.append((program.id, program.name))
            }
            if let template = program.templateID, !styles.contains(template) { styles.append(template) }
        }
        var options: [(value: String, label: String)] = [("all", "All programs (all-time)")]
        options += instances.map { ("program:\($0.0)", $0.1) }
        if styles.count > 1 || (styles.count == 1 && instances.count > 1) {
            options += styles.map { ("style:\($0)", "Style: \($0)") }
        }
        return options
    }

    private var points: [Point] {
        let display = settingsList.unitDisplay
        let shown = { (lb: Double) in display.primaryUnit == .kg ? Weight.kg(fromLb: lb) : lb }
        var result: [Point] = []
        for session in scopedSessions {
            let matching = session.exercises.filter { $0.exercise?.name == selectedLift }
            guard !matching.isEmpty else { continue }
            for role in visibleRoles {
                let entries = matching.filter { ChartRole.of($0, in: session) == role }
                guard !entries.isEmpty else { continue }
                // The session's program tag is the fallback, so accessory
                // slots and pre-phase-capture entries chart under the rotation
                // they were actually performed in instead of "Untracked".
                let rotation = ChartRotation.label(
                    entryPhase: entries.compactMap(\.phase).first?.rawValue,
                    sessionRotation: session.programWeek
                )
                let suffix = showComplementary ? " (\(role == .main ? "main" : "comp."))" : ""
                if metric == .topSet || metric == .all, let top = entries.compactMap(\.topSet?.weightLb).max() {
                    result.append(Point(date: session.date, value: shown(top), rotation: rotation,
                                        role: role, series: "Working weight\(suffix)"))
                }
                if metric == .estimatedMax || metric == .all {
                    let samples = entries.flatMap(\.workingSets).map {
                        ProgramProgression.epleyE1RM(weightLb: $0.weightLb, reps: $0.reps)
                    }
                    if let estimate = samples.max(), estimate > 0 {
                        result.append(Point(date: session.date, value: shown(estimate), rotation: rotation,
                                            role: role, series: "Est. 1RM\(suffix)"))
                    }
                }
                // A lift whose load never changes progresses by reps, so the
                // best completed working set is its "top set".
                if metric == .reps,
                   let best = entries.flatMap(\.workingSets).map(\.reps).max(), best > 0 {
                    result.append(Point(date: session.date, value: Double(best), rotation: rotation,
                                        role: role, series: "Reps\(suffix)"))
                }
            }
        }
        return result
    }

    /// Tonnage for the Volume plot. It keeps its own zero-based scale — a
    /// magnitude, not a load — so it never shares the weight axis.
    private var volumeBars: [Point] {
        let display = settingsList.unitDisplay
        return sessions.compactMap { session -> Point? in
            let entries = session.exercises.filter {
                $0.exercise?.name == selectedLift && ChartRole.of($0, in: session) == .main
            }
            let volume = entries.reduce(0) { $0 + $1.workingVolumeLb }
            guard volume > 0 else { return nil }
            return Point(date: session.date,
                         value: display.primaryUnit == .kg ? Weight.kg(fromLb: volume) : volume,
                         rotation: "", role: .main, series: "Volume")
        }
    }
    /// An unloaded pull-up has no external resistance, so working weight,
    /// est. 1RM and tonnage can only ever draw a flat zero. Offering the load
    /// metrics anyway is how promoting pull-ups to Main turned a real
    /// progression into three straight lines at 0. Mirrors web `metricOptions`.
    private var selectedIsLoaded: Bool {
        guard let exercise = mainLifts.first(where: { $0.name == selectedLift }) else { return true }
        return exercise.loadBasis.supportsLoadPR
    }

    private var availableMetrics: [Metric] {
        selectedIsLoaded ? [.topSet, .estimatedMax, .all] : [.reps]
    }

    /// Reps are a count, not a load: they carry no weight unit and never convert.
    private var chartUnitLabel: String {
        metric == .reps ? "reps" : loadUnitLabel
    }

    /// The display unit for quantities that are ALWAYS a load (tonnage),
    /// independent of the Progression tab's metric state — the Volume plot
    /// must never caption pounds as "(reps)" because a hidden picker on
    /// another tab happens to sit on the reps metric.
    private var loadUnitLabel: String {
        settingsList.unitDisplay.primaryUnit.rawValue
    }

    private var peakTarget: Double? {
        guard metric != .reps,
              let lift = (programs.first(where: \.isActive) ?? programs.first)?.days
                .flatMap(\.lifts).first(where: { $0.exerciseName == selectedLift }),
              lift.peakSingleEnabled, lift.lastPeakSingleLb > 0 else { return nil }
        let targetLb = lift.lastPeakSingleLb + lift.peakSingleIncrementLb
        return settingsList.unitDisplay.primaryUnit == .kg
            ? Weight.kg(fromLb: targetLb) : targetLb
    }

    private var repRecords: [RepRecord] {
        var best: [Int: Double] = [:]
        for session in sessions {
            for entry in session.exercises where entry.exercise?.name == selectedLift {
                for set in entry.workingSets where (1...12).contains(set.reps) {
                    best[set.reps] = max(best[set.reps, default: 0], set.weightLb)
                }
            }
        }
        return best.keys.sorted().map { RepRecord(reps: $0, weightLb: best[$0, default: 0]) }
    }

    /// Rotation → line colour: escalating heat to Peak, muted Deload.
    /// Mirrors web `ROTATION_COLORS`.
    private static let rotationPalette: [Color] = [
        Color(hex: 0x5BA06A), Color(hex: 0xE8B008), Color(hex: 0xEF4444),
        Color(hex: 0x8B9196), Color(hex: 0x666B71),
    ]
    /// Metric → line colour when not split by rotation. Working weight takes
    /// the accent; est. 1RM the green it also carries on web.
    private static let seriesPalette: [Color] = [
        Theme.accent, Color(hex: 0x5BA06A), Theme.accent.opacity(0.75), Color(hex: 0x5BA06A).opacity(0.75),
    ]

    /// Distinct line identity. Rotation split still needs the role in the key
    /// or a main and a complementary point in the same rotation would join.
    private func seriesKey(_ point: Point) -> String {
        splitByRotation ? "\(point.rotation)|\(point.role.rawValue)" : point.series
    }

    // MARK: - Projected trend

    private static let secondsPerDay: TimeInterval = 86_400
    /// Near enough to the history to read as its continuation, distinct enough
    /// to never be mistaken for a session that happened.
    private static let projectionColor = Color(hex: 0x7AA7D9)

    private struct Projection {
        let result: TrendProjection.Result
        let points: [Point]
        let horizonDate: Date
    }

    /// The projection follows the LIFT, not a rotation: it is fitted from every
    /// main-role point of the shown metric, so splitting the history into four
    /// rotation lines does not fit four separate futures through a quarter of
    /// the evidence each.
    private var projectionSeriesPrefix: String {
        switch metric {
        case .estimatedMax: return "Est. 1RM"
        case .reps: return "Reps"
        case .topSet, .all: return "Working weight"
        }
    }

    /// Main-role points, or whatever role the lift actually has. A lift that
    /// only ever occupies complementary slots would otherwise draw a full chart
    /// beside "0 of 4 sessions so far" — refusing on a role distinction the
    /// lifter never asked about. Web falls back the same way.
    private func projectionSamplePoints(in pts: [Point]) -> [Point] {
        let ofMetric = pts.filter { $0.series.hasPrefix(projectionSeriesPrefix) }
        let main = ofMetric.filter { $0.role == .main }
        return main.isEmpty ? ofMetric : main
    }

    private func projection(from pts: [Point]) -> Projection? {
        guard horizon != .off else { return nil }
        let samples = projectionSamplePoints(in: pts)
        guard let origin = samples.map(\.date).min() else { return nil }
        let day = { (date: Date) in date.timeIntervalSince(origin) / Self.secondsPerDay }
        guard let result = TrendProjection.project(
            samples: samples.map { TrendProjection.Sample(day: day($0.date), value: $0.value) },
            horizonDays: horizon.days,
            asOfDay: day(Date.now)
        ) else { return nil }
        let date = { (offset: Double) in origin.addingTimeInterval(offset * Self.secondsPerDay) }
        return Projection(
            result: result,
            points: result.points.map {
                Point(date: date($0.day), value: $0.value, rotation: "", role: .main, series: "Projected")
            },
            horizonDate: date(result.horizonDay)
        )
    }

    /// Say what the projection is, or say why there isn't one. Asking for a
    /// forecast and getting an unchanged chart back reads as a broken control,
    /// and the reason is the useful part: the refusal names what the history is
    /// missing.
    private func projectionRefusal(given projection: Projection?, in pts: [Point]) -> String? {
        guard horizon != .off, projection == nil else { return nil }
        let samples = projectionSamplePoints(in: pts)
        guard samples.count >= TrendProjection.minimumSamples else {
            return "Not enough history to project — \(samples.count) of \(TrendProjection.minimumSamples) sessions so far."
        }
        guard let first = samples.map(\.date).min(), let last = samples.map(\.date).max() else {
            return "Not enough history to project from yet."
        }
        // Compare RAW and truncate only for display. Rounding before the
        // comparison made the message disagree with the engine at the
        // boundary: a 20.6-day span refused, then explained itself as
        // "spans 21 days, and a trend needs 21".
        let span = last.timeIntervalSince(first) / Self.secondsPerDay
        guard span >= TrendProjection.minimumSpanDays else {
            return "Not enough time to project — this lift spans \(Int(span)) days, and a trend needs \(Int(TrendProjection.minimumSpanDays))."
        }
        let idle = Date.now.timeIntervalSince(last) / Self.secondsPerDay
        if idle > TrendProjection.stalenessLimitDays {
            return "Last trained \(Int(idle)) days ago — too long to extend a trend from. Log a session to project again."
        }
        return "Not enough history to project from yet."
    }

    /// The value range every load mark occupies, so the future shading spans
    /// the plot without depending on the chart's derived domain. Volume bars
    /// are excluded — they ride their own scale and would drag the band down
    /// past the load lines it is meant to sit behind.
    private func loadRange(in pts: [Point], including projection: Projection) -> (low: Double, high: Double)? {
        let values = pts.map(\.value) + projection.points.map(\.value)
        guard let low = values.min(), let high = values.max(), high > low else { return nil }
        return (low, high)
    }

    /// Values are already in the display unit — the chart converts before it
    /// builds points, and a linear fit commutes with that scaling — so the
    /// headline needs the unit appended, not converted again.
    /// Reps are whole — a projected "12.4 reps" is precision the count does
    /// not have. Mirrors the web summary's rounding.
    private func chartValueLabel(_ value: Double) -> String {
        metric == .reps ? String(Int(value.rounded())) : Weight.trim(value)
    }

    private func projectionSummary(_ projection: Projection) -> String {
        TrendProjection.summary(
            perWeek: projection.result.perWeek,
            horizonLabel: horizon.label,
            horizonValue: "\(chartValueLabel(projection.result.horizonValue)) \(chartUnitLabel)",
            unit: chartUnitLabel
        )
    }

    /// Whether the fit-description caption should call this trend out as flat.
    /// Separate from `projectionSummary`'s own "Holding flat" wording, which
    /// fires on the rounded rate alone regardless of how noisy the fit is.
    private func isTrendPlateaued(_ projection: Projection) -> Bool {
        TrendProjection.isPlateaued(perWeek: projection.result.perWeek, fitQuality: projection.result.fitQuality)
    }

    /// A single series, drawn on its own, is the only case where an area fill
    /// is depth rather than clutter. Rotation split and the combined metric
    /// both put several lines on the plot, and translucent areas over each
    /// other read as regions that mean something.
    private func showsAreaFill(_ pts: [Point]) -> Bool {
        !splitByRotation && Set(pts.map(\.series)).count == 1
    }

    /// X-axis selection identifies a session date. Draw every visible series
    /// at that date so a combined weight/e1RM chart does not pretend the user
    /// selected one of two coincident records when the gesture only selected
    /// their shared exposure.
    private func selectedChartPoints(in pts: [Point]) -> [Point] {
        guard let selectedDate,
              let nearest = pts.min(by: {
                  abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
              }) else { return [] }
        return pts.filter { abs($0.date.timeIntervalSince(nearest.date)) < 1 }
    }

    /// Declared training breaks as shaded bands BEHIND the lines (issue #97):
    /// a plateau or a drop should carry its visible cause. Clamped to the
    /// plotted span — a break outside it has nothing to explain here.
    /// Mirrors web progressionChart's interval bands.
    @ChartContentBuilder
    private func intervalBands(_ pts: [Point]) -> some ChartContent {
        let dates = pts.map(\.date)
        if let minDate = dates.min(), let maxDate = dates.max(), minDate < maxDate {
            ForEach(trainingIntervals) { interval in
                let snapshot = interval.snapshot
                let start = Date(timeIntervalSince1970: snapshot.startMs / 1000)
                let end = Date(timeIntervalSince1970: snapshot.endMs / 1000)
                if start < maxDate && end > minDate {
                    RectangleMark(
                        xStart: .value("Break start", max(start, minDate)),
                        xEnd: .value("Break end", min(end, maxDate))
                    )
                    .foregroundStyle(Color.secondary.opacity(0.12))
                }
            }
        }
    }

    @ChartContentBuilder
    private func futureBand(_ pts: [Point], _ trend: Projection?) -> some ChartContent {
        if let trend, let range = loadRange(in: pts, including: trend) {
            RectangleMark(
                xStart: .value("Today", Date.now),
                xEnd: .value("Horizon", trend.horizonDate),
                yStart: .value(chartUnitLabel, range.low),
                yEnd: .value(chartUnitLabel, range.high)
            )
            .foregroundStyle(Color.secondary.opacity(0.07))
        }
    }

    @ChartContentBuilder
    private func performedMarks(_ pts: [Point]) -> some ChartContent {
        if showsAreaFill(pts) {
            ForEach(pts) { point in
                AreaMark(x: .value("Date", point.date),
                         y: .value(chartUnitLabel, point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
        }
        ForEach(pts) { point in
            LineMark(x: .value("Date", point.date),
                     y: .value(chartUnitLabel, point.value),
                     series: .value("Series", seriesKey(point)))
                .interpolationMethod(.monotone)
                .foregroundStyle(by: .value("Series", splitByRotation ? point.rotation : point.series))
                .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round,
                                       dash: point.role == .complementary ? [5, 4] : []))
            PointMark(x: .value("Date", point.date),
                      y: .value(chartUnitLabel, point.value))
                .foregroundStyle(by: .value("Series", splitByRotation ? point.rotation : point.series))
                .symbolSize(point.role == .complementary ? 28 : 44)
        }
    }

    @ChartContentBuilder
    private var peakTargetMark: some ChartContent {
        if let peakTarget {
            RuleMark(y: .value("Peak target", peakTarget))
                .foregroundStyle(Theme.accent.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Peak target \(Weight.trim(peakTarget))")
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
        }
    }

    @ChartContentBuilder
    private func projectionMarks(_ trend: Projection?) -> some ChartContent {
        if let trend {
            ForEach(trend.points) { point in
                LineMark(x: .value("Date", point.date),
                         y: .value(chartUnitLabel, point.value),
                         series: .value("Series", "Projected"))
                    .foregroundStyle(Self.projectionColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 5]))
            }
            PointMark(x: .value("Date", trend.horizonDate),
                      y: .value(chartUnitLabel, trend.result.horizonValue))
                .foregroundStyle(Self.projectionColor)
                .symbolSize(36)
                .annotation(position: .top, alignment: .trailing) {
                    Text(chartValueLabel(trend.result.horizonValue))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(Self.projectionColor)
                }
            RuleMark(x: .value("Today", Date.now))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("today")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ChartContentBuilder
    private func selectionMarks(_ pts: [Point]) -> some ChartContent {
        let selected = selectedChartPoints(in: pts)
        if let first = selected.first {
            RuleMark(x: .value("Selected session", first.date))
                .foregroundStyle(Color.primary.opacity(0.22))
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(selected) { point in
                PointMark(x: .value("Selected session", point.date),
                          y: .value(chartUnitLabel, point.value))
                    .foregroundStyle(Color(.systemBackground))
                    .symbolSize(96)
                PointMark(x: .value("Selected session", point.date),
                          y: .value(chartUnitLabel, point.value))
                    .foregroundStyle(Color.primary)
                    .symbolSize(42)
            }
        }
    }

    private var chartCaption: String {
        let metricLabel: String
        switch metric {
        case .topSet: metricLabel = "Top working weight"
        case .estimatedMax: metricLabel = "Estimated 1RM"
        case .all: metricLabel = "Working weight and est. 1RM"
        case .reps: metricLabel = "Best working set"
        }
        let role = showComplementary ? " · solid = main, dashed = complementary" : " · main slots only"
        return "\(metricLabel) per session (\(chartUnitLabel))\(role)"
    }

    /// One caption style for all three plots, so a styling tweak cannot land
    /// on only some of them.
    private func plotCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    var body: some View {
        // Datasets are bound ONCE per render: `points` is a full
        // sessions×entries scan that the marks, legend, selection, and
        // projection would otherwise each re-run (with fresh UUID identities
        // defeating chart diffing), and it is only computed while its plot is
        // visible. Fit only while the progression plot is visible — volume
        // and rep PRs are recorded views, not alternate canvases for a
        // hidden forecast.
        let pts = plot == .progression ? points : []
        let trend = plot == .progression ? projection(from: pts) : nil
        // A ScrollView, so the chart's minimum height can never clip the
        // captions, selected-point detail, or projection summary off-screen
        // on small screens or large Dynamic Type. The collapsed-strip bug
        // this view fixes came from flexible-height compression, which the
        // per-plot minimum heights prevent — with those in place the scroll
        // only ever appears when content genuinely overflows.
        return ScrollView {
            VStack(spacing: 12) {
                Picker("Lift", selection: $selectedLift) {
                    ForEach(mainLifts) { Text($0.name).tag($0.name) }
                }
                .onAppear { if selectedLift.isEmpty { selectedLift = defaultLiftName } }
                // Switching to a bodyweight lift while a load metric is selected
                // would otherwise strand the chart on a metric it can only draw
                // as zero. Mirrors the web picker's clamp.
                .onChange(of: selectedLift, initial: true) {
                    selectedDate = nil
                    if !availableMetrics.contains(metric) { metric = availableMetrics[0] }
                }
                Picker("Plot", selection: $plot) {
                    ForEach(Plot.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: plot) { selectedDate = nil }

                if plot == .progression {
                    Picker("Metric", selection: $metric) {
                        ForEach(availableMetrics, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: metric) { selectedDate = nil }
                    Picker("Chart intent", selection: $intent) {
                        ForEach(ChartIntent.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if programScopeOptions.count > 1 {
                        Picker("Program", selection: $programScope) {
                            ForEach(programScopeOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: programScope) { selectedDate = nil }
                    }
                    Picker("Project forward", selection: $horizon) {
                        ForEach(TrendProjection.Horizon.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Project forward")
                    .accessibilityHint("Extends the trend fitted from performed sessions past today")
                }

                switch plot {
                case .progression: progressionPlot(pts, trend)
                case .volume: volumePlot
                case .repPRs: repPRPlot
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func progressionPlot(_ pts: [Point], _ trend: Projection?) -> some View {
        if pts.isEmpty {
            // A lift that only ever occupied complementary slots has no main
            // points but can hold real rep PRs — say where they are instead
            // of asserting there is no history at all.
            ContentUnavailableView(Copy.emptyHistory, systemImage: "chart.xyaxis.line",
                                   description: repRecords.isEmpty
                                       ? nil : Text("Rep PRs for this lift are under the Rep PRs plot."))
        } else {
            Chart {
                intervalBands(pts)
                futureBand(pts, trend)
                performedMarks(pts)
                peakTargetMark
                projectionMarks(trend)
                selectionMarks(pts)
            }
            .chartForegroundStyleScale(range: splitByRotation ? Self.rotationPalette : Self.seriesPalette)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartLegend(Set(pts.map(\.series)).count > 1 ? .visible : .hidden)
            .chartXSelection(value: $selectedDate)
            .historyChartViewport(min: 220, ideal: 280)
            plotCaption(chartCaption)
            if let detail = selectedPointDetail {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .accessibilityLabel(detail)
            }
            if let trend {
                VStack(alignment: .leading, spacing: 3) {
                    Text(projectionSummary(trend))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Self.projectionColor)
                    Text("\(TrendProjection.fitDescription(trend.result.fitQuality))\(isTrendPlateaued(trend) ? " · Plateaued" : "") · fitted from performed sessions — a continuation of the past, not a plan.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
            } else if let refusal = projectionRefusal(given: trend, in: pts) {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var volumePlot: some View {
        // Which lifts earn a tonnage chart is decided by the lift's CURRENT
        // load basis — the same rule that strips load metrics from the
        // Metric picker, mirrored from web `metricOptions`. Sets snapshot the
        // basis they were logged under, so a lift re-based to bodyweight or
        // assisted can still hold volumeLb > 0 history; charting it would
        // present tonnage the lift's own semantics say is not meaningful,
        // and a genuinely unloaded lift would read "No volume history" as
        // lost data. Explain instead.
        if !selectedIsLoaded {
            ContentUnavailableView("Volume is tonnage", systemImage: "chart.bar.xaxis",
                                   description: Text("This lift tracks reps, not external load, so it has no volume to chart."))
        } else {
            let bars = volumeBars
            if bars.isEmpty {
                ContentUnavailableView(Copy.emptyVolume, systemImage: "chart.bar.xaxis")
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Date", bar.date), y: .value("Volume", bar.value))
                        .foregroundStyle(Color(hex: 0x8B9196).opacity(0.55))
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .historyChartViewport(min: 260, ideal: 340)
                // loadUnitLabel, not chartUnitLabel: tonnage is always a load,
                // whatever metric the (hidden) Progression picker sits on.
                plotCaption("Working volume per session (\(loadUnitLabel)) · main slots only")
            }
        }
    }

    @ViewBuilder
    private var repPRPlot: some View {
        let records = repRecords
        if records.isEmpty {
            ContentUnavailableView(Copy.emptyRepPRs, systemImage: "chart.line.uptrend.xyaxis")
        } else {
            Chart(records) { record in
                LineMark(x: .value("Reps", record.reps),
                         y: .value("Weight", displayRepWeight(record.weightLb)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent)
                PointMark(x: .value("Reps", record.reps),
                          y: .value("Weight", displayRepWeight(record.weightLb)))
                    .foregroundStyle(Theme.accent)
            }
            .historyChartViewport(min: 240, ideal: 300)
            plotCaption("Best completed working set at each rep count")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(record.reps) rep\(record.reps == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(settingsList.unitDisplay.format(lb: record.weightLb))
                                .font(.callout.bold().monospacedDigit())
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var defaultLiftName: String {
        if let program = programs.first(where: \.isActive) ?? programs.first,
           let day = program.nextDay,
           let lift = day.orderedLifts.first(where: { $0.role == .main }),
           mainLifts.contains(where: { $0.name == lift.exerciseName }) {
            return lift.exerciseName
        }
        for session in sessions.reversed() {
            if let name = session.orderedExercises.first(where: { $0.exercise?.category == .main })?.exercise?.name {
                return name
            }
        }
        return mainLifts.first?.name ?? ""
    }

    private func displayRepWeight(_ lb: Double) -> Double {
        settingsList.unitDisplay.primaryUnit == .kg ? Weight.kg(fromLb: lb) : lb
    }

    private var selectedPointDetail: String? {
        guard let selectedDate,
              let session = sessions.min(by: {
                  abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
              }) else { return nil }
        let matching = session.exercises.filter { $0.exercise?.name == selectedLift }
        let entries = matching.filter { visibleRoles.contains(ChartRole.of($0, in: session)) }
        guard let entry = entries.first,
              let top = entry.workingSets.max(by: { $0.weightLb < $1.weightLb }) else { return nil }
        let estimate = entry.workingSets.map {
            ProgramProgression.epleyE1RM(weightLb: $0.weightLb, reps: $0.reps)
        }.max() ?? 0
        let role = ChartRole.of(entry, in: session).rawValue
        let rotation = ChartRotation.label(entryPhase: entry.phase?.rawValue, sessionRotation: session.programWeek)
        let display = settingsList.unitDisplay
        return "\(session.date.formatted(date: .abbreviated, time: .omitted)) · \(display.format(lb: top.weightLb)) × \(top.reps) · e1RM \(display.format(lb: estimate)) · \(role) · \(rotation)"
    }
}

/// The collapse fix, in one place. A history chart gets a real minimum
/// height and wins the layout competition — a flexible-height chart beside
/// fixed-height siblings is exactly how the collapsed-strip bug happened —
/// plus the leading Y axis and the shared horizontal inset every plot
/// carries. Route every plot through this so the next one cannot forget
/// half the incantation.
private extension View {
    func historyChartViewport(min minHeight: CGFloat, ideal idealHeight: CGFloat) -> some View {
        self
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(minHeight: minHeight, idealHeight: idealHeight, maxHeight: .infinity)
            .layoutPriority(1)
            .padding(.horizontal)
    }
}
