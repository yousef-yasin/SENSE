import Foundation
import Observation
import SenseCore
import SwiftData

struct ReminderRequest: Identifiable {
    let id = UUID()
    var draft: ReminderDraft
    var memoryID: UUID?
    var memoryTitle: String?
    var body: String
}

enum CommandOutcome {
    case review(CaptureDraft)
    case reminder(ReminderRequest)
    case search(String)
    case similar(UUID)
    case look
    case message(String)
}

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let location: LocationService
    let permissions: PermissionCenter
    let network: NetworkMonitor
    let container: ModelContainer
    let memories: MemoryStore
    let reminders: ReminderService
    let places: PlaceStore
    let pipeline: CapturePipeline
    let speech = SpeechTranscriber()

    var openedMemoryID: UUID?
    private(set) var storageError: SenseError?

    private let scheduler: ReminderScheduler
    private let intentParser = IntentParser()

    init(inMemory: Bool = false) {
        let schema = Schema([MemoryEntity.self, ReminderEntity.self, PlaceEntity.self])
        var storageError: SenseError?
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)])
        } catch {
            storageError = .storageUnavailable
            do {
                container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            } catch {
                fatalError("Unable to create in-memory storage: \(error)")
            }
        }
        self.container = container
        self.storageError = storageError

        let context = container.mainContext
        settings = AppSettings()
        location = LocationService()
        permissions = PermissionCenter(location: location)
        network = NetworkMonitor()
        scheduler = ReminderScheduler()
        places = PlaceStore(context: context)
        memories = MemoryStore(context: context, embedder: SentenceEmbedder())
        reminders = ReminderService(context: context, scheduler: scheduler, permissions: permissions)
        pipeline = CapturePipeline(settings: settings, location: location, places: places, network: network)

        scheduler.onOpenMemory = { [weak self] id in
            self?.openedMemoryID = id
        }
    }

    func dismissStorageError() {
        storageError = nil
    }

    func handle(command text: String, source: CaptureSource) async throws -> CommandOutcome {
        switch intentParser.parse(text) {
        case .analyzeSurroundings:
            return .look
        case .recallSimilar:
            guard let latest = memories.latest() else {
                return .message(String(localized: "Capture something first, then ask whether you've seen it before."))
            }
            return .similar(latest.id)
        case .search(let query):
            return .search(query)
        case .remind(var draft):
            var memory: MemoryEntity?
            if draft.refersToContext {
                memory = memories.latest()
                draft.title = memory?.displayTitle ?? ""
            }
            return .reminder(ReminderRequest(
                draft: draft,
                memoryID: memory?.id,
                memoryTitle: memory?.displayTitle,
                body: memory?.summary ?? ""
            ))
        case .capture(let content):
            return .review(try await pipeline.process(text: content, source: source))
        }
    }

    func delete(_ memory: MemoryEntity) throws {
        try reminders.deleteReminders(forMemory: memory.id)
        try memories.delete(memory)
    }

    func eraseAllData() throws {
        try reminders.deleteAll()
        try memories.deleteAll()
        try places.deleteAll()
    }
}
