import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Sessions, milestones, and per-lift progression charts.
struct HistoryView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted },
           sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Milestone.date, order: .reverse) private var milestones: [Milestone]
    @Query private var settingsList: [AppSettings]
    @Query private var programs: [Program]
    @Query private var exercises: [Exercise]
    @Query private var checkIns: [CheckIn]

    @State private var view: ViewMode = .rotations

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
            .navigationTitle("History")
        }
    }

    private var rotationList: some View {
        List {
            if let program = programs.first(where: { $0.isActive }) ?? programs.first {
                let report = CoachingService.report(
                    program: program, sessions: sessions,
                    exercises: exercises, checkIns: checkIns
                )
                Section("Rolling load") {
                    LabeledContent("14 days", value: rollingSummary(days: 14))
                    LabeledContent("28 days", value: rollingSummary(days: 28))
                    Text("Working sets and conditioning are separate; warm-ups are excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(report.rotations.reversed()), id: \.key) { rotation in
                    Section("Cycle \(rotation.key.cycleNumber) · R\(rotation.key.rotation)") {
                        HStack {
                            Label(rotation.readiness.name, systemImage: readinessIcon(rotation.readiness))
                                .foregroundStyle(readinessColor(rotation.readiness))
                            Spacer()
                            Text("\(rotation.completedWorkingSets)/\(rotation.plannedWorkingSets) sets")
                                .font(.callout.monospacedDigit())
                        }
                        ForEach(rotation.patternSets.keys.sorted { $0.name < $1.name }, id: \.self) { pattern in
                            if !pattern.isConditioning {
                                LabeledContent(pattern.name, value: "\(rotation.patternSets[pattern, default: 0])")
                            }
                        }
                        LabeledContent("Conditioning", value: "\(Int(rotation.conditioningMinutes.rounded())) min")
                        if let reason = rotation.reasons.first {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
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

    private var sessionList: some View {
        // Session volume relative to the biggest on record — the thin bar under
        // each row makes trends scannable while scrolling.
        let maxVolume = max(1, sessions.map(volumeOf).max() ?? 1)
        return List {
            ForEach(monthGroups, id: \.0) { month, items in
                Section(month) {
                    ForEach(items) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let lead = leadLift(session) {
                                    HStack(spacing: 6) {
                                        Text(lead.name).font(.callout.bold())
                                        Text(lead.set)
                                            .font(.callout.bold().monospacedDigit())
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                let rest = restLine(session)
                                if !rest.isEmpty {
                                    Text(rest)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                let vol = volumeOf(session)
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
                    }
                }
            }
            if sessions.isEmpty {
                Text(Copy.emptyHistory).foregroundStyle(.secondary)
            }
        }
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
        let w = lead.1.weightLb == 0 ? "BW" : (settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lead.1.weightLb)
        return (lead.0, "\(w)×\(lead.1.reps)")
    }

    private func restLine(_ session: WorkoutSession) -> String {
        let tops = session.orderedExercises.compactMap { entry -> (String, SetEntry)? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return (name, top)
        }
        guard let leadName = tops.max(by: { $0.1.weightLb < $1.1.weightLb })?.0 else { return "" }
        return tops.filter { $0.0 != leadName }
            .map { "\($0.0) \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: $0.1.weightLb))×\($0.1.reps)" }
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

    private var monthGroups: [(String, [WorkoutSession])] {
        let groups = Dictionary(grouping: sessions) {
            $0.date.formatted(.dateTime.year().month(.wide))
        }
        return groups.sorted { ($0.value.first?.date ?? .distantPast) > ($1.value.first?.date ?? .distantPast) }
    }

    private func sessionLine(_ session: WorkoutSession) -> String {
        session.orderedExercises.compactMap { entry -> String? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return "\(name) \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: top.weightLb))×\(top.reps)"
        }.joined(separator: " · ")
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    let session: WorkoutSession
    @Query private var settingsList: [AppSettings]

    var body: some View {
        List {
            if !session.notes.isEmpty {
                Section("Notes") { Text(session.notes) }
            }
            ForEach(session.orderedExercises) { entry in
                Section {
                    ForEach(entry.orderedSets) { set in
                        HStack {
                            // Cardio sets carry distance/time/incline, not
                            // weight×reps — same shared label as the logger.
                            // Lookup via plain helper funcs, not inline lets
                            // (type-checker budget — see CompileRegressionTests).
                            Text(Self.setLine(set, type: entry.exercise?.type,
                                              unitDisplay: settingsList.first?.unitDisplay ?? .lbPrimary))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(set.isWarmup ? .secondary : .primary)
                            if entry.exercise?.type != .conditioning && entry.exercise?.type != .timed {
                                Text("× \(set.reps)\(set.isPerSide ? "/side" : "")")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !set.isWarmup && set.status != .completed {
                                Text(set.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !set.flags.isEmpty {
                                Text(set.flags.map(\.rawValue).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.warn)
                            }
                            if let site = set.bodyFlagSite {
                                Label(site.rawValue, systemImage: "bolt.heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.hardStop)
                            }
                        }
                    }
                    if !entry.notes.isEmpty {
                        Text(entry.notes).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text(entry.exercise?.name ?? "Exercise")
                        if let phase = entry.phase {
                            Text(phase.label).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
    }

    /// Lead label for a set line: cardio → the shared distance/time/incline
    /// label; lifts → weight (both units) or BW.
    private static func setLine(_ set: SetEntry, type: ExerciseType?, unitDisplay: UnitDisplay) -> String {
        if type == .conditioning {
            return CardioFormat.setLabel(distanceMiles: set.distanceMiles,
                                         durationSeconds: set.durationSeconds,
                                         inclinePercent: set.inclinePercent)
        }
        if type == .timed { return CardioFormat.durationLabel(seconds: set.durationSeconds ?? 0) }
        return set.weightLb == 0 ? "BW" : unitDisplay.format(lb: set.weightLb)
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

    // Defaults to the first main lift in the library on appear — no
    // hardcoded exercise name (the library is user data).
    @State private var selectedLift = ""
    @State private var metric: Metric = .topSet
    @State private var splitByRotation = false

    enum Metric: String, CaseIterable {
        case topSet = "Working weight"
        case estimatedMax = "Est. 1RM"
        case volume = "Volume"
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        /// "R1 Volume" … "R4 Deload", or "Untracked" for sessions without a
        /// cycle phase — the rotation-split series key.
        let rotation: String
    }

    private struct RepRecord: Identifiable {
        let reps: Int
        let weightLb: Double
        var id: Int { reps }
    }

    private var points: [Point] {
        let display = settingsList.first?.unitDisplay ?? .lbPrimary
        return sessions.compactMap { session -> Point? in
            let entries = session.exercises.filter { $0.exercise?.name == selectedLift }
            guard !entries.isEmpty else { return nil }
            let phase = entries.compactMap(\.phase).first
            let rotation = phase.map { "R\($0.rawValue) \($0.name)" } ?? "Untracked"
            switch metric {
            case .topSet:
                guard let top = entries.compactMap(\.topSet?.weightLb).max() else { return nil }
                return Point(date: session.date, value: display.primaryUnit == .kg ? Weight.kg(fromLb: top) : top, rotation: rotation)
            case .estimatedMax:
                let samples = entries.flatMap(\.workingSets).map {
                    ProgramProgression.epleyE1RM(weightLb: $0.weightLb, reps: $0.reps)
                }
                guard let estimate = samples.max(), estimate > 0 else { return nil }
                return Point(date: session.date,
                             value: display.primaryUnit == .kg ? Weight.kg(fromLb: estimate) : estimate,
                             rotation: rotation)
            case .volume:
                let volume = entries.reduce(0) { $0 + $1.workingVolumeLb }
                let shown = display.primaryUnit == .kg ? Weight.kg(fromLb: volume) : volume
                return volume > 0 ? Point(date: session.date, value: shown, rotation: rotation) : nil
            }
        }
    }
    private var chartUnitLabel: String { (settingsList.first?.unitDisplay ?? .lbPrimary).primaryUnit.rawValue }

    private var peakTarget: Double? {
        guard metric != .volume,
              let lift = (programs.first(where: \.isActive) ?? programs.first)?.days
                .flatMap(\.lifts).first(where: { $0.exerciseName == selectedLift }),
              lift.peakSingleEnabled, lift.lastPeakSingleLb > 0 else { return nil }
        let targetLb = lift.lastPeakSingleLb + lift.peakSingleIncrementLb
        return (settingsList.first?.unitDisplay ?? .lbPrimary).primaryUnit == .kg
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
    private static let rotationColors: KeyValuePairs<String, Color> = [
        "R1 Volume": Color(hex: 0x5BA06A), "R2 Load": Color(hex: 0xE8B008),
        "R3 Peak": Color(hex: 0xEF4444), "R4 Deload": Color(hex: 0x8B9196),
        "Untracked": Color(hex: 0x666B71),
    ]

    var body: some View {
        VStack(spacing: 12) {
            Picker("Lift", selection: $selectedLift) {
                ForEach(mainLifts) { Text($0.name).tag($0.name) }
            }
            .onAppear { if selectedLift.isEmpty { selectedLift = mainLifts.first?.name ?? "" } }
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            // One line per rotation: compare this cycle's R1 against last
            // cycle's R1 instead of reading a sawtooth.
            Toggle("Split by rotation", isOn: $splitByRotation)
                .font(.callout)

            if points.isEmpty {
                ContentUnavailableView(Copy.emptyHistory, systemImage: "chart.xyaxis.line")
            } else if splitByRotation {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(chartUnitLabel, point.value),
                                 series: .value("Rotation", point.rotation))
                            .foregroundStyle(by: .value("Rotation", point.rotation))
                        PointMark(x: .value("Date", point.date), y: .value(chartUnitLabel, point.value))
                            .foregroundStyle(by: .value("Rotation", point.rotation))
                    }
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
                .chartForegroundStyleScale(Self.rotationColors)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(maxHeight: 280)
                .padding(.horizontal)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(chartUnitLabel, point.value))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", point.date), y: .value(chartUnitLabel, point.value))
                            .foregroundStyle(Theme.accent)
                    }
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
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(maxHeight: 280)
                .padding(.horizontal)
            }
            if !repRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rep PRs").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(repRecords) { record in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(record.reps) rep\(record.reps == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: record.weightLb))
                                        .font(.callout.bold().monospacedDigit())
                                }
                                .padding(10)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
