import SenseCore
import SwiftData
import SwiftUI

struct MemoriesView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \MemoryEntity.createdAt, order: .reverse) private var memories: [MemoryEntity]

    @State private var query: String
    @State private var kindFilter: MemoryKind?
    @State private var results: [MemoryEntity]?
    @State private var pendingDeletion: MemoryEntity?
    @State private var error: Error?

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visible: [MemoryEntity] {
        let base = trimmedQuery.isEmpty ? memories : (results ?? [])
        guard let kindFilter else { return base }
        return base.filter { $0.kind == kindFilter }
    }

    var body: some View {
        List {
            ForEach(visible) { memory in
                NavigationLink(value: HomeDestination.memory(memory.id)) {
                    MemoryRow(memory: memory)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        pendingDeletion = memory
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .navigationTitle(String(localized: "Memories"))
        .searchable(text: $query, prompt: String(localized: "Ask about what you've captured"))
        .task(id: trimmedQuery) {
            guard !trimmedQuery.isEmpty else {
                results = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = app.memories.search(trimmedQuery)
        }
        .onChange(of: memories.count) {
            if !trimmedQuery.isEmpty {
                results = app.memories.search(trimmedQuery)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(String(localized: "Type"), selection: $kindFilter) {
                        Text("All Types").tag(MemoryKind?.none)
                        ForEach(MemoryKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(MemoryKind?.some(kind))
                        }
                    }
                } label: {
                    Image(systemName: kindFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(String(localized: "Filter by type"))
            }
        }
        .confirmationDialog(
            String(localized: "Delete this memory?"),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { memory in
            Button(String(localized: "Delete"), role: .destructive) {
                do {
                    try app.delete(memory)
                } catch {
                    self.error = error
                }
            }
        } message: { _ in
            Text("Its photo and reminders are removed too.")
        }
        .errorAlert($error)
    }

    @ViewBuilder
    private var emptyState: some View {
        if memories.isEmpty {
            ContentUnavailableView(
                String(localized: "No Memories Yet"),
                systemImage: "square.stack",
                description: Text("Things you capture with the camera, your voice or text appear here.")
            )
        } else if !trimmedQuery.isEmpty, results != nil, visible.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else if trimmedQuery.isEmpty, visible.isEmpty, let kindFilter {
            ContentUnavailableView(
                String(localized: "No \(kindFilter.title) Memories"),
                systemImage: kindFilter.symbol
            )
        }
    }
}

struct SimilarMemoriesView: View {
    let memoryID: UUID

    @Environment(AppModel.self) private var app
    @State private var source: MemoryEntity?
    @State private var matches: [MemoryEntity] = []
    @State private var isLoaded = false

    var body: some View {
        List {
            if let source {
                Section(String(localized: "Comparing")) {
                    NavigationLink(value: HomeDestination.memory(source.id)) {
                        MemoryRow(memory: source)
                    }
                }
            }
            if !matches.isEmpty {
                Section(String(localized: "Seen before")) {
                    ForEach(matches) { memory in
                        NavigationLink(value: HomeDestination.memory(memory.id)) {
                            MemoryRow(memory: memory)
                        }
                    }
                }
            }
        }
        .overlay {
            if isLoaded && matches.isEmpty {
                ContentUnavailableView(
                    String(localized: "Nothing Similar"),
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("You haven't captured anything like this before.")
                )
            }
        }
        .navigationTitle(String(localized: "Have I Seen This?"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            source = app.memories.memory(id: memoryID)
            if let source {
                matches = app.memories.similar(to: source)
            }
            isLoaded = true
        }
    }
}
