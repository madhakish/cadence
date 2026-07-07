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
        List {
            ForEach(monthGroups, id: \.0) { month, items in
                Section(month) {
                    ForEach(items) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.headline)
                                Text(sessionLine(session))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
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

    enum Metric: String, CaseIterable {
        case topSet = "Working weight"
        case volume = "Volume"
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var points: [Point] {
        sessions.compactMap { session -> Point? in
            let entries = session.exercises.filter { $0.exercise?.name == selectedLift }
            guard !entries.isEmpty else { return nil }
            switch metric {
            case .topSet:
                guard let top = entries.compactMap(\.topSet?.weightLb).max() else { return nil }
                return Point(date: session.date, value: top)
            case .volume:
                let volume = entries.reduce(0) { $0 + $1.workingVolumeLb }
                return volume > 0 ? Point(date: session.date, value: volume) : nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Lift", selection: $selectedLift) {
                ForEach(mainLifts) { Text($0.name).tag($0.name) }
            }
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                ContentUnavailableView(Copy.emptyHistory, systemImage: "chart.xyaxis.line")
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
