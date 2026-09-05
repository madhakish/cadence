import SwiftUI
import SwiftData
import CadenceCore

/// Quick logging for real physical work that belongs on the timeline but not
/// in the training program. The typed registry currently contains Wood
/// Splitting; adding another activity remains an explicit model decision.
struct ActivityQuickLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted },
           sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]
    @Query private var settingsList: [AppSettings]

    let session: WorkoutSession?
    let onDelete: (() -> Void)?

    @State private var kind: ActivityKind
    @State private var startDate: Date
    @State private var durationHours: Int
    @State private var durationMinutes: Int
    @State private var sessionRPE: Double?
    @State private var loadText: String
    @State private var loadUnit: WeightUnit
    @State private var roundsText: String
    @State private var piecesText: String
    @State private var strikesText: String
    @State private var cordsText: String
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var seededRecentImplement = false

    private static let rpeOptions = Array(stride(from: 1.0, through: 10.0, by: 0.5))

    init(session: WorkoutSession? = nil, onDelete: (() -> Void)? = nil) {
        self.session = session
        self.onDelete = onDelete
        let detail = session?.activityDetail
        let resolvedKind = detail?.kind ?? .woodSplitting
        let set = session.flatMap { Self.activitySet(in: $0, kind: resolvedKind) }
        let duration = set?.durationSeconds ?? 0
        let unit = set?.enteredUnit ?? .lb
        let load = set?.weightLb ?? 0

        _kind = State(initialValue: resolvedKind)
        _startDate = State(initialValue: session?.date ?? .now)
        _durationHours = State(initialValue: duration / 3_600)
        _durationMinutes = State(initialValue: (duration % 3_600) / 60)
        _sessionRPE = State(initialValue: detail?.sessionRPE)
        _loadText = State(initialValue: load > 0
            ? Weight.trim(unit == .kg ? Weight.kg(fromLb: load) : load, decimals: 2)
            : "")
        _loadUnit = State(initialValue: unit)
        _roundsText = State(initialValue: detail?.rounds.map(String.init) ?? "")
        _piecesText = State(initialValue: detail?.splitPieces.map(String.init) ?? "")
        _strikesText = State(initialValue: detail?.estimatedStrikes.map(String.init) ?? "")
        _cordsText = State(initialValue: detail?.cordVolume.map { Weight.trim($0, decimals: 3) } ?? "")
        _notes = State(initialValue: session?.notes ?? "")
    }

    private var durationSeconds: Int {
        durationHours * 3_600 + durationMinutes * 60
    }

    private var isEditing: Bool { session != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AD-HOC WORK")
                            .font(.caption.bold())
                            .tracking(0.9)
                            .foregroundStyle(Theme.accent)
                        Text("Physical work, not a training session")
                            .font(.title2.bold())
                        Text("Banks immediately on the same history timeline. It never advances a cycle, changes a PR, or counts as lifting tonnage.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Activity", selection: $kind) {
                        ForEach(ActivityKind.allCases, id: \.self) { option in
                            Text(option.exerciseName).tag(option)
                        }
                    }
                    DatePicker("Started", selection: $startDate)
                    Stepper("Hours: \(durationHours)", value: $durationHours, in: 0...48)
                    Stepper("Minutes: \(durationMinutes)", value: $durationMinutes, in: 0...59)
                    if durationSeconds == 0 {
                        Label("Record at least one minute.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.bold())
                            .foregroundStyle(Theme.warn)
                    } else {
                        Text("Duration \(durationLabel(durationSeconds))")
                            .font(.headline.monospacedDigit())
                    }
                } header: {
                    Text("Work performed")
                }

                Section {
                    Picker("Session effort", selection: $sessionRPE) {
                        Text("Not recorded").tag(Double?.none)
                        ForEach(Self.rpeOptions, id: \.self) { value in
                            Text("RPE \(Weight.trim(value))").tag(Double?.some(value))
                        }
                    }
                    HStack {
                        TextField("Maul weight", text: $loadText)
                            .keyboardType(.decimalPad)
                            .font(.body.monospacedDigit())
                        Picker("Unit", selection: $loadUnit) {
                            Text("lb").tag(WeightUnit.lb)
                            Text("kg").tag(WeightUnit.kg)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 116)
                    }
                    Text("Both are optional. RPE creates a duration × effort workload; maul weight remains an implement fact, never volume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Effort & implement")
                }

                if kind == .woodSplitting {
                    Section {
                        optionalIntegerField("Rounds", text: $roundsText)
                        optionalIntegerField("Split pieces", text: $piecesText)
                        optionalIntegerField("Estimated strikes", text: $strikesText)
                        TextField("Cords split", text: $cordsText)
                            .keyboardType(.decimalPad)
                            .font(.body.monospacedDigit())
                        Text("Leave anything you did not count blank. Cadence does not infer cords, pieces, rounds, or strikes from one another.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Wood splitting — optional detail")
                    }
                }

                Section("Notes") {
                    TextField("Oak, weather, tool, anything useful", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if isEditing {
                    Section {
                        Button("Delete activity", role: .destructive) { confirmDelete = true }
                            .frame(minHeight: 44)
                    }
                }
            }
            .accessibilityIdentifier("activity-log-screen")
            .navigationTitle(isEditing ? "Edit ad-hoc work" : "Log ad-hoc work")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Bank work") { save() }
                        .fontWeight(.bold)
                        .disabled(durationSeconds == 0 || isSaving)
                }
            }
            .alert("Couldn't bank this work", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Delete this activity?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete activity", role: .destructive) { deleteSession() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the banked activity from history. Training cycles and workout records are unchanged.")
            }
            .onAppear { seedRecentImplementIfNeeded() }
        }
    }

    private func optionalIntegerField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .keyboardType(.numberPad)
            .font(.body.monospacedDigit())
    }

    private func seedRecentImplementIfNeeded() {
        guard !seededRecentImplement else { return }
        seededRecentImplement = true
        guard session == nil else { return }
        loadUnit = settingsList.first?.unitDisplay.primaryUnit ?? .lb
        guard let recent = completedSessions.first(where: {
            $0.activityDetail?.kind == kind
                && (Self.activitySet(in: $0, kind: kind)?.weightLb ?? 0) > 0
        }), let set = Self.activitySet(in: recent, kind: kind) else { return }
        loadUnit = set.enteredUnit
        loadText = Weight.trim(
            set.enteredUnit == .kg ? Weight.kg(fromLb: set.weightLb) : set.weightLb,
            decimals: 2
        )
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let input = try draftInput()
            if let session {
                try ActivitySession.update(session: session, input: input, context: context)
            } else {
                _ = try ActivitySession.create(input: input, context: context)
            }
            if PersistenceErrorCenter.shared.save(
                context,
                operation: isEditing ? "Editing ad-hoc work" : "Banking ad-hoc work"
            ) {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func draftInput() throws -> ActivitySession.Input {
        let loadValue = try optionalDouble(loadText, label: "Maul weight")
        return ActivitySession.Input(
            kind: kind,
            startDate: startDate,
            durationSeconds: durationSeconds,
            sessionRPE: sessionRPE,
            loadLb: loadValue.map { Weight.toLb($0, from: loadUnit) },
            notes: notes,
            woodSplitting: kind == .woodSplitting ? .init(
                rounds: try optionalInt(roundsText, label: "Rounds"),
                splitPieces: try optionalInt(piecesText, label: "Split pieces"),
                estimatedStrikes: try optionalInt(strikesText, label: "Estimated strikes"),
                cordVolume: try optionalDouble(cordsText, label: "Cords split")
            ) : nil,
            enteredUnit: loadUnit
        )
    }

    private func optionalDouble(_ raw: String, label: String) throws -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let parsed = Double(value.replacingOccurrences(of: ",", with: ".")),
              parsed.isFinite, parsed >= 0
        else { throw ActivitySession.Error.invalidValue(label) }
        return parsed
    }

    private func optionalInt(_ raw: String, label: String) throws -> Int? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let parsed = Int(value), parsed >= 0
        else { throw ActivitySession.Error.invalidValue(label) }
        return parsed
    }

    private func deleteSession() {
        guard let session else { return }
        context.delete(session)
        if PersistenceErrorCenter.shared.save(context, operation: "Deleting ad-hoc work") {
            dismiss()
            onDelete?()
        }
    }

    private static func activitySet(in session: WorkoutSession, kind: ActivityKind) -> SetEntry? {
        let stableID = StableID.exerciseLegacyID(name: kind.exerciseName)
        return session.orderedExercises.first {
            $0.exerciseID == stableID || $0.exercise?.name == kind.exerciseName
        }?.orderedSets.first
    }

    private func durationLabel(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }
}
