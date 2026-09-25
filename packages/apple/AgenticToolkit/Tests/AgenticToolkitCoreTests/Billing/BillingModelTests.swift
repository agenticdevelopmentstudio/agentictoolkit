import XCTest
import Combine
import AgenticToolkitCore

/// `BillingModel` against a fake client: the daemon round-trip is Task 11's
/// to prove, so these cover what the model adds — caching, lookups, sticky
/// state through a failure, and refreshing after every write.
@MainActor
final class BillingModelTests: XCTestCase {

    private var fake: FakeBillingClient!

    override func setUp() async throws {
        fake = FakeBillingClient.seeded()
    }

    func testRefreshCachesEverythingTheWindowsList() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()

        XCTAssertEqual(model.clients.map(\.id), ["c1"])
        XCTAssertEqual(model.projects.map(\.id), ["p1", "p2"])
        XCTAssertEqual(model.runningTimers.map(\.id), ["s-running"])
        XCTAssertEqual(model.recentSegments.count, 2)
        XCTAssertEqual(model.overview?.unbilled.amountCents, 25_000)
        XCTAssertNil(model.lastError)
        XCTAssertNotNil(model.lastUpdated)
    }

    func testAnUnreachableDaemonKeepsTheLastGoodState() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        fake.reachable = false

        await model.refresh()

        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.projects.count, 2, "a transient failure never blanks an open window")
    }

    /// The daemon's reason survives the refresh that follows every write, so
    /// the window's alert (`"… couldn't be saved. \(lastError)"`) says why.
    func testARefusedWriteLeavesTheDaemonsReasonInLastError() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()

        let saved = await model.saveProject(BillingProjectDTO(id: "", name: "  "))

        XCTAssertNil(saved)
        XCTAssertEqual(model.lastError, "A name is required.")
    }

    func testARefusedDeleteLeavesTheReasonInLastError() async {
        fake.entries = [BillingEntryDTO(id: "e1", projectId: "p1", day: "2026-09-22",
                                        rawSeconds: 3600, billedSeconds: 3600, rateCents: 10_000,
                                        amountCents: 10_000, status: "paid", locked: true)]
        let model = BillingModel(service: fake, refreshInterval: 999)

        let deleted = await model.deleteEntry(id: "e1")

        XCTAssertFalse(deleted)
        // The daemon's own sentence, not a copy the fake keeps.
        XCTAssertEqual(model.lastError, BillingRefusalText.entryIsLocked)
    }

    func testDeletingAnEntryThatIsGoneSaysSoRatherThanLocked() async {
        let model = BillingModel(service: fake, refreshInterval: 999)

        let deleted = await model.deleteEntry(id: "no-such-entry")

        XCTAssertFalse(deleted)
        XCTAssertEqual(model.lastError, BillingRefusalText.unknownEntry)
    }

    func testMovingAnEntryToItsOwnStatusWritesNoAudit() async {
        fake.entries = [BillingEntryDTO(id: "e1", projectId: "p1", day: "2026-09-22",
                                        rawSeconds: 3600, billedSeconds: 3600, rateCents: 10_000,
                                        amountCents: 10_000, status: "unbilled")]
        let model = BillingModel(service: fake, refreshInterval: 999)

        let moved = await model.setEntryStatus(id: "e1", status: .unbilled)

        XCTAssertEqual(moved?.status, "unbilled")
        XCTAssertTrue(fake.audits.isEmpty)
    }

    func testASuccessfulWriteClearsAnEarlierRefusal() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.saveProject(BillingProjectDTO(id: "", name: ""))
        XCTAssertNotNil(model.lastError)

        await model.saveProject(BillingProjectDTO(id: "", name: "Fine"))

        XCTAssertNil(model.lastError)
    }

    func testLookupsNameTheUnassignedBucket() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()

        let assigned = fake.segments.first { $0.projectId == "p1" }!
        let unassigned = fake.segments.first { $0.projectId == nil }!
        XCTAssertEqual(model.projectName(for: assigned), "Website")
        XCTAssertEqual(model.projectName(for: unassigned), BillingModel.unassignedTitle)
        XCTAssertEqual(model.client(id: "c1")?.name, "Acme")
        XCTAssertNil(model.project(id: nil))
    }

    func testArchivedRecordsStayOutOfTheActiveLists() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        XCTAssertEqual(BillingModel.activeSorted(model.projects).map(\.id), ["p1"], "p2 is archived")
    }

    func testActiveProjectsAreOfferedByName() {
        let projects = [
            BillingProjectDTO(id: "b", name: "beta"),
            BillingProjectDTO(id: "x", name: "Alpha", archived: true),
            BillingProjectDTO(id: "a", name: "Alpha 10"),
            BillingProjectDTO(id: "c", name: "Alpha 9")
        ]
        XCTAssertEqual(BillingModel.activeSorted(projects).map(\.id), ["c", "a", "b"],
                       "archived left out; numbers and case compared the way Finder does")
    }

    /// Review V16-b: the overview is a separate read. When it alone fails,
    /// the last good figures stay — "sticky through failures" — rather than
    /// every total turning into a dash as if nothing were billable.
    func testAnOverviewThatFailsAloneKeepsTheLastGoodFigures() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        XCTAssertEqual(model.overview?.unbilled.amountCents, 25_000)

        fake.overviewFails = true
        await model.refresh()

        XCTAssertEqual(model.overview?.unbilled.amountCents, 25_000)
    }

    /// Review V33-c: the poll loop holds the model only while it polls, so a
    /// model nobody keeps is freed rather than kept alive until `stop()`.
    func testAStartedModelNobodyKeepsIsFreed() async throws {
        weak var released: BillingModel?
        do {
            let model = BillingModel(service: fake, refreshInterval: 0.02)
            model.start()
            released = model
        }
        for _ in 0..<200 where released != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(released)
    }

    func testAWriteRefreshesAndNotifies() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        var notified = 0
        let token = model.changes.sink { notified += 1 }
        defer { token.cancel() }

        let saved = await model.saveProject(BillingProjectDTO(id: "", name: "New"))

        XCTAssertEqual(saved?.name, "New")
        XCTAssertEqual(model.projects.map(\.name).contains("New"), true)
        XCTAssertGreaterThan(notified, 0)
    }

    func testStartingAndStoppingATimerRoundTrips() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()

        let started = await model.startTimer(BillingTimerStartDTO(projectId: "p1"))
        XCTAssertEqual(started?.origin, "manual")
        XCTAssertTrue(model.runningTimers.contains { $0.id == started?.id })

        _ = await model.stopTimer(id: started!.id)
        XCTAssertFalse(model.runningTimers.contains { $0.id == started?.id })
    }

    func testBackfillRepliesTheQueuedCount() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        let queued = await model.backfill(since: "2026-09-01T00:00:00Z")
        XCTAssertEqual(queued, 3)
        XCTAssertEqual(fake.lastBackfillSince, "2026-09-01T00:00:00Z")
    }

    // MARK: - Polling only what someone is looking at

    /// With no billing window on screen, a pass reads the running timers (the
    /// menus' Stop Timer needs them) and nothing else. The first pass reads
    /// everything, for a window restored at launch.
    func testWithNoWindowShowingAPassReadsOnlyTheRunningTimers() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.poll()
        XCTAssertEqual(fake.projectReads, 1, "the first pass reads everything")

        fake.projects.append(BillingProjectDTO(id: "p3", name: "Later"))
        fake.segments.append(BillingSegmentDTO(
            id: "s-timer", origin: "manual", projectId: "p1", startedAt: "2026-09-22T09:10:00Z"))
        await model.poll()

        XCTAssertEqual(fake.projectReads, 1)
        XCTAssertTrue(model.runningTimers.contains { $0.id == "s-timer" })
        XCTAssertFalse(model.projects.contains { $0.id == "p3" })
    }

    func testAWindowOnScreenMakesAPassReadEverything() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.poll()
        final class Flag { var isOn = false }
        let showing = Flag()
        let owner = NSObject()
        model.addConsumer(owner) { showing.isOn }

        await model.poll()
        XCTAssertEqual(fake.projectReads, 1, "a window that exists but isn't shown doesn't count")

        showing.isOn = true
        fake.projects.append(BillingProjectDTO(id: "p3", name: "Later"))
        await model.poll()
        XCTAssertEqual(fake.projectReads, 2)
        XCTAssertTrue(model.projects.contains { $0.id == "p3" })

        model.removeConsumer(owner)
        await model.poll()
        XCTAssertEqual(fake.projectReads, 2)
    }

    /// A pass that finds nothing new tells no window to rebuild.
    func testAPassThatFindsNothingNewIsSilent() async {
        let model = BillingModel(service: fake, refreshInterval: 999)
        let owner = NSObject()
        model.addConsumer(owner) { true }
        await model.poll()
        var notified = 0
        let token = model.changes.sink { notified += 1 }
        defer { token.cancel() }

        await model.poll()
        XCTAssertEqual(notified, 0)

        fake.projects.append(BillingProjectDTO(id: "p3", name: "Later"))
        await model.poll()
        XCTAssertEqual(notified, 1)
    }

    // MARK: - A refresh never rolls a write back

    /// A refresh whose reads were answered before a write, but which returns
    /// after it, would put the pre-write project back, and the pane's next
    /// whole-record save would send it to the daemon. It is dropped instead.
    func testARefreshAnsweredBeforeAWriteDoesNotUndoIt() async throws {
        let model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        let gate = FakeGate()
        fake.holdNextProjectsRead = gate
        let stale = Task { await model.refresh() }
        await gate.reached()

        let website = try XCTUnwrap(model.project(id: "p1"))
        _ = await model.saveProject(website.replacing(archived: true))
        XCTAssertEqual(model.project(id: "p1")?.archived, true)

        gate.open()
        await stale.value

        XCTAssertEqual(model.project(id: "p1")?.archived, true, "the stale answer was dropped")
    }
}
