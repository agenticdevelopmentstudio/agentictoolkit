import XCTest
@testable import AgenticToolkitCore

final class BillingRoundingTests: XCTestCase {

    // MARK: - Rounding

    func testRoundUpToTheNextIncrement() {
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 1, roundingMinutes: 15, mode: "up"), 900)
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 900, roundingMinutes: 15, mode: "up"), 900)
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 901, roundingMinutes: 15, mode: "up"), 1800)
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 8100, roundingMinutes: 15, mode: "up"), 8100)
    }

    func testRoundToNearestIncrementHalfUp() {
        // 7 minutes → 0 (below the half-way 7.5)
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 420, roundingMinutes: 15, mode: "nearest"), 0)
        // exactly 7.5 minutes → 15
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 450, roundingMinutes: 15, mode: "nearest"), 900)
        // 8 minutes → 15
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 480, roundingMinutes: 15, mode: "nearest"), 900)
    }

    /// Zero minutes means "don't round" — the raw seconds are the billed
    /// seconds. Not "round to zero", which would bill nothing for everything.
    func testZeroIncrementDoesNotRound() {
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 437, roundingMinutes: 0, mode: "up"), 437)
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 437, roundingMinutes: -5, mode: "up"), 437)
    }

    func testZeroRawSecondsRoundsToZeroNotOneIncrement() {
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 0, roundingMinutes: 15, mode: "up"), 0)
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: -5, roundingMinutes: 15, mode: "up"), 0)
    }

    /// An unrecognised mode behaves as "up" — the default — rather than
    /// silently billing nothing.
    func testUnknownModeFallsBackToUp() {
        XCTAssertEqual(BillingRounding.billedSeconds(rawSeconds: 1, roundingMinutes: 15, mode: "sideways"), 900)
    }

    /// The double-rounding trap: five separate five-minute bursts rounded
    /// individually would bill 75 minutes. Rounded once, as an entry, 25 raw
    /// minutes bill 30.
    func testRoundingOncePerEntryNotPerSegment() {
        let segments = Array(repeating: 300, count: 5)
        let perSegment = segments
            .map { BillingRounding.billedSeconds(rawSeconds: $0, roundingMinutes: 15, mode: "up") }
            .reduce(0, +)
        let perEntry = BillingRounding.billedSeconds(
            rawSeconds: segments.reduce(0, +), roundingMinutes: 15, mode: "up"
        )
        XCTAssertEqual(perSegment, 4500, "the wrong way bills 75 minutes")
        XCTAssertEqual(perEntry, 1800, "the right way bills 30")
    }

    // MARK: - Clock

    func testLocalDayUsesTheSegmentsOwnZone() {
        // 2026-09-23T04:30Z is still the 22nd in Los Angeles.
        XCTAssertEqual(
            BillingClock.localDay(utc: "2026-09-23T04:30:00Z", tz: "America/Los_Angeles"),
            "2026-09-22"
        )
        XCTAssertEqual(
            BillingClock.localDay(utc: "2026-09-23T04:30:00Z", tz: "Europe/Berlin"),
            "2026-09-23"
        )
    }

    /// An unknown or empty zone falls back to UTC rather than the host's
    /// current zone, which would make the answer depend on where the reader is.
    func testLocalDayFallsBackToUTCForAnUnknownZone() {
        XCTAssertEqual(BillingClock.localDay(utc: "2026-09-23T04:30:00Z", tz: ""), "2026-09-23")
        XCTAssertEqual(BillingClock.localDay(utc: "2026-09-23T04:30:00Z", tz: "Mars/Olympus"), "2026-09-23")
    }

    func testSecondsBetweenTimestamps() {
        XCTAssertEqual(
            UTCTimestamp.seconds(from: "2026-09-22T14:00:00Z", to: "2026-09-22T16:15:00Z"), 8100
        )
        XCTAssertEqual(
            UTCTimestamp.seconds(from: "2026-09-22T16:15:00Z", to: "2026-09-22T14:00:00Z"), 0,
            "a backwards pair is zero, never negative"
        )
        XCTAssertEqual(UTCTimestamp.seconds(from: "nonsense", to: "2026-09-22T14:00:00Z"), 0)
    }

    func testUTCStringRoundTrips() throws {
        let text = "2026-09-22T14:00:00Z"
        let date = try XCTUnwrap(UTCTimestamp.date(from: text))
        XCTAssertEqual(UTCTimestamp.string(from: date), text)
    }
}

/// Which day a segment lands on. A segment buckets by the local day of its
/// *start*, in its *own* zone — never the reader's — and its length is plain
/// UTC arithmetic, so a DST change can't add or drop an hour.
final class BillingDayBucketingTests: XCTestCase {

    /// 23:30–00:30 in Los Angeles is one segment on the 22nd, not half a
    /// segment on each day.
    func testASegmentSpanningLocalMidnightBucketsByItsLocalStart() {
        let start = "2026-09-23T06:30:00Z"  // 23:30 PDT on the 22nd
        let end = "2026-09-23T07:30:00Z"    // 00:30 PDT on the 23rd
        XCTAssertEqual(BillingClock.localDay(utc: start, tz: "America/Los_Angeles"), "2026-09-22")
        XCTAssertEqual(UTCTimestamp.seconds(from: start, to: end), 3600)
        // The same instant in Berlin is the morning of the 23rd.
        XCTAssertEqual(BillingClock.localDay(utc: start, tz: "Europe/Berlin"), "2026-09-23")
    }

    /// US fall-back, 2026-11-01: 01:00–02:00 PDT happens, then 01:00–02:00
    /// PST happens again. Two real hours of work are two hours billed.
    func testFallBackNeitherAddsNorDropsAnHour() {
        let start = "2026-11-01T07:30:00Z"  // 00:30 PDT
        let end = "2026-11-01T09:30:00Z"    // 01:30 PST, after the repeat
        XCTAssertEqual(UTCTimestamp.seconds(from: start, to: end), 7200)
        XCTAssertEqual(BillingClock.localDay(utc: start, tz: "America/Los_Angeles"), "2026-11-01")
        XCTAssertEqual(BillingClock.localDay(utc: end, tz: "America/Los_Angeles"), "2026-11-01")
    }

    /// US spring-forward, 2026-03-08: 02:00 PST jumps to 03:00 PDT. An hour
    /// of work straddling the gap is an hour, not two.
    func testSpringForwardNeitherAddsNorDropsAnHour() {
        let start = "2026-03-08T09:30:00Z"  // 01:30 PST
        let end = "2026-03-08T10:30:00Z"    // 03:30 PDT
        XCTAssertEqual(UTCTimestamp.seconds(from: start, to: end), 3600)
        XCTAssertEqual(BillingClock.localDay(utc: start, tz: "America/Los_Angeles"), "2026-03-08")
        XCTAssertEqual(BillingClock.localDay(utc: end, tz: "America/Los_Angeles"), "2026-03-08")
    }
}
