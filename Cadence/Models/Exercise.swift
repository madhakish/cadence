import Foundation
import SwiftData
import CadenceCore

enum ExerciseCategory: String, Codable, CaseIterable {
    case main = "Main"
    case accessory = "Accessory"
    case conditioning = "Conditioning"
}

enum ExerciseType: String, Codable, CaseIterable {
    case barbell, dumbbell, kettlebell, bodyweight, band, machine, timed, conditioning
}

enum ExerciseGateStatus: String, Codable, CaseIterable {
    case open
    case watch
    case shelved
    case reEntry = "re-entry"

    var name: String {
        switch self {
        case .open: return "Available"
        case .watch: return "Watch"
        case .shelved: return "Shelved"
        case .reEntry: return "Re-entry test"
        }
    }
}

/// Generic watch sites. Lightweight signal tracking, not medical.
enum BodySite: String, Codable, CaseIterable, Identifiable {
    case shoulder = "Shoulder"
    case hip = "Hip"
    case knee = "Knee"
    case back = "Back"
    case elbow = "Elbow"
    case wrist = "Wrist"
    case ankle = "Ankle"
    case groin = "Groin"
    case neck = "Neck"

    var id: String { rawValue }

    var watchNote: String {
        switch self {
        case .shoulder: return "Track comfort and range of motion during upper-body work."
        case .hip: return "Track comfort and range of motion during lower-body work."
        case .knee: return "Track comfort during squatting, lunging, and running."
        case .back: return "Track comfort and tolerance during loaded trunk and hinge work."
        case .elbow: return "Track comfort during pressing, pulling, and arm work."
        case .wrist: return "Track comfort in loaded grip and rack positions."
        case .ankle: return "Track comfort and range during lower-body and conditioning work."
        case .groin: return "Track comfort during wide-stance, unilateral, and adductor work."
        case .neck: return "Track comfort and position during loaded work."
        }
    }

    /// Normalizes records from builds that stored a side-specific label.
    /// Matching by anatomical suffix preserves local history without keeping
    /// a user's old injury profile in source or exported data.
    static func fromStorage(_ value: String?) -> BodySite? {
        guard let value else { return nil }
        if let current = BodySite(rawValue: value) { return current }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasSuffix("shoulder") { return .shoulder }
        if normalized.hasSuffix("hip") { return .hip }
        if normalized.hasSuffix("knee") { return .knee }
        for site in BodySite.allCases where normalized.hasSuffix(site.rawValue.lowercased()) { return site }
        return nil
    }
}

@Model
final class Exercise {
    @Attribute(.unique) var name: String
    var categoryRaw: String
    var typeRaw: String
    var isUnilateral: Bool
    /// Explicit per-exercise rest. 0 = none set — the timer falls to the
    /// configurable rest buckets (`RestDefaults.seconds`); > 0 wins everywhere.
    var defaultRestSeconds: Int
    var notes: String
    /// Shelved = in the library but not available for programming.
    var isShelved: Bool
    /// Re-entry test, in the coach's words.
    var shelvedNote: String
    /// Body site to watch when doing this movement, if any.
    var watchSiteRaw: String?
    /// Movement pattern for swap-a-similar-lift (all presses, squat/hinge
    /// variants, the oly lifts). Mirrors web `movementGroup`. Empty = ungrouped.
    var movementGroup: String = ""
    /// More precise coaching/volume taxonomy. Empty means use the canonical
    /// name + movement-group fallback from CadenceCore.
    var movementPatternRaw: String = ""
    var secondaryMovementPatternRaw: String = ""
    var aliases: [String] = []
    var strategyTags: [String] = []
    /// Empty/zero are legacy inference sentinels. Explicit values decouple
    /// progression/volume meaning from display equipment.
    var loadBasisRaw: String = ""
    var implementCount: Int = 0
    /// User-owned movement gate and re-entry checklist. The repository never
    /// seeds an athlete's injury history or personal criteria.
    var gateStatusRaw: String = "open"
    var gateSiteRaw: String?
    var reEntryCriteria: [String] = []
    var completedReEntryCriteria: [String] = []
    var reEntryTestWeightLb: Double = 0
    var reEntryTestSets: Int = 3
    var reEntryTestReps: Int = 5
    var createdAt: Date

    init(
        name: String,
        category: ExerciseCategory,
        type: ExerciseType,
        movementGroup: String = "",
        movementPattern: MovementPattern? = nil,
        secondaryMovementPattern: MovementPattern? = nil,
        aliases: [String] = [],
        strategyTags: [String] = [],
        loadBasis: LoadBasis? = nil,
        implementCount: Int = 0,
        isUnilateral: Bool = false,
        defaultRestSeconds: Int = 0,
        notes: String = "",
        isShelved: Bool = false,
        shelvedNote: String = "",
        watchSite: BodySite? = nil
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.typeRaw = type.rawValue
        self.movementGroup = movementGroup
        let resolvedPattern = movementPattern ?? MovementTaxonomy.pattern(
            exerciseName: name, movementGroup: movementGroup
        )
        self.movementPatternRaw = resolvedPattern == .unknown ? "" : resolvedPattern.rawValue
        self.secondaryMovementPatternRaw = secondaryMovementPattern?.rawValue ?? ""
        self.aliases = aliases
        self.strategyTags = strategyTags
        self.loadBasisRaw = loadBasis?.rawValue ?? ""
        self.implementCount = implementCount
        self.isUnilateral = isUnilateral
        self.defaultRestSeconds = defaultRestSeconds
        self.notes = notes
        self.isShelved = isShelved
        self.shelvedNote = shelvedNote
        self.watchSiteRaw = watchSite?.rawValue
        self.createdAt = .now
    }

    var category: ExerciseCategory {
        get { ExerciseCategory(rawValue: categoryRaw) ?? .accessory }
        set { categoryRaw = newValue.rawValue }
    }

    var type: ExerciseType {
        get { ExerciseType(rawValue: typeRaw) ?? .dumbbell }
        set { typeRaw = newValue.rawValue }
    }

    var watchSite: BodySite? {
        get { BodySite.fromStorage(watchSiteRaw) }
        set { watchSiteRaw = newValue?.rawValue }
    }

    var loadBasis: LoadBasis {
        get { LoadBasis(rawValue: loadBasisRaw) ?? LoadSemantics.inferredBasis(exerciseType: typeRaw) }
        set { loadBasisRaw = newValue.rawValue }
    }

    var resolvedImplementCount: Int {
        let inferred = LoadSemantics.inferredImplementCount(exerciseType: typeRaw)
        return LoadSemantics.normalizedImplementCount(implementCount > 0 ? implementCount : inferred, basis: loadBasis)
    }

    var movementPattern: MovementPattern {
        get {
            MovementTaxonomy.pattern(
                exerciseName: name, movementGroup: movementGroup,
                explicitPattern: movementPatternRaw.isEmpty ? nil : movementPatternRaw
            )
        }
        set { movementPatternRaw = newValue == .unknown ? "" : newValue.rawValue }
    }

    var secondaryMovementPattern: MovementPattern? {
        get { secondaryMovementPatternRaw.isEmpty ? nil : MovementPattern(rawValue: secondaryMovementPatternRaw) }
        set { secondaryMovementPatternRaw = newValue?.rawValue ?? "" }
    }

    var gateStatus: ExerciseGateStatus {
        get {
            if isShelved && gateStatusRaw == ExerciseGateStatus.open.rawValue { return .shelved }
            return ExerciseGateStatus(rawValue: gateStatusRaw) ?? .open
        }
        set {
            gateStatusRaw = newValue.rawValue
            isShelved = newValue == .shelved
        }
    }

    var gateSite: BodySite? {
        get { BodySite.fromStorage(gateSiteRaw) }
        set { gateSiteRaw = newValue?.rawValue }
    }

    var reEntryCriteriaComplete: Bool {
        !reEntryCriteria.isEmpty && Set(reEntryCriteria).isSubset(of: Set(completedReEntryCriteria))
    }

    var isMainLift: Bool { category == .main }
}
