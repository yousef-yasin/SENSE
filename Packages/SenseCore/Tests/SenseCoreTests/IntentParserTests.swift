import XCTest
@testable import SenseCore

final class IntentParserTests: XCTestCase {
    private let parser = IntentParser(calendar: Fixture.calendar, prefersDayFirst: false)

    private func parse(_ text: String) -> UserIntent {
        parser.parse(text, now: Fixture.now)
    }

    func testLocationReminderReferringToContext() {
        XCTAssertEqual(
            parse("Remind me about this when I get to the university."),
            .remind(ReminderDraft(title: "", timing: .arriving("university"), refersToContext: true))
        )
    }

    func testTimedReminder() {
        XCTAssertEqual(
            parse("Remind me to call the lab tomorrow at 5"),
            .remind(ReminderDraft(title: "Call the lab", timing: .at(Fixture.date(2026, 10, 5, 17, 0)), dueDate: Fixture.date(2026, 10, 5, 17, 0)))
        )
    }

    func testReminderWithLeadingTime() {
        guard case .remind(let draft) = parse("remind me at 6pm to water the plants") else {
            return XCTFail("Expected reminder")
        }
        XCTAssertEqual(draft.title, "Water the plants")
        XCTAssertEqual(draft.timing, .at(Fixture.date(2026, 10, 4, 18, 0)))
    }

    func testDateOnlyReminderUsesMorning() {
        guard case .remind(let draft) = parse("Remind me to pay rent on Friday") else {
            return XCTFail("Expected reminder")
        }
        XCTAssertEqual(draft.title, "Pay rent")
        XCTAssertEqual(draft.timing, .at(Fixture.date(2026, 10, 9, 9, 0)))
    }

    func testArrivalAndDepartureReminders() {
        XCTAssertEqual(parse("Remind me to buy milk when I'm at the supermarket"),
                       .remind(ReminderDraft(title: "Buy milk", timing: .arriving("supermarket"))))
        XCTAssertEqual(parse("remind me to lock the door when I leave home"),
                       .remind(ReminderDraft(title: "Lock the door", timing: .leaving("home"))))
        XCTAssertEqual(parse("remind me to charge my laptop when I get home"),
                       .remind(ReminderDraft(title: "Charge my laptop", timing: .arriving("home"))))
        XCTAssertEqual(parse("Remind me to return the book at the library"),
                       .remind(ReminderDraft(title: "Return the book", timing: .arriving("library"))))
    }

    func testCurlyApostrophes() {
        XCTAssertEqual(parse("Don\u{2019}t let me forget to submit the form when I\u{2019}m at work"),
                       .remind(ReminderDraft(title: "Submit the form", timing: .arriving("work"))))
    }

    func testRecallAndAnalyze() {
        XCTAssertEqual(parse("Have I seen this before?"), .recallSimilar)
        XCTAssertEqual(parse("did I already capture this"), .recallSimilar)
        XCTAssertEqual(parse("What's important here?"), .analyzeSurroundings)
        XCTAssertEqual(parse("What does this say"), .analyzeSurroundings)
    }

    func testSearchQuestions() {
        XCTAssertEqual(parse("What was that electronics component I saw last week?"),
                       .search("What was that electronics component I saw last week?"))
        XCTAssertEqual(parse("Did I already see this product?"), .recallSimilar)
        XCTAssertEqual(parse("Where was that announcement about registration?"),
                       .search("Where was that announcement about registration?"))
    }

    func testPlainCapture() {
        XCTAssertEqual(parse("The blue door code is 4471"), .capture("The blue door code is 4471"))
    }
}
