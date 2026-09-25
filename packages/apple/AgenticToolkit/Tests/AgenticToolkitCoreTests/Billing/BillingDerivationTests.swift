import XCTest
@testable import AgenticToolkitCore

/// Derivation is a pure function over timestamps. Every failure mode the design
/// leans on — crash, sleep, reinstall mid-session — reduces to one of these
/// cases, which is the whole reason there is no live timer state machine.
final class BillingDerivationTests: XCTestCase {

    private let cutoff = 15 * 60

    private func at(_ minutes: Int) -> String {
        let base = 14 * 3600
        let total = base + minutes * 60
        return String(format: "2026-09-22T%02d:%02d:00Z", total / 3600, (total % 3600) / 60)
    }

    private func runs(
        _ minutes: [Int],
        sessionStartedAt: String = "",
        active: Bool = false,
        nowMinutes: Int = 600
    ) -> [BillingRun] {
        BillingDerivation.runs(
            activityTimestamps: minutes.map(at),
            sessionStartedAt: sessionStartedAt,
            sessionIsActive: active,
            now: at(nowMinutes),
            cutoffSeconds: cutoff
        )
    }

    func testNoActivityProducesNoRuns() {
        XCTAssertTrue(runs([]).isEmpty)
    }

    /// A single event is a zero-length closed run, not a run with no end.
    func testASingleEventClosesAtItself() {
        let result = runs([0])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startedAt, at(0))
        XCTAssertEqual(result[0].endedAt, at(0))
        XCTAssertEqual(result[0].seconds, 0)
    }

    func testContiguousActivityIsOneRun() {
        let result = runs([0, 5, 10, 14, 20])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startedAt, at(0))
        XCTAssertEqual(result[0].endedAt, at(20))
        XCTAssertEqual(result[0].seconds, 20 * 60)
    }

    /// A gap larger than the cutoff splits. The run closes at the *previous*
    /// timestamp — the idle stretch itself is never billed.
    func testAGapBeyondTheCutoffSplitsAndClosesAtThePreviousEvent() {
        let result = runs([0, 10, 40, 45])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].endedAt, at(10), "closes at the last event before the gap")
        XCTAssertEqual(result[0].seconds, 600)
        XCTAssertEqual(result[1].startedAt, at(40))
        XCTAssertEqual(result[1].endedAt, at(45))
    }

    /// Exactly at the cutoff still counts as continuous; only *beyond* splits.
    func testAGapExactlyAtTheCutoffDoesNotSplit() {
        XCTAssertEqual(runs([0, 15]).count, 1)
        XCTAssertEqual(runs([0, 16]).count, 2)
    }

    /// Sleep is just a gap; a reboot mid-session is just a gap. No recovery
    /// code exists because none is needed.
    func testSleepAcrossHoursIsJustAnotherSplit() {
        let result = runs([0, 5, 480, 485])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].startedAt, at(480))
    }

    /// The final run stays open only while the session is live *and* recent.
    func testFinalRunStaysOpenForALiveRecentSession() {
        let result = runs([0, 10], active: true, nowMinutes: 15)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].endedAt, "", "still running")
        XCTAssertTrue(result[0].isOpen)
        XCTAssertEqual(result[0].seconds, 0, "an open run has no billable duration yet")
    }

    func testFinalRunClosesWhenTheSessionHasGoneQuiet() {
        let result = runs([0, 10], active: true, nowMinutes: 40)
        XCTAssertEqual(result[0].endedAt, at(10), "quiet past the cutoff closes it")
    }

    func testFinalRunClosesWhenTheSessionIsNoLongerActive() {
        let result = runs([0, 10], active: false, nowMinutes: 12)
        XCTAssertEqual(result[0].endedAt, at(10))
    }

    /// A session's *first* run may start at `sessions.started_at` — the session
    /// genuinely began then, and that recovers the prompt-reading minutes
    /// before the first event.
    func testFirstRunLeadsInFromSessionStartWhenWithinCutoff() {
        let result = runs([10, 15], sessionStartedAt: at(0))
        XCTAssertEqual(result[0].startedAt, at(0))
        XCTAssertEqual(result[0].seconds, 15 * 60)
    }

    /// A session start far before the first event is not evidence of work.
    func testFirstRunIgnoresASessionStartBeyondTheCutoff() {
        let result = runs([40, 45], sessionStartedAt: at(0))
        XCTAssertEqual(result[0].startedAt, at(40))
    }

    /// Only the first run gets the lead-in; later runs have no defensible
    /// source, so their head time is lost rather than invented.
    func testLaterRunsGetNoLeadIn() {
        let result = runs([10, 15, 60, 65], sessionStartedAt: at(0))
        XCTAssertEqual(result[0].startedAt, at(0))
        XCTAssertEqual(result[1].startedAt, at(60), "no lead-in on a later run")
    }

    /// A session start *after* the first event is nonsense data; the first
    /// event wins rather than producing a negative-length run.
    func testSessionStartAfterTheFirstEventIsIgnored() {
        let result = runs([0, 5], sessionStartedAt: at(3))
        XCTAssertEqual(result[0].startedAt, at(0))
    }

    /// Timestamps arriving out of order must not produce negative durations.
    func testOutOfOrderTimestampsAreSorted() {
        let result = BillingDerivation.runs(
            activityTimestamps: [at(20), at(0), at(10)],
            sessionStartedAt: "", sessionIsActive: false, now: at(600), cutoffSeconds: cutoff
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startedAt, at(0))
        XCTAssertEqual(result[0].endedAt, at(20))
    }

    /// Unparseable timestamps are dropped, not treated as epoch zero.
    func testUnparseableTimestampsAreDropped() {
        let result = BillingDerivation.runs(
            activityTimestamps: ["", "nonsense", at(0), at(5)],
            sessionStartedAt: "", sessionIsActive: false, now: at(600), cutoffSeconds: cutoff
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startedAt, at(0))
    }

    /// Duplicate timestamps (two hooks in the same second) don't split or
    /// double-count.
    func testDuplicateTimestampsCollapse() {
        let result = runs([0, 0, 5, 5])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].seconds, 300)
    }

    /// A zero or negative cutoff would make every event its own run; clamp to
    /// the 15-minute default rather than billing hundreds of one-second rows.
    func testNonPositiveCutoffFallsBackToTheDefault() {
        let result = BillingDerivation.runs(
            activityTimestamps: [at(0), at(10)],
            sessionStartedAt: "", sessionIsActive: false, now: at(600), cutoffSeconds: 0
        )
        XCTAssertEqual(result.count, 1, "0 is treated as the 15-minute default")
    }

    /// A malformed `sessionStartedAt` must not sneak past the lead-in guards
    /// just because string comparison happens to sort it before the first
    /// event and `UTCTimestamp.seconds` treats it as zero elapsed.
    func testMalformedSessionStartedAtIsIgnored() {
        let result = BillingDerivation.runs(
            activityTimestamps: [at(10), at(15)],
            sessionStartedAt: "2020-01-01T00:00:00X",
            sessionIsActive: false, now: at(600), cutoffSeconds: cutoff
        )
        XCTAssertEqual(result[0].startedAt, at(10), "no lead-in from an unparseable session start")
    }

    /// A malformed `now` can't prove the session is still recent, so an
    /// active session must close rather than stay open forever.
    func testMalformedNowClosesAnActiveSessionRatherThanStayingOpenForever() {
        let result = BillingDerivation.runs(
            activityTimestamps: [at(0), at(10)],
            sessionStartedAt: "", sessionIsActive: true, now: "not-a-timestamp", cutoffSeconds: cutoff
        )
        XCTAssertEqual(result[0].endedAt, at(10), "closes at the last event rather than staying open")
        XCTAssertFalse(result[0].isOpen)
    }

    // MARK: - Timestamp forms the database really holds

    /// `event_log.timestamp` carries milliseconds (`…:05.218Z`). Those stamps
    /// used to fail the whole-second parser and vanish, so a session made of
    /// them derived nothing at all.
    func testFractionalSecondStampsCountAsActivity() {
        let result = BillingDerivation.runs(
            activityTimestamps: ["2026-09-22T14:00:05.218Z", "2026-09-22T14:10:07.900Z"],
            sessionStartedAt: "", sessionIsActive: false, now: at(600), cutoffSeconds: cutoff
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startedAt, "2026-09-22T14:00:05Z", "stored in the canonical whole-second form")
        XCTAssertEqual(result[0].endedAt, "2026-09-22T14:10:07Z")
        XCTAssertEqual(result[0].seconds, 602)
    }

    /// Whole- and fractional-second stamps interleave in one session; they
    /// must sort by instant, not by string, and duplicates at the same second
    /// collapse.
    func testMixedStampFormsSortByInstant() {
        let result = BillingDerivation.runs(
            activityTimestamps: ["2026-09-22T14:05:00Z", "2026-09-22T14:00:00.500Z", "2026-09-22T14:05:00.100Z"],
            sessionStartedAt: "", sessionIsActive: false, now: at(600), cutoffSeconds: cutoff
        )
        XCTAssertEqual(result.map(\.startedAt), ["2026-09-22T14:00:00Z"])
        XCTAssertEqual(result[0].endedAt, "2026-09-22T14:05:00Z")
    }

    /// `sessions.started_at` is written in SQLite's space form
    /// (`2026-09-22 14:00:00`). The lead-in must still apply.
    func testTheLeadInReadsASpaceFormSessionStart() {
        let result = runs([10, 15], sessionStartedAt: "2026-09-22 14:00:00")
        XCTAssertEqual(result[0].startedAt, at(0), "the lead-in from the space-form start")
        XCTAssertEqual(result[0].seconds, 15 * 60)
    }

    func testClockReadsEveryStoredForm() {
        let expected = UTCTimestamp.date(from: "2026-09-22T14:00:05Z")
        XCTAssertNotNil(expected)
        XCTAssertEqual(UTCTimestamp.date(from: "2026-09-22 14:00:05"), expected)
        XCTAssertEqual(UTCTimestamp.canonical("2026-09-22T14:00:05.999Z"), "2026-09-22T14:00:05Z")
        XCTAssertEqual(UTCTimestamp.canonical("2026-09-22 14:00:05.123"), "2026-09-22T14:00:05Z")
        XCTAssertNil(UTCTimestamp.canonical("yesterday"))
    }
}
