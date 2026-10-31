import Foundation

// What travels between the phone and the watch over WatchConnectivity
// (design: docs/superpowers/specs/2026-10-18-apple-watch-design.md, sections
// 3–4). Swift-only by owner decision, like WatchSync.swift. WatchConnectivity
// itself stays in the apps; this file only defines and encodes the payloads,
// so both sides agree byte for byte and the format is tested on Linux.

/// The settings a watch session needs from the phone (design section 3).
public struct WatchSettings: Codable, Hashable, Sendable {
    public var accessoryRestSeconds: Int
    public var secondaryRestSeconds: Int
    public var mainUpperRestSeconds: Int
    public var mainCompoundRestSeconds: Int
    public var autoStartRest: Bool
    public var haptics: Bool
    /// "lb" or "kg": the display unit. Weights on the wire are always pounds.
    public var unit: String
    /// The phone's Health-writing setting. The watch treats it as consent only
    /// when received after its session began (`SyncSessionRules`).
    public var healthKitEnabled: Bool

    public init(accessoryRestSeconds: Int, secondaryRestSeconds: Int, mainUpperRestSeconds: Int,
                mainCompoundRestSeconds: Int, autoStartRest: Bool, haptics: Bool, unit: String,
                healthKitEnabled: Bool) {
        self.accessoryRestSeconds = accessoryRestSeconds
        self.secondaryRestSeconds = secondaryRestSeconds
        self.mainUpperRestSeconds = mainUpperRestSeconds
        self.mainCompoundRestSeconds = mainCompoundRestSeconds
        self.autoStartRest = autoStartRest
        self.haptics = haptics
        self.unit = unit
        self.healthKitEnabled = healthKitEnabled
    }

    /// Rest after a working set, by the entry's program role, mirroring the
    /// phone's rest buckets closely enough for the watch's countdown.
    public func restSeconds(forRole role: String?) -> Int {
        switch role {
        case "main": return mainCompoundRestSeconds
        case "secondary", "complementary": return secondaryRestSeconds
        default: return accessoryRestSeconds
        }
    }
}

/// The phone's latest word to the watch, sent as application context: the
/// next planned session (nil when the program has no next day), the session the
/// phone has open (the watch offers Continue), and settings.
public struct WatchPlan: Codable, Hashable, Sendable {
    public var next: SyncSessionSnapshot?
    /// An open phone session the watch can join, with its operations so far.
    public var active: SyncSessionSnapshot?
    public var activeSessionID: String?
    public var settings: WatchSettings
    public var sentAt: Date

    public init(next: SyncSessionSnapshot?, active: SyncSessionSnapshot? = nil, activeSessionID: String? = nil,
                settings: WatchSettings, sentAt: Date) {
        self.next = next
        self.active = active
        self.activeSessionID = activeSessionID
        self.settings = settings
        self.sentAt = sentAt
    }

    /// A cached plan built on an earlier day may be out of date (design
    /// section 5): offered with a warning, never silently.
    public func isStale(now: Date, calendar: Calendar = .current) -> Bool {
        guard let built = next?.builtAt else { return false }
        return !calendar.isDate(built, inSameDayAs: now)
    }
}

public enum WatchWire: Codable, Hashable, Sendable {
    case operations([SyncOperation])
    case ack(SyncAck)
    case plan(WatchPlan)
    /// The watch asks for a fresh plan at Start when the phone is reachable.
    case requestPlan
    /// The watch joins the session the phone has open: the phone answers with
    /// every operation of that session so far, starting with its start.
    case join(sessionID: String)

    /// WatchConnectivity dictionaries carry property-list values, so every
    /// message travels as one JSON blob under this key.
    public static let key = "cadence.wire.v1"

    public func dictionary() throws -> [String: Any] {
        [Self.key: try JSONEncoder().encode(self)]
    }

    public static func decode(_ dictionary: [String: Any]) -> WatchWire? {
        guard let data = dictionary[key] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchWire.self, from: data)
    }
}
