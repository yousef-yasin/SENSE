import Foundation
import SenseCore

struct ReminderSpec: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var trigger: ReminderTrigger

    var triggerDescription: String {
        trigger.displayText
    }
}

extension ReminderTrigger {
    var displayText: String {
        switch self {
        case .date(let date):
            date.formatted(date: .abbreviated, time: .shortened)
        case .region(let region, let onArrival):
            onArrival
                ? String(localized: "When you arrive at \(region.name)")
                : String(localized: "When you leave \(region.name)")
        }
    }

    var symbol: String {
        switch self {
        case .date: "clock"
        case .region(_, let onArrival): onArrival ? "location" : "figure.walk"
        }
    }
}
