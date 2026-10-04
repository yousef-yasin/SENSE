import Foundation

public protocol TextEmbedder: Sendable {
    var identifier: String { get }
    var relevanceThreshold: Double { get }
    func embed(_ text: String) -> [Float]?
}

public enum VectorMath {
    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return Double(dot / (normA.squareRoot() * normB.squareRoot()))
    }

    public static func normalized(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    public static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decode(_ data: Data) -> [Float] {
        guard data.count % MemoryLayout<Float>.stride == 0 else { return [] }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
}

public struct HashingEmbedder: TextEmbedder {
    public let dimension: Int

    public init(dimension: Int = 384) {
        self.dimension = dimension
    }

    public var identifier: String { "hashing-\(dimension)-v1" }
    public var relevanceThreshold: Double { 0.32 }

    public func embed(_ text: String) -> [Float]? {
        let terms = TextTokenizer.terms(in: text)
        guard !terms.isEmpty else { return nil }
        var vector = [Float](repeating: 0, count: dimension)
        for term in terms {
            add(term, weight: 1.0, to: &vector)
            let padded = Array("<\(term)>")
            if padded.count > 4 {
                for start in 0...(padded.count - 3) {
                    add(String(padded[start..<(start + 3)]), weight: 0.35, to: &vector)
                }
            }
        }
        return VectorMath.normalized(vector)
    }

    private func add(_ feature: String, weight: Float, to vector: inout [Float]) {
        let hash = Self.fnv1a(feature)
        let index = Int(hash % UInt64(dimension))
        let sign: Float = (hash >> 63) == 0 ? 1 : -1
        vector[index] += sign * weight
    }

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
