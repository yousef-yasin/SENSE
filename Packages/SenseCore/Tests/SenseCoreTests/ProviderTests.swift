import XCTest
@testable import SenseCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ProviderTests: XCTestCase {
    private struct StubClient: HTTPClient {
        let status: Int
        let body: String

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    private struct FailingClient: HTTPClient {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            throw URLError(.notConnectedToInternet)
        }
    }

    private let configuration = RemoteProviderConfiguration(baseURL: URL(string: "http://localhost:11434/v1")!, model: "llama3.2", apiKey: "test-key")
    private let input = CaptureInput(source: .camera, text: "Registration closes October 8 at 4 PM.")

    private func chatResponse(_ content: String) -> String {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return #"{"choices":[{"message":{"role":"assistant","content":"\#(escaped)"}}]}"#
    }

    func testRefinementMergesWithLocalUnderstanding() async throws {
        let content = """
        ```json
        {"kind":"announcement","title":"Registration deadline","summary":"Registration closes Oct 8 at 4 PM.","highlights":["Bring your student ID"]}
        ```
        """
        let provider = OpenAICompatibleIntelligence(configuration: configuration, client: StubClient(status: 200, body: chatResponse(content)))
        let result = try await provider.understand(input)

        XCTAssertEqual(result.origin, .remote)
        XCTAssertEqual(result.kind, .announcement)
        XCTAssertEqual(result.title, "Registration deadline")
        XCTAssertTrue(result.highlights.contains { $0.kind == .info && $0.text == "Bring your student ID" })
        XCTAssertTrue(result.entities.contains { $0.kind == .date })
    }

    func testRequestShape() throws {
        let provider = OpenAICompatibleIntelligence(configuration: configuration, client: FailingClient())
        let request = try provider.makeRequest(for: input, base: Understanding(kind: .note, title: "", summary: ""))
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "llama3.2")
    }

    func testFallsBackToOnDeviceWhenProviderFails() async throws {
        let remote = OpenAICompatibleIntelligence(configuration: configuration, client: FailingClient())
        let provider = ResilientIntelligence(primary: remote)
        let result = try await provider.understand(input)
        XCTAssertEqual(result.origin, .onDeviceFallback)
        XCTAssertFalse(result.highlights.isEmpty)
    }

    func testHTTPErrorFallsBack() async throws {
        let remote = OpenAICompatibleIntelligence(configuration: configuration, client: StubClient(status: 401, body: "{}"))
        let result = try await ResilientIntelligence(primary: remote).understand(input)
        XCTAssertEqual(result.origin, .onDeviceFallback)
    }

    func testUnreadableContentIsRejected() {
        XCTAssertThrowsError(try OpenAICompatibleIntelligence.parseRefinement(from: Data(chatResponse("not json").utf8)))
    }

    func testIgnoresUnknownKind() {
        let base = Understanding(kind: .note, title: "A", summary: "B")
        let merged = OpenAICompatibleIntelligence.merge(base, with: .init(kind: "spaceship", title: nil, summary: nil, highlights: nil))
        XCTAssertEqual(merged.kind, .note)
        XCTAssertEqual(merged.title, "A")
    }
}
