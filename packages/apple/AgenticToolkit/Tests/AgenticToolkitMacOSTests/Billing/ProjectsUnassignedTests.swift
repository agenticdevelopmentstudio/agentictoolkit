import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The Unassigned row in the Projects window against the in-memory daemon:
/// it is always last, it cannot be removed, and each of its actions leaves the
/// time in a project and rolled into a billable.
@MainActor
final class ProjectsUnassignedTests: XCTestCase {

    private var fake: FakeBillingClient!
    private var model: BillingModel!
    private var failures: [String] = []

    override func setUp() async throws {
        fake = FakeBillingClient.seeded()
        model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        failures = []
    }

    private func makeController() -> ProjectsWindowController {
        let model = self.model!
        let controller = ProjectsWindowController(
            context: .forTests(model: model),
            confirm: { _, _, answer in answer(true) },
            reportFailure: { [unowned self] message in failures.append(message) },
            chooseFolder: { _, answer in answer(nil) },
            // Every segment root is already resolved; nothing here should call git.
            resolveRoot: { _ in
                XCTFail("a segment's root is used as recorded")
                return .undetermined
            },
            addClient: { nil }
        )
        _ = controller.windowController.window
        return controller
    }

    private func titles(_ controller: ProjectsWindowController) -> [String] {
        controller.windowController.viewController?.panels.map(\.descriptor.title) ?? []
    }

    private func openUnassigned(_ controller: ProjectsWindowController) throws -> UnassignedPanel {
        controller.selectUnassigned()
        let panel = try XCTUnwrap(controller.unassignedPanel)
        _ = panel.view
        return panel
    }

    /// Two more loose runs: one more in `/src/misc` (with `s-loose`), one in `/src/other`.
    private func addLooseRuns() async {
        fake.segments += [
            BillingSegmentDTO(id: "s-misc2", origin: "auto", projectRoot: "/src/misc",
                              startedAt: "2026-09-22T06:00:00Z", endedAt: "2026-09-22T07:00:00Z", seconds: 3600),
            BillingSegmentDTO(id: "s-other", origin: "auto", projectRoot: "/src/other",
                              startedAt: "2026-09-22T05:00:00Z", endedAt: "2026-09-22T05:15:00Z", seconds: 900)
        ]
        await model.refresh()
    }

    private func projectId(of segmentId: String) -> String? {
        fake.segments.first { $0.id == segmentId }?.projectId
    }

    // MARK: - The row

    func testUnassignedIsTheLastRow() {
        let controller = makeController()

        XCTAssertEqual(titles(controller), ["Website", "Old thing", "Unassigned"])
    }

    func testUnassignedCannotBeRemoved() throws {
        let controller = makeController()
        _ = try openUnassigned(controller)

        XCTAssertFalse(controller.windowController.footer.isRemoveEnabled)
        controller.windowController.footer.onRemove?()
        XCTAssertNil(controller.lastWrite, "nothing was asked of the daemon")
    }

    func testThePaneListsTheLooseTime() throws {
        let controller = makeController()
        let panel = try openUnassigned(controller)

        XCTAssertEqual(panel.timeCard.rows.map(\.id), ["s-loose"])
        XCTAssertEqual(panel.chosenProjectId, "p1", "the only active project")
    }

    // MARK: - The actions

    func testAssignRunMovesOnlyThatRunAndRollsItUp() async throws {
        await addLooseRuns()
        let controller = makeController()
        let panel = try openUnassigned(controller)

        panel.select(segmentId: "s-misc2")
        panel.assignRunButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(projectId(of: "s-misc2"), "p1")
        XCTAssertNil(projectId(of: "s-loose"))
        XCTAssertEqual(fake.lastPromotedIDs, ["s-misc2"])
        XCTAssertEqual(panel.timeCard.rows.map(\.id), ["s-loose", "s-other"], "the pane has reloaded")
        XCTAssertTrue(fake.repos.isEmpty, "one run is not a repository")
    }

    func testAssignRepositoryRecordsItAndMovesAllItsTime() async throws {
        await addLooseRuns()
        let controller = makeController()
        let panel = try openUnassigned(controller)

        panel.select(segmentId: "s-loose")
        panel.assignRepositoryButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.repos.map { "\($0.projectRoot)→\($0.projectId)" }, ["/src/misc→p1"])
        XCTAssertEqual(projectId(of: "s-loose"), "p1")
        XCTAssertEqual(projectId(of: "s-misc2"), "p1")
        XCTAssertNil(projectId(of: "s-other"))
        XCTAssertEqual(Set(fake.lastPromotedIDs), ["s-loose", "s-misc2"])
        XCTAssertEqual(panel.timeCard.rows.map(\.id), ["s-other"])
    }

    /// The app holds only the newest page of runs; the repository's older
    /// loose time moves too, because the daemon picks the runs, not the page.
    func testAssignRepositoryMovesRunsTheWindowNeverListed() async throws {
        await addLooseRuns()
        let controller = makeController()
        let panel = try openUnassigned(controller)
        fake.segments.append(BillingSegmentDTO(
            id: "s-ancient", origin: "auto", projectRoot: "/src/misc",
            startedAt: "2026-06-01T08:00:00Z", endedAt: "2026-06-01T08:30:00Z", seconds: 1800))
        XCTAssertFalse(model.recentSegments.contains { $0.id == "s-ancient" })

        panel.select(segmentId: "s-loose")
        panel.assignRepositoryButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(projectId(of: "s-ancient"), "p1")
        XCTAssertTrue(fake.lastPromotedIDs.contains("s-ancient"))
    }

    func testARefusedRepositoryMovesNothing() async throws {
        fake.repos = [BillingRepoDTO(id: "r9", projectId: "p2", projectRoot: "/src/misc")]
        let controller = makeController()
        let panel = try openUnassigned(controller)

        panel.select(segmentId: "s-loose")
        panel.assignRepositoryButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(failures.count, 1)
        XCTAssertNil(projectId(of: "s-loose"))
        XCTAssertTrue(fake.lastPromotedIDs.isEmpty)
    }

    func testNewProjectIsNamedForTheRepositoryAndTakesItsTime() async throws {
        await addLooseRuns()
        let controller = makeController()
        let panel = try openUnassigned(controller)

        panel.select(segmentId: "s-loose")
        panel.newProjectButton.performClick(nil)
        await controller.lastWrite?.value

        let created = try XCTUnwrap(fake.projects.first { $0.name == "misc" })
        XCTAssertEqual(created.roundingMinutes, BillingUserSettings.forTests.roundingMinutes.value)
        XCTAssertEqual(fake.repos.map { "\($0.projectRoot)→\($0.projectId)" }, ["/src/misc→\(created.id)"])
        XCTAssertEqual(projectId(of: "s-loose"), created.id)
        XCTAssertEqual(projectId(of: "s-misc2"), created.id)
        XCTAssertEqual(controller.windowController.selectedRecord?.id, created.id)
        XCTAssertEqual(titles(controller), ["misc", "Website", "Old thing", "Unassigned"])
    }

    func testANewProjectNameIsMadeUnique() async throws {
        fake.projects.append(BillingProjectDTO(id: "p9", name: "misc"))
        await model.refresh()
        let controller = makeController()
        let panel = try openUnassigned(controller)

        panel.select(segmentId: "s-loose")
        panel.newProjectButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertNotNil(fake.projects.first { $0.name == "misc 2" })
    }

    func testANewProjectFromARunWithNoRepositoryTakesJustThatRun() async throws {
        fake.segments.append(BillingSegmentDTO(
            id: "s-timer", origin: "manual", startedAt: "2026-09-22T04:00:00Z",
            endedAt: "2026-09-22T04:30:00Z", seconds: 1800))
        await model.refresh()
        let controller = makeController()
        let panel = try openUnassigned(controller)

        panel.select(segmentId: "s-timer")
        panel.newProjectButton.performClick(nil)
        await controller.lastWrite?.value

        let created = try XCTUnwrap(fake.projects.first { $0.name == ProjectsWindowController.newProjectName })
        XCTAssertEqual(projectId(of: "s-timer"), created.id)
        XCTAssertNil(projectId(of: "s-loose"))
        XCTAssertTrue(fake.repos.isEmpty)
    }

    func testAFailedAssignIsReported() async throws {
        let controller = makeController()
        let panel = try openUnassigned(controller)
        panel.select(segmentId: "s-loose")
        fake.reachable = false

        panel.assignRunButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].hasPrefix("The time couldn't be assigned."), failures[0])
    }
}
