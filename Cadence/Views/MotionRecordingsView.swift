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
        }
        .navigationTitle("Motion recordings")
        .onAppear(perform: reload)
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
