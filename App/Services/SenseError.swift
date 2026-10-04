import Foundation

enum SenseError: LocalizedError, Equatable {
    case cameraUnavailable
    case permissionDenied(PermissionKind)
    case speechUnavailable
    case onDeviceSpeechUnsupported
    case nothingRecognized
    case imageUnreadable
    case locationUnavailable
    case regionLimitReached
    case reminderInPast
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            String(localized: "The camera isn't available on this device.")
        case .permissionDenied(let kind):
            String(localized: "\(kind.title) access is turned off. You can enable it in the Settings app.")
        case .speechUnavailable:
            String(localized: "Speech recognition isn't available right now. Try again in a moment.")
        case .onDeviceSpeechUnsupported:
            String(localized: "On-device transcription isn't supported for your language on this iPhone. You can allow server-based transcription in SENSE Settings.")
        case .nothingRecognized:
            String(localized: "SENSE couldn't find any text or recognizable objects. Try again with better lighting or move closer.")
        case .imageUnreadable:
            String(localized: "That image couldn't be read.")
        case .locationUnavailable:
            String(localized: "Your current location couldn't be determined.")
        case .regionLimitReached:
            String(localized: "iOS allows up to 20 place-based reminders at once. Remove one to add another.")
        case .reminderInPast:
            String(localized: "Choose a time in the future.")
        case .storageUnavailable:
            String(localized: "Your memories couldn't be opened. SENSE is running with temporary storage until it restarts.")
        }
    }
}
