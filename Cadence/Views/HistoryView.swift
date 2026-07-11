import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Sessions, milestones, and per-lift progression charts.
struct HistoryView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Milestone.date, order: .reverse) private var milestones: [Milestone]

    @State private var view: ViewMode = .list

    enum ViewMode: String, CaseIterable {
        case list = "Log"
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
                case .charts: ProgressionChartsView()
                case .milestones: milestoneList
                }
            }
            .navigationTitle("History")
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
                                        Capsule().fill(Color(.tertiarySystemFill))
                                        Capsule().fill(Theme.accent.opacity(0.75))
                                            .frame(width: max(4, geo.size.width * vol / maxVolume))
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
        let w = lead.1.weightLb == 0 ? "BW" : Weight.trim(lead.1.weightLb)
        return (lead.0, "\(w)×\(lead.1.reps)")
    }

    private func restLine(_ session: WorkoutSession) -> String {
        let tops = session.orderedExercises.compactMap { entry -> (String, SetEntry)? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return (name, top)
        }
        guard let leadName = tops.max(by: { $0.1.weightLb < $1.1.weightLb })?.0 else { return "" }
        return tops.filter { $0.0 != leadName }
            .map { "\($0.0) \(Weight.trim($0.1.weightLb))×\($0.1.reps)" }
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
            return "\(name) \(Weight.trim(top.weightLb))×\(top.reps)"
        }.joined(separator: " · ")
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    let session: WorkoutSession

    var body: some View {
        List {
            if !session.notes.isEmpty {
                Section("Notes") { Text(session.notes) }
            }
            ForEach(session.orderedExercises) { entry in
                Section {
                    ForEach(entry.orderedSets) { set in
                        HStack {
                            Text(set.weightLb == 0 ? "BW" : Weight.both(lb: set.weightLb))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(set.isWarmup ? .secondary : .primary)
                            Text("× \(set.reps)\(set.isPerSide ? "/side" : "")")
                                .foregroundStyle(.secondary)
                            Spacer()
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
}

// MARK: - Progression charts

struct ProgressionChartsView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(filter: #Predicate<Exercise> { $0.categoryRaw == "Main" }, sort: \Exercise.name)
    private var mainLifts: [Exercise]

    @State private var selectedLift = "Deadlift"
    @State private var metric: Metric = .topSet
    @State private var splitByRotation = false

    enum Metric: String, CaseIterable {
        case topSet = "Working weight"
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

    private var points: [Point] {
        sessions.compactMap { session -> Point? in
            let entries = session.exercises.filter { $0.exercise?.name == selectedLift }
            guard !entries.isEmpty else { return nil }
            let phase = entries.compactMap(\.phase).first
            let rotation = phase.map { "R\($0.rawValue) \($0.name)" } ?? "Untracked"
            switch metric {
            case .topSet:
                guard let top = entries.compactMap(\.topSet?.weightLb).max() else { return nil }
                return Point(date: session.date, value: top, rotation: rotation)
            case .volume:
                let volume = entries.reduce(0) { $0 + $1.workingVolumeLb }
                return volume > 0 ? Point(date: session.date, value: volume, rotation: rotation) : nil
            }
        }
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
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("lb", point.value),
                             series: .value("Rotation", point.rotation))
                        .foregroundStyle(by: .value("Rotation", point.rotation))
                    PointMark(x: .value("Date", point.date), y: .value("lb", point.value))
                        .foregroundStyle(by: .value("Rotation", point.rotation))
                }
                .chartForegroundStyleScale(Self.rotationColors)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(maxHeight: 280)
                .padding(.horizontal)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("lb", point.value))
                        .foregroundStyle(Theme.accent)
                    PointMark(x: .value("Date", point.date), y: .value("lb", point.value))
                        .foregroundStyle(Theme.accent)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(maxHeight: 280)
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
