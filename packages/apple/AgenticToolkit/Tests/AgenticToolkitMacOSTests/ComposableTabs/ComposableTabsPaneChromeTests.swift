import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class ComposableTabsPaneChromeTests: XCTestCase {

    private final class TitledContent: NSViewController, PaneTitleProviding {
        var paneTitle = "notes.md" { didSet { onPaneTitleChange?() } }
        var onPaneTitleChange: (() -> Void)?
    }

    private final class TeardownContent: NSViewController, PaneContentTeardown {
        var torn = false
        func paneContentWillBeDiscarded() { torn = true }
    }

    private let plain = ComposableTabsViewID("test.plain")
    private let titled = ComposableTabsViewID("test.titled")

    private lazy var project = Self.makeWorkspace()

    /// A workspace backed by a throwaway database. These tests never read a row
    /// back — they need a project only because panes are built from one.
    @MainActor
    private static func makeWorkspace() -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaneChromeTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        // A failure here is a broken test environment, not a case to handle.
        // swiftlint:disable:next force_try
        let database = try! ProjectDatabase(path: path)
        return ProjectWorkspace(
            repo: GitRepo(path: NSTemporaryDirectory(), name: "Test"),
            database: database
        )
    }

    nonisolated override func tearDown() {
        // `install` is global; everything else here is per-test.
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    /// Installs a layout whose two pane types differ only in whether their
    /// content names itself, which is the distinction every title test needs.
    private func installLayout() throws {
        let registry = ComposableTabsViewRegistry()
        registry.register(plain, descriptor: .init(displayName: "Terminal")) { _ in
            NSViewController()
        }
        registry.register(titled, descriptor: .init(displayName: "Notes")) { _ in
            TitledContent()
        }
        ComposableTabsLayout.install(try ComposableTabsLayout(
            registry: registry,
            spec: .split(
                axis: .horizontal,
                children: [.pane(plain), .pane(titled)],
                allows: [.unbounded(plain), .unbounded(titled)]
            )
        ))
    }

    private func makePane(_ viewID: ComposableTabsViewID) throws -> ComposableTabsPaneViewController {
        try installLayout()
        let pane = ComposableTabsPaneViewController(
            nodeID: UUID(),
            paneNumber: project.allocatePaneNumber(),
            viewID: viewID,
            project: project
        )
        pane.loadViewIfNeeded()
        return pane
    }

    // MARK: - Chrome

    func testAPaneNowWearsATitleBar() throws {
        let pane = try makePane(plain)
        XCTAssertTrue(pane.view.subviews.contains { $0 === pane.titleBar })
        XCTAssertNotNil(pane.titleBar.gearView)
    }

    /// The registry's display name is the fallback, so a pane whose content has
    /// no opinion is still called what the Add popup called it.
    func testTheRegistryNamesAPaneWhoseContentDoesNot() throws {
        XCTAssertEqual(try makePane(plain).titleBar.title, "Terminal")
    }

    func testContentThatNamesItselfWins() throws {
        let pane = try makePane(titled)
        XCTAssertEqual(pane.titleBar.title, "notes.md")

        (pane.contentViewController as? TitledContent)?.paneTitle = "README.md"
        XCTAssertEqual(pane.titleBar.title, "README.md")
    }

    func testTheContentIsStillMountedAsAChild() throws {
        let pane = try makePane(plain)
        XCTAssertNotNil(pane.contentViewController)
        XCTAssertTrue(pane.children.contains { $0 === pane.contentViewController })
    }

    func testTheContainerIsStillTheBackgroundThatDrawsTheFocusOutline() throws {
        XCTAssertTrue(try makePane(plain).view is ComposableTabsPaneBackgroundView)
    }

    // MARK: - Identifiers

    func testAPanesIdentifierIsItsContentType() throws {
        XCTAssertEqual(try makePane(plain).view.accessibilityIdentifier(), "pane.plain")
    }

    func testASoleTerminalIsNotNumbered() throws {
        try installLayout()
        let root = ComposableTabsViewController.make(
            from: .leaf(contentType: plain), project: project, isRoot: true)
        _ = root.view
        root.reassignPaneIdentifiers()

        XCTAssertEqual(root.firstLeaf()?.view.accessibilityIdentifier(), "pane.plain")
    }

    func testTwoOfAKindInOneTabAreNumberedInTreeOrder() throws {
        try installLayout()
        let node = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: plain),
            second: .split(orientation: .vertical,
                           first: .leaf(contentType: titled),
                           second: .leaf(contentType: plain))
        )
        let root = ComposableTabsViewController.make(from: node, project: project, isRoot: true)
        _ = root.view
        root.reassignPaneIdentifiers()

        XCTAssertEqual(root.allLeaves().map { $0.view.accessibilityIdentifier() },
                       ["pane.plain.1", "pane.titled", "pane.plain.2"],
                       "the kind that appears twice is numbered; the one that appears once is not")
    }

    // MARK: - What did not change

    func testTearingDownStillReachesTheContent() throws {
        let registry = ComposableTabsViewRegistry()
        let teardown = ComposableTabsViewID("test.teardown")
        registry.register(teardown, descriptor: .init(displayName: "Teardown")) { _ in
            TeardownContent()
        }
        ComposableTabsLayout.install(try ComposableTabsLayout(
            registry: registry,
            spec: .split(axis: .horizontal,
                         children: [.pane(teardown)],
                         allows: [.unbounded(teardown)])
        ))

        let pane = ComposableTabsPaneViewController(
            nodeID: UUID(),
            paneNumber: project.allocatePaneNumber(),
            viewID: teardown,
            project: project
        )
        pane.loadViewIfNeeded()
        pane.paneWillBeRemoved()

        XCTAssertTrue((pane.contentViewController as? TeardownContent)?.torn == true)
    }
}
