import MapKit
import SenseCore
import SwiftUI

struct MemoryDetailView: View {
    let memoryID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var memory: MemoryEntity?
    @State private var image: UIImage?
    @State private var reminders: [ReminderEntity] = []
    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var editedKind: MemoryKind = .note
    @State private var composer: ReminderRequest?
    @State private var confirmDelete = false
    @State private var error: Error?
    @State private var isLoaded = false

    var body: some View {
        Group {
            if let memory {
                content(memory)
            } else if isLoaded {
                ContentUnavailableView(
                    String(localized: "Memory Not Found"),
                    systemImage: "questionmark.square.dashed",
                    description: Text("It may have been deleted.")
                )
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .sheet(item: $composer) { request in
            ReminderComposerView(request: request) { spec in
                try await app.reminders.create(title: spec.title, body: request.body, trigger: spec.trigger, memoryID: request.memoryID)
            } onClose: {
                composer = nil
                reloadReminders()
            }
        }
        .errorAlert($error)
    }

    private func content(_ memory: MemoryEntity) -> some View {
        List {
            if let image {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel(String(localized: "Captured image"))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if isEditing {
                    TextField(String(localized: "Title"), text: $editedTitle, axis: .vertical)
                        .font(.title3.weight(.semibold))
                    Picker(String(localized: "Type"), selection: $editedKind) {
                        ForEach(MemoryKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(memory.kind.title, systemImage: memory.kind.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(memory.kind.tint)
                        Text(memory.displayTitle)
                            .font(.title2.weight(.semibold))
                        if !memory.summary.isEmpty {
                            Text(memory.summary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                HStack(spacing: 4) {
                    Image(systemName: memory.source.symbol)
                    Text(memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if !memory.highlights.isEmpty {
                Section(String(localized: "What matters")) {
                    ForEach(Array(memory.highlights.enumerated()), id: \.offset) { _, highlight in
                        HighlightRow(highlight: highlight)
                    }
                }
            }

            let details = memory.entities.filter { $0.kind != .label }
            if !details.isEmpty {
                Section(String(localized: "Details")) {
                    ForEach(Array(details.enumerated()), id: \.offset) { _, entity in
                        EntityRow(entity: entity)
                    }
                }
            }

            Section(String(localized: "Reminders")) {
                ForEach(reminders) { reminder in
                    ReminderRow(reminder: reminder)
                        .foregroundStyle(reminder.isCompleted ? Color.secondary : Color.primary)
                }
                .onDelete(perform: deleteReminders)
                Button {
                    composer = ReminderRequest(
                        draft: ReminderDraft(title: memory.displayTitle, timing: .unspecified),
                        memoryID: memory.id,
                        memoryTitle: memory.displayTitle,
                        body: memory.summary
                    )
                } label: {
                    Label(String(localized: "Remind me…"), systemImage: "bell.badge")
                }
            }

            if let latitude = memory.latitude, let longitude = memory.longitude {
                Section(String(localized: "Where")) {
                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600))) {
                        Marker(memory.placeName ?? memory.displayTitle, coordinate: coordinate)
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    if let place = memory.placeName {
                        Label(place, systemImage: "mappin.and.ellipse")
                    }
                }
            } else if let place = memory.placeName {
                Section(String(localized: "Where")) {
                    Label(place, systemImage: "mappin.and.ellipse")
                }
            }

            if !memory.tags.isEmpty {
                Section(String(localized: "Tags")) {
                    Text(memory.tags.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
            }

            if !memory.content.isEmpty {
                Section {
                    DisclosureGroup(String(localized: "Captured text")) {
                        Text(memory.content)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                NavigationLink(value: HomeDestination.similar(memory.id)) {
                    Label(String(localized: "Have I seen this before?"), systemImage: "rectangle.on.rectangle")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(String(localized: "Delete Memory"), systemImage: "trash")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button(String(localized: "Done")) { saveEdits(memory) }
                } else {
                    Button(String(localized: "Edit")) {
                        editedTitle = memory.title
                        editedKind = memory.kind
                        isEditing = true
                    }
                }
            }
        }
        .confirmationDialog(String(localized: "Delete this memory?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "Delete"), role: .destructive) { delete(memory) }
        } message: {
            Text("Its photo and reminders are removed too.")
        }
    }

    private func load() {
        memory = app.memories.memory(id: memoryID)
        isLoaded = true
        reloadReminders()
        if let name = memory?.imageFileName {
            image = app.memories.images.load(name)
        }
    }

    private func reloadReminders() {
        reminders = app.reminders.reminders(forMemory: memoryID)
    }

    private func saveEdits(_ memory: MemoryEntity) {
        do {
            try app.memories.update(memory, title: editedTitle, kind: editedKind)
            isEditing = false
        } catch {
            self.error = error
        }
    }

    private func deleteReminders(at offsets: IndexSet) {
        do {
            for index in offsets {
                try app.reminders.delete(reminders[index])
            }
            reloadReminders()
        } catch {
            self.error = error
        }
    }

    private func delete(_ memory: MemoryEntity) {
        do {
            try app.delete(memory)
            self.memory = nil
            dismiss()
        } catch {
            self.error = error
        }
    }
}
