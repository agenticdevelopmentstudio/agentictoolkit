import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The Activity window against the in-memory daemon: it shows the model,
/// follows it, and every control ends in the right daemon call.
@MainActor
final class BillingActivityWindowControllerTests: XCTestCase {

    private var fake: FakeBillingClient!
    private var model: BillingModel!
    private var failures: [String] = []
    private var questions: [String] = []
    private var answer = true

    override func setUp() async throws {
        fake = FakeBillingClient.seeded()
        model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        failures = []
        questions = []
        answer = true
    }

    private func makeController() -> BillingActivityWindowController {
        let controller = BillingActivityWindowController(
            model: model,
            ask: { [unowned self] question, _, actionTitle, reply in
                questions.append(question)
                XCTAssertEqual(actionTitle, "Stop and Start")
                reply(answer)
            },
            reportFailure: { [unowned self] message in failures.append(message) },
            now: { ISO8601DateFormatter().date(from: "2026-09-22T12:00:00Z")! }
        )
        controller.viewController.timeZone = TimeZone(identifier: "UTC")!
        controller.showWindow()
        return controller
    }

    private func choose(_ popup: NSPopUpButton, _ title: String) {
        popup.selectItem(withTitle: title)
        XCTAssertEqual(popup.titleOfSelectedItem, title, "no item titled \(title)")
        _ = popup.sendAction(popup.action, to: popup.target)
    }

    private func manualTimers() -> [BillingSegmentDTO] {
        fake.segments.filter(\.isManual)
    }

    // MARK: - Showing the model

    func testTheWindowShowsWhatTheModelHolds() {
        let controller = makeController()
        let pane = controller.viewController

        XCTAssertEqual(controller.window?.title, "Billing Activity")
        XCTAssertEqual(controller.windowID, "billing.activity")
        XCTAssertEqual(pane.runsCard.rows.map(\.id), ["s-running", "s-loose"])
        XCTAssertEqual(pane.runningList.rows.map(\.model.id), ["s-running"])
        XCTAssertEqual(pane.runningList.rows.first?.stopButton.isHidden, true, "a tracked run")
        XCTAssertEqual(pane.unbilledRow.value, "2 billables · 2.50 h · $250.00")
        XCTAssertEqual(pane.billedRow.value, "—")
    }

    func testTheWindowFollowsTheModel() async {
        let controller = makeController()
        fake.segments.append(BillingSegmentDTO(
            id: "s-new", origin: "auto", projectId: "p1", projectRoot: "/src/site",
            startedAt: "2026-09-22T09:30:00Z", endedAt: "2026-09-22T09:45:00Z", seconds: 900))

        await model.refresh()

        XCTAssertEqual(controller.viewController.runsCard.rows.map(\.id), ["s-new", "s-running", "s-loose"])
    }

    func testChoosingAProjectLoadsItsRepositories() async {
        fake.repos = [BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/src/site", branch: "main")]
        let controller = makeController()

        choose(controller.viewController.projectPopup.popUpButton, "Website")
        await controller.lastRepoLoad?.value

        XCTAssertEqual(controller.viewController.repositoryPopup.popUpButton.itemTitles,
                       ["Any Repository", "/src/site · main"])
    }

    // MARK: - Timers

    func testStartingWithNothingRunningStartsAtOnce() async {
        let controller = makeController()
        let pane = controller.viewController
        choose(pane.projectPopup.popUpButton, "Website")
        await controller.lastRepoLoad?.value
        pane.noteField.textField.stringValue = "Kickoff"

        pane.startButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertTrue(questions.isEmpty, "a tracked run is not a timer, so nothing is stopped")
        XCTAssertEqual(fake.lastStartedTimer?.projectId, "p1")
        XCTAssertEqual(fake.lastStartedTimer?.note, "Kickoff")
        XCTAssertEqual(pane.noteField.textField.stringValue, "", "the note belongs to the timer now")
        XCTAssertEqual(pane.runningList.rows.map(\.model.id), ["s-1", "s-running"])
    }

    func testStartingWhileATimerRunsAsksFirst() async {
        let controller = makeController()
        let pane = controller.viewController
        choose(pane.projectPopup.popUpButton, "Website")
        pane.startButton.performClick(nil)
        await controller.lastWrite?.value
        XCTAssertEqual(manualTimers().count, 1)

        answer = false
        pane.startButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(questions, ["Stop “Website” and start a new timer?"])
        XCTAssertEqual(manualTimers().count, 1, "cancelled: nothing started")

        answer = true
        pane.startButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(manualTimers().count, 2)
    }

    func testStoppingATimerStopsIt() async throws {
        let controller = makeController()
        let pane = controller.viewController
        pane.startButton.performClick(nil)
        await controller.lastWrite?.value
        let row = try XCTUnwrap(pane.runningList.rows.first { $0.model.id == "s-1" })

        row.stopButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.segments.first { $0.id == "s-1" }?.endedAt, "2026-09-22T11:00:00Z")
        XCTAssertEqual(pane.runningList.rows.map(\.model.id), ["s-running"])
    }

    func testTheMenuCommandsStartAndStopTheTimer() async {
        let controller = makeController()
        XCTAssertFalse(controller.stopRunningTimer(), "no timer to stop")

        controller.requestStart(BillingTimerStartDTO(projectId: "p1"))
        await controller.lastWrite?.value
        XCTAssertEqual(manualTimers().count, 1)

        XCTAssertTrue(controller.stopRunningTimer())
        await controller.lastWrite?.value
        XCTAssertEqual(manualTimers().first?.endedAt, "2026-09-22T11:00:00Z")
    }

    // MARK: - Runs

    func testCreateBillableRollsTheRunUp() async {
        fake.segments.append(BillingSegmentDTO(
            id: "s-done", origin: "auto", projectId: "p1", projectRoot: "/src/site",
            startedAt: "2026-09-22T07:00:00Z", endedAt: "2026-09-22T07:30:00Z", seconds: 1800))
        await model.refresh()
        let controller = makeController()

        controller.viewController.select(runId: "s-done")
        controller.viewController.createBillableButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.lastPromotedIDs, ["s-done"])
    }

    func testAssignMovesTheRunAndRollsItUp() async {
        let controller = makeController()

        controller.viewController.select(runId: "s-loose")
        let menu = NSMenu()
        controller.viewController.assignMenuItems().forEach(menu.addItem)
        XCTAssertEqual(menu.items.map(\.title), ["Website"])
        menu.performActionForItem(at: 0)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.segments.first { $0.id == "s-loose" }?.projectId, "p1")
        XCTAssertEqual(fake.lastPromotedIDs, ["s-loose"])
        XCTAssertTrue(failures.isEmpty, "\(failures)")
    }

    /// Review V10-c: the run was rolled into a billable after the list was
    /// read, so the daemon moves nothing. The user is told, with the reason.
    func testAssigningARunAlreadyOnABillableIsReported() async {
        let controller = makeController()
        controller.viewController.select(runId: "s-loose")
        fake.segments = fake.segments.map { segment in
            segment.id != "s-loose" ? segment : BillingSegmentDTO(
                id: segment.id, origin: segment.origin, projectRoot: segment.projectRoot,
                startedAt: segment.startedAt, endedAt: segment.endedAt, seconds: segment.seconds,
                entryId: "e-rolled")
        }
        let menu = NSMenu()
        controller.viewController.assignMenuItems().forEach(menu.addItem)

        menu.performActionForItem(at: 0)
        await controller.lastWrite?.value

        XCTAssertEqual(failures, ["The run couldn't be assigned. \(BillingModel.alreadyOnABillable)"])
    }

    /// Review V6-c: a project that doesn't bill leaves the daemon nothing to
    /// roll up. It answers 0, and a click that does nothing says why.
    func testCreateBillableThatBillsNothingSaysSo() async {
        let controller = makeController()
        let run = try? XCTUnwrap(model.recentSegments.first { $0.id == "s-loose" })
        // The daemon's view: the run was rolled up since the list was read.
        fake.segments = fake.segments.map { segment in
            segment.id != "s-loose" ? segment : BillingSegmentDTO(
                id: segment.id, origin: segment.origin, projectRoot: segment.projectRoot,
                startedAt: segment.startedAt, endedAt: segment.endedAt, seconds: segment.seconds,
                entryId: "e-rolled")
        }

        controller.viewController.onCreateBillable?(run!)
        await controller.lastWrite?.value

        XCTAssertEqual(failures, [BillingActivityWindowController.nothingToBill])
    }

    func testDeriveHistoryQueuesItAndSaysSo() async {
        let controller = makeController()
        let pane = controller.viewController

        choose(pane.deriveSpanPopup.popUpButton, "Last 7 Days")
        pane.deriveButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.lastBackfillSince, "2026-09-15T12:00:00Z")
        XCTAssertEqual(pane.notice.text,
                       "Deriving history for 3 sessions. Runs appear over the next few minutes.")
        XCTAssertFalse(pane.notice.isHidden)
        // Review V32-a: the notice started hidden, and its card row copied
        // that when it was placed. The row has to come back with it.
        XCTAssertEqual(pane.notice.superview?.isHidden, false, "the notice's row is shown too")
        XCTAssertEqual(BillingActivityWindowController.deriveNotice(sessions: 0, days: 30),
                       "No sessions in the last 30 days to derive.")
        XCTAssertEqual(BillingActivityWindowController.deriveNotice(sessions: 1, days: 7),
                       "Deriving history for 1 session. Its runs appear over the next few minutes.")
    }

    // MARK: - Failure

    func testAFailedStartIsReported() async {
        let controller = makeController()
        fake.reachable = false

        controller.viewController.noteField.textField.stringValue = "Kickoff"
        controller.viewController.startButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first?.hasPrefix("The timer couldn't be started.") == true, "\(failures)")
        XCTAssertEqual(controller.viewController.noteField.textField.stringValue, "Kickoff",
                       "a failed start keeps what was typed")
        XCTAssertTrue(controller.viewController.startButton.isEnabled, "a failed start can be tried again")
    }

    /// Review V12-a: the menus' Stop Timer works through this controller
    /// before its window has ever been shown. A failure has to bring the
    /// window forward to be seen, not go to a sheet with no window.
    func testAFailureFromTheMenusBringsTheWindowForward() async {
        let controller = BillingActivityWindowController(
            model: model, ask: { _, _, _, _ in XCTFail("nothing to ask") },
            reportFailure: { [unowned self] message in failures.append(message) })
        defer { controller.window?.close() }
        fake.segments.append(BillingSegmentDTO(
            id: "t1", origin: BillingSegmentDTO.manualOrigin, projectId: "p1",
            startedAt: "2026-09-22T10:00:00Z"))
        await model.refresh()
        XCTAssertNotEqual(controller.window?.isVisible, true, "not opened yet")
        fake.reachable = false

        XCTAssertTrue(controller.stopRunningTimer())
        await controller.lastWrite?.value

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(controller.window?.isVisible, true,
                       "the alert needs a window on screen to sit on")
    }

    /// Review V12-b: two Starts before the first one's write lands. The
    /// second is the same click, not a second timer that would close the
    /// first a second after it began.
    func testADoubleClickedStartStartsOneTimer() async {
        let controller = makeController()
        let start = BillingTimerStartDTO(projectId: "p1")

        controller.requestStart(start)
        XCTAssertFalse(controller.viewController.startButton.isEnabled, "held while the start is sent")
        controller.requestStart(start)
        await controller.lastWrite?.value

        XCTAssertTrue(questions.isEmpty)
        XCTAssertEqual(manualTimers().count, 1)
        XCTAssertTrue(controller.viewController.startButton.isEnabled)
    }

    func testDecliningTheQuestionLetsTheNextStartThrough() async {
        let controller = makeController()
        controller.requestStart(BillingTimerStartDTO(projectId: "p1"))
        await controller.lastWrite?.value

        answer = false
        controller.requestStart(BillingTimerStartDTO(projectId: "p1"))
        XCTAssertTrue(controller.viewController.startButton.isEnabled, "a declined start holds nothing")
        answer = true
        controller.requestStart(BillingTimerStartDTO(projectId: "p1"))
        await controller.lastWrite?.value

        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(manualTimers().count, 2)
    }

    func testNewTimerPutsTheCursorInTheNote() throws {
        let controller = BillingActivityWindowController(model: model)
        // `SingleWindowController.window` is nil until `showWindow()` builds
        // it lazily — reading it does not load it. `presentNewTimer()` shows
        // the window before focusing, so the test does the same.
        controller.showWindow()
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(controller.focusNewTimer())

        let editor = try XCTUnwrap(window.firstResponder as? NSText, "a text field edits through the field editor")
        XCTAssertTrue(editor.delegate === controller.viewController.noteField.textField)
    }
}
