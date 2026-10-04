import CoreLocation
import SenseCore
import UIKit

@MainActor
final class CapturePipeline {
    private let settings: AppSettings
    private let location: LocationService
    private let places: PlaceStore
    private let network: NetworkMonitor
    private let vision = VisionAnalyzer()

    init(settings: AppSettings, location: LocationService, places: PlaceStore, network: NetworkMonitor) {
        self.settings = settings
        self.location = location
        self.places = places
        self.network = network
    }

    func process(image: UIImage, source: CaptureSource) async throws -> CaptureDraft {
        let result = try await vision.analyze(image)
        let input = CaptureInput(source: source, text: result.text, imageLabels: result.labels)
        guard !input.isEmpty else { throw SenseError.nothingRecognized }
        return try await understand(input, image: image)
    }

    func process(text: String, source: CaptureSource) async throws -> CaptureDraft {
        let input = CaptureInput(source: source, text: text)
        guard !input.isEmpty else { throw SenseError.nothingRecognized }
        return try await understand(input, image: nil)
    }

    private func understand(_ input: CaptureInput, image: UIImage?) async throws -> CaptureDraft {
        var input = input
        var coordinate: CLLocationCoordinate2D?

        if settings.attachLocation, location.isAuthorized,
           let current = try? await location.currentLocation(timeout: .seconds(5)) {
            coordinate = current.coordinate
            if let saved = places.place(containing: current) {
                input.placeName = saved.name
            } else {
                input.placeName = await location.reverseGeocode(current)
            }
        }

        let understanding = try await provider().understand(input)
        return CaptureDraft(input: input, understanding: understanding, image: image, coordinate: coordinate)
    }

    private func provider() -> any IntelligenceProvider {
        guard let configuration = settings.remoteConfiguration else {
            return OnDeviceIntelligence()
        }
        guard network.isOnline else {
            return OfflineIntelligence()
        }
        return ResilientIntelligence(primary: OpenAICompatibleIntelligence(configuration: configuration))
    }
}

private struct OfflineIntelligence: IntelligenceProvider {
    var identifier: String { "offline" }

    func understand(_ input: CaptureInput) async throws -> Understanding {
        var understanding = try await OnDeviceIntelligence().understand(input)
        understanding.origin = .onDeviceFallback
        return understanding
    }
}
