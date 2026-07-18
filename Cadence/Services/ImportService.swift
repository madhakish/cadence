import Foundation
import SwiftData
import CadenceCore

/// Restores a JSON backup produced by ExportService (or the web app) into
/// SwiftData — the missing other half of ExportService. Mirrors the web
/// `importBundle`: replaces each store the backup contains, leaves absent
/// stores untouched, and is all-or-nothing. The file is fully decoded before
/// anything is written, and any write failure rolls the context back.
enum ImportService {

    enum ImportError: LocalizedError {
        case notABackup, unsupportedSchemaVersion(Int), invalidData(String), writeFailed
        var errorDescription: String? {
            switch self {
            case .notABackup: return "That file isn't a Cadence backup."
            case .unsupportedSchemaVersion(let version):
                return "This backup uses schema version \(version), which this version of Cadence can't restore. Update Cadence and try again."
            case .invalidData(let reason): return "Backup validation failed at \(reason). Nothing was changed."
            case .writeFailed: return "Couldn't restore the backup — nothing was changed."
            }
        }
    }

    struct Summary { let sessions, programs, tracks, gyms: Int }

    // Lenient decode DTOs — optional everywhere so a partial or web-origin
    // backup never throws on a missing key.
    private struct Bundle: Decodable {
        var schemaVersion: Int?
        var sessions: [Session]?; var bodyweight: [Bodyweight]?; var protein: [Protein]?
        var checkIns: [CheckInDTO]?; var milestones: [MilestoneDTO]?; var programs: [ProgramDTO]?
        var tracks: [Track]?; var gyms: [GymDTO]?; var exercises: [ExerciseDef]?; var settings: SettingsDTO?
    }
    private struct Session: Decodable {
        var date: Date?; var notes: String?; var gym: String?; var isCompleted: Bool?
        var programTag: ProgramTag?; var exercises: [ExerciseEntry]?
    }
    private struct ProgramTag: Decodable {
        var programName: String?; var cycleNumber: Int?; var week: Int?; var dayIndex: Int?
        var planNames: [String]?
    }
    private struct ExerciseEntry: Decodable {
        var name: String?; var notes: String?; var phase: String?; var role: String?
        var plannedWeightLb: Double?; var plannedSets: Int?; var plannedReps: Int?; var sets: [SetDTO]?
    }
    private struct SetDTO: Decodable {
        var weightLb: Double?; var reps: Int?; var isWarmup: Bool?; var isPerSide: Bool?
        var enteredUnit: String?; var flags: [String]?; var bodyFlagSite: String?; var bodyFlagNote: String?
        var durationSeconds: Int?; var distanceMiles: Double?; var inclinePercent: Double?; var autoregReason: String?
    }
    private struct Bodyweight: Decodable { var date: Date?; var weightLb: Double?; var bodyFatPercent: Double?; var milestoneLabel: String? }
    private struct Protein: Decodable { var date: Date?; var grams: Double?; var label: String? }
    private struct CheckInDTO: Decodable { var date: Date?; var site: String?; var response: String?; var note: String? }
    private struct MilestoneDTO: Decodable { var date: Date?; var exercise: String?; var kind: String?; var label: String? }
    private struct ProgramDTO: Decodable {
        var name: String?; var focus: String?; var cycleNumber: Int?; var currentWeek: Int?
        var nextDayIndex: Int?; var roundingLb: Double?; var isActive: Bool?; var days: [DayDTO]?
    }
    private struct DayDTO: Decodable { var name: String?; var order: Int?; var lifts: [LiftDTO]?; var accessories: [AccessoryDTO]? }
    private struct LiftDTO: Decodable {
        var exerciseName: String?; var role: String?; var baseWeightLb: Double?; var estimatedMaxLb: Double?
        var stallCount: Int?; var lastIncrementLb: Double?; var pending: PendingDTO?
        var revertToExerciseName: String?   // cycle-scoped swap, reverts at rollover
    }
    private struct PendingDTO: Decodable { var state: PendingState?; var note: String? }
    private struct PendingState: Decodable { var baseWeightLb: Double?; var estimatedMaxLb: Double?; var stallCount: Int?; var lastIncrementLb: Double? }
    private struct AccessoryDTO: Decodable {
        var exerciseName: String?; var sets: Int?; var minReps: Int?; var maxReps: Int?
        var currentReps: Int?; var weightLb: Double?; var incrementLb: Double?; var stallCount: Int?
        var revertToExerciseName: String?   // cycle-scoped swap, reverts at rollover
    }
    private struct Track: Decodable {
        var exerciseName: String?; var mode: String?; var cycleNumber: Int?; var baseWeightLb: Double?
        var nextPhase: Int?; var incrementLb: Double?; var roundingLb: Double?; var lastCompletedAt: Date?
    }
    private struct GymDTO: Decodable {
        var name: String?; var isDefault: Bool?; var defaultBarId: String?
        var plateToggles: [PlateToggleDTO]?; var barcodeImage: String?; var barcodeLabel: String?
    }
    private struct PlateToggleDTO: Decodable { var value: Double?; var unit: String?; var enabled: Bool? }
    private struct ExerciseDef: Decodable {
        var name: String?; var category: String?; var type: String?; var movementGroup: String?
        var isUnilateral: Bool?; var defaultRestSeconds: Int?; var notes: String?
        var isShelved: Bool?; var shelvedNote: String?; var watchSite: String?; var createdAt: Date?
    }
    /// Web `settings.rest` — the PWA's canonical nested shape for the buckets.
    private struct RestDTO: Decodable {
        var mainCompoundSeconds: Int?; var olympicSeconds: Int?; var mainUpperSeconds: Int?
        var secondarySeconds: Int?; var accessorySeconds: Int?
    }
    private struct SettingsDTO: Decodable {
        var unitDisplay: String?; var proteinTargetGrams: Double?; var accessoryRestSeconds: Int?
        var mainCompoundRestSeconds: Int?; var olympicRestSeconds: Int?; var mainUpperRestSeconds: Int?; var secondaryRestSeconds: Int?
        var rest: RestDTO?
        var autoStartRest: Bool?; var haptics: Bool?; var restSeedStampsCleared: Bool?
        var seededAt: Date?; var theme: String?
    }

    // MARK: - Preflight validation

    private static func requiredText(_ value: String?, _ path: String) throws -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.invalidData("\(path): expected non-empty text") }
        return trimmed
    }

    private static func finite(_ value: Double?, _ path: String, required: Bool = false,
                               min: Double = -Double.greatestFiniteMagnitude,
                               max: Double = .greatestFiniteMagnitude) throws {
        guard let value else {
            if required { throw ImportError.invalidData("\(path): expected a number") }
            return
        }
        guard value.isFinite, value >= min, value <= max else {
            throw ImportError.invalidData("\(path): expected a finite number from \(min) to \(max)")
        }
    }

    private static func integer(_ value: Int?, _ path: String, required: Bool = false,
                                min: Int = .min, max: Int = .max) throws {
        guard let value else {
            if required { throw ImportError.invalidData("\(path): expected an integer") }
            return
        }
        guard value >= min, value <= max else {
            throw ImportError.invalidData("\(path): expected an integer from \(min) to \(max)")
        }
    }

    private static func known(_ value: String?, _ allowed: Set<String>, _ path: String, required: Bool = false) throws {
        guard let value else {
            if required { throw ImportError.invalidData("\(path): expected a known value") }
            return
        }
        guard allowed.contains(value) else { throw ImportError.invalidData("\(path): unknown value \(value)") }
    }

    private static func requireDate(_ value: Date?, _ path: String) throws {
        guard value != nil else { throw ImportError.invalidData("\(path): expected an ISO-8601 date") }
    }

    private static func unique(_ values: [String], _ path: String) throws {
        var seen = Set<String>()
        for (index, value) in values.enumerated() where !seen.insert(value).inserted {
            throw ImportError.invalidData("\(path)[\(index)]: duplicate identifier \(value)")
        }
    }

    /// Mirrors web `validateBackup`: reject data that either platform would
    /// silently coerce to a default. This runs before the first fetch/delete,
    /// so a bad file cannot partially restore or mutate the context.
    private static func validate(_ bundle: Bundle, schemaVersion: Int) throws {
        let units: Set<String> = ["lb", "kg"]
        let roles: Set<String> = ["main", "complementary", "accessory"]
        let liftRoles: Set<String> = ["main", "complementary"]
        let flags: Set<String> = ["clean", "grindy", "wobble", "stopped early"]
        let reasons: Set<String> = ["bar speed", "wobble", "joint signal", "heat", "fatigue"]
        let sites: Set<String> = ["Left shoulder", "Left hip", "Right knee"]

        for (si, session) in (bundle.sessions ?? []).enumerated() {
            let path = "sessions[\(si)]"
            try requireDate(session.date, "\(path).date")
            if let tag = session.programTag {
                if schemaVersion >= 1 { _ = try requiredText(tag.programName, "\(path).programTag.programName") }
                try integer(tag.cycleNumber, "\(path).programTag.cycleNumber", min: 1)
                try integer(tag.week, "\(path).programTag.week", min: 1)
                try integer(tag.dayIndex, "\(path).programTag.dayIndex", min: 0)
                for (i, name) in (tag.planNames ?? []).enumerated() {
                    _ = try requiredText(name, "\(path).programTag.planNames[\(i)]")
                }
            }
            for (ei, exercise) in (session.exercises ?? []).enumerated() {
                let exercisePath = "\(path).exercises[\(ei)]"
                _ = try requiredText(exercise.name, "\(exercisePath).name")
                try known(exercise.role, roles, "\(exercisePath).role")
                try finite(exercise.plannedWeightLb, "\(exercisePath).plannedWeightLb", min: 0)
                try integer(exercise.plannedSets, "\(exercisePath).plannedSets", min: 0)
                try integer(exercise.plannedReps, "\(exercisePath).plannedReps", min: 0)
                for (xi, set) in (exercise.sets ?? []).enumerated() {
                    let setPath = "\(exercisePath).sets[\(xi)]"
                    try finite(set.weightLb, "\(setPath).weightLb", required: true, min: 0)
                    try integer(set.reps, "\(setPath).reps", required: true, min: 0)
                    try known(set.enteredUnit, units, "\(setPath).enteredUnit", required: schemaVersion >= 1)
                    for (fi, flag) in (set.flags ?? []).enumerated() { try known(flag, flags, "\(setPath).flags[\(fi)]") }
                    try known(set.bodyFlagSite, sites, "\(setPath).bodyFlagSite")
                    try known(set.autoregReason, reasons, "\(setPath).autoregReason")
                    try integer(set.durationSeconds, "\(setPath).durationSeconds", min: 0)
                    try finite(set.distanceMiles, "\(setPath).distanceMiles", min: 0)
                    try finite(set.inclinePercent, "\(setPath).inclinePercent", min: -100, max: 100)
                }
            }
        }

        for (i, entry) in (bundle.bodyweight ?? []).enumerated() {
            try requireDate(entry.date, "bodyweight[\(i)].date")
            try finite(entry.weightLb, "bodyweight[\(i)].weightLb", required: true, min: 0)
            try finite(entry.bodyFatPercent, "bodyweight[\(i)].bodyFatPercent", min: 0, max: 100)
        }
        for (i, entry) in (bundle.protein ?? []).enumerated() {
            try requireDate(entry.date, "protein[\(i)].date")
            try finite(entry.grams, "protein[\(i)].grams", required: true, min: 0)
        }
        for (i, entry) in (bundle.checkIns ?? []).enumerated() {
            try requireDate(entry.date, "checkIns[\(i)].date")
            _ = try requiredText(entry.site, "checkIns[\(i)].site")
            try known(entry.site, sites, "checkIns[\(i)].site")
            _ = try requiredText(entry.response, "checkIns[\(i)].response")
        }
        let milestoneKinds: Set<String> = ["heaviestSet", "volumePR", "firstScheme", "programNote"]
        for (i, entry) in (bundle.milestones ?? []).enumerated() {
            try requireDate(entry.date, "milestones[\(i)].date")
            _ = try requiredText(entry.kind, "milestones[\(i)].kind")
            try known(entry.kind, milestoneKinds, "milestones[\(i)].kind")
            _ = try requiredText(entry.label, "milestones[\(i)].label")
        }

        for (pi, program) in (bundle.programs ?? []).enumerated() {
            let path = "programs[\(pi)]"
            _ = try requiredText(program.name, "\(path).name")
            try known(program.focus, ["strength", "hypertrophy", "maintain"], "\(path).focus", required: schemaVersion >= 1)
            try integer(program.cycleNumber, "\(path).cycleNumber", min: 1)
            try integer(program.currentWeek, "\(path).currentWeek", min: 1, max: 4)
            try integer(program.nextDayIndex, "\(path).nextDayIndex", min: 0)
            try finite(program.roundingLb, "\(path).roundingLb", min: Double.leastNonzeroMagnitude)
            for (di, day) in (program.days ?? []).enumerated() {
                let dayPath = "\(path).days[\(di)]"
                _ = try requiredText(day.name, "\(dayPath).name")
                try integer(day.order, "\(dayPath).order", required: true, min: 0)
                for (li, lift) in (day.lifts ?? []).enumerated() {
                    let liftPath = "\(dayPath).lifts[\(li)]"
                    _ = try requiredText(lift.exerciseName, "\(liftPath).exerciseName")
                    try known(lift.role, liftRoles, "\(liftPath).role", required: schemaVersion >= 1)
                    try finite(lift.baseWeightLb, "\(liftPath).baseWeightLb", min: 0)
                    try finite(lift.estimatedMaxLb, "\(liftPath).estimatedMaxLb", min: 0)
                    try integer(lift.stallCount, "\(liftPath).stallCount", min: 0)
                    try finite(lift.lastIncrementLb, "\(liftPath).lastIncrementLb", min: 0)
                    if let state = lift.pending?.state {
                        try finite(state.baseWeightLb, "\(liftPath).pending.state.baseWeightLb", min: 0)
                        try finite(state.estimatedMaxLb, "\(liftPath).pending.state.estimatedMaxLb", min: 0)
                        try integer(state.stallCount, "\(liftPath).pending.state.stallCount", min: 0)
                        try finite(state.lastIncrementLb, "\(liftPath).pending.state.lastIncrementLb", min: 0)
                    }
                }
                for (ai, accessory) in (day.accessories ?? []).enumerated() {
                    let accessoryPath = "\(dayPath).accessories[\(ai)]"
                    _ = try requiredText(accessory.exerciseName, "\(accessoryPath).exerciseName")
                    try integer(accessory.sets, "\(accessoryPath).sets", min: 0)
                    try integer(accessory.minReps, "\(accessoryPath).minReps", min: 0)
                    try integer(accessory.maxReps, "\(accessoryPath).maxReps", min: 0)
                    try integer(accessory.currentReps, "\(accessoryPath).currentReps", min: 0)
                    try finite(accessory.weightLb, "\(accessoryPath).weightLb", min: 0)
                    try finite(accessory.incrementLb, "\(accessoryPath).incrementLb", min: 0)
                    try integer(accessory.stallCount, "\(accessoryPath).stallCount", min: 0)
                }
            }
            try unique((program.days ?? []).compactMap(\.order).map { String($0) }, "\(path).days")
            if let next = program.nextDayIndex, let count = program.days?.count, count > 0, next >= count {
                throw ImportError.invalidData("\(path).nextDayIndex: outside the program's day list")
            }
        }
        try unique((bundle.programs ?? []).map { try requiredText($0.name, "programs.name") }, "programs")

        for (i, track) in (bundle.tracks ?? []).enumerated() {
            let path = "tracks[\(i)]"
            _ = try requiredText(track.exerciseName, "\(path).exerciseName")
            try known(track.mode, ["cycle", "linear"], "\(path).mode", required: schemaVersion >= 1)
            try integer(track.cycleNumber, "\(path).cycleNumber", min: 1)
            try integer(track.nextPhase, "\(path).nextPhase", min: 1, max: 4)
            try finite(track.baseWeightLb, "\(path).baseWeightLb", min: 0)
            try finite(track.incrementLb, "\(path).incrementLb", min: Double.leastNonzeroMagnitude)
            try finite(track.roundingLb, "\(path).roundingLb", min: Double.leastNonzeroMagnitude)
        }
        try unique((bundle.tracks ?? []).map { try requiredText($0.exerciseName, "tracks.exerciseName") }, "tracks")

        for (i, gym) in (bundle.gyms ?? []).enumerated() {
            _ = try requiredText(gym.name, "gyms[\(i)].name")
            for (pi, plate) in (gym.plateToggles ?? []).enumerated() {
                try finite(plate.value, "gyms[\(i)].plateToggles[\(pi)].value", required: true, min: Double.leastNonzeroMagnitude)
                _ = try requiredText(plate.unit, "gyms[\(i)].plateToggles[\(pi)].unit")
                try known(plate.unit, units, "gyms[\(i)].plateToggles[\(pi)].unit", required: schemaVersion >= 1)
            }
        }
        try unique((bundle.gyms ?? []).map { try requiredText($0.name, "gyms.name") }, "gyms")

        let categories: Set<String> = ["Main", "Accessory", "Conditioning"]
        let types: Set<String> = ["barbell", "dumbbell", "kettlebell", "bodyweight", "band", "machine", "timed", "conditioning"]
        for (i, exercise) in (bundle.exercises ?? []).enumerated() {
            let path = "exercises[\(i)]"
            _ = try requiredText(exercise.name, "\(path).name")
            try known(exercise.category, categories, "\(path).category", required: schemaVersion >= 1)
            try known(exercise.type, types, "\(path).type", required: schemaVersion >= 1)
            try known(exercise.watchSite, sites, "\(path).watchSite")
            try integer(exercise.defaultRestSeconds, "\(path).defaultRestSeconds", min: 0, max: 3600)
        }
        try unique((bundle.exercises ?? []).map { try requiredText($0.name, "exercises.name") }, "exercises")

        if let settings = bundle.settings {
            try known(settings.unitDisplay, ["lbPrimary", "kgPrimary", "both"], "settings.unitDisplay", required: schemaVersion >= 1)
            try known(settings.theme, ["memento", "carbon", "slate", "system"], "settings.theme", required: schemaVersion >= 1)
            try finite(settings.proteinTargetGrams, "settings.proteinTargetGrams", min: 0)
            for (path, value) in [
                ("settings.accessoryRestSeconds", settings.accessoryRestSeconds),
                ("settings.mainCompoundRestSeconds", settings.mainCompoundRestSeconds),
                ("settings.olympicRestSeconds", settings.olympicRestSeconds),
                ("settings.mainUpperRestSeconds", settings.mainUpperRestSeconds),
                ("settings.secondaryRestSeconds", settings.secondaryRestSeconds),
                ("settings.rest.mainCompoundSeconds", settings.rest?.mainCompoundSeconds),
                ("settings.rest.olympicSeconds", settings.rest?.olympicSeconds),
                ("settings.rest.mainUpperSeconds", settings.rest?.mainUpperSeconds),
                ("settings.rest.secondarySeconds", settings.rest?.secondarySeconds),
                ("settings.rest.accessorySeconds", settings.rest?.accessorySeconds),
            ] { try integer(value, path, min: 0, max: 3600) }
        }
    }

    @discardableResult
    static func load(_ data: Data, into context: ModelContext) throws -> Summary {
        let decoder = JSONDecoder()
        // Accept BOTH ISO-8601 forms: native ExportService writes no fractional
        // seconds, the web PWA's Date.toISOString() writes ".000Z". A single
        // strategy that rejects fractions would fail every web-origin backup.
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Unrecognised date: \(s)"))
        }
        guard let bundle = try? decoder.decode(Bundle.self, from: data) else { throw ImportError.notABackup }
        let schemaVersion = bundle.schemaVersion ?? 0
        guard BackupContract.supports(schemaVersion: schemaVersion) else {
            throw ImportError.unsupportedSchemaVersion(schemaVersion)
        }

        let hasAnything = [bundle.sessions != nil, bundle.programs != nil, bundle.tracks != nil,
                           bundle.gyms != nil, bundle.exercises != nil, bundle.bodyweight != nil,
                           bundle.protein != nil, bundle.checkIns != nil, bundle.milestones != nil,
                           bundle.settings != nil].contains(true)
        guard hasAnything else { throw ImportError.notABackup }
        try validate(bundle, schemaVersion: schemaVersion)

        do {
            // Exercises: UPSERT by name (never delete — SessionExercise links to
            // them by relationship, so replacing them would orphan history).
            if let defs = bundle.exercises {
                var byName: [String: Exercise] = [:]
                for e in (try context.fetch(FetchDescriptor<Exercise>())) { byName[e.name] = e }
                for d in defs {
                    // Exercise.name is @Attribute(.unique); an unnamed def can't
                    // own a key, and two of them would collide on save.
                    let name = (d.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    if let existing = byName[name] { update(existing, from: d) }
                    else { let e = makeExercise(d); context.insert(e); byName[name] = e }
                }
            }
            var exByName: [String: Exercise] = [:]
            for e in try context.fetch(FetchDescriptor<Exercise>()) { exByName[e.name] = e }

            if let gyms = bundle.gyms {
                try context.delete(model: Gym.self)
                for g in gyms { context.insert(makeGym(g)) }
            }
            if let tracks = bundle.tracks {
                try context.delete(model: LiftTrack.self)
                for t in tracks { context.insert(makeTrack(t)) }
            }
            if let programs = bundle.programs {
                try context.delete(model: Program.self)
                for p in programs { context.insert(makeProgram(p)) }
            }
            if let bw = bundle.bodyweight {
                try context.delete(model: BodyweightEntry.self)
                for b in bw { context.insert(BodyweightEntry(date: b.date ?? .now, weightLb: b.weightLb ?? 0, bodyFatPercent: b.bodyFatPercent, milestoneLabel: b.milestoneLabel)) }
            }
            if let pr = bundle.protein {
                try context.delete(model: ProteinEntry.self)
                for p in pr { context.insert(ProteinEntry(date: p.date ?? .now, grams: p.grams ?? 0, label: p.label ?? "")) }
            }
            if let cis = bundle.checkIns {
                try context.delete(model: CheckIn.self)
                for c in cis {
                    let ci = CheckIn(date: c.date ?? .now, site: BodySite(rawValue: c.site ?? "") ?? .rightKnee, response: c.response ?? "", note: c.note ?? "")
                    ci.siteRaw = c.site ?? ci.siteRaw
                    context.insert(ci)
                }
            }
            if let ms = bundle.milestones {
                try context.delete(model: Milestone.self)
                for m in ms {
                    let mi = Milestone(date: m.date ?? .now, exerciseName: m.exercise, kind: .heaviestSet, label: m.label ?? "")
                    mi.kindRaw = m.kind ?? mi.kindRaw   // preserve exact raw (incl. "programNote")
                    context.insert(mi)
                }
            }
            if let sessions = bundle.sessions {
                try context.delete(model: WorkoutSession.self)
                for s in sessions { context.insert(makeSession(s, exByName: exByName)) }
            }
            if let st = bundle.settings {
                try applySettings(st, restoredExercises: bundle.exercises != nil, in: context)
            } else if bundle.exercises != nil,
                      let s = try context.fetch(FetchDescriptor<AppSettings>()).first {
                // A library restored with no settings riding along is of
                // unknown vintage — re-arm the retired-rest-stamp check so the
                // next launch's syncLibrary re-inspects the restored records.
                s.restSeedStampsCleared = false
            }

            try context.save()
        } catch {
            context.rollback()
            throw ImportError.writeFailed
        }

        return Summary(sessions: bundle.sessions?.count ?? 0, programs: bundle.programs?.count ?? 0,
                       tracks: bundle.tracks?.count ?? 0, gyms: bundle.gyms?.count ?? 0)
    }

    // MARK: - Makers

    private static func makeExercise(_ d: ExerciseDef) -> Exercise {
        let e = Exercise(
            name: d.name ?? "Unknown",
            category: ExerciseCategory(rawValue: d.category ?? "") ?? .accessory,
            type: ExerciseType(rawValue: d.type ?? "") ?? .barbell,
            movementGroup: d.movementGroup ?? "",
            isUnilateral: d.isUnilateral ?? false,
            // 0 = bucket-driven; a missing key must NOT mint a per-exercise
            // override (90 was the retired blanket stamp — web imports the
            // same record raw, so anything else diverges the platforms).
            defaultRestSeconds: d.defaultRestSeconds ?? 0,
            notes: d.notes ?? "",
            isShelved: d.isShelved ?? false,
            shelvedNote: d.shelvedNote ?? "",
            watchSite: BodySite(rawValue: d.watchSite ?? "")
        )
        if let c = d.createdAt { e.createdAt = c }
        return e
    }

    private static func update(_ e: Exercise, from d: ExerciseDef) {
        if let v = d.category, let c = ExerciseCategory(rawValue: v) { e.category = c }
        if let v = d.type, let t = ExerciseType(rawValue: v) { e.type = t }
        if let v = d.movementGroup { e.movementGroup = v }
        if let v = d.isUnilateral { e.isUnilateral = v }
        if let v = d.defaultRestSeconds { e.defaultRestSeconds = v }
        if let v = d.notes { e.notes = v }
        if let v = d.isShelved { e.isShelved = v }
        if let v = d.shelvedNote { e.shelvedNote = v }
        if let v = d.watchSite { e.watchSiteRaw = v } // lenient: don't clear when the key is omitted
    }

    private static func makeGym(_ g: GymDTO) -> Gym {
        let gym = Gym(name: g.name ?? "Gym", isDefault: g.isDefault ?? false, defaultBar: Bar.by(id: g.defaultBarId ?? "45-lb"))
        gym.plateToggles = (g.plateToggles ?? []).map {
            PlateToggle(plate: Plate(value: $0.value ?? 0, unit: WeightUnit(rawValue: $0.unit ?? "lb") ?? .lb), enabled: $0.enabled ?? true)
        }
        gym.barcodeLabel = g.barcodeLabel ?? "Membership tag"
        gym.barcodeImageData = dataFromURL(g.barcodeImage)
        return gym
    }

    private static func makeTrack(_ t: Track) -> LiftTrack {
        let track = LiftTrack(
            exerciseName: t.exerciseName ?? "",
            mode: TrackMode(rawValue: t.mode ?? "cycle") ?? .cycle,
            cycleNumber: t.cycleNumber ?? 1,
            baseWeightLb: t.baseWeightLb ?? 45,
            nextPhase: CyclePhase(rawValue: t.nextPhase ?? 1) ?? .volume,
            incrementLb: t.incrementLb ?? 10,
            roundingLb: t.roundingLb ?? 5
        )
        track.lastCompletedAt = t.lastCompletedAt
        return track
    }

    private static func makeProgram(_ p: ProgramDTO) -> Program {
        let prog = Program(name: p.name ?? "Program", focus: TrainingFocus(rawValue: p.focus ?? "strength") ?? .strength,
                           cycleNumber: p.cycleNumber ?? 1, currentWeek: p.currentWeek ?? 1,
                           nextDayIndex: p.nextDayIndex ?? 0, roundingLb: p.roundingLb ?? 5, isActive: p.isActive ?? false)
        for d in (p.days ?? []) {
            let day = ProgramDay(name: d.name ?? "Day", order: d.order ?? 0)
            day.program = prog
            for l in (d.lifts ?? []) {
                let lift = ProgramLift(exerciseName: l.exerciseName ?? "", role: LiftRole(rawValue: l.role ?? "main") ?? .main,
                                       baseWeightLb: l.baseWeightLb ?? 45, estimatedMaxLb: l.estimatedMaxLb ?? 0,
                                       stallCount: l.stallCount ?? 0, lastIncrementLb: l.lastIncrementLb ?? 0)
                if let st = l.pending?.state {
                    lift.pendingBaseWeightLb = st.baseWeightLb
                    lift.pendingEstimatedMaxLb = st.estimatedMaxLb
                    lift.pendingStallCount = st.stallCount
                    lift.pendingLastIncrementLb = st.lastIncrementLb
                    lift.pendingNote = l.pending?.note
                }
                lift.revertToExerciseName = l.revertToExerciseName
                lift.day = day
                day.lifts.append(lift)
            }
            for a in (d.accessories ?? []) {
                let acc = ProgramAccessory(exerciseName: a.exerciseName ?? "", sets: a.sets ?? 3, minReps: a.minReps ?? 8,
                                           maxReps: a.maxReps ?? 12, currentReps: a.currentReps ?? 8, weightLb: a.weightLb ?? 0,
                                           incrementLb: a.incrementLb ?? 0, stallCount: a.stallCount ?? 0)
                acc.revertToExerciseName = a.revertToExerciseName
                acc.day = day
                day.accessories.append(acc)
            }
            prog.days.append(day)
        }
        return prog
    }

    private static func makeSession(_ s: Session, exByName: [String: Exercise]) -> WorkoutSession {
        let session = WorkoutSession(date: s.date ?? .now, notes: s.notes ?? "", gymName: s.gym)
        // Legacy, unversioned backups only contained completed sessions, so a
        // missing flag means completed. Version 1 carries the actual state.
        session.isCompleted = s.isCompleted ?? true
        if let tag = s.programTag {
            session.programName = tag.programName
            session.programCycleNumber = tag.cycleNumber
            session.programWeek = tag.week
            session.programDayIndex = tag.dayIndex
            session.programPlanNames = tag.planNames
        }
        for (oi, e) in (s.exercises ?? []).enumerated() {
            let entry = SessionExercise(order: oi, exercise: e.name.flatMap { exByName[$0] }, notes: e.notes ?? "")
            entry.programRole = e.role
            entry.plannedWeightLb = e.plannedWeightLb
            entry.plannedSets = e.plannedSets
            entry.plannedReps = e.plannedReps
            entry.phaseRaw = recoverPhase(e.phase)
            entry.session = session
            for (si, x) in (e.sets ?? []).enumerated() {
                let set = SetEntry(order: si, weightLb: x.weightLb ?? 0, reps: x.reps ?? 0,
                                   isWarmup: x.isWarmup ?? false, isPerSide: x.isPerSide ?? false,
                                   enteredUnit: WeightUnit(rawValue: x.enteredUnit ?? "lb") ?? .lb,
                                   flags: (x.flags ?? []).compactMap(SetFlag.init(rawValue:)),
                                   bodyFlagSite: BodySite(rawValue: x.bodyFlagSite ?? ""),
                                   bodyFlagNote: x.bodyFlagNote,
                                   durationSeconds: x.durationSeconds, distanceMiles: x.distanceMiles,
                                   inclinePercent: x.inclinePercent,
                                   autoregReason: AutoregReason(rawValue: x.autoregReason ?? ""))
                set.sessionExercise = entry
                entry.sets.append(set)
            }
            session.exercises.append(entry)
        }
        return session
    }

    private static func applySettings(_ st: SettingsDTO, restoredExercises: Bool, in context: ModelContext) throws {
        let settings = (try context.fetch(FetchDescriptor<AppSettings>()).first) ?? {
            let s = AppSettings(); context.insert(s); return s
        }()
        if let v = st.unitDisplay { settings.unitDisplayRaw = v }
        if let v = st.proteinTargetGrams { settings.proteinTargetGrams = v }
        // Rest buckets arrive flat (native backups) or nested under `rest`
        // (web's canonical shape) — accept both; nested wins when both ride,
        // since the web keeps the legacy flat accessory key merely in sync.
        if let v = st.accessoryRestSeconds { settings.accessoryRestSeconds = v }
        if let v = st.mainCompoundRestSeconds { settings.mainCompoundRestSeconds = v }
        if let v = st.olympicRestSeconds { settings.olympicRestSeconds = v }
        if let v = st.mainUpperRestSeconds { settings.mainUpperRestSeconds = v }
        if let v = st.secondaryRestSeconds { settings.secondaryRestSeconds = v }
        if let v = st.rest?.mainCompoundSeconds { settings.mainCompoundRestSeconds = v }
        if let v = st.rest?.olympicSeconds { settings.olympicRestSeconds = v }
        if let v = st.rest?.mainUpperSeconds { settings.mainUpperRestSeconds = v }
        if let v = st.rest?.secondarySeconds { settings.secondaryRestSeconds = v }
        if let v = st.rest?.accessorySeconds { settings.accessoryRestSeconds = v }
        if let v = st.autoStartRest { settings.autoStartRest = v }
        if let v = st.haptics { settings.haptics = v }
        // restSeedStampsCleared describes the EXERCISE LIBRARY's migration
        // state, so it follows the bundle only when the library itself was
        // restored from it: a pre-migration backup (no flag) restores
        // old-stamped exercises and the next syncLibrary must re-clear them,
        // while a settings-only restore keeps the current marker — resetting
        // it over an untouched library could eat a user-set rest that happens
        // to equal a retired stamp (Codex). Mirrors web importBundle.
        if restoredExercises { settings.restSeedStampsCleared = st.restSeedStampsCleared ?? false }
        // Only accept a known theme; an unknown value would round-trip as
        // garbage on the next export (the UI would silently show Carbon anyway).
        if let v = st.theme, ThemeName(rawValue: v) != nil { settings.themeNameRaw = v }
        // Keep the install marked seeded so a restore isn't re-seeded over
        // (Seeder.seedIfNeeded gates on seededAt != nil).
        settings.seededAt = st.seededAt ?? settings.seededAt ?? .now
    }

    /// Recover a cycle-phase number from an exported phase label ("… R3 …").
    /// Accepts the current "R{n}" prefix and legacy "Wk{n}" from older backups.
    private static func recoverPhase(_ label: String?) -> Int? {
        guard let label,
              let r = label.range(of: #"(?:R|Wk)(\d+)"#, options: .regularExpression) else { return nil }
        return Int(label[r].drop(while: { !$0.isNumber }))
    }

    /// Decode a `data:...;base64,XXXX` URL back to bytes (the gym barcode photo).
    private static func dataFromURL(_ s: String?) -> Data? {
        guard let s, let comma = s.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(s[s.index(after: comma)...]))
    }
}
