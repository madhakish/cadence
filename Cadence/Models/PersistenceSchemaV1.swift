import Foundation
import SwiftData

/// Frozen schema shipped before the training-truth update. These declarations
/// intentionally duplicate the old persisted shape so SwiftData can recognize
/// an installed V1 store and migrate it. Do not add fields here.
enum CadenceSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetEntry.self,
            LiftTrack.self,
            BodyweightEntry.self,
            ProteinEntry.self,
            CheckIn.self,
            Milestone.self,
            Gym.self,
            AppSettings.self,
            Program.self,
            ProgramDay.self,
            ProgramLift.self,
            ProgramAccessory.self,
        ]
    }

    @Model
    final class Exercise {
        @Attribute(.unique) var name: String
        var categoryRaw: String
        var typeRaw: String
        var isUnilateral: Bool
        var defaultRestSeconds: Int
        var notes: String
        var isShelved: Bool
        var shelvedNote: String
        var watchSiteRaw: String?
        var movementGroup: String = ""
        var createdAt: Date

        init(name: String, categoryRaw: String = "Accessory", typeRaw: String = "dumbbell") {
            self.name = name
            self.categoryRaw = categoryRaw
            self.typeRaw = typeRaw
            self.isUnilateral = false
            self.defaultRestSeconds = 0
            self.notes = ""
            self.isShelved = false
            self.shelvedNote = ""
            self.movementGroup = ""
            self.createdAt = .now
        }
    }

    @Model
    final class WorkoutSession {
        var date: Date
        var notes: String
        var isCompleted: Bool
        var gymID: String?
        var gymName: String?
        var programID: String?
        var programName: String?
        var programCycleNumber: Int?
        var programWeek: Int?
        var programDayIndex: Int?
        var programPlanNames: [String]?
        @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
        var exercises: [SessionExercise]

        init(date: Date = .now, notes: String = "", isCompleted: Bool = false) {
            self.date = date
            self.notes = notes
            self.isCompleted = isCompleted
            self.exercises = []
        }
    }

    @Model
    final class SessionExercise {
        var order: Int
        var notes: String
        var barID: String?
        var exercise: Exercise?
        var session: WorkoutSession?
        @Relationship(deleteRule: .cascade, inverse: \SetEntry.sessionExercise)
        var sets: [SetEntry]
        var plannedWeightLb: Double?
        var plannedSets: Int?
        var plannedReps: Int?
        var phaseRaw: Int?
        var programRole: String?
        var programSlotID: String?

        init(order: Int, exercise: Exercise?) {
            self.order = order
            self.notes = ""
            self.exercise = exercise
            self.sets = []
        }
    }

    @Model
    final class SetEntry {
        var order: Int
        var weightLb: Double
        var reps: Int
        var isWarmup: Bool
        var statusRaw: String = ""
        var isPerSide: Bool
        var enteredUnitRaw: String
        var flagsRaw: [String]
        var bodyFlagSiteRaw: String?
        var bodyFlagNote: String?
        var durationSeconds: Int?
        var distanceMiles: Double?
        var inclinePercent: Double?
        var autoregReasonRaw: String?
        var sessionExercise: SessionExercise?

        init(order: Int, weightLb: Double, reps: Int, statusRaw: String = "completed") {
            self.order = order
            self.weightLb = weightLb
            self.reps = reps
            self.isWarmup = false
            self.statusRaw = statusRaw
            self.isPerSide = false
            self.enteredUnitRaw = "lb"
            self.flagsRaw = []
        }
    }

    @Model
    final class LiftTrack {
        @Attribute(.unique) var exerciseName: String
        var modeRaw: String
        var cycleNumber: Int
        var baseWeightLb: Double
        var nextPhaseRaw: Int
        var incrementLb: Double
        var roundingLb: Double
        var lastCompletedAt: Date?

        init(exerciseName: String, baseWeightLb: Double) {
            self.exerciseName = exerciseName
            self.modeRaw = "cycle"
            self.cycleNumber = 1
            self.baseWeightLb = baseWeightLb
            self.nextPhaseRaw = 1
            self.incrementLb = 5
            self.roundingLb = 5
        }
    }

    @Model
    final class BodyweightEntry {
        var date: Date
        var weightLb: Double
        var bodyFatPercent: Double?
        var milestoneLabel: String?

        init(date: Date = .now, weightLb: Double) {
            self.date = date
            self.weightLb = weightLb
        }
    }

    @Model
    final class ProteinEntry {
        var date: Date
        var grams: Double
        var label: String

        init(date: Date = .now, grams: Double, label: String) {
            self.date = date
            self.grams = grams
            self.label = label
        }
    }

    @Model
    final class CheckIn {
        var date: Date
        var siteRaw: String
        var response: String
        var note: String

        init(date: Date = .now, siteRaw: String, response: String) {
            self.date = date
            self.siteRaw = siteRaw
            self.response = response
            self.note = ""
        }
    }

    @Model
    final class Milestone {
        var date: Date
        var exerciseName: String?
        var kindRaw: String
        var label: String

        init(date: Date = .now, exerciseName: String? = nil, kindRaw: String, label: String) {
            self.date = date
            self.exerciseName = exerciseName
            self.kindRaw = kindRaw
            self.label = label
        }
    }

    @Model
    final class Gym {
        @Attribute(.unique) var id: String = UUID().uuidString
        @Attribute(.unique) var name: String
        var isDefault: Bool
        var defaultBarID: String
        var plateToggles: [PlateToggle]
        @Attribute(.externalStorage) var barcodeImageData: Data?
        var barcodeLabel: String

        init(name: String) {
            self.name = name
            self.isDefault = true
            self.defaultBarID = "45-lb"
            self.plateToggles = []
            self.barcodeLabel = "Membership tag"
        }
    }

    @Model
    final class AppSettings {
        var unitDisplayRaw: String
        var proteinTargetGrams: Double
        var accessoryRestSeconds: Int
        var mainCompoundRestSeconds: Int = 300
        var olympicRestSeconds: Int = 240
        var mainUpperRestSeconds: Int = 180
        var secondaryRestSeconds: Int = 180
        var autoStartRest: Bool = false
        var haptics: Bool = true
        var gymTagFirstLaunchOfDay: Bool = false
        var restSeedStampsCleared: Bool = false
        var healthKitEnabled: Bool
        var seededAt: Date?
        var themeNameRaw: String = "carbon"

        init() {
            self.unitDisplayRaw = "lbPrimary"
            self.proteinTargetGrams = 100
            self.accessoryRestSeconds = 90
            self.healthKitEnabled = false
            self.seededAt = .now
        }
    }

    @Model
    final class Program {
        @Attribute(.unique) var id: String = UUID().uuidString
        @Attribute(.unique) var name: String
        var focusRaw: String
        var cycleNumber: Int
        var currentWeek: Int
        var nextDayIndex: Int
        var roundingLb: Double
        var isActive: Bool
        @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program)
        var days: [ProgramDay]
        var createdAt: Date

        init(name: String) {
            self.name = name
            self.focusRaw = "strength"
            self.cycleNumber = 1
            self.currentWeek = 1
            self.nextDayIndex = 0
            self.roundingLb = 5
            self.isActive = true
            self.days = []
            self.createdAt = .now
        }
    }

    @Model
    final class ProgramDay {
        var name: String
        var order: Int
        var program: Program?
        @Relationship(deleteRule: .cascade, inverse: \ProgramLift.day)
        var lifts: [ProgramLift]
        @Relationship(deleteRule: .cascade, inverse: \ProgramAccessory.day)
        var accessories: [ProgramAccessory]

        init(name: String, order: Int) {
            self.name = name
            self.order = order
            self.lifts = []
            self.accessories = []
        }
    }

    @Model
    final class ProgramLift {
        var id: String = UUID().uuidString
        var exerciseName: String
        var roleRaw: String
        var order: Int = 0
        var prescriptionRaw: String = "automatic"
        var warmupPolicyRaw: String = "automatic"
        var baseWeightLb: Double
        var estimatedMaxLb: Double
        var stallCount: Int
        var lastIncrementLb: Double
        var pendingBaseWeightLb: Double?
        var pendingEstimatedMaxLb: Double?
        var pendingStallCount: Int?
        var pendingLastIncrementLb: Double?
        var pendingNote: String?
        var revertToExerciseName: String?
        var day: ProgramDay?

        init(exerciseName: String) {
            self.exerciseName = exerciseName
            self.roleRaw = "main"
            self.baseWeightLb = 100
            self.estimatedMaxLb = 120
            self.stallCount = 0
            self.lastIncrementLb = 0
        }
    }

    @Model
    final class ProgramAccessory {
        var id: String = UUID().uuidString
        var exerciseName: String
        var order: Int = 0
        var sets: Int
        var minReps: Int
        var maxReps: Int
        var currentReps: Int
        var targetSeconds: Int = 30
        var durationStepSeconds: Int = 5
        var weightLb: Double
        var incrementLb: Double
        var stallCount: Int
        var revertToExerciseName: String?
        var day: ProgramDay?

        init(exerciseName: String) {
            self.exerciseName = exerciseName
            self.sets = 3
            self.minReps = 8
            self.maxReps = 12
            self.currentReps = 8
            self.weightLb = 0
            self.incrementLb = 5
            self.stallCount = 0
        }
    }
}
