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
}
