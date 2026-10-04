import XCTest
@testable import SenseCore

final class ContentAnalyzerTests: XCTestCase {
    private let analyzer = ContentAnalyzer(calendar: Fixture.calendar, prefersDayFirst: false)

    private func analyze(_ text: String, source: CaptureSource = .camera, labels: [ImageLabel] = []) -> Understanding {
        analyzer.analyze(CaptureInput(source: source, text: text, imageLabels: labels), now: Fixture.now)
    }

    func testAnnouncementProducesDeadlineReminder() {
        let result = analyze("""
        FALL SEMESTER REGISTRATION
        Registration closes October 8 at 4 PM.
        Students must bring their ID card to the registrar office.
        """)

        XCTAssertEqual(result.kind, .announcement)
        XCTAssertEqual(result.title, "Fall Semester Registration")

        let deadline = result.highlights.first { $0.kind == .deadline }
        XCTAssertEqual(deadline?.text, "Registration closes October 8 at 4 PM.")
        XCTAssertEqual(deadline?.date, Fixture.date(2026, 10, 8, 16, 0))
        XCTAssertTrue(result.highlights.contains { $0.kind == .requirement })

        let reminder = result.reminderSuggestions.first
        XCTAssertEqual(reminder?.title, "Registration closes")
        XCTAssertEqual(reminder?.dueDate, Fixture.date(2026, 10, 8, 16, 0))
        XCTAssertEqual(reminder?.timing, .at(Fixture.date(2026, 10, 7, 16, 0)))
    }

    func testReceiptExtraction() {
        let result = analyze("""
        BLUE BEAN CAFE
        123 Main Street
        Date: 10/02/2026 14:32
        Latte 4.50
        Croissant 3.25
        Subtotal 7.75
        Tax 0.62
        TOTAL $8.37
        VISA ****1234
        """, source: .photo)

        XCTAssertEqual(result.kind, .receipt)
        XCTAssertEqual(result.title, "Blue Bean Cafe")
        XCTAssertTrue(result.summary.contains("$8.37"))
        XCTAssertTrue(result.entities.contains { $0.kind == .merchant && $0.text == "Blue Bean Cafe" })
        XCTAssertTrue(result.entities.contains { $0.kind == .date && $0.date == Fixture.date(2026, 10, 2, 14, 32) })
        XCTAssertTrue(result.entities.contains { $0.kind == .money && $0.value == "8.37 USD" })
        XCTAssertTrue(result.reminderSuggestions.isEmpty)
    }

    func testDocumentWarningsAndRequirements() {
        let result = analyze("""
        Lab Safety Guidelines
        Do not eat or drink in the laboratory.
        Safety goggles are required at all times.
        Reports are due November 2.
        """)

        XCTAssertTrue(result.highlights.contains { $0.kind == .warning && $0.text.hasPrefix("Do not eat") })
        XCTAssertTrue(result.highlights.contains { $0.kind == .requirement && $0.text.contains("goggles") })
        XCTAssertTrue(result.highlights.contains { $0.kind == .deadline && $0.date == Fixture.date(2026, 11, 2) })
        XCTAssertEqual(result.reminderSuggestions.first?.timing, .at(Fixture.date(2026, 11, 1, 9, 0)))
    }

    func testEventClassification() {
        let result = analyze("Robotics workshop\nSaturday October 10, 2:00 PM in Hall B")
        XCTAssertEqual(result.kind, .event)
        XCTAssertEqual(result.reminderSuggestions.first?.dueDate, Fixture.date(2026, 10, 10, 14, 0))
    }

    func testObjectFromImageLabels() {
        let result = analyze("", labels: [
            ImageLabel(identifier: "circuit_board", confidence: 0.82),
            ImageLabel(identifier: "electronics", confidence: 0.77)
        ])
        XCTAssertEqual(result.kind, .object)
        XCTAssertEqual(result.title, "Circuit Board")
        XCTAssertEqual(result.summary, "Circuit Board, Electronics")
        XCTAssertTrue(result.tags.contains("electronics"))
    }

    func testContactSuggestions() {
        let result = analyze("Questions? Email help@campus.edu or call +1 555 010 2030. Details at www.campus.edu/register")
        XCTAssertTrue(result.suggestions.contains(.email("help@campus.edu")))
        XCTAssertTrue(result.suggestions.contains(.call("+1 555 010 2030")))
        XCTAssertTrue(result.suggestions.contains(.openLink(URL(string: "https://www.campus.edu/register")!)))
    }

    func testTypedTaskNote() {
        XCTAssertEqual(analyze("Buy resistors for the lab kit", source: .text).kind, .task)
        XCTAssertEqual(analyze("The parking lot behind building C is free after 6", source: .text).kind, .note)
    }

    func testPastDatesDoNotCreateReminders() {
        let result = analyze("Registration closed on September 30.")
        XCTAssertTrue(result.reminderSuggestions.isEmpty)
    }
}
