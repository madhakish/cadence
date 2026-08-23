import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import CadenceCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(RestTimer.self) private var restTimer
    @Environment(WorkoutClock.self) private var workoutClock
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query(sort: \LiftTrack.exerciseName) private var tracks: [LiftTrack]
    @Query(sort: \TrainingInterval.startDate, order: .reverse)
    private var trainingIntervals: [TrainingInterval]

    @State private var exportJSON: Data?
    @State private var exportCSV: Data?
    @State private var showImporter = false
    @State private var importAlert: String?
    @AppStorage(BackupCheckpointService.lastSuccessKey) private var checkpointLastSuccess = ""
    @AppStorage(BackupCheckpointService.lastFailureKey) private var checkpointLastFailure = ""
    /// Device-local on purpose — a Health read grant must not ride in a backup.
    @AppStorage(HealthKitService.readEnabledKey) private var healthReadEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                if let settings = settingsList.first {
                    let bindable = Bindable(settings)

                    Section("Theme") {
                        Picker("Theme", selection: Binding(
                            get: { ThemeName(rawValue: settings.themeNameRaw) ?? .carbon },
                            set: { settings.themeNameRaw = $0.rawValue }
                        )) {
                            ForEach(ThemeName.allCases) { theme in
                                Label {
                                    Text(theme.label)
                                } icon: {
                                    Circle().fill(theme.palette.accent).frame(width: 14, height: 14)
                                }
                                .tag(theme)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    Section("Units") {
                        Picker("Display", selection: bindable.unitDisplayRaw) {
                            Text("lb primary").tag(UnitDisplay.lbPrimary.rawValue)
                            Text("kg primary").tag(UnitDisplay.kgPrimary.rawValue)
                            Text("Both").tag(UnitDisplay.both.rawValue)
                        }
                    }

                    // The smart defaults an exercise falls to when it has no
                    // rest of its own, listed in the order they're checked:
                    // today's program role first, then movement type
                    // (RestDefaults in CadenceCore). Mirrors web settings.
                    Section {
                        Stepper("Complementary lifts: \(mmss(settings.secondaryRestSeconds))",
                                value: bindable.secondaryRestSeconds, in: 0...600, step: 15)
                        Stepper("Accessories: \(mmss(settings.accessoryRestSeconds))",
                                value: bindable.accessoryRestSeconds, in: 0...600, step: 15)
                    } header: {
                        Text("Rest timer — in a program day, by role")
                    }
                    Section {
                        Stepper("Squat & deadlift mains: \(mmss(settings.mainCompoundRestSeconds))",
                                value: bindable.mainCompoundRestSeconds, in: 0...600, step: 15)
                        Stepper("Olympic lifts: \(mmss(settings.olympicRestSeconds))",
                                value: bindable.olympicRestSeconds, in: 0...600, step: 15)
                        Stepper("Other main lifts (presses…): \(mmss(settings.mainUpperRestSeconds))",
                                value: bindable.mainUpperRestSeconds, in: 0...600, step: 15)
                        Toggle("Auto-start rest after a set", isOn: bindable.autoStartRest)
                        Toggle("Haptics", isOn: bindable.haptics)
                    } header: {
                        Text("Rest timer — everything else, by movement")
                    } footer: {
                        Text("These are the fallback timers. An exercise with a rest of its own (set in the logger or the library) always uses that instead. 0:00 = no timer. Auto-start off = tap Rest yourself.")
                    }

                    Section {
                        Picker("Year of birth", selection: bindable.birthYear) {
                            Text("Not set").tag(0)
                            ForEach(Self.selectableBirthYears, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                    } header: {
                        Text("About you")
                    } footer: {
                        // The only thing age is used for, said plainly. A health
                        // app asking for a birthday without saying why is how
                        // people learn to distrust one.
                        Text("Used only to adjust the per-meal protein figure on the Body screen — muscle responds less to a given dose with age. Nothing else reads it, and it never affects your program.")
                    }

                    Section {
                        Toggle("Show gym tag on first launch of the day",
                               isOn: bindable.gymTagFirstLaunchOfDay)
                    } header: {
                        Text("Arrival")
                    } footer: {
                        Text("Shows the default membership tag once per day, then returns to Today for training.")
                    }

                    Section {
                        Toggle("Write workouts & bodyweight to Health", isOn: Binding(
                            get: { settings.healthKitEnabled },
                            set: { on in
                                settings.healthKitEnabled = on
                                if on {
                                    Task { _ = await HealthKitService.shared.requestWriteAuthorization() }
                                }
                            }
                        ))
                        Toggle("Compare conditioning with Health", isOn: Binding(
                            get: { healthReadEnabled },
                            set: { on in
                                healthReadEnabled = on
                                HealthKitService.shared.isReadEnabled = on
                                if on {
                                    Task { _ = await HealthKitService.shared.requestReadAuthorization() }
                                }
                            }
                        ))
                    } header: {
                        Text("HealthKit")
                    } footer: {
                        // [INV-HEALTH-IS-A-SECOND-OPINION]
                        Text("Two separate permissions. Comparing reads walking, running, and cycling distance for sessions you have already logged, and shows it beside your own numbers — it never changes a logged workout on its own.")
                    }
                }

                Section("Gyms") {
                    ForEach(gyms) { gym in
                        NavigationLink {
                            GymEditorView(gym: gym)
                        } label: {
                            HStack {
                                Text(gym.name)
                                if gym.isDefault {
                                    Text("default").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if gym.barcodeImageData != nil {
                                    Image(systemName: "barcode").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button {
                        let gym = Gym(name: "Gym \(gyms.count + 1)")
                        context.insert(gym)
                        PersistenceErrorCenter.shared.save(context, operation: "Adding the gym")
                    } label: {
                        Label("Add gym", systemImage: "plus")
                    }
                }

                Section("Progression (standalone lifts)") {
                    ForEach(tracks) { track in
                        NavigationLink {
                            TrackEditorView(track: track)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(track.exerciseName)
                                Text("+\(settingsList.unitDisplay.format(lb: track.incrementLb)) per \(track.mode == .cycle ? "cycle" : "session") · next: \(settingsList.unitDisplay.format(lb: track.suggestion.weightLb)) · \(track.suggestion.sets)×\(track.suggestion.reps)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    ForEach(trainingIntervals) { interval in
                        NavigationLink {
                            IntervalEditorView(interval: interval)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(interval.kind.name)
                                Text(Self.intervalRangeLabel(interval))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        let today = Calendar.current.startOfDay(for: .now)
                        let interval = TrainingInterval(startDate: today, endDate: today)
                        context.insert(interval)
                        PersistenceErrorCenter.shared.save(context, operation: "Adding the break")
                    } label: {
                        Label("Add break", systemImage: "plus")
                    }
                } header: {
                    Text("Training breaks")
                } footer: {
                    // [INV-INTERVAL-IS-NOT-A-GAP] [INV-RECOVERY-WORK-IS-OFF-PROGRAM]
                    Text("Declared breaks — deload, rest, away, active recovery — keep a chosen gap from reading as a lapse. Work banked during an active-recovery break stays in history but never advances progression or PR baselines.")
                }

                Section("Library") {
                    NavigationLink("Exercise library") { LibraryView() }
                }

                Section("Export") {
                    Button("Prepare JSON export") {
                        do { exportJSON = try ExportService.jsonData(context: context) }
                        catch {
                            exportJSON = nil
                            importAlert = "Couldn't prepare the JSON export: \(error.localizedDescription)"
                        }
                    }
                    if let exportJSON {
                        ShareLink(
                            item: TransferableFile(data: exportJSON, filename: "cadence-export.json"),
                            preview: SharePreview("cadence-export.json")
                        ) {
                            Label("Share JSON", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Prepare CSV export") {
                        do { exportCSV = try ExportService.csvData(context: context) }
                        catch {
                            exportCSV = nil
                            importAlert = "Couldn't prepare the CSV export: \(error.localizedDescription)"
                        }
                    }
                    if let exportCSV {
                        ShareLink(
                            item: TransferableFile(data: exportCSV, filename: "cadence-sets.csv"),
                            preview: SharePreview("cadence-sets.csv")
                        ) {
                            Label("Share CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    Button("Checkpoint now") {
                        do {
                            try BackupCheckpointService.create(context: context, reason: "manual")
                            importAlert = "Local recovery checkpoint created."
                        } catch {
                            BackupCheckpointService.recordFailure(error)
                            importAlert = "Couldn't create a recovery checkpoint: \(error.localizedDescription)"
                        }
                    }
                    if !checkpointLastSuccess.isEmpty {
                        Button("Restore latest checkpoint") { importAlert = restoreLatestCheckpoint() }
                        Text("Latest: \(checkpointLastSuccess)").font(.caption).foregroundStyle(.secondary)
                    }
                    if !checkpointLastFailure.isEmpty {
                        Text("Last checkpoint failed: \(checkpointLastFailure)").font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Local recovery")
                } footer: {
                    Text("Cadence keeps the last three checkpoints when it backgrounds and before imports. They can undo a bad import, but deleting the app removes them; exported JSON is the durable backup.")
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import JSON backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("Restores a backup, replacing the data it contains and leaving anything it doesn't alone. Export first if you're unsure.")
                }
        }
        .saveChangesOnDisappear(context, operation: "Saving settings")
        .navigationTitle("Settings")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importAlert = restore(from: result)
            }
            .alert("Cadence data", isPresented: Binding(get: { importAlert != nil }, set: { if !$0 { importAlert = nil } })) {
                Button("OK") { importAlert = nil }
            } message: {
                Text(importAlert ?? "")
            }
        }
    }

    private func restore(from result: Result<URL, Error>) -> String {
        switch result {
        case .failure(let err):
            return err.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                // A valid but unwanted restore is still destructive. Keep the
                // current state locally before replacing any sections.
                try BackupCheckpointService.create(context: context, reason: "before-import")
                let s = try ImportService.load(data, into: context)
                // A restore replaces the sessions store wholesale, and
                // backups preserve session IDs — a running clock, its
                // durable record, and any rest countdown all belong to the
                // pre-import world. Left alive, the record (or a surviving
                // activity) would graft the old stopwatch onto whatever
                // restored session reuses the ID.
                restTimer.stop()
                workoutClock.end()
                // syncLibrary right after the restore: a pre-migration backup
                // re-arms the retired-rest-stamp clear, which otherwise
                // wouldn't run until the next app launch — leaving the rest
                // steppers dead in the meantime.
                try Seeder.syncLibrary(context: context)
                let restored = "Restored \(s.sessions) sessions, \(s.programs) program(s), \(s.tracks) tracked lift(s)."
                guard s.repairedSlotIDs > 0 else { return restored }
                // Say so rather than repair silently — the backup carried a
                // slot id on two programs, and the later one has been re-issued.
                return restored + "\n\nRepaired \(s.repairedSlotIDs) duplicate slot "
                    + "\(s.repairedSlotIDs == 1 ? "id" : "ids") the backup reused across programs."
            } catch {
                return error.localizedDescription
            }
        }
    }

    private func restoreLatestCheckpoint() -> String {
        do {
            guard let data = try BackupCheckpointService.latestData() else { return "No local recovery checkpoint exists." }
            // Capture the current state too, so this recovery can itself be undone.
            try BackupCheckpointService.create(context: context, reason: "before-checkpoint-restore")
            let s = try ImportService.load(data, into: context)
            // Same world-reset rule as the JSON import above: the clock,
            // its record, and any rest countdown died with the replaced store.
            restTimer.stop()
            workoutClock.end()
            try Seeder.syncLibrary(context: context)
            return "Restored local checkpoint: \(s.sessions) sessions, \(s.programs) program(s), \(s.tracks) tracked lift(s)."
        } catch {
            return error.localizedDescription
        }
    }

    /// Newest first, so the years most people will pick are the shortest
    /// scroll. Bounded by the same plausible-lifespan window the import
    /// validator enforces, so the picker cannot produce a value a backup
    /// would reject.
    private static var selectableBirthYears: [Int] {
        let thisYear = Calendar.current.component(.year, from: .now)
        return Array((thisYear - 120)...thisYear).reversed()
    }

    static func intervalRangeLabel(_ interval: TrainingInterval) -> String {
        let start = interval.startDate.formatted(date: .abbreviated, time: .omitted)
        let end = interval.endDate.formatted(date: .abbreviated, time: .omitted)
        return start == end ? start : "\(start) – \(end)"
    }
}

/// Editor for one declared training break. The two entry affordances — a day
/// count or an explicit date range — write the same inclusive start/end day
/// pair; `enteredAsDays` remembers which shape to reopen in. Mirrors web
/// settings.js interval editing.
struct IntervalEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var interval: TrainingInterval
    @State private var confirmDelete = false

    private var dayCount: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: interval.startDate),
            to: calendar.startOfDay(for: interval.endDate)
        ).day ?? 0
        return days + 1
    }

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: Binding(
                    get: { interval.kind },
                    set: { interval.kind = $0 }
                )) {
                    ForEach(TrainingIntervalKind.allCases, id: \.self) { kind in
                        Text(kind.name).tag(kind)
                    }
                }
            } footer: {
                // The kinds stay distinct on purpose
                // (INV-INTERVAL-KINDS-STAY-DISTINCT) — each reads differently
                // to the engine, so each says what it means here.
                Text(kindFooter(interval.kind))
            }
            Section("When") {
                Picker("Enter as", selection: $interval.enteredAsDays) {
                    Text("Number of days").tag(true)
                    Text("Date range").tag(false)
                }
                .pickerStyle(.segmented)
                DatePicker("Starts", selection: Binding(
                    get: { interval.startDate },
                    set: { newStart in
                        let count = dayCount
                        interval.startDate = newStart
                        if interval.enteredAsDays {
                            // Moving the start keeps the declared LENGTH; the
                            // range shape keeps the end (clamped, never
                            // inverted).
                            interval.endDate = Calendar.current.date(
                                byAdding: .day, value: count - 1, to: newStart
                            ) ?? newStart
                        } else if interval.endDate < newStart {
                            interval.endDate = newStart
                        }
                    }
                ), displayedComponents: .date)
                if interval.enteredAsDays {
                    Stepper(
                        "\(dayCount) day\(dayCount == 1 ? "" : "s")",
                        value: Binding(
                            get: { dayCount },
                            set: { newCount in
                                interval.endDate = Calendar.current.date(
                                    byAdding: .day, value: max(1, newCount) - 1,
                                    to: interval.startDate
                                ) ?? interval.startDate
                            }
                        ),
                        in: 1...365
                    )
                } else {
                    DatePicker("Ends", selection: Binding(
                        get: { interval.endDate },
                        set: { interval.endDate = max($0, interval.startDate) }
                    ), displayedComponents: .date)
                }
            }
            Section("Note") {
                TextField("Optional note", text: $interval.note)
            }
            Section {
                // Destructive, so it confirms first (matches the web editor).
                Button("Delete break", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(interval.kind.name)
        .confirmationDialog(
            "Delete this break? Sessions and history are unchanged.",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete break", role: .destructive) {
                context.delete(interval)
                PersistenceErrorCenter.shared.save(context, operation: "Deleting the break")
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .saveChangesOnDisappear(context, operation: "Saving the break")
    }

    private func kindFooter(_ kind: TrainingIntervalKind) -> String {
        switch kind {
        case .deload:
            return "Reduced-load training inside the cycle. Sessions are still expected on deload days."
        case .rest:
            return "Planned days off. Not missed days."
        case .away:
            return "Travel, closure, illness, layoff. Not missed days — expect a re-entry suggestion when it ends."
        case .activeRecovery:
            return "Real work, deliberately off-program. Sessions banked inside it stay in history but never advance progression or PR baselines."
        }
    }
}

/// Three deliberate creation paths. Templates live one level deeper so their
/// schedule and prescription shape can be inspected before they mutate data.
struct ProgramCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let existingPrograms: [Program]
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    templatePicker
                } label: {
                    Label("Start from a template", systemImage: "rectangle.stack.badge.plus")
                }

                Button {
                    let name = ProgramTemplates.uniqueProgramName(
                        "Program \(existingPrograms.count + 1)",
                        existing: existingPrograms.map(\.name)
                    )
                    context.insert(Program(name: name, isActive: existingPrograms.isEmpty))
                    PersistenceErrorCenter.shared.save(context, operation: "Adding the program")
                    dismiss()
                } label: {
                    Label("Blank program", systemImage: "doc")
                }

                Button {
                    onImport()
                } label: {
                    Label("Import a program file", systemImage: "square.and.arrow.down")
                }
            }
            .navigationTitle("Add program")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var templatePicker: some View {
        List(ProgramTemplateData.all) { template in
            Button {
                do {
                    try ProgramTemplates.instantiate(template, context: context)
                    PersistenceErrorCenter.shared.save(context, operation: "Adding the program")
                    dismiss()
                } catch {
                    PersistenceErrorCenter.shared.report(error, operation: "Adding the program", context: context)
                }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(template.name).font(.headline)
                    Text(template.tagline).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(template.days.count) days · \(template.focus.capitalized) · \(dominantPrescriptions(template))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Templates")
    }

    private func dominantPrescriptions(_ template: ProgramTemplateData.Template) -> String {
        let focus = TrainingFocus(rawValue: template.focus) ?? .strength
        let rawStyles = template.days.flatMap { day in
            day.lifts.map { lift in
                ProgramEngine.resolvedStyle(
                    PrescriptionStyle(rawValue: lift.prescription) ?? .automatic,
                    movementGroup: nil,
                    role: LiftRole(rawValue: lift.role) ?? .main,
                    focus: focus
                ).rawValue
            }
        }
        guard !rawStyles.isEmpty else { return "Accessory progression" }
        let counts = Dictionary(grouping: rawStyles, by: { $0 }).mapValues { $0.count }
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        .prefix(2)
        .map { PrescriptionStyle(rawValue: $0.key)?.name ?? $0.key }
        .joined(separator: " + ")
    }
}

/// Wraps export bytes for ShareLink.
struct TransferableFile: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

// MARK: - Gym editor (plate inventory + barcode tag)

struct GymEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var gym: Gym

    @State private var photoItem: PhotosPickerItem?
    @State private var showCard = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $gym.name)
                Toggle("Default gym", isOn: $gym.isDefault)
                Picker("Default bar", selection: Binding(
                    get: { gym.defaultBar },
                    set: { gym.defaultBar = $0 }
                )) {
                    ForEach(Bar.all) { Text($0.label).tag($0) }
                }
                Stepper(
                    "Collars: \(Weight.trim(gym.collarWeightLb)) lb combined",
                    value: $gym.collarWeightLb,
                    in: 0...20,
                    step: 0.5
                )
                Picker("Loading policy", selection: Binding(
                    get: { gym.loadingPolicy },
                    set: { gym.loadingPolicy = $0 }
                )) {
                    ForEach(LoadingPolicy.allCases, id: \.self) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
            } footer: {
                Text("Cadence includes collars in the achieved weight and applies this policy whenever a barbell prescription is snapped to your available plates.")
            }

            Section {
                ForEach($gym.plateToggles) { $toggle in
                    Toggle(isOn: $toggle.enabled) {
                        Text(toggle.plate.label)
                            .foregroundStyle(toggle.plate.unit == .kg ? Theme.accent : .primary)
                    }
                }
            } header: {
                Text("Plate inventory")
            } footer: {
                Text("Only enabled plates are used by the calculator for this gym.")
            }

            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(
                        gym.barcodeImageData == nil ? "Add barcode photo" : "Replace barcode photo",
                        systemImage: "barcode.viewfinder"
                    )
                }
                if gym.barcodeImageData != nil {
                    TextField("Tag label", text: $gym.barcodeLabel)
                    Button("Show tag") { showCard = true }
                    Button("Remove photo", role: .destructive) {
                        gym.barcodeImageData = nil
                        PersistenceErrorCenter.shared.save(context, operation: "Removing the membership photo")
                    }
                }
            } header: {
                Text("Membership tag")
            } footer: {
                Text("Snap your keychain barcode once. The phone becomes the second tag your gym's software can't issue.")
            }
        }
        .navigationTitle(gym.name)
        .saveChangesOnDisappear(context, operation: "Saving the gym")
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    gym.barcodeImageData = data
                    PersistenceErrorCenter.shared.save(context, operation: "Saving the membership photo")
                } catch {
                    PersistenceErrorCenter.shared.report(error, operation: "Loading the membership photo", context: context)
                }
            }
        }
        .sheet(isPresented: $showCard) {
            GymCardView(gym: gym)
        }
    }
}

// MARK: - Track editor

struct TrackEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var track: LiftTrack
    @Query private var settingsList: [AppSettings]
    private var unitDisplay: UnitDisplay { settingsList.unitDisplay }

    var body: some View {
        Form {
            Section("Progression") {
                Picker("Mode", selection: Binding(
                    get: { track.mode },
                    set: { track.mode = $0 }
                )) {
                    Text("4-rotation cycle").tag(TrackMode.cycle)
                    Text("Linear").tag(TrackMode.linear)
                }
                Stepper(
                    "Increment: +\(unitDisplay.format(lb: track.incrementLb))",
                    value: $track.incrementLb, in: 2.5...25, step: 2.5
                )
                Stepper(
                    "\(track.mode == .cycle ? "Rotation 1 weight" : "Current weight"): \(unitDisplay.format(lb: track.baseWeightLb))",
                    value: $track.baseWeightLb, in: 0...1000, step: 5
                )
                if track.mode == .cycle {
                    Picker("Next phase", selection: Binding(
                        get: { track.nextPhase },
                        set: { track.nextPhase = $0 }
                    )) {
                        ForEach(CyclePhase.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text("Cycle \(track.cycleNumber)")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Next suggestion") {
                Text("\(unitDisplay.format(lb: track.suggestion.weightLb)) · \(track.suggestion.sets)×\(track.suggestion.reps)")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
            }
        }
        .navigationTitle(track.exerciseName)
        .saveChangesOnDisappear(context, operation: "Saving lift progression")
    }
}

// MARK: - Program editor

struct ProgramEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allPrograms: [Program]
    @Query private var settingsList: [AppSettings]
    @Query private var exercises: [Exercise]
    @Bindable var program: Program

    private var validationMessages: [String] {
        var messages: [String] = []
        let exerciseByName = exercises.indexedByName()
        var rotationSets: [String: Int] = [:]
        var patternSets: [MovementPattern: Int] = [:]
        var intervalSlots = 0
        for day in program.orderedDays {
            if !day.lifts.contains(where: { $0.role == .main }) {
                messages.append("\(day.name) has no main lift.")
            }
            for lift in day.orderedLifts {
                // A bodyweight lift's base IS zero — pull-ups start unloaded
                // by design, so the missing-base warning would fire forever
                // on a slot that is configured exactly right.
                if lift.baseWeightLb <= 0,
                   exerciseByName[lift.exerciseName]?.supportsLoadableIncrement ?? true {
                    messages.append("\(lift.exerciseName) needs a rotation-1 base weight.")
                }
                // A crossed window warns on EVERY lift, resolved exercise or
                // not: `ProgramFileContract` rejects the stored pair on every
                // style, the endpoints are deliberately never repaired, and
                // the engine's swapped reading means training gives no other
                // sign. Gating this on double progression left wave/automatic
                // slots exporting into a contract error with no editor trail.
                if lift.minimumReps > lift.maximumReps {
                    messages.append("\(lift.exerciseName)'s minimum reps exceed its maximum; program export will reject it.")
                }
                if lift.estimatedMaxLb > 0, lift.baseWeightLb > lift.estimatedMaxLb {
                    messages.append("\(lift.exerciseName)'s base is above its estimated 1RM.")
                } else if lift.estimatedMaxLb > 0, program.focus.tmFraction > 0,
                          lift.baseWeightLb > lift.estimatedMaxLb * program.focus.tmFraction {
                    messages.append("\(lift.exerciseName)'s base is above the \(Int(program.focus.tmFraction * 100))% training-max ceiling; verify its estimated 1RM or lower the base.")
                }
                if let exercise = exerciseByName[lift.exerciseName] {
                    let plan = ProgramEngine.programPlan(
                        for: CycleState(baseWeightLb: lift.baseWeightLb, nextPhase: .volume),
                        programRoundingLb: program.roundingLb, exerciseType: exercise.typeRaw,
                        movementGroup: exercise.movementGroup, role: lift.role, focus: program.focus,
                        prescriptionStyle: lift.prescription,
                        configuration: lift.prescriptionConfiguration(
                            movementGroup: exercise.movementGroup,
                            loadable: exercise.supportsLoadableIncrement))
                    // Published methodology slots deliberately shape their
                    // own weekly balance (squat 3×/week, one heavy pull); the
                    // press/pull and squat/hinge heuristics would permanently
                    // flag the canon, so those sums skip methodology slots —
                    // but NOT generic double-progression rows, and pattern
                    // coverage (vertical pulling) counts every slot.
                    let methodologySlot = lift.prescription.buildsOwnSessionShape
                        && lift.prescription != .doubleProgression
                    if !methodologySlot {
                        rotationSets[exercise.movementGroup, default: 0] += plan.sets
                    }
                    patternSets[exercise.movementPattern, default: 0] += plan.sets
                    if exercise.movementPattern == .olympicPower, plan.reps > 3 {
                        messages.append("\(lift.exerciseName) is power work; keep programmed sets at 1–3 reps.")
                    }
                }
            }
            for accessory in day.orderedAccessories {
                let exercise = exerciseByName[accessory.exerciseName]
                let type = exercise?.type
                let isTimed = type == .timed || type == .conditioning
                // A slot with no load step climbs PAST its window top on
                // purpose — reps are its only progression. Calling that
                // "outside its rep range" told a correctly-progressing
                // bodyweight accessory it was misconfigured, every rotation,
                // forever. Only a target below the window, or above it on a
                // slot that really does cap, is worth saying.
                let capped = accessory.hasLoadStep(
                    loadable: exercise?.supportsLoadableIncrement ?? true
                )
                if !isTimed, accessory.minReps > accessory.maxReps {
                    messages.append("\(accessory.exerciseName)'s minimum reps exceed its maximum.")
                } else if !isTimed, accessory.currentReps < accessory.minReps
                            || (capped && accessory.currentReps > accessory.maxReps) {
                    messages.append("\(accessory.exerciseName)'s current reps are outside its rep range.")
                }
                // A load step on an identity that carries no external load is
                // ignored, so say so rather than letting the stepper imply it
                // does something.
                if let exercise, !exercise.supportsLoadableIncrement, accessory.incrementLb > 0 {
                    messages.append("\(accessory.exerciseName) carries no external load, so its load step is ignored. Use the weighted variant to add load.")
                }
                // A loaded accessory with no increment can never add weight —
                // it climbs reps past its own maximum forever. Flag it here
                // rather than let the slot quietly stop progressing. A missing
                // exercise must not fail OPEN: fall back to the inferred
                // (external) basis, the same reading web's resolvedLoadBasis
                // gives an unknown exercise.
                if ProgramProgression.accessoryCannotProgressLoad(
                       exerciseType: exercise?.typeRaw,
                       loadBasis: exercise?.loadBasis
                           ?? LoadSemantics.inferredBasis(exerciseType: nil),
                       weightLb: accessory.weightLb, incrementLb: accessory.incrementLb) {
                    messages.append("\(accessory.exerciseName) carries load but has no increment, so it can never add weight. Set an increment.")
                }
                if let group = exerciseByName[accessory.exerciseName]?.movementGroup {
                    rotationSets[group, default: 0] += accessory.sets
                }
                if let pattern = exerciseByName[accessory.exerciseName]?.movementPattern {
                    patternSets[pattern, default: 0] += accessory.sets
                    if pattern == .olympicPower, accessory.currentReps > 3 {
                        messages.append("\(accessory.exerciseName) is power work; keep programmed sets at 1–3 reps.")
                    }
                }
                if type == .conditioning, accessory.conditioningEffort == .interval { intervalSlots += 1 }
            }
            let hasPower = day.lifts.contains { exerciseByName[$0.exerciseName]?.movementPattern == .olympicPower }
            let hasIntervals = day.accessories.contains {
                exerciseByName[$0.exerciseName]?.type == .conditioning && $0.conditioningEffort == .interval
            }
            if hasPower, hasIntervals {
                messages.append("Move intervals off \(day.name); power work and intervals should not share a session.")
            }
        }
        if intervalSlots > 1 {
            messages.append("The rotation has \(intervalSlots) interval blocks; keep one interval dose and make the rest easy conditioning.")
        }
        let pressing = rotationSets["press", default: 0]
        let pulling = rotationSets["pull", default: 0]
        if pressing >= 8, pulling * 5 < pressing * 4 {
            messages.append("Per-rotation pulling volume (\(pulling) sets) trails pressing (\(pressing)); consider more rows or pull-ups.")
        }
        if patternSets[.verticalPull, default: 0] < 3 {
            messages.append("Vertical pulling is \(patternSets[.verticalPull, default: 0])/3 sets per rotation.")
        }
        let squat = rotationSets["squat", default: 0]
        let hinge = rotationSets["hinge", default: 0]
        if max(squat, hinge) >= 8, min(squat, hinge) * 2 < max(squat, hinge) {
            messages.append("Per-rotation squat/hinge volume is uneven (\(squat)/\(hinge) sets).")
        }
        let days = program.orderedDays
        for (index, day) in days.enumerated() where !days.isEmpty {
            let next = days[(index + 1) % days.count]
            let nextIsHingeLed = next.lifts.contains {
                $0.role == .main && exerciseByName[$0.exerciseName]?.movementPattern == .hipHinge
            }
            if nextIsHingeLed, day.accessories.contains(where: {
                guard let pattern = exerciseByName[$0.exerciseName]?.movementPattern else { return false }
                return pattern == .kneeFlexion || pattern == .hipExtension
            }) {
                messages.append("Move hamstring isolation/back extensions off \(day.name); it immediately precedes hinge-led \(next.name).")
            }
        }
        return messages
    }

    var body: some View {
        Form {
            if !validationMessages.isEmpty {
                Section("Coach check") {
                    ForEach(validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section("Name") {
                TextField("Program name", text: $program.name)
            }
            Section("Training focus") {
                Picker("Focus", selection: Binding(get: { program.focus }, set: { program.focus = $0 })) {
                    Text("Strength").tag(TrainingFocus.strength)
                    Text("Hypertrophy").tag(TrainingFocus.hypertrophy)
                    Text("Maintain").tag(TrainingFocus.maintain)
                }
                Picker("Equipment", selection: Binding(
                    get: { program.equipmentPolicy },
                    set: { program.equipmentPolicy = $0 }
                )) {
                    ForEach(EquipmentPolicy.allCases, id: \.self) { policy in
                        Text(policy.name).tag(policy)
                    }
                }
                Stepper("Rounding: \(settingsList.unitDisplay.format(lb: program.roundingLb))", value: $program.roundingLb, in: 2.5...10, step: 2.5)
                // Activation is exclusive — only one program drives Today.
                Toggle("Active", isOn: Binding(get: { program.isActive }, set: { on in
                    if on { for p in allPrograms { p.isActive = (p === program) } } else { program.isActive = false }
                }))
            }
            Section {
                Toggle("Enable coaching proposals", isOn: $program.coachEnabled)
                Stepper("Preferred spacing: \(program.preferredSessionSpacingDays) days",
                        value: $program.preferredSessionSpacingDays, in: 2...7)
                Stepper("Maximum added work: \(program.maximumAddedSetsPerRotation) sets / rotation",
                        value: $program.maximumAddedSetsPerRotation, in: 0...10)
                Toggle("Ignore early incomplete logs", isOn: Binding(
                    get: { program.reliableHistoryStart != nil },
                    set: { program.reliableHistoryStart = $0 ? (program.reliableHistoryStart ?? .now) : nil }
                ))
                if program.reliableHistoryStart != nil {
                    DatePicker("Reliable history starts", selection: Binding(
                        get: { program.reliableHistoryStart ?? .now },
                        set: { program.reliableHistoryStart = $0 }
                    ), displayedComponents: .date)
                }
            } header: {
                Text("Deterministic coach")
            } footer: {
                Text("Proposals use completed output by full program rotation. They never change the program until you apply them.")
            }
            Section {
                Stepper("Cycle: \(program.cycleNumber)", value: $program.cycleNumber, in: 1...99)
                // Position, not phase — this pointer is shared by every slot in
                // the program, and most styles never run a Volume/Load/Peak
                // wave. The per-slot badges say what each one does.
                Stepper(ProgramEngine.rotationLabel(rotation: program.currentWeek),
                        value: Binding(get: { program.currentWeek }, set: { positionAtRotation($0) }),
                        in: 1...ProgramProgression.deloadWeek)
                if !program.orderedDays.isEmpty {
                    Picker("Next day", selection: Binding(get: { program.nextDayIndex }, set: { program.nextDayIndex = $0 })) {
                        ForEach(program.orderedDays) { day in
                            Text(day.name).tag(day.order)
                        }
                    }
                }
            } header: {
                Text("Where you are")
            } footer: {
                Text("Set your position mid-cycle. Rotations 1–3 are complete authored passes (volume/load/peak); recovery is one representative lower and upper exposure, then rollover. Weights are the rotation-1 base.")
            }
            Section("Days") {
                ForEach(program.orderedDays) { day in
                    NavigationLink {
                        ProgramDayEditorView(day: day, step: program.roundingLb)
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(day.name)
                                Text(day.trainingIntent.name)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.14), in: Capsule())
                            }
                            // orderedLifts, not lifts: the SwiftData to-many
                            // array is unordered, so the raw list can show the
                            // complementary lift before the main.
                            Text(day.orderedLifts.map(\.exerciseName).joined(separator: " + "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove(perform: moveDays)
                .onDelete(perform: deleteDays)
                Button {
                    let day = ProgramDay(name: "Day \(program.days.count + 1)", order: program.days.count)
                    program.days.append(day)
                    context.insert(day)
                    PersistenceErrorCenter.shared.save(context, operation: "Adding the program day")
                } label: {
                    Label("Add day", systemImage: "plus")
                }
            }
            Section {
                // The plan, not a snapshot: no stall counters, no stashed peak
                // grade, no wave position, no slot ids. Those are this
                // lifter's state, not properties of the program, and they are
                // actively misleading on someone else's device. Re-importing
                // this file makes a fresh copy rather than resuming this one.
                // Fails closed: if the program somehow can't be encoded the
                // button is absent rather than sharing an empty file.
                if let data = try? ProgramExportService.jsonData(for: program) {
                    ShareLink(
                        item: TransferableFile(
                            data: data,
                            filename: ProgramExportService.filename(for: program)
                        ),
                        preview: SharePreview(ProgramExportService.filename(for: program))
                    ) {
                        Label("Export program", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    cloneProgram()
                } label: {
                    Label("Duplicate program", systemImage: "square.on.square")
                }
                Button(role: .destructive) {
                    context.delete(program)
                    if PersistenceErrorCenter.shared.save(context, operation: "Deleting the program") { dismiss() }
                } label: {
                    Text("Delete program")
                }
            }
        }
        .navigationTitle(program.name)
        .saveChangesOnDisappear(context, operation: "Saving the program")
    }

    /// Move the program to a rotation. Placing at/after Peak (rotation 3) with no
    /// banked Peak result would otherwise make the next rollover treat the skipped
    /// Peak as a stall and deload; seed a neutral hold (carry current state forward,
    /// no note) for any lift lacking pending so manual positioning never penalizes.
    /// A real Peak session logged in rotation 3 overwrites this hold with its grade.
    private func positionAtRotation(_ newValue: Int) {
        program.currentWeek = newValue
        if newValue == ProgramProgression.deloadWeek {
            let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            let exerciseByName = exercises.indexedByName()
            let recoveryOrders = ProgramProgression.recoveryDayOrders(
                program.orderedDays.map { day in
                    let mainName = day.orderedLifts.first(where: { $0.role == .main })?.exerciseName
                    return RecoveryDayCandidate(
                        order: day.order,
                        mainMovementGroup: mainName.flatMap { exerciseByName[$0]?.movementGroup }
                    )
                }
            )
            program.nextDayIndex = recoveryOrders.first ?? program.nextDayIndex
        }
        if newValue >= 3 {
            for day in program.days {
                for lift in day.lifts where lift.pendingBaseWeightLb == nil {
                    lift.pendingBaseWeightLb = lift.baseWeightLb
                    lift.pendingEstimatedMaxLb = lift.estimatedMaxLb
                    lift.pendingStallCount = lift.stallCount
                    lift.pendingLastIncrementLb = lift.lastIncrementLb
                    lift.pendingNote = nil
                }
            }
        }
        PersistenceErrorCenter.shared.save(context, operation: "Changing the program rotation")
    }

    private func deleteDays(at offsets: IndexSet) {
        // `nextDayIndex` addresses a day by its ORDER VALUE, not a list
        // position. Remember which day it points at before renumbering —
        // clamping after a renumber silently re-addresses the schedule on
        // sparse-order programs (imported files keep verbatim orders).
        let pointed = program.orderedDays.first { $0.order == program.nextDayIndex }
        let ordered = program.orderedDays
        let removed = Set(offsets.map { ordered[$0].id })
        for i in offsets { context.delete(ordered[i]) }
        for (i, day) in program.orderedDays.enumerated() { day.order = i }
        program.nextDayIndex = pointed.flatMap { removed.contains($0.id) ? nil : $0.order } ?? 0
        PersistenceErrorCenter.shared.save(context, operation: "Deleting the program day")
    }

    private func moveDays(from offsets: IndexSet, to destination: Int) {
        // Same rule as deleteDays: the pointer follows ITS day through the
        // renumbering, never a clamped position.
        let pointed = program.orderedDays.first { $0.order == program.nextDayIndex }
        var ordered = program.orderedDays
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, day) in ordered.enumerated() { day.order = index }
        program.nextDayIndex = pointed?.order ?? min(program.nextDayIndex, max(ordered.count - 1, 0))
        PersistenceErrorCenter.shared.save(context, operation: "Reordering program days")
    }

    private func cloneProgram() {
        let copy = Program(
            name: ProgramTemplates.uniqueProgramName("\(program.name) Copy", existing: allPrograms.map(\.name)),
            focus: program.focus, cycleNumber: program.cycleNumber, currentWeek: program.currentWeek,
            nextDayIndex: program.nextDayIndex, roundingLb: program.roundingLb, isActive: false)
        copy.coachEnabled = program.coachEnabled
        copy.equipmentPolicy = program.equipmentPolicy
        copy.reliableHistoryStart = program.reliableHistoryStart
        copy.preferredSessionSpacingDays = program.preferredSessionSpacingDays
        copy.maximumAddedSetsPerRotation = program.maximumAddedSetsPerRotation
        context.insert(copy)
        for sourceDay in program.orderedDays {
            let dayCopy = ProgramDay(name: sourceDay.name, order: sourceDay.order)
            dayCopy.trainingIntent = sourceDay.trainingIntent
            context.insert(dayCopy)
            copy.days.append(dayCopy)
            // Stamp the clone's slot orders from the enumerated DISPLAY order:
            // a legacy tied-order day (pre-#69 store) freezes exactly the
            // sequence its source already shows, instead of cloning the tie.
            for (index, source) in sourceDay.orderedLifts.enumerated() {
                let lift = ProgramLift(exerciseName: source.exerciseName, role: source.role, order: index,
                                       prescription: source.prescription, warmupPolicy: source.warmupPolicy,
                                       baseWeightLb: source.baseWeightLb, estimatedMaxLb: source.estimatedMaxLb,
                                       stallCount: source.stallCount, lastIncrementLb: source.lastIncrementLb)
                lift.loadOffsetLb = source.loadOffsetLb
                lift.peakOffsetLb = source.peakOffsetLb
                lift.deloadMultiplier = source.deloadMultiplier
                lift.doubleProgressionSets = source.doubleProgressionSets
                lift.minimumReps = source.minimumReps
                lift.maximumReps = source.maximumReps
                lift.currentReps = source.currentReps
                lift.peakSingleEnabled = source.peakSingleEnabled
                lift.lastPeakSingleLb = source.lastPeakSingleLb
                lift.peakSingleIncrementLb = source.peakSingleIncrementLb
                lift.phasePrimerEnabled = source.phasePrimerEnabled
                lift.dropIncrementLb = source.dropIncrementLb
                lift.capacityManaged = source.capacityManaged
                lift.maximumSets = source.maximumSets
                context.insert(lift)
                dayCopy.lifts.append(lift)
            }
            for (index, source) in sourceDay.orderedAccessories.enumerated() {
                let accessory = ProgramAccessory(exerciseName: source.exerciseName, order: index,
                                                 sets: source.sets, minReps: source.minReps, maxReps: source.maxReps,
                                                 currentReps: source.currentReps, targetSeconds: source.targetSeconds,
                                                 durationStepSeconds: source.durationStepSeconds, weightLb: source.weightLb,
                                                 incrementLb: source.incrementLb, stallCount: source.stallCount)
                accessory.capacityManaged = source.capacityManaged
                accessory.maximumSets = source.maximumSets
                accessory.conditioningEffortRaw = source.conditioningEffortRaw
                accessory.targetRPE = source.targetRPE
                context.insert(accessory)
                dayCopy.accessories.append(accessory)
            }
        }
        PersistenceErrorCenter.shared.save(context, operation: "Duplicating the program")
    }
}

struct ProgramDayEditorView: View {
    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]
    @Bindable var day: ProgramDay
    let step: Double
    @State private var picking: PickTarget?

    private enum PickTarget: Identifiable { case lift, accessory; var id: Int { hashValue } }

    var body: some View {
        Form {
            Section("Day") {
                TextField("Name", text: $day.name)
                Picker("Training intent", selection: Binding(
                    get: { day.trainingIntent },
                    set: { day.trainingIntent = $0 }
                )) {
                    ForEach(DayTrainingIntent.allCases, id: \.self) { intent in
                        Text(intent.name).tag(intent)
                    }
                }
            }
            Section("Lifts") {
                // Every row carries an explicit Remove button (mirroring the web
                // editor): the segmented Role picker spans the row and eats the
                // horizontal pan, so swipe-to-delete alone is undiscoverable here.
                ForEach(day.orderedLifts) { lift in
                    ProgramLiftRow(lift: lift, step: step, focus: day.program?.focus ?? .strength,
                                   rotation: day.program?.currentWeek ?? 1,
                                   cycleNumber: day.program?.cycleNumber ?? 1,
                                   previewSchedule: previewSchedule(for: lift)) {
                        context.delete(lift)
                        PersistenceErrorCenter.shared.save(context, operation: "Removing the program lift")
                    }
                }
                .onDelete { offsets in
                    let ordered = day.orderedLifts
                    for i in offsets { context.delete(ordered[i]) }
                    PersistenceErrorCenter.shared.save(context, operation: "Removing the program lift")
                }
                .onMove(perform: moveLifts)
                Button { picking = .lift } label: { Label("Add lift", systemImage: "plus") }
            }
            Section("Accessories") {
                ForEach(day.orderedAccessories) { accessory in
                    ProgramAccessoryRow(accessory: accessory) {
                        context.delete(accessory)
                        PersistenceErrorCenter.shared.save(context, operation: "Removing the program accessory")
                    }
                }
                .onDelete { offsets in
                    let ordered = day.orderedAccessories
                    for i in offsets { context.delete(ordered[i]) }
                    PersistenceErrorCenter.shared.save(context, operation: "Removing the program accessory")
                }
                .onMove(perform: moveAccessories)
                Button { picking = .accessory } label: { Label("Add accessory", systemImage: "plus") }
            }
        }
        .navigationTitle(day.name)
        .saveChangesOnDisappear(context, operation: "Saving the program day")
        .toolbar { EditButton() }
        .sheet(item: $picking) { target in
            ExercisePickerSheetView { name in
                switch target {
                case .lift:
                    let exercise = exercises.first { $0.name == name }
                    let bootstrap = ProgrammingDefaultsData.recommendation(
                        exerciseName: name, slotCategory: ExerciseCategory.main.rawValue,
                        exerciseType: exercise?.typeRaw ?? ExerciseType.dumbbell.rawValue
                    )
                    let historyBootstrap = exercise.flatMap { exercise in
                        try? ProgramTemplates.bootstrapLift(
                            exercise: exercise, role: .complementary,
                            focus: day.program?.focus ?? .strength, roundingLb: step,
                            context: context
                        )
                    }
                    let lift = ProgramLift(exerciseName: name, role: .complementary,
                                           order: day.lifts.count,
                                           baseWeightLb: historyBootstrap?.baseWeightLb ?? bootstrap.weightLb,
                                           estimatedMaxLb: historyBootstrap?.estimatedMaxLb ?? bootstrap.estimatedMaxLb)
                    context.insert(lift)
                    day.lifts.append(lift)
                case .accessory:
                    let type = exercises.first { $0.name == name }?.type
                    let bootstrap = ProgrammingDefaultsData.recommendation(
                        exerciseName: name, slotCategory: ExerciseCategory.accessory.rawValue,
                        exerciseType: type?.rawValue ?? ExerciseType.dumbbell.rawValue
                    )
                    let historyBootstrap = exercises.first { $0.name == name }.flatMap { exercise in
                        try? ProgramTemplates.bootstrapAccessory(exercise: exercise, context: context)
                    }
                    let acc = ProgramAccessory(exerciseName: name, order: day.accessories.count,
                                               sets: type == .conditioning ? 1 : 3,
                                               minReps: 8, maxReps: 12, currentReps: 8,
                                               targetSeconds: type == .conditioning ? 1_200 : 30,
                                               weightLb: historyBootstrap?.weightLb ?? bootstrap.weightLb,
                                               incrementLb: historyBootstrap?.incrementLb ?? bootstrap.incrementLb)
                    context.insert(acc)
                    day.accessories.append(acc)
                }
                PersistenceErrorCenter.shared.save(context, operation: "Adding the program exercise")
                picking = nil
            }
        }
    }

    /// Full schedule context is load-bearing. Counting matching slots is not
    /// enough: a twin before this day can advance the shared base before the
    /// first preview row, and a manually diverged twin must not advance it at
    /// all. Recovery also omits two authored days in an upper/lower program.
    private func previewSchedule(for lift: ProgramLift) -> ProgramEngine.ExposurePreviewSchedule? {
        guard let program = day.program else { return nil }
        let orderedDays = program.orderedDays
        let recoveryOrders = ProgramProgression.recoveryDayOrders(
            orderedDays.map { programDay in
                let mainName = programDay.orderedLifts.first(where: { $0.role == .main })?.exerciseName
                return RecoveryDayCandidate(
                    order: programDay.order,
                    mainMovementGroup: mainName.flatMap { name in
                        exercises.first(where: { $0.name == name })?.movementGroup
                    }
                )
            }
        )
        let synchronizedOrders = orderedDays.compactMap { programDay -> Int? in
            programDay.lifts.contains { candidate in
                candidate.exerciseName == lift.exerciseName
                    && candidate.prescription == lift.prescription
                    && abs(candidate.baseWeightLb - lift.baseWeightLb) < 0.001
            } ? programDay.order : nil
        }
        return ProgramEngine.ExposurePreviewSchedule(
            targetDayOrder: day.order,
            nextDayOrder: program.nextDayIndex,
            allDayOrders: orderedDays.map(\.order),
            recoveryDayOrders: recoveryOrders,
            synchronizedDayOrders: synchronizedOrders
        )
    }

    private func moveLifts(from offsets: IndexSet, to destination: Int) {
        var ordered = day.orderedLifts
        ordered.move(fromOffsets: offsets, toOffset: destination)
        // Role-first ordering is enforced at display time: a drop that lands
        // complementary work ahead of a main would snap back visually while
        // silently rewriting every authored order, so refuse it (no write)
        // instead of churning a no-op. Mirrors web settings.js moveSlot.
        let roles = ordered.map(\.roleRaw)
        if let lastMain = roles.lastIndex(of: LiftRole.main.rawValue),
           let firstOther = roles.firstIndex(where: { $0 != LiftRole.main.rawValue }),
           firstOther < lastMain { return }
        for (index, lift) in ordered.enumerated() { lift.order = index }
        PersistenceErrorCenter.shared.save(context, operation: "Reordering program lifts")
    }

    private func moveAccessories(from offsets: IndexSet, to destination: Int) {
        var ordered = day.orderedAccessories
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, accessory) in ordered.enumerated() { accessory.order = index }
        PersistenceErrorCenter.shared.save(context, operation: "Reordering program accessories")
    }
}

/// Opens the exercise detail from a program-editor row.
///
/// A `NavigationLink` is what the day view uses and it works there, because
/// those rows hold nothing but text. A program-editor row is packed with
/// Pickers, Steppers and Toggles, and in a Form row full of controls a
/// `.plain`-styled NavigationLink stops taking taps — the proof is in the same
/// HStack, where the `.borderless` Remove button next to it kept working the
/// whole time. So this uses the style that demonstrably survives that row, and
/// presents the detail as a sheet, matching the exercise picker one level up.
private struct ExerciseDetailButton: View {
    let name: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Text(name).font(.headline)
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Shows muscles worked, history, and which programs use \(name)")
        .sheet(isPresented: $showing) {
            NavigationStack {
                ExerciseDetailByNameView(name: name)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showing = false }
                        }
                    }
            }
        }
    }
}

private struct ProgramLiftRow: View {
    @Query private var settingsList: [AppSettings]
    @Query private var exercises: [Exercise]
    @Bindable var lift: ProgramLift
    let step: Double
    var focus: TrainingFocus = .strength
    var rotation: Int = 1
    var cycleNumber: Int = 1
    var previewSchedule: ProgramEngine.ExposurePreviewSchedule?
    let onRemove: () -> Void

    private var loadStep: Double {
        ProgramEngine.loadStep(programRoundingLb: step,
                               exerciseType: exercises.first { $0.name == lift.exerciseName }?.typeRaw)
    }

    /// Whether this slot's double progression has a load step to earn. A
    /// bodyweight identity has none, so its window top is advisory and the
    /// target climbs past it. An unknown exercise reads loadable, matching the
    /// `?? true` the prescription call sites use.
    private var loadableIncrement: Bool {
        exercises.first { $0.name == lift.exerciseName }?.supportsLoadableIncrement ?? true
    }

    private var deloadKnobApplies: Bool {
        resolvedPrescription == .wave || resolvedPrescription == .offsetWave
    }

    private var resolvedPrescription: PrescriptionStyle {
        let group = exercises.first { $0.name == lift.exerciseName }?.movementGroup
        return ProgramEngine.resolvedStyle(lift.prescription, movementGroup: group,
                                           role: lift.role, focus: focus)
    }

    private var baseLabel: String {
        switch resolvedPrescription {
        case .maxEffort: return "Current target"
        case .dynamicEffort: return "Wave step-1 base"
        case .fiveThreeOne: return "Training max"
        default: return "Rotation-1 base"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Tapping the name opens the exercise detail (muscles worked,
                // history, program membership).
                ExerciseDetailButton(name: lift.exerciseName)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless) // scoped to the icon, not the whole row
                .accessibilityLabel("Remove \(lift.exerciseName)")
            }
            // What this slot actually does, resolved through the engine — the
            // picker below can still say "Automatic".
            SlotPrescriptionBadge(
                lift: lift, rotation: rotation,
                movementGroup: exercises.first { $0.name == lift.exerciseName }?.movementGroup,
                focus: focus
            )
            Picker("Role", selection: Binding(get: { lift.role }, set: { lift.role = $0 })) {
                Text("Main").tag(LiftRole.main)
                Text("Complementary").tag(LiftRole.complementary)
            }
            .pickerStyle(.segmented)
            Picker("Prescription", selection: Binding(get: { lift.prescription }, set: { lift.prescription = $0 })) {
                ForEach(PrescriptionStyle.selectable(current: lift.prescription), id: \.self) { style in
                    Text(style.name).tag(style)
                }
            }
            Picker("Warm-up", selection: Binding(get: { lift.warmupPolicy }, set: { lift.warmupPolicy = $0 })) {
                ForEach(WarmupPolicy.allCases, id: \.self) { policy in
                    Text(policy.name).tag(policy)
                }
            }
            // A hand-set base is its own truth: clearing the last earned
            // increment switches off the honest-base repair (planningBase)
            // for this slot until the next machine advance re-earns it.
            Stepper("\(baseLabel): \(settingsList.unitDisplay.format(lb: lift.baseWeightLb))",
                    value: Binding(get: { lift.baseWeightLb },
                                   set: { lift.baseWeightLb = $0; lift.lastIncrementLb = 0 }),
                    in: 0...1000, step: loadStep)
            Stepper("Est. 1RM: \(settingsList.unitDisplay.format(lb: lift.estimatedMaxLb))", value: $lift.estimatedMaxLb, in: 0...1200, step: 5)
            if lift.prescription == .offsetWave {
                Stepper("Load offset: +\(settingsList.unitDisplay.format(lb: lift.loadOffsetLb))",
                        value: $lift.loadOffsetLb, in: 0...100, step: loadStep)
                Stepper("Peak offset: +\(settingsList.unitDisplay.format(lb: lift.peakOffsetLb))",
                        value: $lift.peakOffsetLb, in: 0...150, step: loadStep)
            }
            // Every wave-shaped style deloads at this slot's own intensity.
            // Volume stays cut regardless; the knob is for the lifter who finds
            // 77.5% unproductively light and wants a heavier easy week. Gated
            // on the RESOLVED style so it never appears where the engine would
            // ignore it (automatic on a complementary slot resolves secondary).
            if deloadKnobApplies {
                Stepper("Recovery: \(Weight.trim(lift.deloadMultiplier * 100))% of rotation-1 base",
                        value: $lift.deloadMultiplier, in: 0.5...0.9, step: 0.025)
            }
            if lift.prescription == .doubleProgression {
                Stepper("Sets: \(lift.doubleProgressionSets)", value: $lift.doubleProgressionSets, in: 1...8)
                // The endpoints carry each other rather than crossing; the
                // maximum stepper's own lower bound cannot do that alone,
                // because raising the minimum past it is what crosses them.
                Stepper("Minimum reps: \(lift.minimumReps)", value: Binding(
                    get: { lift.minimumReps },
                    set: { (value: Int) in
                        lift.minimumReps = value
                        lift.maximumReps = max(lift.maximumReps, value)
                        // The endpoints are the ONLY fields a stepper moves.
                        // `repWindow` floors the target into the window at
                        // every read, so writing it here would only inject
                        // reps the lifter never earned — an exploratory
                        // up-and-back-down tap used to ratchet the target up
                        // with no way back.
                    }
                ), in: 1...20)
                Stepper("Maximum reps: \(lift.maximumReps)", value: Binding(
                    get: { lift.maximumReps },
                    set: { (value: Int) in
                        lift.maximumReps = value
                        lift.minimumReps = min(lift.minimumReps, value)
                    }
                ), in: 1...30)
                // An unloadable slot has no load to add and climbs past its
                // window top, so it must be shown its real target — reading
                // the window as capped told a bodyweight slot sitting at 11
                // reps that it was stuck at 8 and owed a load step it can
                // never take.
                Text(loadableIncrement
                     ? "Current target: \(lift.repWindow(loadable: true).current) reps · add \(settingsList.unitDisplay.format(lb: loadStep)) only after every set reaches the top of the window."
                     : "Current target: \(lift.repWindow(loadable: false).current) reps · no external load to add, so this slot keeps earning reps past the top of the window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if lift.prescription.advancesPerExposure
                && lift.prescription != .doubleProgression && lift.prescription != .maxEffort {
                Stepper("Working sets: \(lift.doubleProgressionSets)", value: $lift.doubleProgressionSets, in: 1...10)
                if lift.prescription == .linearFives {
                    Picker("Working reps", selection: Binding(
                        get: { lift.currentReps <= 3 ? 3 : 5 },
                        set: { lift.currentReps = $0 }
                    )) {
                        Text("5 reps").tag(5)
                        Text("3 reps").tag(3)
                    }
                    .pickerStyle(.segmented)
                }
                Text("Sets-across of \(lift.prescription == .linearFives && lift.currentReps <= 3 ? 3 : 5). The base moves every banked session; the Est. 1RM above is what the coach derives it from.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if lift.prescription == .fiveThreeOne {
                Text("The base above is the TRAINING MAX (≈90% of 1RM), not a working weight. The top set each week is as many quality reps as you have.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if lift.prescription == .maxEffort {
                Text("The base is today's top-single target. Cadence builds through 90% and a near-max single, then advances the target after this exposure. Swap to a different special variation next week.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if lift.prescription == .dynamicEffort {
                Text("The base is wave week 1: 50% for squat/pull or 40% for bench. Speed work waves for three weeks, then resets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !resolvedPrescription.buildsOwnSessionShape {
                Toggle("Peak top single", isOn: $lift.peakSingleEnabled)
                if lift.peakSingleEnabled {
                    Stepper("Last clean single: \(settingsList.unitDisplay.format(lb: lift.lastPeakSingleLb))",
                            value: $lift.lastPeakSingleLb, in: 0...1200, step: loadStep)
                    Stepper("Single step: +\(settingsList.unitDisplay.format(lb: lift.peakSingleIncrementLb))",
                            value: $lift.peakSingleIncrementLb, in: loadStep...25, step: loadStep)
                }
                Toggle("Phase primer single", isOn: $lift.phasePrimerEnabled)
            }
            Stepper("One-tap drop: \(settingsList.unitDisplay.format(lb: lift.dropIncrementLb)) (0 = automatic)",
                    value: $lift.dropIncrementLb, in: 0...50, step: loadStep)
            Toggle("Coach may add sets", isOn: $lift.capacityManaged)
            if lift.capacityManaged {
                Stepper("Maximum sets: \(lift.maximumSets)", value: $lift.maximumSets, in: 1...10)
            }
            Divider()
            // What all of the above produces. Every value on this row is an
            // input; without this, nothing on the screen is an output.
            ExposurePreviewView(lift: lift, rotation: rotation, cycleNumber: cycleNumber,
                                roundingLb: step, focus: focus,
                                schedule: previewSchedule)
        }
    }
}

private struct ProgramAccessoryRow: View {
    @Query private var settingsList: [AppSettings]
    @Query private var exercises: [Exercise]
    @Bindable var accessory: ProgramAccessory
    let onRemove: () -> Void

    private var isTimed: Bool {
        let type = exercises.first { $0.name == accessory.exerciseName }?.type
        return type == .timed || type == .conditioning
    }

    private var isConditioning: Bool {
        exercises.first { $0.name == accessory.exerciseName }?.type == .conditioning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ExerciseDetailButton(name: accessory.exerciseName)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless) // scoped to the icon, not the whole row
                .accessibilityLabel("Remove \(accessory.exerciseName)")
            }
            Stepper("Sets: \(accessory.sets)", value: $accessory.sets, in: 1...8)
            Toggle("Coach may adjust sets", isOn: $accessory.capacityManaged)
            if accessory.capacityManaged {
                Stepper("Maximum sets: \(accessory.maximumSets)", value: $accessory.maximumSets, in: 1...10)
            }
            if isTimed {
                Stepper(isConditioning
                        ? "Duration: \(CardioFormat.durationLabel(seconds: accessory.targetSeconds))"
                        : "Hold: \(CardioFormat.durationLabel(seconds: accessory.targetSeconds))",
                        value: $accessory.targetSeconds, in: 5...1800, step: 5)
                if isConditioning {
                    Picker("Effort", selection: Binding(get: { accessory.conditioningEffort }, set: { accessory.conditioningEffort = $0 })) {
                        ForEach(ConditioningEffort.allCases, id: \.self) { effort in
                            Text(effort.name).tag(effort)
                        }
                    }
                    Stepper("Target RPE: \(accessory.targetRPE == 0 ? "none" : String(accessory.targetRPE))",
                            value: $accessory.targetRPE, in: 0...10)
                } else {
                    Stepper("Progress by: +\(accessory.durationStepSeconds) sec",
                            value: $accessory.durationStepSeconds, in: 0...60, step: 5)
                }
            } else {
                Stepper("Weight: \(settingsList.unitDisplay.format(lb: accessory.weightLb))", value: $accessory.weightLb, in: 0...500, step: 2.5)
                // The endpoints carry each other rather than crossing. A
                // crossed window is a state the engine has to guess at, and
                // the guess used to hand the lifter a rep jump and a load
                // step in the same exposure.
                Stepper("Min reps: \(accessory.minReps)", value: Binding(
                    get: { accessory.minReps },
                    set: { (value: Int) in
                        accessory.minReps = value
                        accessory.maxReps = max(accessory.maxReps, value)
                        // Endpoints only — see the lift window above.
                    }
                ), in: 1...20)
                Stepper("Max reps: \(accessory.maxReps)", value: Binding(
                    get: { accessory.maxReps },
                    set: { (value: Int) in
                        accessory.maxReps = value
                        accessory.minReps = min(accessory.minReps, value)
                    }
                ), in: 1...30)
                Stepper("Load step: +\(settingsList.unitDisplay.format(lb: accessory.incrementLb)) (0 = bodyweight)", value: $accessory.incrementLb, in: 0...25, step: 2.5)
            }
        }
    }
}

/// Exercise picker used by the program day editor.
private struct ExercisePickerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var typeFilter: ExerciseType?
    @State private var detailExercise: Exercise?
    let onPick: (String) -> Void

    private var visible: [Exercise] {
        // The shared search rule (diacritic-insensitive POSIX folding), not a
        // hand-rolled locale-collation predicate — this was the one picker
        // left off the canonical matcher, so "degage" found an accented
        // exercise everywhere except here.
        let available = exercises.filter(\.isAvailableForProgramming)
        let pool = typeFilter.map { filter in available.filter { $0.type == filter } } ?? available
        guard !search.isEmpty else { return pool }
        let term = ExerciseSearch.preparedTerm(search)
        return pool.filter { $0.matchesSearch(preparedTerm: term) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Equipment filter + detail preview: the same picker surface
                // as the logger's add-exercise sheet (issues #63/#66).
                Section {
                    ExerciseTypeFilterRow(typeFilter: $typeFilter)
                }
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    let inCategory = visible.filter { $0.category == category }
                    if !inCategory.isEmpty {
                        Section(category.rawValue) {
                            ForEach(inCategory) { exercise in
                                HStack {
                                    Button(exercise.name) { onPick(exercise.name); dismiss() }
                                    Spacer()
                                    Button {
                                        detailExercise = exercise
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .accessibilityLabel("\(exercise.name) — muscles, history, and settings")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick exercise")
            .searchable(text: $search, prompt: "Exercise, movement, or equipment")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $detailExercise) { exercise in
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                }
            }
        }
    }
}
