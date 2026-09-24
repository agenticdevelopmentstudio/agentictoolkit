import XCTest
@testable import AgenticToolkitCore

final class DurationFormatterTests: XCTestCase {

    func testHoursMinutes() {
        XCTAssertEqual(DurationFormatter.hoursMinutes(seconds: 0), "0m")
        XCTAssertEqual(DurationFormatter.hoursMinutes(seconds: 59), "0m")
        XCTAssertEqual(DurationFormatter.hoursMinutes(seconds: 60), "1m")
        XCTAssertEqual(DurationFormatter.hoursMinutes(seconds: 900), "15m")
        XCTAssertEqual(DurationFormatter.hoursMinutes(seconds: 3600), "1h")
        XCTAssertEqual(DurationFormatter.hoursMinutes(seconds: 8100), "2h 15m")
        XCTAssertEqual(DurationFormatter.hoursMinutes(seconds: 90_000), "25h")
    }

    /// The transcribable form: what gets typed into the client's tool.
    func testDecimalHours() {
        XCTAssertEqual(DurationFormatter.decimalHours(seconds: 900), "0.25")
        XCTAssertEqual(DurationFormatter.decimalHours(seconds: 8100), "2.25")
        XCTAssertEqual(DurationFormatter.decimalHours(seconds: 3600), "1.00")
        XCTAssertEqual(DurationFormatter.decimalHours(seconds: 0), "0.00")
    }

    func testDecimalHoursRoundsHalfUp() {
        // 1 second = 0.000277… h → 0.00 at two places.
        XCTAssertEqual(DurationFormatter.decimalHours(seconds: 1), "0.00")
        // 18 seconds = 0.005 h → 0.01 at two places (half-up).
        XCTAssertEqual(DurationFormatter.decimalHours(seconds: 18), "0.01")
    }

    /// The running-timer form.
    func testClock() {
        XCTAssertEqual(DurationFormatter.clock(seconds: 0), "0:00:00")
        XCTAssertEqual(DurationFormatter.clock(seconds: 61), "0:01:01")
        XCTAssertEqual(DurationFormatter.clock(seconds: 8100), "2:15:00")
        XCTAssertEqual(DurationFormatter.clock(seconds: 360_000), "100:00:00")
    }

    /// Negative input is a caller bug, not a reason to print nonsense.
    func testNegativeSecondsClampToZero() {
        XCTAssertEqual(DurationFormatter.hoursMinutes(seconds: -1), "0m")
        XCTAssertEqual(DurationFormatter.decimalHours(seconds: -1), "0.00")
        XCTAssertEqual(DurationFormatter.clock(seconds: -1), "0:00:00")
    }

    /// The forms people type into an hours cell.
    func testSecondsParsingAcceptsTheCommonForms() {
        XCTAssertEqual(DurationFormatter.seconds(parsing: "1.5"), 5400)
        XCTAssertEqual(DurationFormatter.seconds(parsing: "0.25"), 900)
        XCTAssertEqual(DurationFormatter.seconds(parsing: ".5"), 1800)
        XCTAssertEqual(DurationFormatter.seconds(parsing: "2"), 7200)
        XCTAssertEqual(DurationFormatter.seconds(parsing: "1,5"), 5400, "a comma is a decimal point in most of Europe")
        XCTAssertEqual(DurationFormatter.seconds(parsing: "1:30"), 5400)
        XCTAssertEqual(DurationFormatter.seconds(parsing: "1h 30m"), 5400)
        XCTAssertEqual(DurationFormatter.seconds(parsing: "1h30m"), 5400)
        XCTAssertEqual(DurationFormatter.seconds(parsing: "2h"), 7200)
        XCTAssertEqual(DurationFormatter.seconds(parsing: "90m"), 5400)
        XCTAssertEqual(DurationFormatter.seconds(parsing: " 45M "), 2700)
        XCTAssertEqual(DurationFormatter.seconds(parsing: "0"), 0)
    }

    /// Fractions of an hour round half-up to the second, in integers.
    func testSecondsParsingRoundsFractionsHalfUp() {
        // 0.333 h = 1198.8 s → 1199.
        XCTAssertEqual(DurationFormatter.seconds(parsing: "0.333"), 1199)
        // 0.1 h is exactly 360 s.
        XCTAssertEqual(DurationFormatter.seconds(parsing: "0.1"), 360)
    }

    func testSecondsParsingRefusesWhatIsNotADuration() {
        for text in ["", "  ", "-1", "abc", "1.2.3", ".", "h", "m", "1:5", "1:75", "1m30", "1.5h", "1234567"] {
            XCTAssertNil(DurationFormatter.seconds(parsing: text), "\(text.debugDescription) is not a duration")
        }
    }
}
