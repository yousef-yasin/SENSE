import Foundation

public enum CaptureSource: String, Codable, CaseIterable, Sendable {
    case camera
    case photo
    case live
    case voice
    case text
}

public struct ImageLabel: Codable, Hashable, Sendable {
    public var identifier: String
    public var confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }

    public var displayName: String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

public struct CaptureInput: Hashable, Sendable {
    public var source: CaptureSource
    public var text: String
    public var imageLabels: [ImageLabel]
    public var capturedAt: Date
    public var placeName: String?

    public init(
        source: CaptureSource,
        text: String,
        imageLabels: [ImageLabel] = [],
        capturedAt: Date = Date(),
        placeName: String? = nil
    ) {
        self.source = source
        self.text = text
        self.imageLabels = imageLabels
        self.capturedAt = capturedAt
        self.placeName = placeName
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageLabels.isEmpty
    }
}
