import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class BranchControllerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("branch-controller-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    private func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = tempRoot
        try process.run()
        process.waitUntilExit()
    }

    private func makeController(branch: String? = "main") -> BranchController {
        let checkout = ProjectCheckout(directory: tempRoot, branch: branch, isMain: true)
        return BranchController(checkout: checkout, gitClient: GitClient(configuration: .default))
    }

    func testAVendedPaneShowsThePlaceholdersAndTheCheckout() {
        let controller = makeController()
        let pane = controller.makeTabPane(edge: .left, tabID: UUID())
        pane.loadViewIfNeeded()
        pane.reload()
        XCTAssertEqual(pane.paneView.agentLabel.stringValue, "Claude")
        XCTAssertEqual(pane.paneView.sessionLabel.stringValue, "main")
        XCTAssertEqual(pane.paneView.branchLabel.stringValue, "main")
        XCTAssertTrue(pane.paneView.directoryLabel.stringValue.hasSuffix(tempRoot.lastPathComponent))
        XCTAssertTrue(pane.paneView.summaryLabel.isHidden)
        XCTAssertTrue(pane.dataSource === controller)
        XCTAssertTrue(pane.delegate === controller)
    }

    func testRefreshReadsTheBranchFromGitAndReloadsPanes() async throws {
        try git(["init", "-b", "feature"])
        try git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "init"])
        let controller = makeController(branch: nil)
        let pane = controller.makeTabPane(edge: .left, tabID: UUID())
        pane.loadViewIfNeeded()
        await controller.refresh()
        XCTAssertEqual(controller.currentBranch, "feature")
        XCTAssertEqual(pane.paneView.branchLabel.stringValue, "feature")
        XCTAssertEqual(pane.paneView.sessionLabel.stringValue, "feature")
    }

    func testCommandsAreNamespacedByCheckout() {
        let controller = makeController()
        let ids = controller.commands.map(\.id)
        let suffix = controller.checkout.identifier
        XCTAssertEqual(ids, [
            "branch.action.refreshStatus.\(suffix)",
            "branch.action.revealInFinder.\(suffix)",
            "branch.action.copyPath.\(suffix)"
        ])
        XCTAssertTrue(controller.commands.allSatisfy { $0.category == "Branch — main" })
    }

    /// A palette row is title + category; the id is namespaced but never shown.
    /// With every checkout's three commands reading "Refresh Status" under a
    /// bare "Branch", a two-worktree project offered six rows the user could
    /// not tell apart — and picking one was a coin flip over which directory it
    /// acted on. The checkout's `displayName` goes in the category rather than
    /// the title because the per-pane context menu renders titles alone, where
    /// the pane already says which checkout it is.
    func testCommandRowsAreDistinctAcrossTwoCheckouts() throws {
        let otherRoot = tempRoot.appendingPathComponent("feature-worktree")
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let main = makeController()
        let feature = BranchController(
            checkout: ProjectCheckout(directory: otherRoot, branch: "feature", isMain: false),
            gitClient: GitClient(configuration: .default)
        )

        let rows = (main.commands + feature.commands).map { "\($0.title)\t\($0.category)" }
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(Set(rows).count, 6, "every palette row must name the checkout it acts on")
        XCTAssertTrue(main.commands.allSatisfy { $0.category == "Branch — main" })
        XCTAssertTrue(feature.commands.allSatisfy { $0.category == "Branch — feature" })
    }

    func testTheContextMenuListsTheCommands() {
        let controller = makeController()
        let pane = controller.makeTabPane(edge: .left, tabID: UUID())
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let menu = controller.tabPane(pane, contextMenuFor: event)
        XCTAssertEqual(menu?.items.map(\.title), ["Refresh Status", "Reveal in Finder", "Copy Path"])
        // Ruling A's trap: `NSMenuItem.target` is weak. A `ClosureMenuItemTarget`
        // assigned only to `item.target` is deallocated before the menu is ever
        // shown, and every item's target silently comes back nil. Assert every
        // item still has a live target after the menu has been built and control
        // has returned to the caller, which is exactly the deallocation window.
        XCTAssertNotNil(menu?.items.first?.target)
        XCTAssertTrue(menu?.items.allSatisfy { $0.target != nil } ?? false)
    }
}
