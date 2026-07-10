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
        case notABackup, writeFailed
        var errorDescription: String? {
            switch self {
            case .notABackup: return "That file isn't a Cadence backup."
            case .writeFailed: return "Couldn't restore the backup — nothing was changed."
            }
        }
    }

    struct Summary { let sessions, programs, tracks, gyms: Int }

    // Lenient decode DTOs — optional everywhere so a partial or web-origin
    // backup never throws on a missing key.
    private struct Bundle: Decodable {
        var sessions: [Session]?; var bodyweight: [Bodyweight]?; var protein: [Protein]?
        var checkIns: [CheckInDTO]?; var milestones: [MilestoneDTO]?; var programs: [ProgramDTO]?
        var tracks: [Track]?; var gyms: [GymDTO]?; var exercises: [ExerciseDef]?; var settings: SettingsDTO?
    }
    private struct Session: Decodable {
        var date: Date?; var notes: String?; var gym: String?
        var programTag: ProgramTag?; var exercises: [ExerciseEntry]?
    }
    private struct ProgramTag: Decodable { var programName: String?; var cycleNumber: Int?; var week: Int?; var dayIndex: Int? }
    private struct ExerciseEntry: Decodable {
        var name: String?; var notes: String?; var phase: String?; var role: String?
        var plannedWeightLb: Double?; var plannedSets: Int?; var plannedReps: Int?; var sets: [SetDTO]?
    }
    private struct SetDTO: Decodable {
        var weightLb: Double?; var reps: Int?; var isWarmup: Bool?; var isPerSide: Bool?
        var enteredUnit: String?; var flags: [String]?; var bodyFlagSite: String?; var bodyFlagNote: String?
        var durationSeconds: Int?; var distanceMiles: Double?; var autoregReason: String?
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
    }
    private struct PendingDTO: Decodable { var state: PendingState?; var note: String? }
    private struct PendingState: Decodable { var baseWeightLb: Double?; var estimatedMaxLb: Double?; var stallCount: Int?; var lastIncrementLb: Double? }
    private struct AccessoryDTO: Decodable {
        var exerciseName: String?; var sets: Int?; var minReps: Int?; var maxReps: Int?
        var currentReps: Int?; var weightLb: Double?; var incrementLb: Double?; var stallCount: Int?
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
    private struct SettingsDTO: Decodable {
        var unitDisplay: String?; var proteinTargetGrams: Double?; var accessoryRestSeconds: Int?
        var autoStartRest: Bool?; var haptics: Bool?; var seededAt: Date?
    }

    @discardableResult
    static func load(_ data: Data, into context: ModelContext) throws -> Summary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(Bundle.self, from: data) else { throw ImportError.notABackup }

        let hasAnything = [bundle.sessions != nil, bundle.programs != nil, bundle.tracks != nil,
                           bundle.gyms != nil, bundle.exercises != nil, bundle.bodyweight != nil,
                           bundle.protein != nil, bundle.checkIns != nil, bundle.milestones != nil,
                           bundle.settings != nil].contains(true)
        guard hasAnything else { throw ImportError.notABackup }

        do {
            // Exercises: UPSERT by name (never delete — SessionExercise links to
            // them by relationship, so replacing them would orphan history).
            if let defs = bundle.exercises {
                var byName: [String: Exercise] = [:]
                for e in (try context.fetch(FetchDescriptor<Exercise>())) { byName[e.name] = e }
                for d in defs {
                    if let existing = byName[d.name ?? ""] { update(existing, from: d) }
                    else { let e = makeExercise(d); context.insert(e); byName[e.name] = e }
                }
            }
            let exByName: [String: Exercise] = {
                var m: [String: Exercise] = [:]
                for e in ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []) { m[e.name] = e }
                return m
            }()

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
            if let st = bundle.settings { applySettings(st, in: context) }

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
            defaultRestSeconds: d.defaultRestSeconds ?? 90,
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
        e.watchSiteRaw = d.watchSite
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
                lift.day = day
                day.lifts.append(lift)
            }
            for a in (d.accessories ?? []) {
                let acc = ProgramAccessory(exerciseName: a.exerciseName ?? "", sets: a.sets ?? 3, minReps: a.minReps ?? 8,
                                           maxReps: a.maxReps ?? 12, currentReps: a.currentReps ?? 8, weightLb: a.weightLb ?? 0,
                                           incrementLb: a.incrementLb ?? 0, stallCount: a.stallCount ?? 0)
                acc.day = day
                day.accessories.append(acc)
            }
            prog.days.append(day)
        }
        return prog
    }

    private static func makeSession(_ s: Session, exByName: [String: Exercise]) -> WorkoutSession {
        let session = WorkoutSession(date: s.date ?? .now, notes: s.notes ?? "", gymName: s.gym)
        session.isCompleted = true
        if let tag = s.programTag {
            session.programName = tag.programName
            session.programCycleNumber = tag.cycleNumber
            session.programWeek = tag.week
            session.programDayIndex = tag.dayIndex
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
                                   autoregReason: AutoregReason(rawValue: x.autoregReason ?? ""))
                set.sessionExercise = entry
                entry.sets.append(set)
            }
            session.exercises.append(entry)
        }
        return session
    }

    private static func applySettings(_ st: SettingsDTO, in context: ModelContext) {
        let settings = ((try? context.fetch(FetchDescriptor<AppSettings>()))?.first) ?? {
            let s = AppSettings(); context.insert(s); return s
        }()
        if let v = st.unitDisplay { settings.unitDisplayRaw = v }
        if let v = st.proteinTargetGrams { settings.proteinTargetGrams = v }
        if let v = st.accessoryRestSeconds { settings.accessoryRestSeconds = v }
        if let v = st.autoStartRest { settings.autoStartRest = v }
        if let v = st.haptics { settings.haptics = v }
    }

    /// Recover a cycle-phase number from an exported phase label ("… Wk3 …").
    private static func recoverPhase(_ label: String?) -> Int? {
        guard let label, let r = label.range(of: #"Wk(\d)"#, options: .regularExpression) else { return nil }
        return Int(label[r].dropFirst(2))
    }

    /// Decode a `data:...;base64,XXXX` URL back to bytes (the gym barcode photo).
    private static func dataFromURL(_ s: String?) -> Data? {
        guard let s, let comma = s.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(s[s.index(after: comma)...]))
    }
}
