import Foundation

public protocol IntelligenceProvider: Sendable {
    var identifier: String { get }
    func understand(_ input: CaptureInput) async throws -> Understanding
}

public struct OnDeviceIntelligence: IntelligenceProvider {
    public let analyzer: ContentAnalyzer

    public init(analyzer: ContentAnalyzer = ContentAnalyzer()) {
        self.analyzer = analyzer
    }

    public var identifier: String { "on-device" }

    public func understand(_ input: CaptureInput) async throws -> Understanding {
        analyzer.analyze(input, now: Date())
    }
}

public struct ResilientIntelligence: IntelligenceProvider {
    public let primary: any IntelligenceProvider
    public let fallback: OnDeviceIntelligence

    public init(primary: any IntelligenceProvider, fallback: OnDeviceIntelligence = OnDeviceIntelligence()) {
        self.primary = primary
        self.fallback = fallback
    }

    public var identifier: String { primary.identifier }

    public func understand(_ input: CaptureInput) async throws -> Understanding {
        do {
            return try await primary.understand(input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            var understanding = try await fallback.understand(input)
            understanding.origin = .onDeviceFallback
            return understanding
        }
    }
}
