import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The Unassigned pane on its own: which runs it lists and how, which project
/// it offers, and what its buttons report. No daemon is involved.
@MainActor
final class UnassignedPanelTests: XCTestCase {

    private let website = BillingProjectDTO(id: "p1", name: "Website")
    private let api = BillingProjectDTO(id: "p3", name: "api")
    private let old = BillingProjectDTO(id: "p2", name: "Old thing", archived: true)

    private func loose(
        _ id: String, root: String = "/src/misc", branch: String = "",
        start: String = "2026-09-22T08:00:00Z", seconds: Int = 1800, origin: String = "auto"
    ) -> BillingSegmentDTO {
        BillingSegmentDTO(id: id, origin: origin, projectRoot: root, branch: branch,
                          startedAt: start, endedAt: "2026-09-22T23:00:00Z", seconds: seconds)
    }

    private func makePanel() -> UnassignedPanel {
        let panel = UnassignedPanel()
        panel.timeZone = TimeZone(identifier: "UTC")!
        panel.locale = Locale(identifier: "en_GB")
        _ = panel.view
        return panel
    }

    /// `EditableTableCellValue` is not `Equatable`, and a test only cares what it reads as.
    private func show(_ value: ComposableSettings.EditableTableCellValue?) -> String {
        return shownCell(value)
    }

    // MARK: - What is listed

    func testOnlyStoppedUnrolledTimeWithNoProjectIsListedNewestFirst() {
        let panel = makePanel()
        let running = BillingSegmentDTO(id: "running", origin: "auto", projectRoot: "/src/misc",
                                        startedAt: "2026-09-22T10:00:00Z")
        let mapped = BillingSegmentDTO(id: "mapped", origin: "auto", projectId: "p1", projectRoot: "/src/site",
                                       startedAt: "2026-09-22T07:00:00Z", endedAt: "2026-09-22T08:00:00Z",
                                       seconds: 3600)
        let rolled = BillingSegmentDTO(id: "rolled", origin: "auto", projectRoot: "/src/misc",
                                       startedAt: "2026-09-22T06:00:00Z", endedAt: "2026-09-22T07:00:00Z",
                                       seconds: 3600, entryId: "e1")

        panel.show(segments: [loose("early", start: "2026-09-21T09:00:00Z"), running, mapped, rolled,
                              loose("late")],
                   projects: [website])

        XCTAssertEqual(panel.timeCard.rows.map(\.id), ["late", "early"])
    }

    func testARowShowsRepositoryBranchStartHoursAndOrigin() {
        let panel = makePanel()

        panel.show(segments: [loose("a", branch: "feature/x"),
                              loose("b", root: "", start: "2026-09-21T09:00:00Z", seconds: 5400, origin: "manual")],
                   projects: [website])

        let rows = panel.timeCard.rows
        XCTAssertEqual(rows.map { show($0.cells["repository"]) }, ["/src/misc", "(No repository)"])
        XCTAssertEqual(rows.map { show($0.cells["branch"]) }, ["feature/x", "(—)"])
        XCTAssertEqual(rows.map { show($0.cells["started"]) }, ["22 Sep, 8:00", "21 Sep, 9:00"])
        XCTAssertEqual(rows.map { show($0.cells["hours"]) }, ["0.50", "1.50"])
        XCTAssertEqual(rows.map { show($0.cells["origin"]) }, ["Tracked", "Timer"])
    }

    // MARK: - The project popup

    func testTheProjectPopupOffersActiveProjectsByName() {
        let panel = makePanel()

        panel.show(segments: [], projects: [website, old, api])

        XCTAssertEqual(panel.projectPopup.popUpButton.itemTitles, ["api", "Website"])
        XCTAssertEqual(panel.chosenProjectId, "p3", "the first project is chosen until the user picks one")
    }

    func testStartTimesFollowATwelveHourLocale() {
        let panel = makePanel()
        panel.locale = Locale(identifier: "en_US")
        panel.show(segments: [loose("a", start: "2026-09-22T14:05:00Z")], projects: [website])
        XCTAssertEqual(show(panel.timeCard.rows.first?.cells["started"]), "Sep 22, 2:05 PM")
    }

    func testProjectsThatShareANameAreToldApartAndEachCanBeChosen() {
        let panel = makePanel()
        let acme = BillingClientDTO(id: "c1", name: "Acme")
        let globex = BillingClientDTO(id: "c2", name: "Globex")
        let acmeSite = BillingProjectDTO(id: "p1", clientId: "c1", name: "Website")
        let globexSite = BillingProjectDTO(id: "p2", clientId: "c2", name: "Website")
        let beta = BillingProjectDTO(id: "p3", name: "Beta")

        panel.show(segments: [], projects: [acmeSite, globexSite, beta], clients: [acme, globex])

        let popup = panel.projectPopup.popUpButton
        XCTAssertEqual(popup.itemTitles, ["Beta", "Website — Acme", "Website — Globex"])
        popup.selectItem(withTitle: "Website — Acme")
        popup.sendAction(popup.action, to: popup.target)
        XCTAssertEqual(panel.chosenProjectId, "p1", "the namesake of the project meant took the time")
        XCTAssertEqual(popup.titleOfSelectedItem, "Website — Acme")
    }

    func testProjectLabelsFallBackToTheIdWhenTheClientRepeatsToo() {
        let labels = BillingRecordTitle.projectLabels([
            BillingProjectDTO(id: "aaaaaa-1", name: "Site"),
            BillingProjectDTO(id: "bbbbbb-2", name: "Site"),
            BillingProjectDTO(id: "cccccc-3", name: "Other")
        ], clients: [])
        XCTAssertEqual(labels["aaaaaa-1"], "Site — No Client — aaaaaa")
        XCTAssertEqual(labels["bbbbbb-2"], "Site — No Client — bbbbbb")
        XCTAssertEqual(labels["cccccc-3"], "Other")
    }

    func testAChosenProjectStaysChosenUntilItIsArchived() {
        let panel = makePanel()
        panel.show(segments: [], projects: [website, api])
        panel.projectPopup.popUpButton.selectItem(withTitle: "Website")
        panel.projectPopup.popUpButton.sendAction(panel.projectPopup.popUpButton.action,
                                                  to: panel.projectPopup.popUpButton.target)
        XCTAssertEqual(panel.chosenProjectId, "p1")

        panel.show(segments: [], projects: [website, api])
        XCTAssertEqual(panel.chosenProjectId, "p1", "a reload keeps the user's choice")

        panel.show(segments: [], projects: [website.replacing(archived: true), api])
        XCTAssertEqual(panel.chosenProjectId, "p3")
    }

    func testWithNoProjectsThePopupSaysSoAndOnlyNewProjectWorks() {
        let panel = makePanel()
        panel.show(segments: [loose("a")], projects: [old])
        panel.select(segmentId: "a")

        XCTAssertEqual(panel.projectPopup.popUpButton.itemTitles, ["No Projects"])
        XCTAssertFalse(panel.projectPopup.popUpButton.isEnabled)
        XCTAssertNil(panel.chosenProjectId)
        XCTAssertFalse(panel.assignRunButton.isEnabled)
        XCTAssertFalse(panel.assignRepositoryButton.isEnabled)
        XCTAssertTrue(panel.newProjectButton.isEnabled)
    }

    // MARK: - The buttons

    func testTheButtonsNeedASelectedRun() {
        let panel = makePanel()
        panel.show(segments: [loose("a")], projects: [website])

        XCTAssertFalse(panel.assignRunButton.isEnabled)
        XCTAssertFalse(panel.assignRepositoryButton.isEnabled)
        XCTAssertFalse(panel.newProjectButton.isEnabled)

        panel.select(segmentId: "a")

        XCTAssertTrue(panel.assignRunButton.isEnabled)
        XCTAssertTrue(panel.assignRepositoryButton.isEnabled)
        XCTAssertTrue(panel.newProjectButton.isEnabled)
    }

    func testARunWithNoRepositoryCanOnlyBeAssignedOnItsOwn() {
        let panel = makePanel()
        panel.show(segments: [loose("a", root: "")], projects: [website])

        panel.select(segmentId: "a")

        XCTAssertTrue(panel.assignRunButton.isEnabled)
        XCTAssertFalse(panel.assignRepositoryButton.isEnabled)
        XCTAssertTrue(panel.newProjectButton.isEnabled)
    }

    func testTheButtonsReportTheRunAndTheChosenProject() {
        let panel = makePanel()
        var runs: [String] = []
        var repos: [String] = []
        var fresh: [String] = []
        panel.onAssignRun = { runs.append("\($0.id)→\($1)") }
        panel.onAssignRepository = { repos.append("\($0.projectRoot)→\($1)") }
        panel.onNewProject = { fresh.append($0.id) }
        panel.show(segments: [loose("a")], projects: [website])
        panel.select(segmentId: "a")

        panel.assignRunButton.performClick(nil)
        panel.assignRepositoryButton.performClick(nil)
        panel.newProjectButton.performClick(nil)

        XCTAssertEqual(runs, ["a→p1"])
        XCTAssertEqual(repos, ["/src/misc→p1"])
        XCTAssertEqual(fresh, ["a"])
    }
}
