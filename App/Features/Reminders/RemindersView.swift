import SenseCore
import SwiftData
import SwiftUI

struct RemindersView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \ReminderEntity.createdAt, order: .reverse) private var reminders: [ReminderEntity]
    @State private var error: Error?

    private var upcoming: [ReminderEntity] { reminders.filter { !$0.isCompleted } }
    private var past: [ReminderEntity] { reminders.filter(\.isCompleted) }

    var body: some View {
        List {
            if !upcoming.isEmpty {
                Section(String(localized: "Upcoming")) {
                    ForEach(upcoming) { reminder in
                        row(for: reminder)
                    }
                    .onDelete { delete(upcoming, at: $0) }
                }
            }
            if !past.isEmpty {
                Section(String(localized: "Delivered")) {
                    ForEach(past) { reminder in
                        row(for: reminder)
                            .foregroundStyle(.secondary)
                    }
                    .onDelete { delete(past, at: $0) }
                }
            }
        }
        .overlay {
            if reminders.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Reminders"),
                    systemImage: "bell",
                    description: Text("Reminders you add from captures or by voice appear here.")
                )
            }
        }
        .navigationTitle(String(localized: "Reminders"))
        .refreshable { await app.reminders.syncDelivered() }
        .task { await app.reminders.syncDelivered() }
        .errorAlert($error)
    }

    @ViewBuilder
    private func row(for reminder: ReminderEntity) -> some View {
        if let memoryID = reminder.memoryID {
            NavigationLink(value: HomeDestination.memory(memoryID)) {
                ReminderRow(reminder: reminder)
            }
        } else {
            ReminderRow(reminder: reminder)
        }
    }

    private func delete(_ list: [ReminderEntity], at offsets: IndexSet) {
        do {
            for index in offsets {
                try app.reminders.delete(list[index])
            }
        } catch {
            self.error = error
        }
    }
}

struct ReminderRow: View {
    let reminder: ReminderEntity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.trigger?.symbol ?? "bell")
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.body)
                    .lineLimit(2)
                if let trigger = reminder.trigger {
                    Text(trigger.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
