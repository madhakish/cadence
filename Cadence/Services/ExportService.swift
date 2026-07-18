import Foundation
import SwiftData
import CadenceCore

/// Full data export, JSON and CSV. The data is the user's; getting it out
/// must never require a backend.
enum ExportService {

    // MARK: - DTOs

    struct ExportSet: Codable {
        let weightLb: Double
        let reps: Int
        let isWarmup: Bool
        let status: String
        let isPerSide: Bool
        let enteredUnit: String
        let flags: [String]
        let bodyFlagSite: String?
        let bodyFlagNote: String?
        let durationSeconds: Int?
        let distanceMiles: Double?
        let inclinePercent: Double?
        let autoregReason: String?
    }

    struct ExportExercise: Codable {
        let name: String
        let notes: String
        let phase: String?
        let role: String?
        let barId: String?
        let plannedWeightLb: Double?
        let plannedSets: Int?
        let plannedReps: Int?
        let sets: [ExportSet]
    }

    /// Program linkage on a session (web `programTag`; historical metadata).
    struct ExportProgramTag: Codable {
        let programId: String
        let programName: String
        let cycleNumber: Int?
        let week: Int?
        let dayIndex: Int?
        let planNames: [String]?
    }

    struct ExportSession: Codable {
        let date: Date
        let notes: String
        let gym: String?
        let gymId: String?
        let isCompleted: Bool
        let programTag: ExportProgramTag?
        let exercises: [ExportExercise]
    }

    // The bundle must round-trip ALL mutable state (mirrors web exportBundle):
    // tracks, gyms, the exercise library, and settings ride along with the log
    // so a restore — the web importBundle is the only restore path — recovers
    // everything, not just history.
    struct ExportBundle: Codable {
        let schemaVersion: Int
        let exportedAt: Date
        let appVersion: String
        let sessions: [ExportSession]
        let bodyweight: [ExportBodyweight]
        let protein: [ExportProtein]
        let checkIns: [ExportCheckIn]
        let milestones: [ExportMilestone]
        let programs: [ExportProgram]
        let tracks: [ExportTrack]
        let gyms: [ExportGym]
        let exercises: [ExportExerciseDef]
        let settings: ExportSettings?
    }

    /// Web `tracks` store record shape (imported verbatim there).
    struct ExportTrack: Codable {
        let exerciseName: String
        let mode: String
        let cycleNumber: Int
        let baseWeightLb: Double
        let nextPhase: Int
        let incrementLb: Double
        let roundingLb: Double
        let lastCompletedAt: Date?
    }

    struct ExportPlateToggle: Codable {
        let value: Double
        let unit: String
        let enabled: Bool
    }

    /// Web `gyms` store record shape; barcodeImage is a data URL.
    struct ExportGym: Codable {
        let id: String
        let name: String
        let isDefault: Bool
        let defaultBarId: String
        let plateToggles: [ExportPlateToggle]
        let barcodeImage: String?
        let barcodeLabel: String
    }

    /// Web `exercises` store record shape.
    struct ExportExerciseDef: Codable {
        let name: String
        let category: String
        let type: String
        let movementGroup: String
        let isUnilateral: Bool
        let defaultRestSeconds: Int
        let notes: String
        let isShelved: Bool
        let shelvedNote: String
        let watchSite: String?
        let createdAt: Date
    }

    /// Web `settings.rest` shape — the five buckets under the key names the
    /// PWA stores, so a native backup restores the buckets on web directly.
    struct ExportRest: Codable {
        let mainCompoundSeconds: Int
        let olympicSeconds: Int
        let mainUpperSeconds: Int
        let secondarySeconds: Int
        let accessorySeconds: Int
    }

    /// Web `settings` row shape (sans row id). The rest buckets ride twice:
    /// nested `rest` (the web's canonical shape) and the flat `*RestSeconds`
    /// keys (what native importers of the first bucket release read).
    struct ExportSettings: Codable {
        let unitDisplay: String
        let proteinTargetGrams: Double
        let accessoryRestSeconds: Int
        let mainCompoundRestSeconds: Int?
        let olympicRestSeconds: Int?
        let mainUpperRestSeconds: Int?
        let secondaryRestSeconds: Int?
        let rest: ExportRest?
        let autoStartRest: Bool
        let haptics: Bool
        /// Rides in the bundle so restoring a post-migration backup doesn't
        /// re-run the retired-rest-stamp clear; absent in old backups → re-run.
        let restSeedStampsCleared: Bool?
        let seededAt: Date?
        let theme: String?
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

    /// Mid-cycle backup: the week-3 Peak result pending application at
    /// rollover. Web stores it nested as `{state, note}` — losing it turns the
    /// next rollover into a spurious stall.
    struct ExportPendingState: Codable {
        let baseWeightLb: Double
        let estimatedMaxLb: Double
        let stallCount: Int
        let lastIncrementLb: Double
    }

    struct ExportPendingResult: Codable {
        let state: ExportPendingState
        let note: String?
    }

    struct ExportProgramLift: Codable {
        let exerciseName: String
        let role: String
        let baseWeightLb: Double
        let estimatedMaxLb: Double
        let stallCount: Int
        let lastIncrementLb: Double
        let pending: ExportPendingResult?
        let revertToExerciseName: String?   // cycle-scoped swap, reverts at rollover
    }

    struct ExportProgramAccessory: Codable {
        let exerciseName: String
        let sets: Int
        let minReps: Int
        let maxReps: Int
        let currentReps: Int
        let weightLb: Double
        let incrementLb: Double
        let stallCount: Int
        let revertToExerciseName: String?   // cycle-scoped swap, reverts at rollover
    }

    struct ExportProgramDay: Codable {
        let name: String
        let order: Int
        let lifts: [ExportProgramLift]
        let accessories: [ExportProgramAccessory]
    }

    struct ExportProgram: Codable {
        let id: String
        let name: String
        let focus: String
        let cycleNumber: Int
        let currentWeek: Int
        let nextDayIndex: Int
        let roundingLb: Double
        let isActive: Bool
        let days: [ExportProgramDay]
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
        var rows = ["date,exercise,set_index,weight_lb,weight_kg,reps,is_warmup,status,per_side,flags,body_flag_site,body_flag_note,autoreg_reason,session_notes"]
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
                        set.status,
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
        let programs = try context.fetch(
            FetchDescriptor<Program>(sortBy: [SortDescriptor(\.name)])
        )
        let tracks = try context.fetch(
            FetchDescriptor<LiftTrack>(sortBy: [SortDescriptor(\.exerciseName)])
        )
        let gyms = try context.fetch(
            FetchDescriptor<Gym>(sortBy: [SortDescriptor(\.name)])
        )
        let exerciseDefs = try context.fetch(
            FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        )
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first

        return ExportBundle(
            schemaVersion: BackupContract.currentSchemaVersion,
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            sessions: sessions.map { session in
                let resolvedGymID = session.gymID ?? gyms.first(where: { $0.name == session.gymName })?.id
                let resolvedProgramID = session.programID
                    ?? programs.first(where: { $0.name == session.programName })?.id
                    ?? session.programName.map { "legacy:\($0)" }
                let programTag: ExportProgramTag?
                if let id = resolvedProgramID, let name = session.programName {
                    programTag = ExportProgramTag(
                        programId: id, programName: name,
                        cycleNumber: session.programCycleNumber,
                        week: session.programWeek,
                        dayIndex: session.programDayIndex,
                        planNames: session.programPlanNames
                    )
                } else {
                    programTag = nil
                }
                return ExportSession(
                    date: session.date,
                    notes: session.notes,
                    gym: session.gymName,
                    gymId: resolvedGymID,
                    isCompleted: session.isCompleted,
                    programTag: programTag,
                    exercises: session.orderedExercises.map { entry in
                        ExportExercise(
                            name: entry.exercise?.name ?? "Unknown",
                            notes: entry.notes,
                            phase: entry.phase?.label,
                            role: entry.programRole,
                            barId: entry.barID,
                            plannedWeightLb: entry.plannedWeightLb,
                            plannedSets: entry.plannedSets,
                            plannedReps: entry.plannedReps,
                            sets: entry.orderedSets.map { set in
                                ExportSet(
                                    weightLb: set.weightLb,
                                    reps: set.reps,
                                    isWarmup: set.isWarmup,
                                    status: set.status.rawValue,
                                    isPerSide: set.isPerSide,
                                    enteredUnit: set.enteredUnitRaw,
                                    flags: set.flags.map(\.rawValue),
                                    bodyFlagSite: set.bodyFlagSite?.rawValue,
                                    bodyFlagNote: set.bodyFlagNote,
                                    durationSeconds: set.durationSeconds,
                                    distanceMiles: set.distanceMiles,
                                    inclinePercent: set.inclinePercent,
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
                ExportCheckIn(date: $0.date, site: $0.site?.rawValue ?? BodySite.knee.rawValue,
                              response: $0.response, note: $0.note)
            },
            milestones: milestones.map {
                ExportMilestone(date: $0.date, exercise: $0.exerciseName, kind: $0.kindRaw, label: $0.label)
            },
            programs: programs.map { p in
                ExportProgram(
                    id: p.id, name: p.name, focus: p.focusRaw, cycleNumber: p.cycleNumber, currentWeek: p.currentWeek,
                    nextDayIndex: p.nextDayIndex, roundingLb: p.roundingLb, isActive: p.isActive,
                    days: p.orderedDays.map { d in
                        ExportProgramDay(
                            name: d.name, order: d.order,
                            lifts: d.orderedLifts.map { l in
                                ExportProgramLift(
                                    exerciseName: l.exerciseName, role: l.roleRaw, baseWeightLb: l.baseWeightLb,
                                    estimatedMaxLb: l.estimatedMaxLb, stallCount: l.stallCount, lastIncrementLb: l.lastIncrementLb,
                                    pending: l.pendingBaseWeightLb.map { pendingBase in
                                        ExportPendingResult(
                                            state: ExportPendingState(
                                                baseWeightLb: pendingBase,
                                                estimatedMaxLb: l.pendingEstimatedMaxLb ?? l.estimatedMaxLb,
                                                stallCount: l.pendingStallCount ?? l.stallCount,
                                                lastIncrementLb: l.pendingLastIncrementLb ?? 0
                                            ),
                                            note: l.pendingNote
                                        )
                                    },
                                    revertToExerciseName: l.revertToExerciseName
                                )
                            },
                            accessories: d.accessories.map { a in
                                ExportProgramAccessory(exerciseName: a.exerciseName, sets: a.sets, minReps: a.minReps, maxReps: a.maxReps,
                                                       currentReps: a.currentReps, weightLb: a.weightLb, incrementLb: a.incrementLb, stallCount: a.stallCount,
                                                       revertToExerciseName: a.revertToExerciseName)
                            }
                        )
                    }
                )
            },
            tracks: tracks.map { t in
                ExportTrack(exerciseName: t.exerciseName, mode: t.modeRaw, cycleNumber: t.cycleNumber,
                            baseWeightLb: t.baseWeightLb, nextPhase: t.nextPhaseRaw, incrementLb: t.incrementLb,
                            roundingLb: t.roundingLb, lastCompletedAt: t.lastCompletedAt)
            },
            gyms: gyms.map { g in
                ExportGym(
                    id: g.id, name: g.name, isDefault: g.isDefault,
                    // Normalize through Bar.by so legacy untrimmed ids export
                    // in the shared format the web can resolve.
                    defaultBarId: Bar.by(id: g.defaultBarID).id,
                    plateToggles: g.plateToggles.map { ExportPlateToggle(value: $0.value, unit: $0.unitRaw, enabled: $0.enabled) },
                    barcodeImage: dataURL(g.barcodeImageData),
                    barcodeLabel: g.barcodeLabel
                )
            },
            exercises: exerciseDefs.map { e in
                ExportExerciseDef(name: e.name, category: e.categoryRaw, type: e.typeRaw, movementGroup: e.movementGroup,
                                  isUnilateral: e.isUnilateral, defaultRestSeconds: e.defaultRestSeconds, notes: e.notes,
                                  isShelved: e.isShelved, shelvedNote: e.shelvedNote,
                                  watchSite: e.watchSite?.rawValue, createdAt: e.createdAt)
            },
            settings: settings.map { s in
                ExportSettings(unitDisplay: s.unitDisplayRaw, proteinTargetGrams: s.proteinTargetGrams,
                               accessoryRestSeconds: s.accessoryRestSeconds,
                               mainCompoundRestSeconds: s.mainCompoundRestSeconds, olympicRestSeconds: s.olympicRestSeconds,
                               mainUpperRestSeconds: s.mainUpperRestSeconds, secondaryRestSeconds: s.secondaryRestSeconds,
                               rest: ExportRest(mainCompoundSeconds: s.mainCompoundRestSeconds,
                                                olympicSeconds: s.olympicRestSeconds,
                                                mainUpperSeconds: s.mainUpperRestSeconds,
                                                secondarySeconds: s.secondaryRestSeconds,
                                                accessorySeconds: s.accessoryRestSeconds),
                               autoStartRest: s.autoStartRest,
                               haptics: s.haptics, restSeedStampsCleared: s.restSeedStampsCleared,
                               seededAt: s.seededAt, theme: s.themeNameRaw)
            }
        )
    }

    /// Barcode photo as a data URL (the web `gyms` store shape).
    private static func dataURL(_ data: Data?) -> String? {
        guard let data else { return nil }
        let mime = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
