import SwiftUI
import SwiftData
import CadenceCore

/// Per-site signal timeline: every body flag and morning check-in across
/// weeks, one site at a time. Lightweight pattern-spotting, not medical.
struct InjuryTimelineView: View {
    @Environment(\.modelContext) private var context
    @Query private var allSets: [SetEntry]
    @Query(sort: \CheckIn.date, order: .reverse) private var checkIns: [CheckIn]

    @State private var site: BodySite = .leftShoulder
    @State private var showCheckIn = false

    private struct TimelineItem: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let detail: String
        let isHardStop: Bool
    }

    private var items: [TimelineItem] {
        let flagged = allSets
            .filter { $0.bodyFlagSite == site }
            .map { set -> TimelineItem in
                let session = set.sessionExercise?.session
                let exercise = set.sessionExercise?.exercise?.name ?? "Set"
                return TimelineItem(
                    date: session?.date ?? .distantPast,
                    title: "\(exercise) — \(Weight.trim(set.weightLb))×\(set.reps)",
                    detail: set.bodyFlagNote ?? "",
                    isHardStop: false
                )
            }
        let checks = checkIns
            .filter { $0.site == site }
            .map { check in
                TimelineItem(
                    date: check.date,
                    title: "Check-in: \(check.response)",
                    detail: check.note,
                    isHardStop: check.isHardStop
                )
            }
        return (flagged + checks).sorted { $0.date > $1.date }
    }

    private var latestKneeHardStop: Bool {
        guard site == .rightKnee else { return false }
        return checkIns.first { $0.site == .rightKnee }?.isHardStop ?? false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Site", selection: $site) {
                    ForEach(BodySite.allCases) { Text(shortName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if latestKneeHardStop {
                    Label(Copy.swelling, systemImage: "hand.raised.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.bigTap)
                        .background(Theme.hardStop.opacity(0.25))
                        .foregroundStyle(Theme.hardStop)
                }

                List {
                    Section {
                        Text(site.watchNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Section("Timeline") {
                        if items.isEmpty {
                            Text("No signals logged. Good.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.title).font(.headline)
                                    if item.isHardStop {
                                        Image(systemName: "hand.raised.fill")
                                            .foregroundStyle(Theme.hardStop)
                                    }
                                }
                                if !item.detail.isEmpty {
                                    Text(item.detail).font(.callout)
                                }
                                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Signals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCheckIn = true
                    } label: {
                        Label("Check-in", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCheckIn) {
                CheckInSheet(site: site)
                    .presentationDetents([.medium])
            }
        }
    }

    private func shortName(_ site: BodySite) -> String {
        switch site {
        case .leftShoulder: return "L shoulder"
        case .leftHip: return "L hip"
        case .rightKnee: return "R knee"
        }
    }
}

/// Morning check-in entry ("Right knee — any swelling?").
struct CheckInSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let site: BodySite
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(site == .rightKnee ? "Any swelling?" : "How is it?") {
                    Button {
                        save(response: site == .rightKnee ? "No swelling" : "Fine")
                    } label: {
                        Label(Copy.noSwelling, systemImage: "checkmark")
                            .foregroundStyle(Theme.good)
                    }
                    Button {
                        save(response: site == .rightKnee ? "Swelling" : "Flagged")
                    } label: {
                        Label(site == .rightKnee ? Copy.swelling : "Something's off",
                              systemImage: "hand.raised.fill")
                            .foregroundStyle(Theme.hardStop)
                    }
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(site.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save(response: String) {
        context.insert(CheckIn(site: site, response: response, note: note))
        if PersistenceErrorCenter.shared.save(context, operation: "Saving the check-in") { dismiss() }
    }
}
