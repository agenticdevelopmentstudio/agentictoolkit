import XCTest
@testable import AgenticToolkitCore

final class LocalTimeTextTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let unitedStates = Locale(identifier: "en_US")
    private let britain = Locale(identifier: "en_GB")
    private typealias Clock = LocalTimeText.Clock

    func testTheClockFollowsTheLocale() {
        let date = Date(timeIntervalSince1970: 1_790_085_900) // 2026-09-22T14:05:00Z
        XCTAssertTrue(LocalTimeText.uses12HourClock(unitedStates))
        XCTAssertFalse(LocalTimeText.uses12HourClock(britain))
        XCTAssertTrue(LocalTimeText.clock(date, timeZone: utc, locale: unitedStates).hasPrefix("2:05"))
        XCTAssertEqual(LocalTimeText.clock(date, timeZone: utc, locale: britain), "14:05")
    }

    func testEitherClockIsAcceptedWhenTyped() {
        XCTAssertEqual(LocalTimeText.clocks(parsing: "2:05 PM", locale: britain), [Clock(hour: 14, minute: 5)])
        XCTAssertEqual(LocalTimeText.clocks(parsing: "2pm", locale: britain), [Clock(hour: 14, minute: 0)])
        XCTAssertEqual(LocalTimeText.clocks(parsing: "14:05", locale: unitedStates), [Clock(hour: 14, minute: 5)])
        XCTAssertEqual(LocalTimeText.clocks(parsing: "not a time", locale: unitedStates), [])
    }

    /// In a 12-hour locale a bare `2:05` could be either end of the day.
    func testABareTimeIsAmbiguousOnlyOnATwelveHourClock() {
        XCTAssertEqual(
            LocalTimeText.clocks(parsing: "2:05", locale: unitedStates),
            [Clock(hour: 2, minute: 5), Clock(hour: 14, minute: 5)]
        )
        XCTAssertEqual(LocalTimeText.clocks(parsing: "2:05", locale: britain), [Clock(hour: 2, minute: 5)])
    }

    /// A time typed over one shown past midnight means the same stretch of time.
    func testTheNearestInstantMayFallOnTheNextDay() {
        let reference = Date(timeIntervalSince1970: 1_790_121_300) // 2026-09-22T23:55:00Z
        let chosen = LocalTimeText.instant(nearest: reference, clocks: [Clock(hour: 0, minute: 10)], timeZone: utc)
        XCTAssertEqual(chosen, Date(timeIntervalSince1970: 1_790_122_200)) // 2026-09-23T00:10:00Z
    }

    func testStartOfDayAndSeconds() throws {
        let start = try XCTUnwrap(LocalTimeText.startOfDay("2026-09-22", timeZone: utc))
        XCTAssertEqual(start, Date(timeIntervalSince1970: 1_790_035_200))
        XCTAssertNil(LocalTimeText.startOfDay("someday", timeZone: utc))
        XCTAssertEqual(LocalTimeText.seconds(from: start, to: start.addingTimeInterval(3_600)), 3_600)
    }
}
