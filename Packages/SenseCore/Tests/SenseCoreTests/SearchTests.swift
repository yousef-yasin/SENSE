import XCTest
@testable import SenseCore

final class SearchTests: XCTestCase {
    private let queryParser = QueryParser(calendar: Fixture.calendar)
    private let engine = MemorySearchEngine(embedder: HashingEmbedder())

    private func document(_ title: String, _ body: String, kind: MemoryKind = .note, daysAgo: Int = 0, place: String? = nil, tags: [String] = []) -> SearchDocument {
        var doc = SearchDocument(
            id: UUID(),
            title: title,
            body: body,
            tags: tags,
            kind: kind,
            createdAt: Fixture.now.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            placeName: place,
            embedding: nil
        )
        doc.embedding = HashingEmbedder().embed(doc.embeddingText)
        return doc
    }

    func testQueryParserExtractsFilters() {
        let query = queryParser.parse("What did I capture at the university yesterday?", now: Fixture.now)
        XCTAssertEqual(query.place, "university")
        XCTAssertEqual(query.dateInterval, DateInterval(start: Fixture.date(2026, 10, 3), end: Fixture.date(2026, 10, 4)))
        XCTAssertTrue(query.terms.isEmpty)
    }

    func testQueryParserLastWeekAndTerms() {
        let query = queryParser.parse("What was that electronics component I saw last week?", now: Fixture.now)
        XCTAssertEqual(query.dateInterval, DateInterval(start: Fixture.date(2026, 9, 27), end: Fixture.date(2026, 10, 4)))
        XCTAssertEqual(query.terms, ["electronic", "component"])
    }

    func testQueryParserKinds() {
        let query = queryParser.parse("Where was that announcement about registration?", now: Fixture.now)
        XCTAssertEqual(query.kinds, [.announcement])
        XCTAssertEqual(query.terms, ["registration"])
        XCTAssertNil(query.place)
    }

    func testKeywordSearchRanksRelevantMemoryFirst() {
        let registration = document("Fall Registration", "Registration closes October 8 at 4 PM.", kind: .announcement, daysAgo: 2)
        let receipt = document("Blue Bean Cafe", "Latte 4.50 Total 8.37", kind: .receipt, daysAgo: 1)
        let resistor = document("Resistor Kit", "Electronic components: resistors, capacitors", kind: .object, daysAgo: 5, tags: ["electronics"])

        let hits = engine.search(queryParser.parse("Where was that announcement about registration?", now: Fixture.now), in: [receipt, resistor, registration])
        XCTAssertEqual(hits.first?.id, registration.id)
        XCTAssertFalse(hits.contains { $0.id == receipt.id })

        let componentHits = engine.search(queryParser.parse("electronics component", now: Fixture.now), in: [receipt, resistor, registration])
        XCTAssertEqual(componentHits.first?.id, resistor.id)
    }

    func testFilterOnlyQueryReturnsMatchingPlaceAndDay() {
        let atUniversity = document("Lab schedule", "Lab moved to room 204", daysAgo: 1, place: "University of Jordan")
        let atHome = document("Groceries", "Eggs and bread", daysAgo: 1, place: "Home")
        let olderAtUniversity = document("Parking", "Lot C closed", daysAgo: 4, place: "University of Jordan")

        let hits = engine.search(queryParser.parse("What did I capture at the university yesterday?", now: Fixture.now), in: [atUniversity, atHome, olderAtUniversity])
        XCTAssertEqual(hits.map(\.id), [atUniversity.id])
    }

    func testUnknownPlaceFallsBackToKeywords() {
        let memory = document("Library hours", "The library opens at 8", daysAgo: 0)
        let hits = engine.search(queryParser.parse("what did I see at the library", now: Fixture.now), in: [memory])
        XCTAssertEqual(hits.first?.id, memory.id)
    }

    func testNoMatchesReturnsEmpty() {
        let memory = document("Blue Bean Cafe", "Latte", kind: .receipt)
        XCTAssertTrue(engine.search(queryParser.parse("quantum physics lecture", now: Fixture.now), in: [memory]).isEmpty)
    }

    func testSimilarFindsRelatedCapture() {
        let first = document("Arduino Uno board", "Arduino Uno microcontroller board with USB", kind: .object, daysAgo: 6, tags: ["electronics"])
        let unrelated = document("Groceries", "Eggs bread milk", daysAgo: 3)
        let again = document("Arduino Uno", "Arduino Uno board", kind: .object, tags: ["electronics"])

        let hits = engine.similar(to: again, in: [first, unrelated, again])
        XCTAssertEqual(hits.map(\.id), [first.id])
    }

    func testEmbeddingRoundTrip() {
        let vector = HashingEmbedder().embed("registration deadline")!
        XCTAssertEqual(VectorMath.decode(VectorMath.encode(vector)), vector)
        XCTAssertEqual(VectorMath.cosine(vector, vector), 1, accuracy: 0.0001)
    }

    func testStemming() {
        XCTAssertEqual(TextTokenizer.stem("components"), TextTokenizer.stem("component"))
        XCTAssertEqual(TextTokenizer.stem("captured"), TextTokenizer.stem("capture"))
        XCTAssertEqual(TextTokenizer.stem("batteries"), "battery")
        XCTAssertEqual(TextTokenizer.stem("boxes"), "box")
    }
}
