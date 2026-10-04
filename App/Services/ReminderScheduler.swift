import CoreLocation
import Foundation
import SenseCore
import UserNotifications

@MainActor
final class ReminderScheduler {
    static let regionLimit = 20
    static let memoryKey = "memoryID"

    private let center = UNUserNotificationCenter.current()
    private let delegate = NotificationDelegate()

    var onOpenMemory: ((UUID) -> Void)? {
        didSet {
            let handler = onOpenMemory
            delegate.onOpenMemory = { id in
                Task { @MainActor in handler?(id) }
            }
        }
    }

    init() {
        center.delegate = delegate
    }

    func schedule(id: UUID, title: String, body: String, trigger: ReminderTrigger, memoryID: UUID?) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let memoryID {
            content.userInfo = [Self.memoryKey: memoryID.uuidString]
        }

        let notificationTrigger: UNNotificationTrigger
        switch trigger {
        case .date(let date):
            guard date > Date() else { throw SenseError.reminderInPast }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            notificationTrigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .region(let region, let onArrival):
            let pending = await center.pendingNotificationRequests()
            let regionCount = pending.filter { $0.trigger is UNLocationNotificationTrigger }.count
            guard regionCount < Self.regionLimit else { throw SenseError.regionLimitReached }
            let circular = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude),
                radius: min(max(region.radius, 100), 1_000),
                identifier: id.uuidString
            )
            circular.notifyOnEntry = onArrival
            circular.notifyOnExit = !onArrival
            notificationTrigger = UNLocationNotificationTrigger(region: circular, repeats: false)
        }

        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: notificationTrigger)
        try await center.add(request)
    }

    func cancel(_ ids: [UUID]) {
        let identifiers = ids.map(\.uuidString)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func pendingIdentifiers() async -> Set<String> {
        Set(await center.pendingNotificationRequests().map(\.identifier))
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpenMemory: ((UUID) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let value = response.notification.request.content.userInfo[ReminderScheduler.memoryKey] as? String,
           let id = UUID(uuidString: value) {
            onOpenMemory?(id)
        }
        completionHandler()
    }
}
