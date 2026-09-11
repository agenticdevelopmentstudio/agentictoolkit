import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class TabPaneViewControllerTests: XCTestCase {
    private final class StubSource: TabPaneDataSource {
        var agent = "Claude"
        var model: String? = "Fable 5.1"
        var symbols = [TabPaneStatusSymbol.idle]
        var session = "tabs"
        var directory = URL(fileURLWithPath: "/tmp/repo/.claude/worktrees/tabs")
        var branch: String? = "tabs"
        var summary: String?

        func tabPaneAgentName(_ pane: TabPaneViewController) -> String { agent }
        func tabPaneModelName(_ pane: TabPaneViewController) -> String? { model }
        func tabPaneStatusSymbols(_ pane: TabPaneViewController) -> [TabPaneStatusSymbol] { symbols }
        func tabPaneSessionName(_ pane: TabPaneViewController) -> String { session }
        func tabPaneWorkingDirectory(_ pane: TabPaneViewController) -> URL { directory }
        func tabPaneBranch(_ pane: TabPaneViewController) -> String? { branch }
        func tabPaneSummary(_ pane: TabPaneViewController) -> String? { summary }
    }

    private final class StubDelegate: TabPaneDelegate {
        var menu = NSMenu()
        var asked = 0
        func tabPane(_ pane: TabPaneViewController, contextMenuFor event: NSEvent) -> NSMenu? {
            asked += 1
            return menu
        }
    }

    private func makePane(edge: Edge, source: StubSource) -> TabPaneViewController {
        let pane = TabPaneViewController(edge: edge, tabID: UUID())
        pane.dataSource = source
        pane.loadViewIfNeeded()
        pane.reload()
        return pane
    }

    func testReloadFillsTheLabelsFromTheDataSource() {
        let source = StubSource()
        let pane = makePane(edge: .left, source: source)
        XCTAssertEqual(pane.paneView.agentLabel.stringValue, "Claude · Fable 5.1")
        XCTAssertEqual(pane.paneView.sessionLabel.stringValue, "tabs")
        XCTAssertEqual(pane.paneView.branchLabel.stringValue, "tabs")
        XCTAssertTrue(pane.paneView.directoryLabel.stringValue.hasSuffix("worktrees/tabs"))
        XCTAssertTrue(pane.paneView.summaryLabel.isHidden)
    }

    func testAModelOfNilShowsOnlyTheAgent() {
        let source = StubSource()
        source.model = nil
        let pane = makePane(edge: .left, source: source)
        XCTAssertEqual(pane.paneView.agentLabel.stringValue, "Claude")
    }

    func testSideEdgesAreStackedAndTopEdgesAreARow() {
        let source = StubSource()
        let left = makePane(edge: .left, source: source)
        let top = makePane(edge: .top, source: source)
        XCTAssertEqual(left.preferredContentSize.width, 220)
        XCTAssertGreaterThan(left.preferredContentSize.height, 28)
        XCTAssertEqual(top.preferredContentSize.height, 28)
        XCTAssertLessThanOrEqual(top.preferredContentSize.width, 320)
    }

    func testAccessibilityIdentifiersCarryTheTabID() {
        let source = StubSource()
        let pane = makePane(edge: .left, source: source)
        let id = pane.tabID.uuidString
        XCTAssertEqual(pane.view.accessibilityIdentifier(), "tab-pane.\(id)")
        XCTAssertEqual(pane.paneView.agentLabel.accessibilityIdentifier(), "tab-pane.agent.\(id)")
        XCTAssertEqual(pane.paneView.sessionLabel.accessibilityIdentifier(), "tab-pane.session.\(id)")
        XCTAssertEqual(pane.paneView.branchLabel.accessibilityIdentifier(), "tab-pane.branch.\(id)")
        XCTAssertEqual(pane.paneView.directoryLabel.accessibilityIdentifier(), "tab-pane.directory.\(id)")
        XCTAssertEqual(pane.paneView.closeButton.accessibilityIdentifier(), "tab-pane.close.\(id)")
    }

    func testClosePressedFiresOnClose() {
        let source = StubSource()
        let pane = makePane(edge: .left, source: source)
        var closed = false
        pane.onClose = { closed = true }
        pane.paneView.closeButton.performClick(nil)
        XCTAssertTrue(closed)
    }

    func testContextMenuComesFromTheDelegate() {
        let source = StubSource()
        let delegate = StubDelegate()
        let pane = makePane(edge: .left, source: source)
        pane.delegate = delegate
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        XCTAssertTrue(pane.paneView.menu(for: event) === delegate.menu)
        XCTAssertEqual(delegate.asked, 1)
    }
}
