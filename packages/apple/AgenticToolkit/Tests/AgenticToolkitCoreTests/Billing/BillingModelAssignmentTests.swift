import XCTest
import AgenticToolkitCore

/// Giving unassigned time to a project: it moves, it becomes billable at once,
/// and a failed move bills nothing.
@MainActor
final class BillingModelAssignmentTests: XCTestCase {

    private var fake: FakeBillingClient!
    private var model: BillingModel!

    override func setUp() async throws {
        fake = FakeBillingClient.seeded()
        model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
    }

    func testAssignAndRollMovesTheTimeAndRollsItUp() async {
        let rolled = await model.assignAndRoll(segmentIDs: ["s-loose"], projectId: "p1")

        XCTAssertEqual(rolled, 1)
        XCTAssertEqual(fake.segments.first { $0.id == "s-loose" }?.projectId, "p1")
        XCTAssertEqual(fake.lastPromotedIDs, ["s-loose"])
        XCTAssertEqual(model.recentSegments.first { $0.id == "s-loose" }?.projectId, "p1",
                       "the model has refreshed")
    }

    func testNothingIsRolledWhenTheMoveFails() async {
        fake.reachable = false

        let rolled = await model.assignAndRoll(segmentIDs: ["s-loose"], projectId: "p1")

        XCTAssertNil(rolled)
        XCTAssertTrue(fake.lastPromotedIDs.isEmpty)
    }

    /// Review V10-c / V18-b: the daemon's minute pass rolled the run into a
    /// billable after the list was read. The daemon moves nothing and answers
    /// 0; that must read as a failure with a reason, not a quiet success
    /// that leaves the time billed to the old project.
    func testAssigningTimeAlreadyOnABillableFailsWithAReason() async {
        fake.segments = fake.segments.map { segment in
            segment.id != "s-loose" ? segment : BillingSegmentDTO(
                id: segment.id, origin: segment.origin, projectId: "p2", projectRoot: segment.projectRoot,
                startedAt: segment.startedAt, endedAt: segment.endedAt, seconds: segment.seconds,
                entryId: "e-rolled")
        }

        let rolled = await model.assignAndRoll(segmentIDs: ["s-loose"], projectId: "p1")

        XCTAssertNil(rolled)
        XCTAssertEqual(model.lastError, BillingModel.alreadyOnABillable)
        XCTAssertTrue(fake.lastPromotedIDs.isEmpty, "nothing moved, so nothing is rolled")
        XCTAssertEqual(fake.segments.first { $0.id == "s-loose" }?.projectId, "p2")
    }

    func testAFailedMoveIsNotBlamedOnABillable() async {
        fake.reachable = false

        _ = await model.assignAndRoll(segmentIDs: ["s-loose"], projectId: "p1")

        XCTAssertNotEqual(model.lastError, BillingModel.alreadyOnABillable)
    }

    func testDatesAreReadWithAndWithoutFractionalSeconds() {
        XCTAssertEqual(BillingModel.date(iso: "2026-09-22T08:00:00Z")?.timeIntervalSince1970, 1_790_064_000)
        XCTAssertEqual(BillingModel.date(iso: "2026-09-22T08:00:00.500Z")?.timeIntervalSince1970, 1_790_064_000.5)
        XCTAssertNil(BillingModel.date(iso: ""))
        XCTAssertNil(BillingModel.date(iso: "yesterday"))
    }
}
