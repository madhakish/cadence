import Foundation
import SwiftData
import CadenceCore

/// First-launch seed: exercise library, gym, program state, and the real
/// training history so charts, PRs, and suggestions work on day one.
enum Seeder {

    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let settings = existing.first, settings.seededAt != nil { return }

        let settings = existing.first ?? {
            let s = AppSettings()
            context.insert(s)
            return s
        }()

        let exercises = seedExercises(context: context)
        seedGym(context: context)
        seedBodyweight(context: context)
        seedHistory(context: context, exercises: exercises)
        seedTracks(context: context)
        seedProgram(context: context)

        settings.seededAt = .now
        try? context.save()
    }

    // MARK: - Exercise library (exact seed list; movementGroup enables swap)

    /// Fresh (un-inserted) Exercise objects for the whole library — mirror of
    /// web `seed.js` exercises. Used by the first-run seed and by `syncLibrary`
    /// to top up older installs. Groups: squat, hinge, press, olympic, pull,
    /// shoulder, arms, core, conditioning.
    static func libraryDefinitions() -> [Exercise] {
        [
            // Main barbell + press
            Exercise(name: "Deadlift", category: .main, type: .barbell, movementGroup: "hinge", defaultRestSeconds: 300),
            Exercise(name: "Back Squat", category: .main, type: .barbell, movementGroup: "squat", defaultRestSeconds: 300, watchSite: .leftHip),
            Exercise(name: "Front Squat", category: .main, type: .barbell, movementGroup: "squat", defaultRestSeconds: 300, watchSite: .leftHip),
            Exercise(name: "Overhead Squat", category: .main, type: .barbell, movementGroup: "squat", defaultRestSeconds: 300, watchSite: .leftShoulder),
            Exercise(
                name: "Barbell Bench", category: .main, type: .barbell, movementGroup: "press", defaultRestSeconds: 300,
                isShelved: true,
                shelvedNote: "Shelved — left shoulder. Re-entry test: symmetric DB pressing, no 'not there' feeling.",
                watchSite: .leftShoulder
            ),
            Exercise(name: "Overhead Press", category: .main, type: .barbell, movementGroup: "press", defaultRestSeconds: 300, notes: "Strict barbell press", watchSite: .leftShoulder),
            Exercise(name: "Push Press", category: .main, type: .barbell, movementGroup: "press", defaultRestSeconds: 300, watchSite: .leftShoulder),
            Exercise(name: "Push Jerk", category: .main, type: .barbell, movementGroup: "press", defaultRestSeconds: 300, watchSite: .leftShoulder),
            Exercise(name: "Split Jerk", category: .main, type: .barbell, movementGroup: "press", defaultRestSeconds: 300, watchSite: .leftShoulder),
            Exercise(name: "Incline DB Press", category: .main, type: .dumbbell, movementGroup: "press", defaultRestSeconds: 300, watchSite: .leftShoulder),
            Exercise(name: "Flat DB Press", category: .main, type: .dumbbell, movementGroup: "press", defaultRestSeconds: 300, watchSite: .leftShoulder),
            Exercise(name: "Seated Upright DB Press", category: .main, type: .dumbbell, movementGroup: "press", defaultRestSeconds: 300, watchSite: .leftShoulder),
            Exercise(name: "Overhead DB Press", category: .main, type: .dumbbell, movementGroup: "press", defaultRestSeconds: 300, watchSite: .leftShoulder),
            // Olympic lifts + supporting pulls
            Exercise(name: "Snatch", category: .main, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 240, watchSite: .leftShoulder),
            Exercise(name: "Clean & Jerk", category: .main, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 240, watchSite: .leftShoulder),
            Exercise(name: "Clean", category: .main, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 240),
            Exercise(name: "Power Clean", category: .main, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 240),
            Exercise(name: "Power Snatch", category: .main, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 240, watchSite: .leftShoulder),
            Exercise(name: "Hang Power Clean", category: .accessory, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 180),
            Exercise(name: "Hang Power Snatch", category: .accessory, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 180, watchSite: .leftShoulder),
            Exercise(name: "Clean Pull", category: .accessory, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 180),
            Exercise(name: "Snatch Pull", category: .accessory, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 180),
            // Hinge supporting
            Exercise(name: "Romanian Deadlift", category: .accessory, type: .barbell, movementGroup: "hinge", defaultRestSeconds: 180),
            Exercise(name: "Snatch-grip Deadlift", category: .accessory, type: .barbell, movementGroup: "hinge", defaultRestSeconds: 180),
            Exercise(name: "Good Morning", category: .accessory, type: .barbell, movementGroup: "hinge", defaultRestSeconds: 120, watchSite: .leftHip),
            // Accessories
            Exercise(name: "Turkish Get-up", category: .accessory, type: .kettlebell, movementGroup: "core", isUnilateral: true, defaultRestSeconds: 90),
            Exercise(name: "Single-arm DB Row", category: .accessory, type: .dumbbell, movementGroup: "pull", isUnilateral: true, defaultRestSeconds: 90),
            Exercise(name: "Lat Pulldown", category: .accessory, type: .machine, movementGroup: "pull", defaultRestSeconds: 90),
            Exercise(name: "Chest-supported Row", category: .accessory, type: .machine, movementGroup: "pull", defaultRestSeconds: 90),
            Exercise(name: "Ring Row", category: .accessory, type: .bodyweight, movementGroup: "pull", defaultRestSeconds: 90, notes: "Face-pull style"),
            Exercise(name: "Band Pull-aparts", category: .accessory, type: .band, movementGroup: "pull", defaultRestSeconds: 60),
            Exercise(name: "Face Pulls", category: .accessory, type: .machine, movementGroup: "pull", defaultRestSeconds: 90),
            Exercise(name: "Y-T-W Raises", category: .accessory, type: .dumbbell, movementGroup: "shoulder", defaultRestSeconds: 60),
            Exercise(name: "Band External Rotation", category: .accessory, type: .band, movementGroup: "shoulder", isUnilateral: true, defaultRestSeconds: 60, watchSite: .leftShoulder),
            Exercise(name: "DB Curls", category: .accessory, type: .dumbbell, movementGroup: "arms", defaultRestSeconds: 90),
            Exercise(name: "DB Overhead Triceps Extension", category: .accessory, type: .dumbbell, movementGroup: "arms", defaultRestSeconds: 90),
            Exercise(name: "Walking Lunges", category: .accessory, type: .bodyweight, movementGroup: "squat", isUnilateral: true, defaultRestSeconds: 90, watchSite: .leftHip),
            Exercise(name: "GHD Sit-up", category: .accessory, type: .bodyweight, movementGroup: "core", defaultRestSeconds: 90),
            Exercise(name: "Plank", category: .accessory, type: .timed, movementGroup: "core", defaultRestSeconds: 60),
            Exercise(name: "Side Plank", category: .accessory, type: .timed, movementGroup: "core", isUnilateral: true, defaultRestSeconds: 60),
            Exercise(name: "KB Swing", category: .accessory, type: .kettlebell, movementGroup: "hinge", defaultRestSeconds: 90),
            Exercise(name: "KB Clean", category: .accessory, type: .kettlebell, movementGroup: "olympic", isUnilateral: true, defaultRestSeconds: 90),
            Exercise(name: "Dips", category: .accessory, type: .bodyweight, movementGroup: "press", defaultRestSeconds: 90, watchSite: .leftShoulder),
            // Conditioning
            Exercise(name: "Walk", category: .conditioning, type: .conditioning, movementGroup: "conditioning", defaultRestSeconds: 0, notes: "Distance / time / incline"),
            Exercise(name: "Run-Walk Intervals", category: .conditioning, type: .conditioning, movementGroup: "conditioning", defaultRestSeconds: 0,
                     notes: "Jog min / walk min × rounds", watchSite: .rightKnee),
            Exercise(name: "Bike", category: .conditioning, type: .conditioning, movementGroup: "conditioning", defaultRestSeconds: 0),
            Exercise(name: "Ruck", category: .conditioning, type: .conditioning, movementGroup: "conditioning", defaultRestSeconds: 0),
        ]
    }

    private static func seedExercises(context: ModelContext) -> [String: Exercise] {
        var byName: [String: Exercise] = [:]
        for ex in libraryDefinitions() {
            context.insert(ex)
            byName[ex.name] = ex
        }
        return byName
    }

    /// Idempotent library top-up, run every launch (mirror of web `syncLibrary`):
    /// insert movements an older install is missing and backfill `movementGroup`
    /// on existing records — never clobbering user edits to exercises that
    /// already exist (rest, shelved, watch site, etc.).
    static func syncLibrary(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var byName: [String: Exercise] = [:]
        for ex in existing { byName[ex.name] = ex }
        for def in libraryDefinitions() {
            if let cur = byName[def.name] {
                if cur.movementGroup.isEmpty && !def.movementGroup.isEmpty { cur.movementGroup = def.movementGroup }
            } else {
                context.insert(def)
                byName[def.name] = def
            }
        }
        try? context.save()
    }

    private static func seedGym(context: ModelContext) {
        let gym = Gym(name: "Main Gym", isDefault: true, defaultBar: .bar45lb)
        context.insert(gym)
    }

    private static func seedBodyweight(context: ModelContext) {
        context.insert(BodyweightEntry(date: date(2026, 1, 10), weightLb: 168, milestoneLabel: "Discharge"))
        context.insert(BodyweightEntry(date: date(2026, 5, 12), weightLb: 190))
        context.insert(BodyweightEntry(date: date(2026, 6, 7), weightLb: 194))
    }

    // MARK: - Program state on first launch

    private static func seedTracks(context: ModelContext) {
        // Deadlift just banked Wk2 Load → next Wk3 Peak 3×3 (~245).
        context.insert(LiftTrack(
            exerciseName: "Deadlift", mode: .cycle, cycleNumber: 1,
            baseWeightLb: 210, nextPhase: .peak, incrementLb: 10
        ))
        // Squat banked Wk1 Volume at 175 → next Wk2 Load 5×3 (~195).
        context.insert(LiftTrack(
            exerciseName: "Back Squat", mode: .cycle, cycleNumber: 1,
            baseWeightLb: 175, nextPhase: .load, incrementLb: 10
        ))
        // DB press progressing linearly at 45s.
        context.insert(LiftTrack(
            exerciseName: "Incline DB Press", mode: .linear,
            baseWeightLb: 45, incrementLb: 5
        ))
    }

    // MARK: - Default 4-day Upper/Lower program (mirrors web seed.js)

    private static func seedProgram(context: ModelContext) {
        let program = Program(name: "Upper/Lower 4-Day", focus: .strength)
        context.insert(program)

        func cyc(_ name: String, _ role: LiftRole, _ base: Double, _ e1rm: Double) -> ProgramLift {
            ProgramLift(exerciseName: name, role: role, baseWeightLb: base, estimatedMaxLb: e1rm)
        }
        func acc(_ name: String, _ weight: Double, _ inc: Double = 5) -> ProgramAccessory {
            ProgramAccessory(exerciseName: name, sets: 3, minReps: 8, maxReps: 12,
                             currentReps: 8, weightLb: weight, incrementLb: inc)
        }
        func day(_ name: String, _ order: Int, _ lifts: [ProgramLift], _ accessories: [ProgramAccessory]) {
            let d = ProgramDay(name: name, order: order)
            d.program = program
            program.days.append(d)
            context.insert(d)
            for l in lifts { l.day = d; d.lifts.append(l); context.insert(l) }
            for a in accessories { a.day = d; d.accessories.append(a); context.insert(a) }
        }

        // Squat & deadlift each appear as a heavy (main) and lighter (complementary)
        // slot across the two lower days — independent program-lift states.
        day("Lower A", 0,
            [cyc("Back Squat", .main, 175, 204), cyc("Deadlift", .complementary, 185, 255)],
            [acc("Walking Lunges", 0, 0), acc("GHD Sit-up", 0, 0), acc("Plank", 0, 0)])
        day("Upper A", 1,
            [cyc("Incline DB Press", .main, 45, 52), cyc("Single-arm DB Row", .complementary, 65, 80)],
            [acc("Face Pulls", 40), acc("DB Curls", 35), acc("Band Pull-aparts", 0, 0)])
        day("Lower B", 2,
            [cyc("Deadlift", .main, 210, 255), cyc("Back Squat", .complementary, 150, 204)],
            [acc("KB Swing", 53), acc("Side Plank", 0, 0), acc("Walking Lunges", 0, 0)])
        day("Upper B", 3,
            [cyc("Overhead DB Press", .main, 35, 42), cyc("Chest-supported Row", .complementary, 90, 110)],
            [acc("Y-T-W Raises", 10), acc("DB Overhead Triceps Extension", 45), acc("Band External Rotation", 0, 0)])
    }

    // MARK: - Session history (exact seed log, 2026)

    private static func seedHistory(context: ModelContext, exercises ex: [String: Exercise]) {
        func session(_ m: Int, _ d: Int, note: String = "") -> WorkoutSession {
            let s = WorkoutSession(date: date(2026, m, d), notes: note, gymName: "Main Gym")
            s.isCompleted = true
            context.insert(s)
            return s
        }

        func entry(_ s: WorkoutSession, _ order: Int, _ name: String, note: String = "") -> SessionExercise {
            let e = SessionExercise(order: order, exercise: ex[name], notes: note)
            e.session = s
            context.insert(e)
            s.exercises.append(e)
            return e
        }

        @discardableResult
        func add(_ e: SessionExercise, _ w: Double, _ r: Int, sets n: Int = 1,
                 warm: Bool = false, perSide: Bool = false, flags: [SetFlag] = [],
                 site: BodySite? = nil, siteNote: String? = nil) -> SessionExercise {
            for _ in 0..<n {
                let set = SetEntry(
                    order: e.sets.count, weightLb: w, reps: r, isWarmup: warm,
                    isPerSide: perSide, flags: flags, bodyFlagSite: site, bodyFlagNote: siteNote
                )
                set.sessionExercise = e
                context.insert(set)
                e.sets.append(set)
            }
            return e
        }

        // May 9 — Deadlift ramp + 221×3. Push press 88 3×3.
        let s1 = session(5, 9)
        let dl1 = entry(s1, 0, "Deadlift")
        add(dl1, 133, 5, warm: true); add(dl1, 155, 5, warm: true)
        add(dl1, 177, 5, warm: true); add(dl1, 199, 3, warm: true)
        add(dl1, 221, 3)
        add(entry(s1, 1, "Push Press"), 88, 3, sets: 3)

        // May 12 — Squat. Bench. Incline DB stopped on wobble.
        let s2 = session(5, 12)
        let sq2 = entry(s2, 0, "Back Squat")
        add(sq2, 145, 3); add(sq2, 155, 3, sets: 2)
        add(entry(s2, 1, "Barbell Bench"), 135, 5)
        let idb2 = entry(s2, 2, "Incline DB Press")
        add(idb2, 35, 5); add(idb2, 40, 5)
        add(idb2, 45, 3, sets: 2, flags: [.wobble, .stoppedEarly])

        // May 15 — Deadlift 221×3. TGU. GHD. Incline DB.
        let s3 = session(5, 15)
        add(entry(s3, 0, "Deadlift"), 221, 3)
        add(entry(s3, 1, "Turkish Get-up"), 35, 3, perSide: true)
        add(entry(s3, 2, "GHD Sit-up"), 0, 5, sets: 3)
        add(entry(s3, 3, "Incline DB Press"), 40, 5, sets: 3)

        // May 19 — Squat. Bench autoregulated from 140 plan.
        let s4 = session(5, 19)
        let sq4 = entry(s4, 0, "Back Squat")
        add(sq4, 165, 3, sets: 2); add(sq4, 175, 3)
        let bb4 = entry(s4, 1, "Barbell Bench", note: "Autoregulated from 140 plan")
        bb4.plannedWeightLb = 140
        add(bb4, 135, 5, sets: 2)

        // May 22 — Deadlift volume + heavy doubles. Incline DB. Triceps.
        let s5 = session(5, 22)
        let dl5 = entry(s5, 0, "Deadlift")
        add(dl5, 210, 5, sets: 3); add(dl5, 221, 2, sets: 3)
        add(entry(s5, 1, "Incline DB Press"), 45, 5, sets: 3)
        add(entry(s5, 2, "DB Overhead Triceps Extension"), 45, 10, sets: 3)

        // May 26 — Squat 155 5×5. Seated press. Rows. Lunges.
        let s6 = session(5, 26)
        add(entry(s6, 0, "Back Squat"), 155, 5, sets: 5)
        add(entry(s6, 1, "Seated Upright DB Press"), 40, 5, sets: 5)
        add(entry(s6, 2, "Single-arm DB Row"), 60, 8, sets: 3, perSide: true)
        add(entry(s6, 3, "Walking Lunges"), 0, 8, perSide: true)

        // May 29 — Deadlift Cycle 1 Wk1 Volume. 90°F gym, cut short.
        let s7 = session(5, 29, note: "90°F gym, cut short")
        let dl7 = entry(s7, 0, "Deadlift")
        dl7.phase = .volume
        add(dl7, 210, 5, sets: 5)
        add(entry(s7, 1, "Overhead DB Press"), 35, 6, sets: 3)
        add(entry(s7, 2, "Turkish Get-up"), 45, 3, perSide: true)

        // Jun 1 — Squat Wk1 Volume at 175 (milestone).
        let s8 = session(6, 1)
        let sq8 = entry(s8, 0, "Back Squat")
        sq8.phase = .volume
        add(sq8, 175, 5, sets: 5)
        add(entry(s8, 1, "Overhead DB Press"), 30, 10, sets: 3)
        add(entry(s8, 2, "DB Curls"), 35, 5, sets: 3)
        add(entry(s8, 3, "Walking Lunges"), 0, 10, perSide: true)
        context.insert(Milestone(
            date: date(2026, 6, 1), exerciseName: "Back Squat",
            kind: .heaviestSet, label: "175×5×5 — Wk1 Volume banked"
        ))

        // Jun 4 — Barbell bench shelved on left-shoulder signal.
        let s9 = session(6, 4, note: "Left shoulder 'not there' on barbell bench — shelved. DB pressing from here.")
        let bb9 = entry(s9, 0, "Barbell Bench")
        add(bb9, 135, 3, sets: 4, site: .leftShoulder, siteNote: "'Not there' feeling — shelving barbell bench")
        add(entry(s9, 1, "Flat DB Press", note: "Switched after shelving barbell"), 45, 5, sets: 3)
        add(entry(s9, 2, "Single-arm DB Row"), 65, 8, sets: 5, perSide: true)
        add(entry(s9, 3, "GHD Sit-up"), 0, 5, sets: 4)

        // Jun 7 — Deadlift Wk2 Load 232×5×3, heaviest of the comeback.
        let s10 = session(6, 7)
        let dl10 = entry(s10, 0, "Deadlift")
        dl10.phase = .load
        add(dl10, 232, 3, sets: 5)
        add(entry(s10, 1, "Turkish Get-up"), 45, 3, perSide: true)
        add(entry(s10, 2, "Incline DB Press"), 45, 5, sets: 3)
        context.insert(Milestone(
            date: date(2026, 6, 7), exerciseName: "Deadlift",
            kind: .heaviestSet, label: "232×5×3 — heaviest pull of the comeback"
        ))
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 17) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = hour
        return Calendar.current.date(from: comps) ?? .now
    }
}
