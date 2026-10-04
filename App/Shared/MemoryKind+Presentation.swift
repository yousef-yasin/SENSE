import SenseCore
import SwiftUI

extension MemoryKind {
    var title: String {
        switch self {
        case .note: String(localized: "Note")
        case .document: String(localized: "Document")
        case .receipt: String(localized: "Receipt")
        case .announcement: String(localized: "Announcement")
        case .event: String(localized: "Event")
        case .task: String(localized: "Task")
        case .object: String(localized: "Object")
        case .place: String(localized: "Place")
        case .observation: String(localized: "Observation")
        case .person: String(localized: "Person")
        }
    }

    var symbol: String {
        switch self {
        case .note: "note.text"
        case .document: "doc.text"
        case .receipt: "creditcard"
        case .announcement: "megaphone"
        case .event: "calendar"
        case .task: "checklist"
        case .object: "cube"
        case .place: "mappin.and.ellipse"
        case .observation: "eye"
        case .person: "person"
        }
    }

    var tint: Color {
        switch self {
        case .note, .observation: .gray
        case .document: .blue
        case .receipt: .green
        case .announcement: .orange
        case .event: .purple
        case .task: .teal
        case .object: .indigo
        case .place: .red
        case .person: .pink
        }
    }
}

extension Highlight.Kind {
    var title: String {
        switch self {
        case .deadline: String(localized: "Deadline")
        case .warning: String(localized: "Warning")
        case .requirement: String(localized: "Requirement")
        case .date: String(localized: "Date")
        case .info: String(localized: "Key point")
        }
    }

    var symbol: String {
        switch self {
        case .deadline: "hourglass"
        case .warning: "exclamationmark.triangle"
        case .requirement: "checkmark.seal"
        case .date: "calendar"
        case .info: "sparkle"
        }
    }

    var tint: Color {
        switch self {
        case .deadline: .orange
        case .warning: .red
        case .requirement: .blue
        case .date: .purple
        case .info: .secondary
        }
    }
}

extension CaptureSource {
    var title: String {
        switch self {
        case .camera: String(localized: "Camera")
        case .photo: String(localized: "Photo")
        case .live: String(localized: "Live view")
        case .voice: String(localized: "Voice")
        case .text: String(localized: "Text")
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .photo: "photo"
        case .live: "viewfinder"
        case .voice: "mic"
        case .text: "character.cursor.ibeam"
        }
    }
}

extension Understanding.Origin {
    var title: String {
        switch self {
        case .onDevice: String(localized: "Understood on this iPhone")
        case .remote: String(localized: "Enhanced by your AI provider")
        case .onDeviceFallback: String(localized: "Provider unavailable — understood on this iPhone")
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: "iphone"
        case .remote: "sparkles"
        case .onDeviceFallback: "wifi.slash"
        }
    }
}
