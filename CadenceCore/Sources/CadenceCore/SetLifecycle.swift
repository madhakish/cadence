import Foundation

/// Prescription state shared by native and web. A missing legacy value is
/// performed only when it already belongs to banked history; ambiguous open
/// sessions stay planned.
public enum SetStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case completed
    case skipped
}

public enum SetLifecycle {
    public static let qualityValues = ["clean", "grindy", "wobble"]

    public static func resolve(_ rawValue: String?, sessionCompleted: Bool) -> SetStatus {
        rawValue.flatMap { SetStatus(rawValue: $0) } ?? (sessionCompleted ? .completed : .planned)
    }

    public static func quality(in flags: [String]) -> String? {
        flags.first { qualityValues.contains($0) }
    }

    /// Quality is mutually exclusive; stopped-early remains independent.
    public static func normalizedFlags(quality: String?, stoppedEarly: Bool) -> [String] {
        var result: [String] = []
        if let quality, qualityValues.contains(quality) { result.append(quality) }
        if stoppedEarly { result.append("stopped early") }
        return result
    }
}
