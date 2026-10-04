import SenseCore
import SwiftUI

struct CaptureReviewView: View {
    let draft: CaptureDraft
    let onClose: (UUID?) -> Void

    @Environment(AppModel.self) private var app
    @State private var title: String
    @State private var kind: MemoryKind
    @State private var suggestions: [SuggestedReminder]
    @State private var extraReminders: [ReminderSpec] = []
    @State private var similar: [MemoryEntity] = []
    @State private var composer: ReminderRequest?
    @State private var isSaving = false
    @State private var error: Error?
    @State private var savedID: UUID?

    struct SuggestedReminder: Identifiable {
        let id = UUID()
        var title: String
        var date: Date
        var dueDate: Date?
        var isOn: Bool
    }

    init(draft: CaptureDraft, onClose: @escaping (UUID?) -> Void) {
        self.draft = draft
        self.onClose = onClose
        _title = State(initialValue: draft.understanding.title)
        _kind = State(initialValue: draft.understanding.kind)
        _suggestions = State(initialValue: draft.understanding.reminderSuggestions.compactMap { suggestion in
            guard case .at(let date) = suggestion.timing else { return nil }
            return SuggestedReminder(title: suggestion.title, date: date, dueDate: suggestion.dueDate, isOn: false)
        })
    }

    private var understanding: Understanding { draft.understanding }

    private var detailEntities: [ExtractedEntity] {
        understanding.entities.filter { $0.kind != .date && $0.kind != .label }
    }

    var body: some View {
        NavigationStack {
            List {
                if let image = draft.image {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel(String(localized: "Captured image"))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField(String(localized: "Title"), text: $title, prompt: Text(kind.title), axis: .vertical)
                        .font(.headline)
                    Picker(String(localized: "Type"), selection: $kind) {
                        ForEach(MemoryKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                } footer: {
                    Label(understanding.origin.title, systemImage: understanding.origin.symbol)
                }

                if !understanding.summary.isEmpty {
                    Section(String(localized: "Summary")) {
                        Text(understanding.summary)
                    }
                }

                if !understanding.highlights.isEmpty {
                    Section(String(localized: "What matters")) {
                        ForEach(Array(understanding.highlights.enumerated()), id: \.offset) { _, highlight in
                            HighlightRow(highlight: highlight)
                        }
                    }
                }

                remindersSection

                if !detailEntities.isEmpty {
                    Section(String(localized: "Details")) {
                        ForEach(Array(detailEntities.enumerated()), id: \.offset) { _, entity in
                            EntityRow(entity: entity)
                        }
                    }
                }

                if !similar.isEmpty {
                    Section {
                        ForEach(similar) { memory in
                            MemoryRow(memory: memory)
                        }
                    } header: {
                        Text("You've captured something similar")
                    }
                }

                if !draft.input.text.isEmpty {
                    Section {
                        DisclosureGroup(String(localized: "Captured text")) {
                            Text(draft.input.text)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                if let place = draft.input.placeName {
                    Section {
                        Label(place, systemImage: "mappin.and.ellipse")
                    } footer: {
                        Text("Location tagging is on. You can turn it off in Settings.")
                    }
                }
            }
            .navigationTitle(String(localized: "Review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Discard"), role: .destructive) { onClose(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .disabled(isSaving)
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving { ProcessingOverlay(message: String(localized: "Saving…")) }
            }
        }
        .task { similar = app.memories.similar(to: draft) }
        .sheet(item: $composer) { request in
            ReminderComposerView(request: request) { spec in
                extraReminders.append(spec)
            } onClose: {
                composer = nil
            }
        }
        .errorAlert($error)
        .onChange(of: error == nil) { _, cleared in
            if cleared, let savedID {
                onClose(savedID)
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var remindersSection: some View {
        Section {
            ForEach($suggestions) { $suggestion in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $suggestion.isOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                            if let due = suggestion.dueDate {
                                Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if suggestion.isOn {
                        DatePicker(String(localized: "Remind me"), selection: $suggestion.date, in: Date()...)
                            .font(.subheadline)
                    }
                }
            }
            ForEach(extraReminders) { spec in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spec.title)
                        Text(spec.triggerDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: spec.trigger.symbol)
                }
            }
            .onDelete { extraReminders.remove(atOffsets: $0) }

            Button {
                composer = ReminderRequest(
                    draft: ReminderDraft(title: title.isEmpty ? kind.title : title, timing: .unspecified),
                    memoryID: nil,
                    memoryTitle: nil,
                    body: understanding.summary
                )
            } label: {
                Label(String(localized: "Add a reminder…"), systemImage: "bell.badge")
            }
        } header: {
            Text(suggestions.isEmpty ? String(localized: "Reminders") : String(localized: "Suggested reminders"))
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            let memory: MemoryEntity
            do {
                memory = try app.memories.save(draft, title: title, kind: kind)
            } catch {
                self.error = error
                return
            }

            let specs = suggestions.filter(\.isOn).map { ReminderSpec(title: $0.title, trigger: .date($0.date)) } + extraReminders
            var failure: Error?
            for spec in specs {
                do {
                    try await app.reminders.create(title: spec.title, body: memory.summary, trigger: spec.trigger, memoryID: memory.id)
                } catch {
                    failure = failure ?? error
                }
            }

            if let failure {
                savedID = memory.id
                error = failure
            } else {
                onClose(memory.id)
            }
        }
    }
}

struct HighlightRow: View {
    let highlight: Highlight

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(highlight.kind.tint)
                Text(highlight.text)
            }
        } icon: {
            Image(systemName: highlight.kind.symbol)
                .foregroundStyle(highlight.kind.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EntityRow: View {
    let entity: ExtractedEntity

    var body: some View {
        switch entity.kind {
        case .phone:
            if let url = URL(string: "tel:\(entity.value)") {
                Link(destination: url) { Label(entity.text, systemImage: "phone") }
            }
        case .email:
            if let url = URL(string: "mailto:\(entity.value)") {
                Link(destination: url) { Label(entity.text, systemImage: "envelope") }
            }
        case .link:
            if let url = URL(string: entity.value) {
                Link(destination: url) { Label(entity.text, systemImage: "link").lineLimit(1) }
            }
        case .money:
            Label(entity.text, systemImage: "banknote")
        case .merchant:
            Label(entity.text, systemImage: "building.2")
        case .date:
            Label(entity.text, systemImage: "calendar")
        case .label:
            Label(entity.text, systemImage: "tag")
        }
    }
}
