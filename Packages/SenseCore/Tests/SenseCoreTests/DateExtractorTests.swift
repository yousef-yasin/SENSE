import XCTest
@testable import SenseCore

final class DateExtractorTests: XCTestCase {
    private let extractor = DateExtractor(calendar: Fixture.calendar, prefersDayFirst: false)

    private func extract(_ text: String, options: DateExtractor.Options = []) -> [DetectedDate] {
        extractor.extract(from: text, relativeTo: Fixture.now, options: options)
    }

    func testMonthNameWithTime() {
        let dates = extract("Registration closes October 8 at 4 PM.")
        XCTAssertEqual(dates.count, 1)
        XCTAssertEqual(dates.first?.date, Fixture.date(2026, 10, 8, 16, 0))
        XCTAssertEqual(dates.first?.includesTime, true)
        XCTAssertEqual(dates.first?.text, "October 8 at 4 PM")
    }

    func testAbbreviatedMonthWithOrdinalAndYear() {
        let dates = extract("Due: Oct. 12th, 2026")
        XCTAssertEqual(dates.first?.date, Fixture.date(2026, 10, 12))
        XCTAssertEqual(dates.first?.includesTime, false)
    }

    func testDayBeforeMonth() {
        XCTAssertEqual(extract("Submit by 15 November").first?.date, Fixture.date(2026, 11, 15))
    }

    func testTimeBeforeDate() {
        let date = extract("Doors open 6:30pm on Friday, October 9").first
        XCTAssertEqual(date?.date, Fixture.date(2026, 10, 9, 18, 30))
    }

    func testWeekdayNextToDateIsNotCountedTwice() {
        let dates = extract("Thursday, October 8")
        XCTAssertEqual(dates.count, 1)
        XCTAssertEqual(dates.first?.date, Fixture.date(2026, 10, 8))
    }

    func testNumericDates() {
        XCTAssertEqual(extract("Date: 10/02/2026 14:32").first?.date, Fixture.date(2026, 10, 2, 14, 32))
        XCTAssertEqual(extract("2026-11-20").first?.date, Fixture.date(2026, 11, 20))
        XCTAssertEqual(extract("expires 25/12/2026").first?.date, Fixture.date(2026, 12, 25))
    }

    func testDayFirstLocale() {
        let dayFirst = DateExtractor(calendar: Fixture.calendar, prefersDayFirst: true)
        XCTAssertEqual(dayFirst.extract(from: "03/11/2026", relativeTo: Fixture.now).first?.date, Fixture.date(2026, 11, 3))
    }

    func testYearInferencePicksNearestOccurrence() {
        XCTAssertEqual(extract("January 15").first?.date, Fixture.date(2027, 1, 15))
        XCTAssertEqual(extract("September 20").first?.date, Fixture.date(2026, 9, 20))
    }

    func testRelativeDays() {
        XCTAssertEqual(extract("tomorrow at 5pm").first?.date, Fixture.date(2026, 10, 5, 17, 0))
        XCTAssertEqual(extract("tonight").first?.date, Fixture.date(2026, 10, 4, 20, 0))
        XCTAssertEqual(extract("the day after tomorrow").first?.date, Fixture.date(2026, 10, 6))
        XCTAssertEqual(extract("tomorrow morning").first?.date, Fixture.date(2026, 10, 5, 9, 0))
    }

    func testWeekdays() {
        XCTAssertEqual(extract("on Friday").first?.date, Fixture.date(2026, 10, 9))
        XCTAssertEqual(extract("next Sunday").first?.date, Fixture.date(2026, 10, 11))
        XCTAssertEqual(extract("this Sunday").first?.date, Fixture.date(2026, 10, 4))
    }

    func testDurations() {
        XCTAssertEqual(extract("in 2 hours").first?.date, Fixture.now.addingTimeInterval(7200))
        XCTAssertEqual(extract("in half an hour").first?.date, Fixture.now.addingTimeInterval(1800))
        XCTAssertEqual(extract("in three days").first?.date, Fixture.date(2026, 10, 7))
    }

    func testStandaloneTimesOnlyWhenRequested() {
        XCTAssertTrue(extract("Office hours 9:00").isEmpty)
        XCTAssertEqual(extract("at 5", options: .standaloneTimes).first?.date, Fixture.date(2026, 10, 4, 17, 0))
        XCTAssertEqual(extract("at 8:15 am", options: .standaloneTimes).first?.date, Fixture.date(2026, 10, 5, 8, 15))
    }

    func testRejectsInvalidDatesAndPrices() {
        XCTAssertTrue(extract("February 31").isEmpty)
        XCTAssertTrue(extract("Total 12.30").isEmpty)
        XCTAssertTrue(extract("Rated 4.5 stars").isEmpty)
    }
}
