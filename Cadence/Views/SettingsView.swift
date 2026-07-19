import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import CadenceCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query(sort: \LiftTrack.exerciseName) private var tracks: [LiftTrack]
    @Query private var programs: [Program]

    @State private var exportJSON: Data?
    @State private var exportCSV: Data?
    @State private var showImporter = false
    @State private var importAlert: String?
    @AppStorage(BackupCheckpointService.lastSuccessKey) private var checkpointLastSuccess = ""
    @AppStorage(BackupCheckpointService.lastFailureKey) private var checkpointLastFailure = ""

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

                    Section("Protein") {
                        Stepper(
                            "Daily target: \(Int(settings.proteinTargetGrams)) g",
                            value: bindable.proteinTargetGrams, in: 80...300, step: 5
                        )
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
                    } header: {
                        Text("HealthKit")
                    } footer: {
                        Text("Write-only. This app reads nothing from Health.")
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

                Section("Program") {
                    ForEach(programs) { program in
                        NavigationLink {
                            ProgramEditorView(program: program)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(program.name)
                                HStack(spacing: 6) {
                                    WaveGlyph(week: program.currentWeek)
                                    Text("\(program.focus.rawValue) · \(program.days.count) days · Cycle \(program.cycleNumber)\(program.isActive ? " · active" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    // Start from a style (ProgramTemplateData in CadenceCore,
                    // fixture-locked to the web copy) or from scratch. First
                    // program = active; names kept unique (Program.name is a
                    // unique attribute — a collision would upsert, not add).
                    Menu {
                        ForEach(ProgramTemplateData.all) { template in
                            Button {
                                do {
                                    try ProgramTemplates.instantiate(template, context: context)
                                    PersistenceErrorCenter.shared.save(context, operation: "Adding the program")
                                } catch {
                                    PersistenceErrorCenter.shared.report(error, operation: "Adding the program", context: context)
                                }
                            } label: {
                                Text(template.name)
                                Text(template.tagline)
                            }
                        }
                        Button {
                            let name = ProgramTemplates.uniqueProgramName("Program \(programs.count + 1)", existing: programs.map(\.name))
                            let program = Program(name: name, isActive: programs.isEmpty)
                            context.insert(program)
                            PersistenceErrorCenter.shared.save(context, operation: "Adding the program")
                        } label: {
                            Text("Blank program")
                        }
                    } label: {
                        Label("Add program", systemImage: "plus")
                    }
                }

                Section("Progression (standalone lifts)") {
                    ForEach(tracks) { track in
                        NavigationLink {
                            TrackEditorView(track: track)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(track.exerciseName)
                                Text("+\((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: track.incrementLb)) per \(track.mode == .cycle ? "cycle" : "session") · next: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: track.suggestion.weightLb)) · \(track.suggestion.sets)×\(track.suggestion.reps)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
                // syncLibrary right after the restore: a pre-migration backup
                // re-arms the retired-rest-stamp clear, which otherwise
                // wouldn't run until the next app launch — leaving the rest
                // steppers dead in the meantime.
                try Seeder.syncLibrary(context: context)
                return "Restored \(s.sessions) sessions, \(s.programs) program(s), \(s.tracks) tracked lift(s)."
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
            try Seeder.syncLibrary(context: context)
            return "Restored local checkpoint: \(s.sessions) sessions, \(s.programs) program(s), \(s.tracks) tracked lift(s)."
        } catch {
            return error.localizedDescription
        }
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
    private var unitDisplay: UnitDisplay { settingsList.first?.unitDisplay ?? .lbPrimary }

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
        let exerciseByName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        var rotationSets: [String: Int] = [:]
        var patternSets: [MovementPattern: Int] = [:]
        var intervalSlots = 0
        for day in program.orderedDays {
            if !day.lifts.contains(where: { $0.role == .main }) {
                messages.append("\(day.name) has no main lift.")
            }
            for lift in day.orderedLifts {
                if lift.baseWeightLb <= 0 { messages.append("\(lift.exerciseName) needs a rotation-1 base weight.") }
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
                        configuration: lift.prescriptionConfiguration(movementGroup: exercise.movementGroup))
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
                let type = exerciseByName[accessory.exerciseName]?.type
                let isTimed = type == .timed || type == .conditioning
                if !isTimed, accessory.minReps > accessory.maxReps {
                    messages.append("\(accessory.exerciseName)'s minimum reps exceed its maximum.")
                } else if !isTimed, !(accessory.minReps...accessory.maxReps).contains(accessory.currentReps) {
                    messages.append("\(accessory.exerciseName)'s current reps are outside its rep range.")
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
                Stepper("Rounding: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: program.roundingLb))", value: $program.roundingLb, in: 2.5...10, step: 2.5)
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
                Stepper("Rotation: \(program.currentWeek) of 4 · \((CyclePhase(rawValue: program.currentWeek) ?? .volume).name)",
                        value: Binding(get: { program.currentWeek }, set: { positionAtRotation($0) }), in: 1...4)
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
                Text("Set your position mid-cycle. Rotations 1–3 are working (volume/load/peak), rotation 4 is the rest rotation, then the cycle bumps. Lifts progress automatically — weights are the rotation-1 base.")
            }
            Section("Days") {
                ForEach(program.orderedDays) { day in
                    NavigationLink {
                        ProgramDayEditorView(day: day, step: program.roundingLb)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(day.name)
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
        let ordered = program.orderedDays
        for i in offsets { context.delete(ordered[i]) }
        for (i, day) in program.orderedDays.enumerated() { day.order = i }
        if program.nextDayIndex >= program.days.count { program.nextDayIndex = 0 }
        PersistenceErrorCenter.shared.save(context, operation: "Deleting the program day")
    }

    private func moveDays(from offsets: IndexSet, to destination: Int) {
        var ordered = program.orderedDays
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, day) in ordered.enumerated() { day.order = index }
        program.nextDayIndex = min(program.nextDayIndex, max(ordered.count - 1, 0))
        PersistenceErrorCenter.shared.save(context, operation: "Reordering program days")
    }

    private func cloneProgram() {
        let copy = Program(
            name: ProgramTemplates.uniqueProgramName("\(program.name) Copy", existing: allPrograms.map(\.name)),
            focus: program.focus, cycleNumber: program.cycleNumber, currentWeek: program.currentWeek,
            nextDayIndex: program.nextDayIndex, roundingLb: program.roundingLb, isActive: false)
        copy.coachEnabled = program.coachEnabled
        copy.reliableHistoryStart = program.reliableHistoryStart
        copy.preferredSessionSpacingDays = program.preferredSessionSpacingDays
        copy.maximumAddedSetsPerRotation = program.maximumAddedSetsPerRotation
        context.insert(copy)
        for sourceDay in program.orderedDays {
            let dayCopy = ProgramDay(name: sourceDay.name, order: sourceDay.order)
            context.insert(dayCopy)
            copy.days.append(dayCopy)
            for source in sourceDay.orderedLifts {
                let lift = ProgramLift(exerciseName: source.exerciseName, role: source.role, order: source.order,
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
            for source in sourceDay.orderedAccessories {
                let accessory = ProgramAccessory(exerciseName: source.exerciseName, order: source.order,
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
            }
            Section("Lifts") {
                // Every row carries an explicit Remove button (mirroring the web
                // editor): the segmented Role picker spans the row and eats the
                // horizontal pan, so swipe-to-delete alone is undiscoverable here.
                ForEach(day.orderedLifts) { lift in
                    ProgramLiftRow(lift: lift, step: step) {
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
                    let lift = ProgramLift(exerciseName: name, role: .complementary,
                                           order: day.lifts.count, baseWeightLb: 45, estimatedMaxLb: 52)
                    context.insert(lift)
                    day.lifts.append(lift)
                case .accessory:
                    let type = exercises.first { $0.name == name }?.type
                    let acc = ProgramAccessory(exerciseName: name, order: day.accessories.count,
                                               sets: type == .conditioning ? 1 : 3,
                                               minReps: 8, maxReps: 12, currentReps: 8,
                                               targetSeconds: type == .conditioning ? 1_200 : 30,
                                               weightLb: 0, incrementLb: 0)
                    context.insert(acc)
                    day.accessories.append(acc)
                }
                PersistenceErrorCenter.shared.save(context, operation: "Adding the program exercise")
                picking = nil
            }
        }
    }

    private func moveLifts(from offsets: IndexSet, to destination: Int) {
        var ordered = day.orderedLifts
        ordered.move(fromOffsets: offsets, toOffset: destination)
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

private struct ProgramLiftRow: View {
    @Query private var settingsList: [AppSettings]
    @Query private var exercises: [Exercise]
    @Bindable var lift: ProgramLift
    let step: Double
    let onRemove: () -> Void

    private var loadStep: Double {
        ProgramEngine.loadStep(programRoundingLb: step,
                               exerciseType: exercises.first { $0.name == lift.exerciseName }?.typeRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Tapping the name opens the exercise detail (muscles worked,
                // history, program membership).
                NavigationLink {
                    ExerciseDetailByNameView(name: lift.exerciseName)
                } label: {
                    Text(lift.exerciseName).font(.headline)
                }
                .buttonStyle(.plain)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless) // scoped to the icon, not the whole row
                .accessibilityLabel("Remove \(lift.exerciseName)")
            }
            Picker("Role", selection: Binding(get: { lift.role }, set: { lift.role = $0 })) {
                Text("Main").tag(LiftRole.main)
                Text("Complementary").tag(LiftRole.complementary)
            }
            .pickerStyle(.segmented)
            Picker("Prescription", selection: Binding(get: { lift.prescription }, set: { lift.prescription = $0 })) {
                ForEach(PrescriptionStyle.allCases, id: \.self) { style in
                    Text(style.name).tag(style)
                }
            }
            Picker("Warm-up", selection: Binding(get: { lift.warmupPolicy }, set: { lift.warmupPolicy = $0 })) {
                ForEach(WarmupPolicy.allCases, id: \.self) { policy in
                    Text(policy.name).tag(policy)
                }
            }
            Stepper("Rotation-1 base: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lift.baseWeightLb))", value: $lift.baseWeightLb, in: 0...1000, step: loadStep)
            Stepper("Est. 1RM: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lift.estimatedMaxLb))", value: $lift.estimatedMaxLb, in: 0...1200, step: 5)
            if lift.prescription == .offsetWave {
                Stepper("Load offset: +\((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lift.loadOffsetLb))",
                        value: $lift.loadOffsetLb, in: 0...100, step: loadStep)
                Stepper("Peak offset: +\((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lift.peakOffsetLb))",
                        value: $lift.peakOffsetLb, in: 0...150, step: loadStep)
                Stepper("Deload: \(Int(lift.deloadMultiplier * 100))%", value: $lift.deloadMultiplier,
                        in: 0.5...0.9, step: 0.025)
            }
            if lift.prescription == .doubleProgression {
                Stepper("Sets: \(lift.doubleProgressionSets)", value: $lift.doubleProgressionSets, in: 1...8)
                Stepper("Minimum reps: \(lift.minimumReps)", value: $lift.minimumReps, in: 1...20)
                Stepper("Maximum reps: \(lift.maximumReps)", value: $lift.maximumReps, in: lift.minimumReps...30)
                Text("Current target: \(lift.currentReps) reps · add \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: loadStep)) only after every set reaches the top of the window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if lift.prescription.advancesPerExposure && lift.prescription != .doubleProgression {
                Stepper("Working sets: \(lift.doubleProgressionSets)", value: $lift.doubleProgressionSets, in: 1...10)
                Text("Sets-across of five. The base moves every banked session; the Est. 1RM above is what the coach derives it from.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if lift.prescription == .fiveThreeOne {
                Text("The base above is the TRAINING MAX (≈90% of 1RM), not a working weight. The top set each week is as many quality reps as you have.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Peak top single", isOn: $lift.peakSingleEnabled)
            if lift.peakSingleEnabled {
                Stepper("Last clean single: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lift.lastPeakSingleLb))",
                        value: $lift.lastPeakSingleLb, in: 0...1200, step: loadStep)
                Stepper("Single step: +\((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lift.peakSingleIncrementLb))",
                        value: $lift.peakSingleIncrementLb, in: loadStep...25, step: loadStep)
            }
            Toggle("Phase primer single", isOn: $lift.phasePrimerEnabled)
            Stepper("One-tap drop: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lift.dropIncrementLb)) (0 = automatic)",
                    value: $lift.dropIncrementLb, in: 0...50, step: loadStep)
            Toggle("Coach may add sets", isOn: $lift.capacityManaged)
            if lift.capacityManaged {
                Stepper("Maximum sets: \(lift.maximumSets)", value: $lift.maximumSets, in: 1...10)
            }
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
                NavigationLink {
                    ExerciseDetailByNameView(name: accessory.exerciseName)
                } label: {
                    Text(accessory.exerciseName).font(.headline)
                }
                .buttonStyle(.plain)
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
                Stepper("Weight: \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: accessory.weightLb))", value: $accessory.weightLb, in: 0...500, step: 2.5)
                Stepper("Min reps: \(accessory.minReps)", value: $accessory.minReps, in: 1...20)
                Stepper("Max reps: \(accessory.maxReps)", value: $accessory.maxReps, in: 1...30)
                Stepper("Load step: +\((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: accessory.incrementLb)) (0 = bodyweight)", value: $accessory.incrementLb, in: 0...25, step: 2.5)
            }
        }
    }
}

/// Exercise picker used by the program day editor.
private struct ExercisePickerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    let onPick: (String) -> Void

    private var visible: [Exercise] {
        let available = exercises.filter { $0.gateStatus != .shelved }
        return search.isEmpty ? available : available.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.movementGroup.localizedCaseInsensitiveContains(search)
                || $0.movementPattern.name.localizedCaseInsensitiveContains(search)
                || $0.typeRaw.localizedCaseInsensitiveContains(search)
                || $0.aliases.contains(where: { $0.localizedCaseInsensitiveContains(search) })
                || $0.strategyTags.contains(where: { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    let inCategory = visible.filter { $0.category == category }
                    if !inCategory.isEmpty {
                        Section(category.rawValue) {
                            ForEach(inCategory) { exercise in
                                Button(exercise.name) { onPick(exercise.name); dismiss() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick exercise")
            .searchable(text: $search, prompt: "Exercise, movement, or equipment")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
