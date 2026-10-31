import CadenceCore
import SwiftUI

/// Settings → Watch → Motion recordings (design #339, section 8). Recordings
/// stay on this phone, outside the backup; exporting is the only way they
/// leave, as one zip through the share sheet.
struct MotionRecordingsView: View {
    @State private var recordings: [MotionSidecar] = []
    @State private var bytes = 0
    @State private var archive: URL?
    @State private var exportError: String?
    @State private var preparing = false
    @State private var confirmingDeleteAll = false

    var body: some View {
        List {
            Section {
                LabeledContent("Recordings", value: "\(recordings.count)")
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                if let latest = recordings.first {
                    LabeledContent("Latest", value: latest.startedAt.formatted(date: .abbreviated, time: .shortened))
                }
            } footer: {
                Text("Your watch records wrist motion during sessions it runs, so Cadence can later learn to count your reps. Recordings stay on this phone and are not part of your backup. Turn recording off in the Cadence app on your watch.")
            }
            if !recordings.isEmpty {
                Section("Sessions") {
                    ForEach(recordings, id: \.recordingID) { recording in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened))
                            let sets = recording.events.filter { $0.kind == .setCompleted }.count
                            Text(sets == 1 ? "1 set" : "\(sets) sets").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { try? MotionRecordingStore.delete(recordingID: recordings[index].recordingID) }
                        reload()
                    }
                }
            }
            Section {
                if let archive {
                    ShareLink(item: archive) {
                        Label("Share motion recordings", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        prepare()
                    } label: {
                        Label(preparing ? "Preparing…" : "Export motion recordings", systemImage: "archivebox")
                    }
                    .disabled(recordings.isEmpty || preparing)
                }
                if let exportError {
                    Text(exportError).font(.footnote).foregroundStyle(.red)
                }
            }
            if !recordings.isEmpty {
                Section {
                    Button("Delete all recordings", role: .destructive) { confirmingDeleteAll = true }
                }
            }
        }
        .navigationTitle("Motion recordings")
        .onAppear(perform: reload)
        // The zip is a copy of real data in tmp; it goes when this screen does.
        .onDisappear { MotionRecordingStore.removeExports() }
        .confirmationDialog("Delete all motion recordings?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete \(recordings.count) recordings", role: .destructive) {
                try? MotionRecordingStore.deleteAll()
                reload()
            }
        } message: {
            Text("They are removed from this iPhone. Your logged workouts are not affected.")
        }
    }

    private func reload() {
        recordings = MotionRecordingStore.list()
        bytes = MotionRecordingStore.totalBytes()
        archive = nil
    }

    private func prepare() {
        preparing = true
        defer { preparing = false }
        do {
            archive = try MotionRecordingStore.exportArchive()
            exportError = nil
        } catch {
            exportError = "Couldn't prepare the export: \(error.localizedDescription)"
        }
    }
}
