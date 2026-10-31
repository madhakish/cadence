import CadenceCore
import Foundation

// Local detector evaluation (design #339 section 9), outside CI:
//
//   swift run --package-path CadenceCore cadence-motion-eval <folder>
//
// <folder> is an unzipped "Export motion recordings" archive: one sub-folder
// per recording holding samples.cdmr and sidecar.json. Prints the per-exercise
// accuracy table. Only that table may be posted; never the recordings.

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: cadence-motion-eval <exported recordings folder>\n".utf8))
    exit(64)
}
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
var folders = [root]
if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
    for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        folders.append(url)
    }
}
var recordings: [MotionRecordingData] = []
var skipped = 0
for folder in folders {
    let samplesURL = folder.appendingPathComponent("samples.cdmr")
    let sidecarURL = folder.appendingPathComponent("sidecar.json")
    guard FileManager.default.fileExists(atPath: samplesURL.path),
          FileManager.default.fileExists(atPath: sidecarURL.path) else { continue }
    do {
        let sidecar = try JSONDecoder().decode(MotionSidecar.self, from: Data(contentsOf: sidecarURL))
        let samples = try MotionRecording.read(Data(contentsOf: samplesURL)).samples
        recordings.append(MotionRecordingData(sidecar: sidecar, samples: samples))
    } catch {
        skipped += 1
    }
}
guard !recordings.isEmpty else {
    FileHandle.standardError.write(Data("no recordings found under \(root.path)\n".utf8))
    exit(66)
}
print("\(recordings.count) recordings" + (skipped > 0 ? " (\(skipped) unreadable, skipped)" : ""))
print(DetectorEvaluation.table(DetectorEvaluation.evaluate(recordings)))
