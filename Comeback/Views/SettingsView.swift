import SwiftUI
import SwiftData
import PhotosUI
import ComebackCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query(sort: \LiftTrack.exerciseName) private var tracks: [LiftTrack]
    @Query private var programs: [Program]

    @State private var exportJSON: Data?
    @State private var exportCSV: Data?

    var body: some View {
        NavigationStack {
            Form {
                if let settings = settingsList.first {
                    let bindable = Bindable(settings)

                    Section("Units") {
                        Picker("Display", selection: bindable.unitDisplayRaw) {
                            Text("lb primary").tag(UnitDisplay.lbPrimary.rawValue)
                            Text("kg primary").tag(UnitDisplay.kgPrimary.rawValue)
                            Text("Both").tag(UnitDisplay.both.rawValue)
                        }
                    }

                    Section {
                        Stepper(
                            "Accessory: \(mmss(settings.accessoryRestSeconds))",
                            value: bindable.accessoryRestSeconds, in: 30...300, step: 15
                        )
                        Toggle("Auto-start rest after a set", isOn: bindable.autoStartRest)
                        Toggle("Haptics", isOn: bindable.haptics)
                    } header: {
                        Text("Rest timer")
                    } footer: {
                        Text("Rest is smart by movement (lower 5:00 · oly 4:00 · upper 3:00 · accessory 1:30). The stepper is the accessory fallback; a per-exercise rest set in the logger or library overrides the default for any movement. Auto-start off = tap Rest yourself.")
                    }

                    Section("Protein") {
                        Stepper(
                            "Daily target: \(Int(settings.proteinTargetGrams)) g",
                            value: bindable.proteinTargetGrams, in: 80...300, step: 5
                        )
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
                        try? context.save()
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
                                Text("\(program.focus.rawValue) · \(program.days.count) days · Cycle \(program.cycleNumber), Wk\(program.currentWeek)\(program.isActive ? " · active" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        let program = Program(name: "Program \(programs.count + 1)", isActive: programs.isEmpty)
                        context.insert(program)
                        try? context.save()
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
                                Text("+\(Weight.trim(track.incrementLb)) lb per \(track.mode == .cycle ? "cycle" : "session") · next: \(track.suggestion.label)")
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
                        exportJSON = try? ExportService.jsonData(context: context)
                    }
                    if let exportJSON {
                        ShareLink(
                            item: TransferableFile(data: exportJSON, filename: "comeback-export.json"),
                            preview: SharePreview("comeback-export.json")
                        ) {
                            Label("Share JSON", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Prepare CSV export") {
                        exportCSV = try? ExportService.csvData(context: context)
                    }
                    if let exportCSV {
                        ShareLink(
                            item: TransferableFile(data: exportCSV, filename: "comeback-sets.csv"),
                            preview: SharePreview("comeback-sets.csv")
                        ) {
                            Label("Share CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
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
                        try? context.save()
                    }
                }
            } header: {
                Text("Membership tag")
            } footer: {
                Text("Snap your keychain barcode once. The phone becomes the second tag your gym's software can't issue.")
            }
        }
        .navigationTitle(gym.name)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    gym.barcodeImageData = data
                    try? context.save()
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
    @Bindable var track: LiftTrack

    var body: some View {
        Form {
            Section("Progression") {
                Picker("Mode", selection: Binding(
                    get: { track.mode },
                    set: { track.mode = $0 }
                )) {
                    Text("4-week cycle").tag(TrackMode.cycle)
                    Text("Linear").tag(TrackMode.linear)
                }
                Stepper(
                    "Increment: +\(Weight.trim(track.incrementLb)) lb",
                    value: $track.incrementLb, in: 2.5...25, step: 2.5
                )
                Stepper(
                    "\(track.mode == .cycle ? "Week 1 weight" : "Current weight"): \(Weight.trim(track.baseWeightLb)) lb",
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
                Text(track.suggestion.label)
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
            }
        }
        .navigationTitle(track.exerciseName)
    }
}

// MARK: - Program editor

struct ProgramEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allPrograms: [Program]
    @Bindable var program: Program

    var body: some View {
        Form {
            Section("Name") {
                TextField("Program name", text: $program.name)
            }
            Section("Training focus") {
                Picker("Focus", selection: Binding(get: { program.focus }, set: { program.focus = $0 })) {
                    Text("Strength").tag(TrainingFocus.strength)
                    Text("Hypertrophy").tag(TrainingFocus.hypertrophy)
                    Text("Maintain").tag(TrainingFocus.maintain)
                }
                Stepper("Rounding: \(Weight.trim(program.roundingLb)) lb", value: $program.roundingLb, in: 2.5...10, step: 2.5)
                // Activation is exclusive — only one program drives Today.
                Toggle("Active", isOn: Binding(get: { program.isActive }, set: { on in
                    if on { for p in allPrograms { p.isActive = (p === program) } } else { program.isActive = false }
                }))
            }
            Section {
                Text("Cycle \(program.cycleNumber), week \(program.currentWeek). Lifts progress automatically — weights are the current week-1 base.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Days") {
                ForEach(program.orderedDays) { day in
                    NavigationLink {
                        ProgramDayEditorView(day: day, step: program.roundingLb)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(day.name)
                            Text(day.lifts.map(\.exerciseName).joined(separator: " + "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteDays)
                Button {
                    let day = ProgramDay(name: "Day \(program.days.count + 1)", order: program.days.count)
                    day.program = program
                    program.days.append(day)
                    context.insert(day)
                    try? context.save()
                } label: {
                    Label("Add day", systemImage: "plus")
                }
            }
            Section {
                Button(role: .destructive) {
                    context.delete(program)
                    try? context.save()
                    dismiss()
                } label: {
                    Text("Delete program")
                }
            }
        }
        .navigationTitle(program.name)
    }

    private func deleteDays(at offsets: IndexSet) {
        let ordered = program.orderedDays
        for i in offsets { context.delete(ordered[i]) }
        for (i, day) in program.orderedDays.enumerated() { day.order = i }
        if program.nextDayIndex >= program.days.count { program.nextDayIndex = 0 }
        try? context.save()
    }
}

struct ProgramDayEditorView: View {
    @Environment(\.modelContext) private var context
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
                ForEach(day.orderedLifts) { lift in
                    ProgramLiftRow(lift: lift, step: step)
                }
                .onDelete { offsets in
                    let ordered = day.orderedLifts
                    for i in offsets { context.delete(ordered[i]) }
                }
                Button { picking = .lift } label: { Label("Add lift", systemImage: "plus") }
            }
            Section("Accessories") {
                ForEach(day.accessories) { accessory in
                    ProgramAccessoryRow(accessory: accessory)
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(day.accessories[i]) }
                }
                Button { picking = .accessory } label: { Label("Add accessory", systemImage: "plus") }
            }
        }
        .navigationTitle(day.name)
        .sheet(item: $picking) { target in
            ExercisePickerSheetView { name in
                switch target {
                case .lift:
                    let lift = ProgramLift(exerciseName: name, role: .complementary, baseWeightLb: 45, estimatedMaxLb: 52)
                    lift.day = day
                    day.lifts.append(lift)
                    context.insert(lift)
                case .accessory:
                    let acc = ProgramAccessory(exerciseName: name, sets: 3, minReps: 8, maxReps: 12, currentReps: 8, weightLb: 0, incrementLb: 0)
                    acc.day = day
                    day.accessories.append(acc)
                    context.insert(acc)
                }
                picking = nil
            }
        }
    }
}

private struct ProgramLiftRow: View {
    @Bindable var lift: ProgramLift
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lift.exerciseName).font(.headline)
            Picker("Role", selection: Binding(get: { lift.role }, set: { lift.role = $0 })) {
                Text("Main").tag(LiftRole.main)
                Text("Complementary").tag(LiftRole.complementary)
            }
            .pickerStyle(.segmented)
            Stepper("Week-1 base: \(Weight.trim(lift.baseWeightLb)) lb", value: $lift.baseWeightLb, in: 0...1000, step: step)
            Stepper("Est. 1RM: \(Weight.trim(lift.estimatedMaxLb)) lb", value: $lift.estimatedMaxLb, in: 0...1200, step: 5)
        }
    }
}

private struct ProgramAccessoryRow: View {
    @Bindable var accessory: ProgramAccessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(accessory.exerciseName).font(.headline)
            Stepper("Weight: \(Weight.trim(accessory.weightLb)) lb", value: $accessory.weightLb, in: 0...500, step: 2.5)
            Stepper("Sets: \(accessory.sets)", value: $accessory.sets, in: 1...8)
            Stepper("Min reps: \(accessory.minReps)", value: $accessory.minReps, in: 1...20)
            Stepper("Max reps: \(accessory.maxReps)", value: $accessory.maxReps, in: 1...30)
            Stepper("Load step: +\(Weight.trim(accessory.incrementLb)) lb (0 = bodyweight)", value: $accessory.incrementLb, in: 0...25, step: 2.5)
        }
    }
}

/// Exercise picker used by the program day editor.
private struct ExercisePickerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    let inCategory = exercises.filter { $0.category == category }
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
