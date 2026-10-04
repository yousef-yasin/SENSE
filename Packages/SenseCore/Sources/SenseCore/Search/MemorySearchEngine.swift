import Foundation

public struct SearchDocument: Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var tags: [String]
    public var kind: MemoryKind
    public var createdAt: Date
    public var placeName: String?
    public var embedding: [Float]?

    public init(id: UUID, title: String, body: String, tags: [String], kind: MemoryKind, createdAt: Date, placeName: String?, embedding: [Float]?) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.kind = kind
        self.createdAt = createdAt
        self.placeName = placeName
        self.embedding = embedding
    }

    public var embeddingText: String {
        ([title, title] + tags + [body]).joined(separator: " ")
    }
}

public struct SearchHit: Hashable, Sendable {
    public var id: UUID
    public var score: Double
}

public struct MemorySearchEngine: Sendable {
    public var embedder: (any TextEmbedder)?

    public init(embedder: (any TextEmbedder)? = nil) {
        self.embedder = embedder
    }

    public func search(_ query: MemoryQuery, in documents: [SearchDocument], limit: Int = 50) -> [SearchHit] {
        var candidates = documents
        var terms = query.terms

        if let interval = query.dateInterval {
            candidates = candidates.filter { interval.contains($0.createdAt) }
        }

        if let place = query.place {
            let placeTerms = Set(TextTokenizer.terms(in: place))
            let atPlace = candidates.filter { document in
                guard let name = document.placeName else { return false }
                let nameTerms = Set(TextTokenizer.terms(in: name))
                return !placeTerms.isDisjoint(with: nameTerms)
            }
            if atPlace.isEmpty {
                terms += placeTerms
            } else {
                candidates = atPlace
            }
        }

        guard !candidates.isEmpty else { return [] }

        if terms.isEmpty {
            return candidates
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(limit)
                .map { SearchHit(id: $0.id, score: query.kinds.contains($0.kind) ? 2 : 1) }
                .sorted { $0.score > $1.score }
        }

        let lexical = bm25(terms: terms, documents: candidates)
        let queryVector = embedder?.embed(terms.joined(separator: " ") + " " + query.raw)
        let threshold = embedder?.relevanceThreshold ?? 1

        var hits: [SearchHit] = []
        for (index, document) in candidates.enumerated() {
            let lexicalScore = lexical[index]
            var semantic = 0.0
            if let queryVector, let vector = document.embedding {
                semantic = max(0, VectorMath.cosine(queryVector, vector))
            }
            guard lexicalScore > 0 || semantic >= threshold else { continue }
            var score = lexicalScore + semantic * 2
            if query.kinds.contains(document.kind) {
                score *= 1.5
            }
            hits.append(SearchHit(id: document.id, score: score))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    public func similar(to target: SearchDocument, in documents: [SearchDocument], limit: Int = 10) -> [SearchHit] {
        let targetTerms = Set(fieldTerms(target))
        guard !targetTerms.isEmpty || target.embedding != nil else { return [] }
        var hits: [SearchHit] = []
        for document in documents where document.id != target.id {
            let terms = Set(fieldTerms(document))
            let union = targetTerms.union(terms).count
            let jaccard = union == 0 ? 0 : Double(targetTerms.intersection(terms).count) / Double(union)
            var semantic = 0.0
            if let a = target.embedding, let b = document.embedding {
                semantic = max(0, VectorMath.cosine(a, b))
            }
            let score = jaccard * 0.5 + semantic * 0.5
            let threshold = embedder?.relevanceThreshold ?? 0.25
            guard jaccard >= 0.25 || semantic >= max(threshold, 0.5) else { continue }
            hits.append(SearchHit(id: document.id, score: score))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    private func fieldTerms(_ document: SearchDocument) -> [String] {
        TextTokenizer.terms(in: ([document.title, document.title] + document.tags + document.tags + [document.body]).joined(separator: " "))
    }

    private func bm25(terms: [String], documents: [SearchDocument]) -> [Double] {
        let k1 = 1.2
        let b = 0.75
        let tokenized = documents.map(fieldTerms)
        let averageLength = max(1, Double(tokenized.reduce(0) { $0 + $1.count }) / Double(tokenized.count))
        let queryTerms = Array(Set(terms))
        let count = Double(documents.count)

        var documentFrequency: [String: Double] = [:]
        for term in queryTerms {
            documentFrequency[term] = Double(tokenized.filter { tokens in tokens.contains { Self.matches($0, term) } }.count)
        }

        return tokenized.map { tokens in
            let length = Double(tokens.count)
            var score = 0.0
            for term in queryTerms {
                var frequency = 0.0
                for token in tokens {
                    if token == term {
                        frequency += 1
                    } else if Self.matches(token, term) {
                        frequency += 0.5
                    }
                }
                guard frequency > 0 else { continue }
                let df = documentFrequency[term] ?? 0
                let idf = log(1 + (count - df + 0.5) / (df + 0.5))
                score += idf * (frequency * (k1 + 1)) / (frequency + k1 * (1 - b + b * length / averageLength))
            }
            return score
        }
    }

    private static func matches(_ token: String, _ term: String) -> Bool {
        if token == term { return true }
        guard term.count >= 3, token.count >= 3 else { return false }
        return token.hasPrefix(term) || term.hasPrefix(token)
    }
}
