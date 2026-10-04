import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: ProviderError.invalidResponse)
                }
            }
            task.resume()
        }
    }
}

public enum ProviderError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case unreadableContent
}

public struct RemoteProviderConfiguration: Hashable, Sendable {
    public var baseURL: URL
    public var model: String
    public var apiKey: String?
    public var timeout: TimeInterval

    public init(baseURL: URL, model: String, apiKey: String? = nil, timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
    }
}

public struct OpenAICompatibleIntelligence: IntelligenceProvider {
    public let configuration: RemoteProviderConfiguration
    public let local: OnDeviceIntelligence
    public let client: any HTTPClient

    public init(configuration: RemoteProviderConfiguration, local: OnDeviceIntelligence = OnDeviceIntelligence(), client: any HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.local = local
        self.client = client
    }

    public var identifier: String { "openai-compatible" }

    struct Refinement: Decodable {
        var kind: String?
        var title: String?
        var summary: String?
        var highlights: [String]?
    }

    public func understand(_ input: CaptureInput) async throws -> Understanding {
        let base = try await local.understand(input)
        guard !input.isEmpty else { return base }
        let request = try makeRequest(for: input, base: base)
        let (data, response) = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.httpStatus(response.statusCode)
        }
        let refinement = try Self.parseRefinement(from: data)
        return Self.merge(base, with: refinement)
    }

    func makeRequest(for input: CaptureInput, base: Understanding) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = configuration.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let kinds = MemoryKind.allCases.map(\.rawValue).joined(separator: ", ")
        let system = """
        You turn text a person captured from the real world into a short structured memory. \
        Respond with a single JSON object with keys: "kind" (one of: \(kinds)), "title" (max 8 words), \
        "summary" (one or two sentences stating what matters), "highlights" (array of up to 5 short strings: \
        deadlines, warnings, requirements, or key facts). Use only information present in the input.
        """
        var user = "Source: \(input.source.rawValue)\n"
        if !input.imageLabels.isEmpty {
            user += "Visual labels: \(input.imageLabels.prefix(5).map(\.displayName).joined(separator: ", "))\n"
        }
        user += "Text:\n\(String(input.text.prefix(6000)))"

        let body: [String: Any] = [
            "model": configuration.model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parseRefinement(from data: Data) throws -> Refinement {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProviderError.invalidResponse
        }
        var json = content.trimmed
        if json.hasPrefix("```") {
            json = json
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmed
        }
        if let start = json.firstIndex(of: "{"), let end = json.lastIndex(of: "}"), start < end {
            json = String(json[start...end])
        }
        guard let payload = json.data(using: .utf8),
              let refinement = try? JSONDecoder().decode(Refinement.self, from: payload) else {
            throw ProviderError.unreadableContent
        }
        return refinement
    }

    static func merge(_ base: Understanding, with refinement: Refinement) -> Understanding {
        var result = base
        if let raw = refinement.kind?.lowercased(), let kind = MemoryKind(rawValue: raw) {
            result.kind = kind
        }
        if let title = refinement.title?.trimmed, !title.isEmpty {
            result.title = title.truncated(to: 80)
        }
        if let summary = refinement.summary?.trimmed, !summary.isEmpty {
            result.summary = summary.truncated(to: 400)
        }
        let existing = Set(base.highlights.map { $0.text.lowercased() })
        let additions = (refinement.highlights ?? [])
            .map(\.trimmed)
            .filter { !$0.isEmpty && !existing.contains($0.lowercased()) }
            .prefix(5)
            .map { Highlight(kind: .info, text: $0.truncated(to: 200)) }
        result.highlights += additions
        result.origin = .remote
        return result
    }
}
