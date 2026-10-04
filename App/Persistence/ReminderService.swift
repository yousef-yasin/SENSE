import Foundation
import SenseCore
import SwiftData

@MainActor
final class ReminderService {
    private let context: ModelContext
    private let scheduler: ReminderScheduler
    private let permissions: PermissionCenter

    init(context: ModelContext, scheduler: ReminderScheduler, permissions: PermissionCenter) {
        self.context = context
        self.scheduler = scheduler
        self.permissions = permissions
    }

    @discardableResult
    func create(title: String, body: String, trigger: ReminderTrigger, memoryID: UUID?) async throws -> ReminderEntity {
        try await permissions.ensure(.notifications)
        if case .region = trigger {
            try await permissions.ensure(.location)
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let reminder = ReminderEntity(
            title: cleanTitle.isEmpty ? String(localized: "Reminder") : cleanTitle,
            body: body,
            trigger: trigger,
            memoryID: memoryID
        )
        try await scheduler.schedule(id: reminder.id, title: reminder.title, body: body, trigger: trigger, memoryID: memoryID)
        context.insert(reminder)
        do {
            try context.save()
        } catch {
            scheduler.cancel([reminder.id])
            throw error
        }
        return reminder
    }

    func delete(_ reminder: ReminderEntity) throws {
        scheduler.cancel([reminder.id])
        context.delete(reminder)
        try context.save()
    }

    func deleteReminders(forMemory memoryID: UUID) throws {
        let target: UUID? = memoryID
        let descriptor = FetchDescriptor<ReminderEntity>(predicate: #Predicate { $0.memoryID == target })
        let reminders = try context.fetch(descriptor)
        scheduler.cancel(reminders.map(\.id))
        for reminder in reminders {
            context.delete(reminder)
        }
        try context.save()
    }

    func reminders(forMemory memoryID: UUID) -> [ReminderEntity] {
        let target: UUID? = memoryID
        let descriptor = FetchDescriptor<ReminderEntity>(
            predicate: #Predicate { $0.memoryID == target },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func deleteAll() throws {
        scheduler.cancelAll()
        try context.delete(model: ReminderEntity.self)
        try context.save()
    }

    func syncDelivered() async {
        let pending = await scheduler.pendingIdentifiers()
        let descriptor = FetchDescriptor<ReminderEntity>(predicate: #Predicate { $0.isCompleted == false })
        guard let open = try? context.fetch(descriptor) else { return }
        var changed = false
        for reminder in open where !pending.contains(reminder.id.uuidString) {
            reminder.isCompleted = true
            changed = true
        }
        if changed {
            try? context.save()
        }
    }
}
