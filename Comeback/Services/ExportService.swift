import Foundation
import SwiftData
import ComebackCore

/// Full data export, JSON and CSV. The data is the user's; getting it out
/// must never require a backend.
enum ExportService {

    // MARK: - DTOs

    struct ExportSet: Codable {
        let weightLb: Double
        let reps: Int
        let isWarmup: Bool
        let isPerSide: Bool
        let flags: [String]
        let bodyFlagSite: String?
        let bodyFlagNote: String?
        let durationSeconds: Int?
        let distanceMiles: Double?
        let autoregReason: String?
    }

    struct ExportExercise: Codable {
        let name: String
        let notes: String
        let phase: String?
        let sets: [ExportSet]
    }

    struct ExportSession: Codable {
        let date: Date
        let notes: String
        let gym: String?
        let exercises: [ExportExercise]
    }

    struct ExportBundle: Codable {
        let exportedAt: Date
        let appVersion: String
        let sessions: [ExportSession]
        let bodyweight: [ExportBodyweight]
        let protein: [ExportProtein]
        let checkIns: [ExportCheckIn]
        let milestones: [ExportMilestone]
    }

    struct ExportBodyweight: Codable {
        let date: Date
        let weightLb: Double
        let bodyFatPercent: Double?
        let milestoneLabel: String?
    }

    struct ExportProtein: Codable {
        let date: Date
        let grams: Double
        let label: String
    }

    struct ExportCheckIn: Codable {
        let date: Date
        let site: String
        let response: String
        let note: String
    }

    struct ExportMilestone: Codable {
        let date: Date
        let exercise: String?
        let kind: String
        let label: String
    }

    // MARK: - JSON

    static func jsonData(context: ModelContext) throws -> Data {
        let bundle = try buildBundle(context: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    // MARK: - CSV (one row per set — the spreadsheet-friendly shape)

    static func csvData(context: ModelContext) throws -> Data {
        let bundle = try buildBundle(context: context)
        var rows = ["date,exercise,set_index,weight_lb,weight_kg,reps,is_warmup,per_side,flags,body_flag_site,body_flag_note,autoreg_reason,session_notes"]
        let formatter = ISO8601DateFormatter()
        for session in bundle.sessions {
            for exercise in session.exercises {
                for (i, set) in exercise.sets.enumerated() {
                    let fields = [
                        formatter.string(from: session.date),
                        exercise.name,
                        "\(i + 1)",
                        String(format: "%.2f", set.weightLb),
                        String(format: "%.2f", Weight.kg(fromLb: set.weightLb)),
                        "\(set.reps)",
                        "\(set.isWarmup)",
                        "\(set.isPerSide)",
                        set.flags.joined(separator: ";"),
                        set.bodyFlagSite ?? "",
                        set.bodyFlagNote ?? "",
                        set.autoregReason ?? "",
                        session.notes,
                    ]
                    rows.append(fields.map(escapeCSV).joined(separator: ","))
                }
            }
        }
        return Data(rows.joined(separator: "\n").utf8)
    }

    private static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    // MARK: - Assembly

    private static func buildBundle(context: ModelContext) throws -> ExportBundle {
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)])
        )
        let bodyweight = try context.fetch(
            FetchDescriptor<BodyweightEntry>(sortBy: [SortDescriptor(\.date)])
        )
        let protein = try context.fetch(
            FetchDescriptor<ProteinEntry>(sortBy: [SortDescriptor(\.date)])
        )
        let checkIns = try context.fetch(
            FetchDescriptor<CheckIn>(sortBy: [SortDescriptor(\.date)])
        )
        let milestones = try context.fetch(
            FetchDescriptor<Milestone>(sortBy: [SortDescriptor(\.date)])
        )

        return ExportBundle(
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            sessions: sessions.map { session in
                ExportSession(
                    date: session.date,
                    notes: session.notes,
                    gym: session.gymName,
                    exercises: session.orderedExercises.map { entry in
                        ExportExercise(
                            name: entry.exercise?.name ?? "Unknown",
                            notes: entry.notes,
                            phase: entry.phase?.label,
                            sets: entry.orderedSets.map { set in
                                ExportSet(
                                    weightLb: set.weightLb,
                                    reps: set.reps,
                                    isWarmup: set.isWarmup,
                                    isPerSide: set.isPerSide,
                                    flags: set.flagsRaw,
                                    bodyFlagSite: set.bodyFlagSiteRaw,
                                    bodyFlagNote: set.bodyFlagNote,
                                    durationSeconds: set.durationSeconds,
                                    distanceMiles: set.distanceMiles,
                                    autoregReason: set.autoregReasonRaw
                                )
                            }
                        )
                    }
                )
            },
            bodyweight: bodyweight.map {
                ExportBodyweight(date: $0.date, weightLb: $0.weightLb,
                                 bodyFatPercent: $0.bodyFatPercent, milestoneLabel: $0.milestoneLabel)
            },
            protein: protein.map { ExportProtein(date: $0.date, grams: $0.grams, label: $0.label) },
            checkIns: checkIns.map {
                ExportCheckIn(date: $0.date, site: $0.siteRaw, response: $0.response, note: $0.note)
            },
            milestones: milestones.map {
                ExportMilestone(date: $0.date, exercise: $0.exerciseName, kind: $0.kindRaw, label: $0.label)
            }
        )
    }
}
