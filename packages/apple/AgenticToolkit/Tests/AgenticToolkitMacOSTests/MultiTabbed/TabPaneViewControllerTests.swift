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

    /// Discriminates the `switch edge` in `TabPaneView.contentSize`: it reads
    /// back the two hardcoded literals (`sideWidth`, `rowHeight`) and nothing
    /// about layout or content — see `testLeftPaneHeightGrowsToFitStackedContent`
    /// and `testTopPaneWidthIsCappedAtRowMaxWidth` for the measured ones.
    func testEdgeSwitchRoutesTheHardcodedDimensions() {
        let source = StubSource()
        let left = makePane(edge: .left, source: source)
        let top = makePane(edge: .top, source: source)
        XCTAssertEqual(left.preferredContentSize.width, 220)
        XCTAssertEqual(top.preferredContentSize.height, 28)
    }

    /// Discriminates `TabPaneView.contentSize`'s
    /// `max(Self.rowHeight, fittingSize.height)` — a stacked left/right pane
    /// with real content measures taller than the 28pt floor.
    func testLeftPaneHeightGrowsToFitStackedContent() {
        let source = StubSource()
        let left = makePane(edge: .left, source: source)
        XCTAssertGreaterThan(left.preferredContentSize.height, 28)
    }

    /// Discriminates `TabPaneView.contentSize`'s
    /// `min(Self.rowMaxWidth, fittingSize.width)` — long enough content that
    /// `fittingSize.width` genuinely exceeds 320 still reports exactly 320,
    /// which only holds while the `min` is there.
    func testTopPaneWidthIsCappedAtRowMaxWidth() {
        let source = StubSource()
        source.agent = String(repeating: "Agent Name ", count: 20)
        source.model = String(repeating: "Model Name ", count: 20)
        source.session = String(repeating: "session-name-", count: 20)
        source.branch = String(repeating: "branch-name-", count: 20)
        source.summary = String(repeating: "summary text ", count: 20)
        let top = makePane(edge: .top, source: source)
        XCTAssertEqual(top.preferredContentSize.width, 320)
    }

    /// Discriminates the `~`-substitution branch of
    /// `TabPaneViewController.abbreviate`, which the other tests never
    /// exercise because their stub path sits outside the home directory.
    func testWorkingDirectoryUnderHomeIsAbbreviatedWithATilde() {
        let source = StubSource()
        // Same API `TabPaneViewController.abbreviate` reads, not
        // `NSHomeDirectory()` — the two are not guaranteed to agree, so a
        // mismatch here could go green against a production path this test
        // never actually exercises.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        source.directory = URL(fileURLWithPath: home + "/Projects/worktrees/tabs")
        let pane = makePane(edge: .left, source: source)
        XCTAssertEqual(pane.paneView.directoryLabel.stringValue, "~/Projects/worktrees/tabs")
    }

    /// Discriminates `TabPaneViewController.reload()`'s final
    /// `preferredContentSize = paneView.contentSize` line on a *second*
    /// call: branch stays visible across both reloads (so no row drops out
    /// to offset the new one) and only the summary row is newly added,
    /// so a second pass that skips recomputing `preferredContentSize`
    /// leaves it at the first call's (shorter) height.
    func testReloadTwiceFollowsChangedDataSourceValues() {
        let source = StubSource()
        let pane = makePane(edge: .left, source: source)
        let firstSize = pane.preferredContentSize

        source.agent = "Codex"
        source.model = nil
        source.session = "renamed-session"
        source.branch = "renamed-branch"
        source.summary = "now has a summary"
        pane.reload()

        XCTAssertEqual(pane.paneView.agentLabel.stringValue, "Codex")
        XCTAssertEqual(pane.paneView.sessionLabel.stringValue, "renamed-session")
        XCTAssertEqual(pane.paneView.branchLabel.stringValue, "renamed-branch")
        XCTAssertEqual(pane.paneView.summaryLabel.stringValue, "now has a summary")
        XCTAssertFalse(pane.paneView.summaryLabel.isHidden)
        XCTAssertGreaterThan(pane.preferredContentSize.height, firstSize.height)
    }

    /// Discriminates `TabPaneViewController.reload()`'s
    /// `paneView.branchLabel.isHidden = branch == nil` line specifically on
    /// a *second* call: the first `reload()` in `makePane` already leaves a
    /// non-nil branch visible, so only a genuine second pass that
    /// re-evaluates this line catches a branch that goes nil turning the
    /// label hidden.
    func testReloadTwiceHidesTheBranchLabelWhenBranchGoesNil() {
        let source = StubSource()
        let pane = makePane(edge: .left, source: source)
        XCTAssertFalse(pane.paneView.branchLabel.isHidden)

        source.branch = nil
        pane.reload()
        XCTAssertTrue(pane.paneView.branchLabel.isHidden)
    }

    /// Discriminates `TabPaneView.setStatusSymbols`'s
    /// `for view in statusViews { statusStack.removeView(view) }` — without
    /// it, a second call leaves the first call's symbol views parented
    /// alongside the new ones instead of replacing them.
    func testSetStatusSymbolsTwiceDoesNotAccumulateViews() {
        let source = StubSource()
        source.symbols = [TabPaneStatusSymbol.idle]
        let pane = makePane(edge: .left, source: source)
        XCTAssertEqual(pane.paneView.statusStack.arrangedSubviews.count, 1)

        source.symbols = [
            TabPaneStatusSymbol.idle,
            TabPaneStatusSymbol(symbolName: "bolt.fill", accessibilityLabel: "Busy"),
            TabPaneStatusSymbol(symbolName: "checkmark.circle", accessibilityLabel: "Done")
        ]
        pane.reload()
        XCTAssertEqual(pane.paneView.statusStack.arrangedSubviews.count, 3)
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
        XCTAssertEqual(pane.paneView.summaryLabel.accessibilityIdentifier(), "tab-pane.summary.\(id)")
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
