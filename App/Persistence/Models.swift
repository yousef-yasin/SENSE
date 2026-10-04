import Foundation
import SenseCore
import SwiftData

@Model
final class MemoryEntity {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var sourceRaw: String
    var originRaw: String
    var title: String
    var summary: String
    var content: String
    var tags: [String]
    var highlightsData: Data
    var entitiesData: Data
    var createdAt: Date
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
    var imageFileName: String?
    var embedding: Data?
    var embeddingModel: String?

    init(
        id: UUID = UUID(),
        kind: MemoryKind,
        source: CaptureSource,
        origin: Understanding.Origin,
        title: String,
        summary: String,
        content: String,
        tags: [String],
        highlights: [Highlight],
        entities: [ExtractedEntity],
        createdAt: Date,
        placeName: String?,
        latitude: Double?,
        longitude: Double?,
        imageFileName: String?
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.originRaw = origin.rawValue
        self.title = title
        self.summary = summary
        self.content = content
        self.tags = tags
        self.highlightsData = (try? JSONEncoder().encode(highlights)) ?? Data()
        self.entitiesData = (try? JSONEncoder().encode(entities)) ?? Data()
        self.createdAt = createdAt
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.imageFileName = imageFileName
    }

    var kind: MemoryKind {
        get { MemoryKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var source: CaptureSource {
        CaptureSource(rawValue: sourceRaw) ?? .text
    }

    var origin: Understanding.Origin {
        Understanding.Origin(rawValue: originRaw) ?? .onDevice
    }

    var highlights: [Highlight] {
        (try? JSONDecoder().decode([Highlight].self, from: highlightsData)) ?? []
    }

    var entities: [ExtractedEntity] {
        (try? JSONDecoder().decode([ExtractedEntity].self, from: entitiesData)) ?? []
    }

    var hasCoordinate: Bool {
        latitude != nil && longitude != nil
    }

    var displayTitle: String {
        title.isEmpty ? kind.title : title
    }
}

@Model
final class ReminderEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var triggerData: Data
    var createdAt: Date
    var memoryID: UUID?
    var isCompleted: Bool

    init(id: UUID = UUID(), title: String, body: String, trigger: ReminderTrigger, memoryID: UUID?, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.triggerData = (try? JSONEncoder().encode(trigger)) ?? Data()
        self.createdAt = createdAt
        self.memoryID = memoryID
        self.isCompleted = false
    }

    var trigger: ReminderTrigger? {
        try? JSONDecoder().decode(ReminderTrigger.self, from: triggerData)
    }

    var fireDate: Date? {
        if case .date(let date) = trigger { return date }
        return nil
    }
}

@Model
final class PlaceEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var aliases: [String]
    var latitude: Double
    var longitude: Double
    var radius: Double
    var createdAt: Date

    init(id: UUID = UUID(), name: String, aliases: [String] = [], latitude: Double, longitude: Double, radius: Double = 150, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.createdAt = createdAt
    }

    var region: GeoRegion {
        GeoRegion(name: name, latitude: latitude, longitude: longitude, radius: radius)
    }

    func matches(_ spoken: String) -> Bool {
        let target = spoken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return false }
        return ([name] + aliases).contains { candidate in
            let value = candidate.lowercased()
            return value == target || value.contains(target) || target.contains(value)
        }
    }
}
