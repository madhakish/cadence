import Foundation
import SwiftData

/// Frozen schema shipped as V9. V9 is the V8 model plus
/// `Program.equipmentPolicyRaw` and `ProgramDay.trainingIntentRaw`, both with
/// literal legacy defaults, and nothing else. These declarations preserve that
/// checksum and must never be edited.
enum CadenceSchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self, WorkoutSession.self, SessionExercise.self, SetEntry.self,
            LiftTrack.self, BodyweightEntry.self, CheckIn.self,
            Milestone.self, Gym.self, AppSettings.self, Program.self, ProgramDay.self,
            ProgramLift.self, ProgramAccessory.self, CoachingDecision.self,
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
        var movementPatternRaw: String = ""
        var secondaryMovementPatternRaw: String = ""
        var aliases: [String] = []
        var strategyTags: [String] = []
        var loadBasisRaw: String = ""
        var implementCount: Int = 0
        var gateStatusRaw: String = "open"
        var gateSiteRaw: String?
        var reEntryCriteria: [String] = []
        var completedReEntryCriteria: [String] = []
        var reEntryTestWeightLb: Double = 0
        var reEntryTestSets: Int = 3
        var reEntryTestReps: Int = 5
        var stationDenominationRaw: String?
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
            self.createdAt = .now
        }
    }

    @Model
    final class WorkoutSession {
        var id: String = ""
        var date: Date
        var notes: String
        var isCompleted: Bool
        var completedAt: Date?
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

        init(date: Date = .now) {
            self.id = UUID().uuidString
            self.date = date
            self.notes = ""
            self.isCompleted = false
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
        var targetWeightLb: Double?
        var plannedSets: Int?
        var plannedReps: Int?
        var plannedDurationSeconds: Int?
        var fallbackWeightLb: Double?
        var prescriptionStyleRaw: String = ""
        var phaseRaw: Int?
        var programRole: String?
        var programSlotID: String?

        init(order: Int = 0) {
            self.order = order
            self.notes = ""
            self.sets = []
        }
    }

    @Model
    final class SetEntry {
        var order: Int
        var weightLb: Double
        var reps: Int
        var targetWeightLb: Double?
        var plannedWeightLb: Double?
        var plannedReps: Int?
        var plannedDurationSeconds: Int?
        var prescriptionBlockRaw: String = "work"
        var isWarmup: Bool
        var statusRaw: String = ""
        var isPerSide: Bool
        var enteredUnitRaw: String
        var flagsRaw: [String]
        var bodyFlagSiteRaw: String?
        var bodyFlagNote: String?
        var durationSeconds: Int?
        var distanceMiles: Double?
        var flights: Double?
        var inclinePercent: Double?
        var loadBasisRaw: String = ""
        var implementCount: Int = 0
        var autoregReasonRaw: String?
        var sessionExercise: SessionExercise?

        init(order: Int = 0) {
            self.order = order
            self.weightLb = 0
            self.reps = 0
            self.isWarmup = false
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

        init(exerciseName: String) {
            self.exerciseName = exerciseName
            self.modeRaw = "linear"
            self.cycleNumber = 1
            self.baseWeightLb = 0
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
    final class CheckIn {
        var date: Date
        var siteRaw: String
        var response: String
        var note: String

        init(date: Date = .now, siteRaw: String, response: String, note: String = "") {
            self.date = date
            self.siteRaw = siteRaw
            self.response = response
            self.note = note
        }
    }

    @Model
    final class Milestone {
        var date: Date
        var exerciseName: String?
        var kindRaw: String
        var label: String

        init(date: Date = .now, kindRaw: String, label: String) {
            self.date = date
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
        var collarWeightLb: Double = 0
        var loadingPolicyRaw: String = "closest"
        @Attribute(.externalStorage) var barcodeImageData: Data?
        var barcodeLabel: String

        init(name: String) {
            self.name = name
            self.isDefault = true
            self.defaultBarID = "45-lb"
            self.plateToggles = []
            self.collarWeightLb = 0
            self.loadingPolicyRaw = "closest"
            self.barcodeLabel = "Membership tag"
        }
    }

    @Model
    final class AppSettings {
        var unitDisplayRaw: String
        var birthYear: Int = 0
        var accessoryRestSeconds: Int
        var mainCompoundRestSeconds: Int = 300
        var olympicRestSeconds: Int = 240
        var mainUpperRestSeconds: Int = 180
        var secondaryRestSeconds: Int = 180
        var autoStartRest: Bool = false
        var haptics: Bool = true
        var gymTagFirstLaunchOfDay: Bool = false
        var restSeedStampsCleared: Bool = false
        var loadSemanticsMigrated: Bool = false
        var verticalPullMainsPromoted: Bool = false
        var healthKitEnabled: Bool
        var seededAt: Date?
        var themeNameRaw: String = "carbon"

        init() {
            self.unitDisplayRaw = "lbPrimary"
            self.accessoryRestSeconds = 90
            self.healthKitEnabled = false
        }
    }

    @Model
    final class Program {
        @Attribute(.unique) var id: String = UUID().uuidString
        @Attribute(.unique) var name: String
        var focusRaw: String
        var equipmentPolicyRaw: String = "any"
        var cycleNumber: Int
        var currentWeek: Int
        var nextDayIndex: Int
        var roundingLb: Double
        var isActive: Bool
        var coachEnabled: Bool = true
        var reliableHistoryStart: Date?
        var preferredSessionSpacingDays: Int = 3
        var maximumAddedSetsPerRotation: Int = 6
        @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program)
        var days: [ProgramDay]
        var createdAt: Date

        init(name: String) {
            self.name = name
            self.focusRaw = "strength"
            self.equipmentPolicyRaw = "any"
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
        var trainingIntentRaw: String = "general"
        var program: Program?
        @Relationship(deleteRule: .cascade, inverse: \ProgramLift.day)
        var lifts: [ProgramLift]
        @Relationship(deleteRule: .cascade, inverse: \ProgramAccessory.day)
        var accessories: [ProgramAccessory]

        init(name: String, order: Int = 0) {
            self.name = name
            self.order = order
            self.trainingIntentRaw = "general"
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
        var loadOffsetLb: Double = 0
        var peakOffsetLb: Double = 0
        var deloadMultiplier: Double = 0.775
        var doubleProgressionSets: Int = 3
        var minimumReps: Int = 5
        var maximumReps: Int = 8
        var currentReps: Int = 5
        var peakSingleEnabled: Bool = false
        var lastPeakSingleLb: Double = 0
        var peakSingleIncrementLb: Double = 5
        var phasePrimerEnabled: Bool = true
        var dropIncrementLb: Double = 0
        var capacityManaged: Bool = true
        var maximumSets: Int = 6
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
            self.baseWeightLb = 0
            self.estimatedMaxLb = 0
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
        var capacityManaged: Bool = true
        var maximumSets: Int = 6
        var conditioningEffortRaw: String = "easy"
        var targetRPE: Int = 0
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

    @Model
    final class CoachingDecision {
        @Attribute(.unique) var id: String = UUID().uuidString
        var date: Date = Date.now
        var programID: String = ""
        var ruleID: String = ""
        var recommendationID: String = ""
        var actionRaw: String = "accepted"
        var title: String = ""
        var explanation: String = ""
        var evidence: [String] = []
        var beforeValue: String?
        var afterValue: String?

        init(programID: String = "", ruleID: String = "") {
            self.programID = programID
            self.ruleID = ruleID
        }
    }
}
