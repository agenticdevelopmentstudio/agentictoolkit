import XCTest
@testable import AgenticToolkitCore

final class UTCTimestampTests: XCTestCase {

    func testWritesTheFixedWidthWireInstant() {
        XCTAssertEqual(UTCTimestamp.string(epochSeconds: 0), "1970-01-01T00:00:00Z")
        XCTAssertEqual(UTCTimestamp.string(epochSeconds: 1_790_067_600), "2026-09-22T09:00:00Z")
        XCTAssertEqual(UTCTimestamp.string(epochSeconds: -1), "1969-12-31T23:59:59Z")
    }

    /// A fraction truncates, so an instant never reads later than it happened.
    func testFractionsTruncate() {
        let date = Date(timeIntervalSince1970: 1_790_067_600.999)
        XCTAssertEqual(UTCTimestamp.string(from: date), "2026-09-22T09:00:00Z")
    }

    func testDaysAgoIsWholeDaysBeforeTheReference() {
        let reference = Date(timeIntervalSince1970: 1_790_067_600)
        XCTAssertEqual(UTCTimestamp.string(daysAgo: 14, from: reference), "2026-09-08T09:00:00Z")
    }

    func testTheDayIsTheLocalCalendarDay() throws {
        let instant = 1_790_137_800 // 2026-09-23T04:30:00Z
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        XCTAssertEqual(UTCTimestamp.day(epochSeconds: instant, in: losAngeles), "2026-09-22")
        XCTAssertEqual(UTCTimestamp.day(epochSeconds: instant, in: berlin), "2026-09-23")
    }

    func testReadsEveryStoredShape() {
        XCTAssertEqual(UTCTimestamp.epochSeconds("2026-09-22T09:00:00Z"), 1_790_067_600)
        XCTAssertEqual(UTCTimestamp.epochSeconds("2026-09-22T09:00:00.750Z"), 1_790_067_600)
        XCTAssertEqual(UTCTimestamp.epochSeconds("2026-09-22 09:00:00"), 1_790_067_600)
        XCTAssertEqual(UTCTimestamp.epochSeconds("2026-09-22T11:00:00+02:00"), 1_790_067_600,
                       "an offset falls back to the shared parser")
        XCTAssertNil(UTCTimestamp.epochSeconds("yesterday"))
    }

    func testTheFastPathRefusesWhatItCannotReadExactly() {
        XCTAssertEqual(UTCTimestamp.epochSeconds(fast: "2026-09-22T09:00:00Z"), 1_790_067_600)
        XCTAssertNil(UTCTimestamp.epochSeconds(fast: "2026-09-22T11:00:00+02:00"))
        XCTAssertNil(UTCTimestamp.epochSeconds(fast: "2026-13-22T09:00:00Z"))
    }

    func testCanonicalMakesInstantsComparableAsStrings() {
        XCTAssertEqual(UTCTimestamp.canonical("2026-09-22T14:00:05.999Z"), "2026-09-22T14:00:05Z")
        XCTAssertEqual(UTCTimestamp.canonical("2026-09-22 14:00:05.123"), "2026-09-22T14:00:05Z")
        XCTAssertNil(UTCTimestamp.canonical("yesterday"))
    }

    func testSecondsNeverGoNegative() {
        XCTAssertEqual(UTCTimestamp.seconds(from: "2026-09-22T14:00:00Z", to: "2026-09-22T16:15:00Z"), 8100)
        XCTAssertEqual(UTCTimestamp.seconds(from: "2026-09-22T16:15:00Z", to: "2026-09-22T14:00:00Z"), 0)
        XCTAssertEqual(UTCTimestamp.seconds(from: "nonsense", to: "2026-09-22T14:00:00Z"), 0)
    }

    func testAddingMovesByWholeSeconds() {
        XCTAssertEqual(UTCTimestamp.adding(1, to: "2026-09-22T23:59:59Z"), "2026-09-23T00:00:00Z")
        XCTAssertNil(UTCTimestamp.adding(1, to: "nonsense"))
    }

    func testRoundTripsThroughDate() throws {
        let text = "2026-02-28T23:59:59Z"
        let date = try XCTUnwrap(UTCTimestamp.date(from: text))
        XCTAssertEqual(UTCTimestamp.string(from: date), text)
    }
}
