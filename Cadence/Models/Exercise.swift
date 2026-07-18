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

/// Generic watch sites. Lightweight signal tracking, not medical.
enum BodySite: String, Codable, CaseIterable, Identifiable {
    case shoulder = "Shoulder"
    case hip = "Hip"
    case knee = "Knee"

    var id: String { rawValue }

    var watchNote: String {
        switch self {
        case .shoulder: return "Track comfort and range of motion during upper-body work."
        case .hip: return "Track comfort and range of motion during lower-body work."
        case .knee: return "Track comfort during squatting, lunging, and running."
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
    var createdAt: Date

    init(
        name: String,
        category: ExerciseCategory,
        type: ExerciseType,
        movementGroup: String = "",
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

    var isMainLift: Bool { category == .main }
}
