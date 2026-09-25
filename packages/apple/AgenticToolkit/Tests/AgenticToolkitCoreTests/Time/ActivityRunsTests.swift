import XCTest
@testable import AgenticToolkitCore

final class ActivityRunsTests: XCTestCase {

    private typealias Span = ActivityRuns.Span<Int>

    func testSplitsAtEveryGapLongerThanTheIdleGap() {
        let spans = ActivityRuns.split([0, 60, 120, 1200, 1260, 3000], idleGap: 900)
        XCTAssertEqual(spans, [Span(start: 0, end: 120), Span(start: 1200, end: 1260), Span(start: 3000, end: 3000)])
    }

    /// A gap of exactly the idle gap keeps the run going: only a longer one stops it.
    func testAGapEqualToTheIdleGapDoesNotSplit() {
        XCTAssertEqual(ActivityRuns.split([0, 900], idleGap: 900), [Span(start: 0, end: 900)])
    }

    func testNoStampsIsNoSpans() {
        XCTAssertEqual(ActivityRuns.split([Int](), idleGap: 900), [])
    }

    func testTheSplitterClosesARunAtABoundaryTheStampsDontShow() {
        var splitter = ActivityRuns.Splitter(idleGap: 900)
        splitter.add(0)
        splitter.add(60)
        splitter.closeRun()
        splitter.add(120)
        XCTAssertEqual(splitter.finish(), [Span(start: 0, end: 60), Span(start: 120, end: 120)])
    }

    func testUnionMergesOverlappingAndTouchingIntervals() {
        let merged = ActivityRuns.union([
            Span(start: 50, end: 70), Span(start: 0, end: 10), Span(start: 10, end: 20), Span(start: 55, end: 60)
        ])
        XCTAssertEqual(merged, [Span(start: 0, end: 20), Span(start: 50, end: 70)])
    }

    func testUnionLengthCountsOverlapOnce() {
        XCTAssertEqual(ActivityRuns.unionLength([Span(start: 0, end: 100), Span(start: 50, end: 150)]), 150)
    }

    /// The union needs only ordering, so fixed-width ISO strings work too.
    func testUnionWorksOnFixedWidthStrings() {
        let merged = ActivityRuns.union([
            ActivityRuns.Span(start: "2026-09-22T10:00:00Z", end: "2026-09-22T11:00:00Z"),
            ActivityRuns.Span(start: "2026-09-22T10:30:00Z", end: "2026-09-22T12:00:00Z")
        ])
        XCTAssertEqual(merged, [ActivityRuns.Span(start: "2026-09-22T10:00:00Z", end: "2026-09-22T12:00:00Z")])
    }
}
