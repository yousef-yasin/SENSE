import CoreLocation
import Foundation
import SenseCore
import SwiftData
import UIKit

struct CaptureDraft: Identifiable {
    let id = UUID()
    var input: CaptureInput
    var understanding: Understanding
    var image: UIImage?
    var coordinate: CLLocationCoordinate2D?
}

@MainActor
final class MemoryStore {
    let images: ImageStore
    private let context: ModelContext
    private let embedder: any TextEmbedder
    private let engine: MemorySearchEngine
    private let queryParser = QueryParser()

    init(context: ModelContext, images: ImageStore = ImageStore(), embedder: any TextEmbedder) {
        self.context = context
        self.images = images
        self.embedder = embedder
        self.engine = MemorySearchEngine(embedder: embedder)
    }

    @discardableResult
    func save(_ draft: CaptureDraft, title: String, kind: MemoryKind) throws -> MemoryEntity {
        let fileName = try draft.image.map { try images.save($0) }
        let understanding = draft.understanding
        let entity = MemoryEntity(
            kind: kind,
            source: draft.input.source,
            origin: understanding.origin,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: understanding.summary,
            content: draft.input.text,
            tags: understanding.tags,
            highlights: understanding.highlights,
            entities: understanding.entities,
            createdAt: draft.input.capturedAt,
            placeName: draft.input.placeName,
            latitude: draft.coordinate?.latitude,
            longitude: draft.coordinate?.longitude,
            imageFileName: fileName
        )
        refreshEmbedding(for: entity)
        context.insert(entity)
        do {
            try context.save()
        } catch {
            if let fileName { images.delete(fileName) }
            context.delete(entity)
            throw error
        }
        return entity
    }

    func update(_ entity: MemoryEntity, title: String, kind: MemoryKind) throws {
        entity.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entity.kind = kind
        refreshEmbedding(for: entity)
        try context.save()
    }

    func memory(id: UUID) -> MemoryEntity? {
        var descriptor = FetchDescriptor<MemoryEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func memories(ids: [UUID]) -> [MemoryEntity] {
        let all = allMemories()
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    func latest() -> MemoryEntity? {
        var descriptor = FetchDescriptor<MemoryEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<MemoryEntity>())) ?? 0
    }

    func search(_ text: String) -> [MemoryEntity] {
        let query = queryParser.parse(text)
        let all = allMemories()
        let hits = engine.search(query, in: documents(for: all))
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return hits.compactMap { byID[$0.id] }
    }

    func similar(to entity: MemoryEntity) -> [MemoryEntity] {
        let all = allMemories()
        let docs = documents(for: all)
        guard let target = docs.first(where: { $0.id == entity.id }) else { return [] }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return engine.similar(to: target, in: docs).compactMap { byID[$0.id] }
    }

    func similar(to draft: CaptureDraft) -> [MemoryEntity] {
        let all = allMemories()
        var target = SearchDocument(
            id: draft.id,
            title: draft.understanding.title,
            body: searchableBody(summary: draft.understanding.summary, content: draft.input.text, highlights: draft.understanding.highlights, place: draft.input.placeName),
            tags: draft.understanding.tags,
            kind: draft.understanding.kind,
            createdAt: draft.input.capturedAt,
            placeName: draft.input.placeName,
            embedding: nil
        )
        target.embedding = embedder.embed(target.embeddingText)
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return engine.similar(to: target, in: documents(for: all), limit: 3).compactMap { byID[$0.id] }
    }

    func delete(_ entity: MemoryEntity) throws {
        if let fileName = entity.imageFileName {
            images.delete(fileName)
        }
        context.delete(entity)
        try context.save()
    }

    func deleteAll() throws {
        try context.delete(model: MemoryEntity.self)
        try context.save()
        images.deleteAll()
    }

    private func allMemories() -> [MemoryEntity] {
        (try? context.fetch(FetchDescriptor<MemoryEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    private func documents(for entities: [MemoryEntity]) -> [SearchDocument] {
        var changed = false
        let docs = entities.map { entity -> SearchDocument in
            if entity.embeddingModel != embedder.identifier {
                refreshEmbedding(for: entity)
                changed = true
            }
            return document(for: entity)
        }
        if changed {
            try? context.save()
        }
        return docs
    }

    private func document(for entity: MemoryEntity) -> SearchDocument {
        SearchDocument(
            id: entity.id,
            title: entity.title,
            body: searchableBody(summary: entity.summary, content: entity.content, highlights: entity.highlights, place: entity.placeName),
            tags: entity.tags,
            kind: entity.kind,
            createdAt: entity.createdAt,
            placeName: entity.placeName,
            embedding: entity.embedding.map(VectorMath.decode)
        )
    }

    private func refreshEmbedding(for entity: MemoryEntity) {
        let text = document(for: entity).embeddingText
        entity.embedding = embedder.embed(text).map(VectorMath.encode)
        entity.embeddingModel = embedder.identifier
    }

    private func searchableBody(summary: String, content: String, highlights: [Highlight], place: String?) -> String {
        ([summary, content] + highlights.map(\.text) + [place ?? ""]).joined(separator: "\n")
    }
}
