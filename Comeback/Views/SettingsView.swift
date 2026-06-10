import SwiftUI
import SwiftData
import PhotosUI
import ComebackCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query(sort: \LiftTrack.exerciseName) private var tracks: [LiftTrack]

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

                    Section("Rest timer defaults") {
                        Stepper(
                            "Main lifts: \(timeLabel(settings.mainLiftRestSeconds))",
                            value: bindable.mainLiftRestSeconds, in: 60...600, step: 30
                        )
                        Stepper(
                            "Accessory: \(timeLabel(settings.accessoryRestSeconds))",
                            value: bindable.accessoryRestSeconds, in: 30...300, step: 15
                        )
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

                Section("Progression") {
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

    private func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
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
