import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class LocationService {
    private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private let delegate = Delegate()
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<Bool, Never>] = []
    @ObservationIgnored private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    init() {
        authorization = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = delegate
        delegate.onAuthorization = { [weak self] status in
            Task { @MainActor in self?.handleAuthorization(status) }
        }
        delegate.onLocation = { [weak self] result in
            Task { @MainActor in self?.handleLocation(result) }
        }
    }

    var permissionState: PermissionState {
        switch authorization {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    var isAuthorized: Bool { permissionState == .granted }

    func requestWhenInUseAuthorization() async -> Bool {
        guard authorization == .notDetermined else { return isAuthorized }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation(timeout: Duration = .seconds(10)) async throws -> CLLocation {
        guard isAuthorized else { throw SenseError.permissionDenied(.location) }
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -60, recent.horizontalAccuracy <= 200 {
            return recent
        }
        let timeoutTask = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.handleLocation(.failure(SenseError.locationUnavailable))
        }
        defer { timeoutTask.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            if locationWaiters.count == 1 {
                manager.requestLocation()
            }
        }
    }

    func reverseGeocode(_ location: CLLocation) async -> String? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return placemark.areasOfInterest?.first ?? placemark.name ?? placemark.locality
    }

    func searchPlaces(matching query: String, near location: CLLocation?) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let location {
            request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }
        return try await MKLocalSearch(request: request).start().mapItems
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        authorization = status
        guard status != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: isAuthorized) }
    }

    private func handleLocation(_ result: Result<CLLocation, Error>) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        waiters.forEach { $0.resume(with: result) }
    }

    private final class Delegate: NSObject, CLLocationManagerDelegate {
        var onAuthorization: ((CLAuthorizationStatus) -> Void)?
        var onLocation: ((Result<CLLocation, Error>) -> Void)?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            onAuthorization?(manager.authorizationStatus)
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            if let location = locations.last {
                onLocation?(.success(location))
            }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            if let clError = error as? CLError, clError.code == .locationUnknown {
                return
            }
            onLocation?(.failure(SenseError.locationUnavailable))
        }
    }
}
