import AppKit
import XCTest

import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The window shape the Clients and Projects windows are both made of.
@MainActor
final class RecordDetailWindowControllerTests: XCTestCase {

    private struct Client: RecordDetailItem {
        let id: String
        var recordTitle: String
        var note: String = ""
    }

    /// A panel that records what it was told, so the tests can see that an
    /// update reached the pane instead of a new pane being built behind it.
    private final class ClientPanel: ComposableSettings.SettingsPanelViewController {
        // `descriptor` is the base class's `public let`; only its `@Published`
        // title moves.
        private(set) var appliedNotes: [String] = []
        func apply(_ client: Client) {
            descriptor.title = client.recordTitle
            appliedNotes.append(client.note)
        }
    }

    private var built = 0

    private func makeController() -> ComposableSettings.RecordDetailWindowController<Client> {
        built = 0
        let controller = ComposableSettings.RecordDetailWindowController<Client>(
            windowID: "test.clients-\(UUID().uuidString)",
            title: "Clients",
            accessibilityPrefix: "test.clients",
            makeDetailPanel: { [weak self] _ in
                self?.built += 1
                return ClientPanel()
            },
            updateDetailPanel: { panel, client in
                (panel as? ClientPanel)?.apply(client)
            })
        // The split builds its detail container in `viewDidLoad`, and nothing
        // can be *shown* before that: setting a window's contentViewController
        // is what loads it.
        _ = controller.window
        return controller
    }

    private let acme = Client(id: "c1", recordTitle: "Acme")
    private let bolt = Client(id: "c2", recordTitle: "Bolt")

    // MARK: - The list

    func testRecordsBecomeSidebarPanels() {
        let controller = makeController()

        controller.setRecords([acme, bolt])

        XCTAssertEqual(controller.viewController?.panels.map(\.descriptor.title), ["Acme", "Bolt"])
    }

    func testTheFirstRecordIsSelectedSoTheDetailPaneIsNeverBlank() {
        let controller = makeController()

        controller.setRecords([acme, bolt])

        XCTAssertEqual(controller.selectedRecord?.id, "c1")
    }

    func testTheOrderIsTheModelsOwn() {
        let controller = makeController()

        controller.setRecords([bolt, acme])

        XCTAssertEqual(
            controller.viewController?.panels.map(\.descriptor.title), ["Bolt", "Acme"],
            "sorting here would make a rename jump the row out from under the cursor")
    }

    // MARK: - Updates

    func testAnUpdatedRecordKeepsItsPanel() {
        let controller = makeController()
        controller.setRecords([acme])
        let panel = controller.viewController?.panels.first as? ClientPanel

        var renamed = acme
        renamed.recordTitle = "Acme Ltd"
        renamed.note = "second"
        controller.setRecords([renamed])

        XCTAssertEqual(built, 1, "a rebuilt panel destroys the field being typed into")
        XCTAssertIdentical(controller.viewController?.panels.first as? ClientPanel, panel)
        XCTAssertEqual(panel?.appliedNotes, ["", "second"])
        XCTAssertEqual(controller.viewController?.panels.first?.descriptor.title, "Acme Ltd")
    }

    func testSelectionSurvivesAReload() {
        let controller = makeController()
        controller.setRecords([acme, bolt])
        controller.selectRecord(id: "c2")

        controller.setRecords([acme, bolt])

        XCTAssertEqual(controller.selectedRecord?.id, "c2")
    }

    func testDeletingTheSelectedRecordSelectsItsNeighbour() {
        let controller = makeController()
        controller.setRecords([acme, bolt])
        controller.selectRecord(id: "c2")

        controller.setRecords([acme])

        XCTAssertEqual(controller.selectedRecord?.id, "c1",
                       "an empty detail pane after a delete reads as a broken window")
    }

    func testAnEmptyListSelectsNothingAndSaysSo() {
        let controller = makeController()
        controller.emptyMessage = "No clients yet."
        controller.setRecords([acme])

        controller.setRecords([])

        XCTAssertNil(controller.selectedRecord)
        XCTAssertFalse(controller.footer.isRemoveEnabled)
        XCTAssertFalse(controller.footer.trailingView?.isHidden ?? true)
    }

    // MARK: - The footer

    func testTheFooterIsUnderTheSidebar() throws {
        let controller = makeController()
        let list = try XCTUnwrap(controller.viewController?.listViewController)

        XCTAssertTrue(controller.footer.isDescendant(of: list.view))
    }

    func testAddAndRemoveReportOut() {
        let controller = makeController()
        var added = 0
        var removed: [String] = []
        controller.onAddRecord = { added += 1 }
        controller.onRemoveRecord = { removed.append($0.id) }
        controller.setRecords([acme, bolt])
        controller.selectRecord(id: "c2")

        controller.footer.addButton.performClick(nil)
        controller.footer.removeButton.performClick(nil)

        XCTAssertEqual(added, 1)
        XCTAssertEqual(removed, ["c2"])
    }

    func testRemoveIsDeadWithNothingSelected() {
        let controller = makeController()
        var removed: [String] = []
        controller.onRemoveRecord = { removed.append($0.id) }

        controller.setRecords([])
        controller.footer.removeButton.performClick(nil)

        XCTAssertFalse(controller.footer.isRemoveEnabled)
        XCTAssertTrue(removed.isEmpty)
    }

    // MARK: - Selection reporting

    func testSelectingAnotherRecordIsReportedOnce() {
        let controller = makeController()
        controller.setRecords([acme, bolt])
        var seen: [String?] = []
        controller.onSelectRecord = { seen.append($0?.id) }

        controller.selectRecord(id: "c2")
        controller.setRecords([acme, bolt])

        XCTAssertEqual(seen, ["c2"], "a reload that changed nothing must not re-announce the selection")
    }
}
