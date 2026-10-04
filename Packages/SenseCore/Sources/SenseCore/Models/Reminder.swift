import Foundation

public enum ReminderTiming: Hashable, Sendable {
    case at(Date)
    case arriving(String)
    case leaving(String)
    case unspecified
}

public struct ReminderDraft: Hashable, Sendable {
    public var title: String
    public var timing: ReminderTiming
    public var dueDate: Date?
    public var refersToContext: Bool

    public init(title: String, timing: ReminderTiming, dueDate: Date? = nil, refersToContext: Bool = false) {
        self.title = title
        self.timing = timing
        self.dueDate = dueDate
        self.refersToContext = refersToContext
    }
}

public struct GeoRegion: Codable, Hashable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var radius: Double

    public init(name: String, latitude: Double, longitude: Double, radius: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }
}

public enum ReminderTrigger: Codable, Hashable, Sendable {
    case date(Date)
    case region(GeoRegion, onArrival: Bool)
}

public enum ReminderPolicy {
    public static let defaultHour = 9

    public static func suggestedFireDate(
        for due: Date,
        includesTime: Bool,
        isDeadline: Bool,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let anchored = includesTime
            ? due
            : calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: due) ?? due
        guard anchored > now else { return nil }

        var candidates: [Date] = []
        if isDeadline {
            if let dayBefore = calendar.date(byAdding: .day, value: -1, to: anchored) {
                candidates.append(dayBefore)
            }
        }
        if includesTime {
            candidates.append(anchored.addingTimeInterval(-3600))
        }
        candidates.append(anchored)

        return candidates.first { $0 > now.addingTimeInterval(300) } ?? anchored
    }
}
