import XCTest
@testable import AgenticToolkitCore

/// The one shared timestamp parser: every shape that appears across the daemon, app,
/// and CLI must parse — including the SQLite `datetime()` form (UTC, space-separated)
/// that the old per-site ISO-only parsers silently rejected.
final class TimestampParsingTests: XCTestCase {

    func testFractionalMatchesPlainPlusFraction() throws {
        let fractional = try XCTUnwrap(TimestampParsing.parse("2026-04-14T10:00:00.500Z"))
        let plain = try XCTUnwrap(TimestampParsing.parse("2026-04-14T10:00:00Z"))
        XCTAssertEqual(fractional.timeIntervalSince(plain), 0.5, accuracy: 0.001)
    }

    func testSQLiteDateTimeParsedAsUTC() throws {
        // Space-separated, no zone — what SQLite datetime() stores. It must parse, and
        // as UTC (matching how the DB writes it), i.e. the same instant as the Z form —
        // not reinterpreted in the device's local zone.
        let sqlite = try XCTUnwrap(TimestampParsing.parse("2026-04-14 10:00:00"))
        let iso = try XCTUnwrap(TimestampParsing.parse("2026-04-14T10:00:00Z"))
        XCTAssertEqual(sqlite, iso, "SQLite datetime() form is UTC, the same instant as the Z form")
    }

    func testEmptyAndGarbageAreNil() {
        XCTAssertNil(TimestampParsing.parse(""))
        XCTAssertNil(TimestampParsing.parse("not a date"))
        XCTAssertNil(TimestampParsing.parse("2026-13-99"))
    }
}
