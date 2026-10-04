import Foundation
import NaturalLanguage
import SenseCore

final class SentenceEmbedder: TextEmbedder, @unchecked Sendable {
    private static let semanticDimension = 512
    private static let lexicalWeight = Float(0.6).squareRoot()
    private static let semanticWeight = Float(0.4).squareRoot()

    private let hashing = HashingEmbedder()
    private let embedding: NLEmbedding?
    private let lock = NSLock()
    let identifier: String

    init(language: NLLanguage = .english) {
        embedding = NLEmbedding.sentenceEmbedding(for: language)
        if embedding != nil {
            identifier = "\(hashing.identifier)+nl-\(language.rawValue)-\(NLEmbedding.currentSentenceEmbeddingRevision(for: language))"
        } else {
            identifier = hashing.identifier
        }
    }

    var relevanceThreshold: Double {
        embedding == nil ? hashing.relevanceThreshold : 0.42
    }

    func embed(_ text: String) -> [Float]? {
        guard let lexical = hashing.embed(text) else { return nil }
        guard let embedding else { return lexical }

        let semantic = lock.withLock { embedding.vector(for: String(text.prefix(1_000))) }
        var semanticPart = VectorMath.normalized((semantic ?? []).map(Float.init))
        if semanticPart.count > Self.semanticDimension {
            semanticPart = Array(semanticPart.prefix(Self.semanticDimension))
        } else if semanticPart.count < Self.semanticDimension {
            semanticPart += [Float](repeating: 0, count: Self.semanticDimension - semanticPart.count)
        }
        return lexical.map { $0 * Self.lexicalWeight } + semanticPart.map { $0 * Self.semanticWeight }
    }
}
