import Foundation

public enum SuggestedAction: Hashable, Sendable {
    case reminder(ReminderDraft)
    case openLink(URL)
    case call(String)
    case email(String)
}

public struct Understanding: Hashable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case onDevice
        case remote
        case onDeviceFallback
    }

    public var kind: MemoryKind
    public var title: String
    public var summary: String
    public var highlights: [Highlight]
    public var entities: [ExtractedEntity]
    public var suggestions: [SuggestedAction]
    public var tags: [String]
    public var origin: Origin

    public init(
        kind: MemoryKind,
        title: String,
        summary: String,
        highlights: [Highlight] = [],
        entities: [ExtractedEntity] = [],
        suggestions: [SuggestedAction] = [],
        tags: [String] = [],
        origin: Origin = .onDevice
    ) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.highlights = highlights
        self.entities = entities
        self.suggestions = suggestions
        self.tags = tags
        self.origin = origin
    }

    public var reminderSuggestions: [ReminderDraft] {
        suggestions.compactMap {
            if case .reminder(let draft) = $0 { return draft }
            return nil
        }
    }
}
