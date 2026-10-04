import AVFoundation
import CoreLocation
import Observation
import Speech
import UIKit
import UserNotifications

enum PermissionKind: String, CaseIterable, Identifiable {
    case camera
    case microphone
    case speech
    case location
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: String(localized: "Camera")
        case .microphone: String(localized: "Microphone")
        case .speech: String(localized: "Speech Recognition")
        case .location: String(localized: "Location")
        case .notifications: String(localized: "Notifications")
        }
    }

    var purpose: String {
        switch self {
        case .camera: String(localized: "Read text and recognize objects when you capture or look at something.")
        case .microphone: String(localized: "Hear you only while a voice capture is open.")
        case .speech: String(localized: "Turn what you say into text, on this iPhone when supported.")
        case .location: String(localized: "Remind you at places you choose and, if you allow it, tag where memories were captured.")
        case .notifications: String(localized: "Deliver the reminders you create.")
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .microphone: "mic"
        case .speech: "waveform"
        case .location: "location"
        case .notifications: "bell"
        }
    }
}

enum PermissionState: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted

    var label: String {
        switch self {
        case .notDetermined: String(localized: "Not requested")
        case .granted: String(localized: "Allowed")
        case .denied: String(localized: "Off")
        case .restricted: String(localized: "Restricted")
        }
    }
}

@MainActor
@Observable
final class PermissionCenter {
    private(set) var states: [PermissionKind: PermissionState] = [:]
    private let location: LocationService

    init(location: LocationService) {
        self.location = location
    }

    func state(of kind: PermissionKind) -> PermissionState {
        states[kind] ?? .notDetermined
    }

    func refresh() async {
        states[.camera] = Self.cameraState()
        states[.microphone] = Self.microphoneState()
        states[.speech] = Self.speechState()
        states[.location] = location.permissionState
        states[.notifications] = await Self.notificationState()
    }

    @discardableResult
    func request(_ kind: PermissionKind) async -> Bool {
        let granted: Bool
        switch kind {
        case .camera:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            granted = await AVAudioApplication.requestRecordPermission()
        case .speech:
            granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .location:
            granted = await location.requestWhenInUseAuthorization()
        case .notifications:
            granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        await refresh()
        return granted
    }

    func ensure(_ kind: PermissionKind) async throws {
        await refresh()
        switch state(of: kind) {
        case .granted:
            return
        case .notDetermined:
            if await request(kind) { return }
            throw SenseError.permissionDenied(kind)
        case .denied, .restricted:
            throw SenseError.permissionDenied(kind)
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func cameraState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    private static func microphoneState() -> PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }

    private static func speechState() -> PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    private static func notificationState() async -> PermissionState {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }
}
