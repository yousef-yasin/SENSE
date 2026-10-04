import Foundation

public enum MemoryKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case note
    case document
    case receipt
    case announcement
    case event
    case task
    case object
    case place
    case observation
    case person

    public var id: String { rawValue }
}

public struct ExtractedEntity: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case date
        case money
        case email
        case phone
        case link
        case merchant
        case label
    }

    public var kind: Kind
    public var text: String
    public var value: String
    public var date: Date?

    public init(kind: Kind, text: String, value: String? = nil, date: Date? = nil) {
        self.kind = kind
        self.text = text
        self.value = value ?? text
        self.date = date
    }
}

public struct Highlight: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case deadline
        case warning
        case requirement
        case date
        case info
    }

    public var kind: Kind
    public var text: String
    public var date: Date?

    public init(kind: Kind, text: String, date: Date? = nil) {
        self.kind = kind
        self.text = text
        self.date = date
    }
}
