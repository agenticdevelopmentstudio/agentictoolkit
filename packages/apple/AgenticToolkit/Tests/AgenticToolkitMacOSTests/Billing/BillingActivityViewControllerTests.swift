import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The Activity pane on its own: which runs it lists and how, the running
/// rows and their clocks, and what each control reports. No daemon is involved.
@MainActor
final class BillingActivityViewControllerTests: XCTestCase {

    private let website = BillingProjectDTO(id: "p1", name: "Website")
    private let api = BillingProjectDTO(id: "p3", name: "api")
    private let old = BillingProjectDTO(id: "p2", name: "Old thing", archived: true)
    private var projects: [BillingProjectDTO] { [website, api, old] }

    /// 09:30Z on the fixtures' day. Tests that need time to pass move it.
    private var current = ISO8601DateFormatter().date(from: "2026-09-22T09:30:00Z")!

    private func run(
        _ id: String, origin: String = "auto", project: String? = "p1",
        root: String = "/src/site", branch: String = "",
        start: String = "2026-09-22T08:00:00Z", end: String = "2026-09-22T08:30:00Z",
        seconds: Int = 1800, entry: String? = nil, flags: String = "", note: String = ""
    ) -> BillingSegmentDTO {
        BillingSegmentDTO(id: id, origin: origin, projectId: project, projectRoot: root, branch: branch,
                          startedAt: start, endedAt: end, seconds: seconds, note: note,
                          entryId: entry, flags: flags)
    }

    private func running(
        _ id: String, origin: String = "auto", project: String? = "p1", root: String = "/src/site",
        branch: String = "", start: String = "2026-09-22T09:00:00Z", flags: String = "", note: String = ""
    ) -> BillingSegmentDTO {
        run(id, origin: origin, project: project, root: root, branch: branch,
            start: start, end: "", seconds: 0, flags: flags, note: note)
    }

    /// Whether the pane's window can be seen. Starts off screen, the way a
    /// pane with no window is.
    private var onScreen = false

    private func makePane() -> BillingActivityViewController {
        let pane = BillingActivityViewController()
        pane.timeZone = TimeZone(identifier: "UTC")!
        pane.locale = Locale(identifier: "en_US")
        pane.now = { [unowned self] in self.current }
        _ = pane.view
        pane.runningList.windowIsVisible = { [unowned self] in self.onScreen }
        return pane
    }

    /// The window comes on screen, or goes off it.
    private func setOnScreen(_ pane: BillingActivityViewController, _ visible: Bool) {
        onScreen = visible
        pane.runningList.visibilityChanged()
    }

    private func show(
        _ pane: BillingActivityViewController,
        running: [BillingSegmentDTO] = [], recent: [BillingSegmentDTO] = [],
        overview: BillingOverviewDTO? = nil
    ) {
        pane.show(running: running, recent: recent, projects: projects, overview: overview)
    }

    /// `EditableTableCellValue` is not `Equatable`, and a test only cares what it reads as.
    private func cell(_ pane: BillingActivityViewController, _ rowID: String, _ column: String) -> String {
        let card: ComposableSettings.EditableTableCard = pane.runsCard
        return shownCell(card.rows.first(where: { $0.id == rowID })?.cells[column],
                         timeZone: card.timeZone, locale: card.locale)
    }

    /// Picks a menu item the way a click does, so the popup's own action runs.
    private func choose(_ popup: NSPopUpButton, _ title: String) {
        popup.selectItem(withTitle: title)
        XCTAssertEqual(popup.titleOfSelectedItem, title, "no item titled \(title)")
        _ = popup.sendAction(popup.action, to: popup.target)
    }

    // MARK: - Runs

    func testRunsAreTheRecentOnesAndTheRunningOnesNewestFirst() {
        let pane = makePane()
        let early = run("early", start: "2026-09-22T06:00:00Z")
        let late = run("late", start: "2026-09-22T08:00:00Z")
        // Started 20 days ago, so it is older than the recent list reaches,
        // but it is still running, so it is listed.
        let old = running("old", origin: "manual", start: "2026-09-02T09:00:00Z")
        let now = running("now")

        show(pane, running: [old, now], recent: [early, now, late])

        XCTAssertEqual(pane.runsCard.rows.map(\.id), ["now", "late", "early", "old"])
    }

    func testARunningRowCountsFromItsStart() {
        let pane = makePane()
        show(pane, running: [running("r", branch: "main")])

        XCTAssertEqual(cell(pane, "r", "running"), "●")
        XCTAssertEqual(cell(pane, "r", "project"), "Website")
        XCTAssertEqual(cell(pane, "r", "repository"), "/src/site · main")
        XCTAssertEqual(cell(pane, "r", "started"), "Sep 22, 9:00 AM", "the viewer's own clock")
        XCTAssertEqual(cell(pane, "r", "elapsed"), "0:30:00")
        XCTAssertEqual(cell(pane, "r", "origin"), "Tracked")
        XCTAssertEqual(cell(pane, "r", "status"), "Running")
    }

    func testAStoppedRowShowsItsLength() {
        let pane = makePane()
        show(pane, recent: [run("t", origin: "manual", project: nil, root: "", seconds: 5400)])

        XCTAssertEqual(cell(pane, "t", "running"), "○")
        XCTAssertEqual(cell(pane, "t", "project"), "Unassigned")
        XCTAssertEqual(cell(pane, "t", "repository"), "(No repository)")
        XCTAssertEqual(cell(pane, "t", "elapsed"), "1:30:00")
        XCTAssertEqual(cell(pane, "t", "origin"), "Timer")
    }

    func testStatusSaysWhereEachRunStands() {
        let pane = makePane()
        show(pane,
             running: [running("cap", start: "2026-09-22T07:00:00Z", flags: "runaway"), running("going")],
             recent: [run("billed", entry: "e1"), run("loose", project: nil), run("waiting")])

        XCTAssertEqual(cell(pane, "cap", "status"), "Past the cap")
        XCTAssertEqual(cell(pane, "going", "status"), "Running")
        XCTAssertEqual(cell(pane, "billed", "status"), "On a billable")
        XCTAssertEqual(cell(pane, "loose", "status"), "Unassigned")
        XCTAssertEqual(cell(pane, "waiting", "status"), "Not on a billable")
    }

    func testARunawayIsFlaggedAndItsLiveRowSaysSo() {
        let pane = makePane()
        show(pane,
             running: [running("cap", flags: "runaway")],
             recent: [run("was", entry: "e1", flags: "runaway"), run("fine")])

        let flagged = pane.runsCard.rows.filter(\.isFlagged).map(\.id)
        XCTAssertEqual(Set(flagged), ["cap", "was"])
        XCTAssertEqual(pane.runningList.rows.first?.model.subtitle, "/src/site · Running past the cap")
    }

    // MARK: - Running timers

    func testEachRunningTimerGetsARowAndOnlyTimersCanBeStopped() {
        let pane = makePane()
        show(pane, running: [
            running("tracked", branch: "main", start: "2026-09-22T08:00:00Z"),
            running("timer", origin: "manual", project: nil, root: "", note: "Kickoff call")
        ])

        XCTAssertEqual(pane.runningList.rows.map(\.model.id), ["timer", "tracked"])
        XCTAssertEqual(pane.runningList.rows.map(\.model.title), ["Unassigned", "Website"])
        XCTAssertEqual(pane.runningList.rows.map(\.model.subtitle), ["Kickoff call", "/src/site · main"])
        XCTAssertEqual(pane.runningList.rows.map(\.model.isManual), [true, false])
        XCTAssertEqual(pane.runningList.rows.map(\.stopButton.isHidden), [false, true])
        XCTAssertTrue(pane.runningList.emptyLabel.isHidden)

        show(pane)

        XCTAssertTrue(pane.runningList.rows.isEmpty)
        XCTAssertFalse(pane.runningList.emptyLabel.isHidden)
        XCTAssertEqual(pane.runningList.emptyLabel.stringValue, "No timers running.")
    }

    func testARowIsKeptWhileItsTimerRuns() {
        let pane = makePane()
        show(pane, running: [running("timer", origin: "manual")])
        let row = pane.runningList.rows.first

        show(pane, running: [running("timer", origin: "manual", note: "Renamed")])

        XCTAssertTrue(pane.runningList.rows.first === row, "a reload updates the row, it does not rebuild it")
        XCTAssertEqual(row?.model.subtitle, "/src/site · Renamed")
    }

    func testStoppingATimerReportsIt() {
        let pane = makePane()
        var stopped: [String] = []
        pane.onStop = { stopped.append($0.id) }
        show(pane, running: [running("timer", origin: "manual")])

        pane.runningList.rows.first?.stopButton.performClick(nil)

        XCTAssertEqual(stopped, ["timer"])
    }

    func testTheTickerMovesBothClocks() {
        let pane = makePane()
        setOnScreen(pane, true)
        show(pane, running: [running("r")])
        XCTAssertEqual(cell(pane, "r", "elapsed"), "0:30:00")

        current += 60
        pane.runningList.ticker.fireForTests()

        XCTAssertEqual(cell(pane, "r", "elapsed"), "0:31:00")
        XCTAssertEqual(pane.runningList.rows.first?.elapsedText, "0:31:00")
    }

    func testTheTickerRunsOnlyOnScreenWithSomethingRunning() {
        let pane = makePane()
        var ticks = 0
        let onTick = pane.runningList.ticker.onTick
        pane.runningList.ticker.onTick = { ticks += 1; onTick?() }

        show(pane, running: [running("r")])
        pane.runningList.ticker.fireForTests()
        XCTAssertEqual(ticks, 0, "off screen: not started")

        setOnScreen(pane, true)
        pane.runningList.ticker.fireForTests()
        XCTAssertEqual(ticks, 1)

        show(pane)
        pane.runningList.ticker.fireForTests()
        XCTAssertEqual(ticks, 1, "nothing running: stopped")

        show(pane, running: [running("r")])
        setOnScreen(pane, false)
        pane.runningList.ticker.fireForTests()
        XCTAssertEqual(ticks, 1, "closed: stopped")
    }

    /// Review V17-d: a window behind others or on another Space can't be
    /// seen, so it has no clock to move; it catches up the moment it shows.
    func testTheTickerStopsWhileTheWindowIsHidden() {
        let pane = makePane()
        var ticks = 0
        let onTick = pane.runningList.ticker.onTick
        pane.runningList.ticker.onTick = { ticks += 1; onTick?() }
        setOnScreen(pane, true)
        show(pane, running: [running("r")])

        setOnScreen(pane, false)
        pane.runningList.ticker.fireForTests()
        XCTAssertEqual(ticks, 0, "covered: stopped")

        current += 120
        setOnScreen(pane, true)
        XCTAssertEqual(cell(pane, "r", "elapsed"), "0:32:00", "caught up as it shows, not a second later")
        pane.runningList.ticker.fireForTests()
        XCTAssertEqual(ticks, 1, "running again")
    }

    /// Review V17-a: the once-a-second tick redraws the running rows alone.
    /// A whole reload every second rebuilt every cell under the pointer and
    /// dropped a cell being edited in another row.
    func testATickRedrawsOnlyTheRunningRows() {
        let pane = makePane()
        pane.view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        setOnScreen(pane, true)
        show(pane, running: [running("r")], recent: [run("done")])
        pane.view.layoutSubtreeIfNeeded()
        let table = pane.runsCard.tableView
        let doneIndex = pane.runsCard.rows.firstIndex { $0.id == "done" }!
        let before = table.view(atColumn: 0, row: doneIndex, makeIfNecessary: true)
        pane.select(runId: "done")

        current += 60
        pane.runningList.ticker.fireForTests()

        XCTAssertEqual(cell(pane, "r", "elapsed"), "0:31:00")
        XCTAssertTrue(table.view(atColumn: 0, row: doneIndex, makeIfNecessary: true) === before,
                      "a stopped row is not rebuilt by the tick")
        XCTAssertEqual(pane.runsCard.selectedRowID, "done")
    }

    // MARK: - New timer

    func testTheProjectPopupOffersActiveProjectsByName() {
        let pane = makePane()
        show(pane)

        XCTAssertEqual(pane.projectPopup.popUpButton.itemTitles, ["No Project", "api", "Website"])
        XCTAssertNil(pane.chosenProjectId)
    }

    func testAChosenProjectThatIsArchivedFallsBackToNoProject() {
        let pane = makePane()
        var chosen: [String?] = []
        pane.onProjectChosen = { chosen.append($0) }
        show(pane)
        choose(pane.projectPopup.popUpButton, "Website")

        pane.show(running: [], recent: [],
                  projects: [BillingProjectDTO(id: "p1", name: "Website", archived: true), api],
                  overview: nil)

        XCTAssertNil(pane.chosenProjectId)
        XCTAssertEqual(pane.projectPopup.popUpButton.titleOfSelectedItem, "No Project")
        XCTAssertEqual(chosen, ["p1", nil])
    }

    func testChoosingAProjectAsksForItsRepositories() {
        let pane = makePane()
        var chosen: [String?] = []
        pane.onProjectChosen = { chosen.append($0) }
        show(pane)
        XCTAssertFalse(pane.repositoryPopup.popUpButton.isEnabled)

        choose(pane.projectPopup.popUpButton, "Website")

        XCTAssertEqual(chosen, ["p1"])
        XCTAssertEqual(pane.chosenProjectId, "p1")
        XCTAssertEqual(pane.repositoryPopup.popUpButton.itemTitles, ["Any Repository"])
        XCTAssertFalse(pane.repositoryPopup.popUpButton.isEnabled, "no repositories yet")
        // Review V32-c: the whole row greys, not the popup beside a live title.
        XCTAssertLessThan(pane.repositoryPopup.label.alphaValue, 1, "its title dims with it")

        // A late answer for a project no longer chosen is dropped.
        pane.showRepos([BillingRepoDTO(id: "r9", projectId: "p3", projectRoot: "/src/api")], projectId: "p3")
        XCTAssertEqual(pane.repositoryPopup.popUpButton.itemTitles, ["Any Repository"])

        pane.showRepos([
            BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/src/site"),
            BillingRepoDTO(id: "r2", projectId: "p1", projectRoot: "/src/site", branch: "release")
        ], projectId: "p1")

        XCTAssertEqual(pane.repositoryPopup.popUpButton.itemTitles,
                       ["Any Repository", "/src/site", "/src/site · release"])
        XCTAssertTrue(pane.repositoryPopup.popUpButton.isEnabled)
        XCTAssertEqual(pane.repositoryPopup.label.alphaValue, 1)

        choose(pane.projectPopup.popUpButton, "No Project")

        XCTAssertEqual(chosen, ["p1", nil])
        XCTAssertEqual(pane.repositoryPopup.popUpButton.itemTitles, ["Any Repository"])
        XCTAssertFalse(pane.repositoryPopup.popUpButton.isEnabled)
    }

    func testStartReportsTheChosenProjectRepositoryAndNote() {
        let pane = makePane()
        var started: [BillingTimerStartDTO] = []
        pane.onStart = { started.append($0) }
        show(pane)
        choose(pane.projectPopup.popUpButton, "Website")
        pane.showRepos([
            BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/src/site"),
            BillingRepoDTO(id: "r2", projectId: "p1", projectRoot: "/src/site", branch: "release")
        ], projectId: "p1")
        choose(pane.repositoryPopup.popUpButton, "/src/site · release")
        pane.noteField.textField.stringValue = "  Kickoff call "

        pane.startButton.performClick(nil)

        XCTAssertEqual(started, [BillingTimerStartDTO(
            projectId: "p1", repoId: "r2", projectRoot: "/src/site", branch: "release", note: "Kickoff call")])

        pane.clearNote()
        XCTAssertEqual(pane.noteField.textField.stringValue, "")
    }

    func testStartWithNoProjectStartsAnUnassignedTimer() {
        let pane = makePane()
        var started: [BillingTimerStartDTO] = []
        pane.onStart = { started.append($0) }
        show(pane)

        pane.startButton.performClick(nil)

        XCTAssertEqual(started, [BillingTimerStartDTO(projectId: nil, repoId: nil, projectRoot: "",
                                                      branch: "", note: "")])
    }

    // MARK: - The footer

    func testTheFooterFollowsTheSelectedRun() {
        let pane = makePane()
        show(pane,
             running: [running("timer", origin: "manual"), running("tracked", start: "2026-09-22T08:50:00Z")],
             recent: [run("done"), run("billed", entry: "e1"), run("loose", project: nil)])

        func buttons() -> [Bool] {
            [pane.stopButton.isEnabled, pane.createBillableButton.isEnabled, pane.assignButton.isEnabled]
        }

        XCTAssertEqual(buttons(), [false, false, false], "nothing selected")
        pane.select(runId: "timer")
        XCTAssertEqual(buttons(), [true, false, true])
        pane.select(runId: "tracked")
        XCTAssertEqual(buttons(), [false, false, true], "a tracked run ends on its own")
        pane.select(runId: "done")
        XCTAssertEqual(buttons(), [false, true, true])
        pane.select(runId: "billed")
        XCTAssertEqual(buttons(), [false, false, false], "time on a billable stays where it is")
        pane.select(runId: "loose")
        XCTAssertEqual(buttons(), [false, false, true], "a billable needs a project")
    }

    func testStopAndCreateBillableReportTheSelectedRun() {
        let pane = makePane()
        var stopped: [String] = []
        var promoted: [String] = []
        pane.onStop = { stopped.append($0.id) }
        pane.onCreateBillable = { promoted.append($0.id) }
        show(pane, running: [running("timer", origin: "manual")], recent: [run("done")])

        pane.select(runId: "timer")
        pane.stopButton.performClick(nil)
        pane.select(runId: "done")
        pane.createBillableButton.performClick(nil)

        XCTAssertEqual(stopped, ["timer"])
        XCTAssertEqual(promoted, ["done"])
    }

    func testAssignOffersTheOtherActiveProjects() {
        let pane = makePane()
        var assigned: [String] = []
        pane.onAssign = { assigned.append("\($0.id)→\($1)") }
        show(pane, recent: [run("done"), run("loose", project: nil)])

        pane.select(runId: "done")
        XCTAssertEqual(pane.assignMenuItems().map(\.title), ["api"], "not its own project, not archived ones")

        pane.select(runId: "loose")
        let menu = NSMenu()
        pane.assignMenuItems().forEach(menu.addItem)
        XCTAssertEqual(menu.items.map(\.title), ["api", "Website"])
        menu.performActionForItem(at: 1)

        XCTAssertEqual(assigned, ["loose→p1"])
    }

    /// Review V32-b: Assign is a pull-down, so it says it opens a menu, and
    /// what it offers is read from the run selected as it opens.
    func testAssignIsAPullDownBuiltAsItOpens() {
        let pane = makePane()
        show(pane, recent: [run("done"), run("loose", project: nil)])
        let button = pane.assignButton!

        XCTAssertTrue(button.pullsDown)
        XCTAssertEqual(button.cell?.accessibilityRole(), .menuButton)

        pane.select(runId: "done")
        button.menu.map { $0.delegate?.menuNeedsUpdate?($0) }
        XCTAssertEqual(Array(button.itemTitles.dropFirst()), ["api"])

        pane.select(runId: "loose")
        button.menu.map { $0.delegate?.menuNeedsUpdate?($0) }
        XCTAssertEqual(Array(button.itemTitles.dropFirst()), ["api", "Website"])
    }

    // MARK: - History and overview

    func testDeriveHistoryReportsTheChosenSpan() {
        let pane = makePane()
        var spans: [Int] = []
        pane.onDeriveHistory = { spans.append($0) }
        show(pane)
        XCTAssertEqual(pane.deriveSpanPopup.popUpButton.itemTitles,
                       ["Last 7 Days", "Last 30 Days", "Last 90 Days"])
        XCTAssertEqual(pane.deriveSpanPopup.popUpButton.titleOfSelectedItem, "Last 30 Days")

        pane.deriveButton.performClick(nil)
        choose(pane.deriveSpanPopup.popUpButton, "Last 90 Days")
        pane.deriveButton.performClick(nil)

        XCTAssertEqual(spans, [30, 90])
        XCTAssertTrue(pane.notice.isHidden)
        XCTAssertEqual(pane.notice.superview?.isHidden, true)
        pane.showNotice("Queued.")
        XCTAssertFalse(pane.notice.isHidden)
        XCTAssertEqual(pane.notice.superview?.isHidden, false, "review V32-a: its card row shows too")
        XCTAssertEqual(pane.notice.text, "Queued.")
        pane.showNotice(nil)
        XCTAssertTrue(pane.notice.isHidden)
        XCTAssertEqual(pane.notice.superview?.isHidden, true)
    }

    func testTheOverviewDescribesEachStatus() {
        let pane = makePane()
        show(pane)
        XCTAssertEqual([pane.unbilledRow.value, pane.billedRow.value, pane.paidRow.value], ["—", "—", "—"])

        show(pane, overview: BillingOverviewDTO(
            unbilled: BillingOverviewBucketDTO(seconds: 9000, amountCents: 25_000, entryCount: 2),
            billed: BillingOverviewBucketDTO(seconds: 3600, amountCents: 10_000, entryCount: 1),
            paid: BillingOverviewBucketDTO(seconds: 0, amountCents: 0, entryCount: 0)
        ))

        XCTAssertEqual(pane.unbilledRow.value, "2 billables · 2.50 h · $250.00")
        XCTAssertEqual(pane.billedRow.value, "1 billable · 1.00 h · $100.00")
        XCTAssertEqual(pane.paidRow.value, "—")
    }

    /// Two currencies are never one sum: hours and counts add, the money is
    /// listed per currency.
    func testTheOverviewKeepsCurrenciesApart() {
        let pane = makePane()
        let none = BillingOverviewBucketDTO(seconds: 0, amountCents: 0, entryCount: 0)
        let usd = BillingOverviewCurrencyDTO(
            currency: "USD",
            unbilled: BillingOverviewBucketDTO(seconds: 3600, amountCents: 10_000, entryCount: 1),
            billed: none, paid: none)
        let eur = BillingOverviewCurrencyDTO(
            currency: "EUR",
            unbilled: BillingOverviewBucketDTO(seconds: 1800, amountCents: 4_000, entryCount: 1),
            billed: BillingOverviewBucketDTO(seconds: 3600, amountCents: 8_000, entryCount: 1), paid: none)
        show(pane, overview: BillingOverviewDTO(
            unbilled: usd.unbilled, billed: usd.billed, paid: usd.paid, currency: "USD", byCurrency: [usd, eur]
        ))

        let unbilled = pane.unbilledRow.value
        XCTAssertTrue(unbilled.hasPrefix("2 billables · 1.50 h · "), unbilled)
        XCTAssertTrue(unbilled.contains("$100.00"), unbilled)
        XCTAssertTrue(unbilled.contains("€40.00"), unbilled)
        XCTAssertFalse(unbilled.contains("140"), "never one mixed sum: \(unbilled)")
        XCTAssertTrue(pane.billedRow.value.contains("€80.00"), pane.billedRow.value)
        XCTAssertEqual(pane.paidRow.value, "—")
    }
}
