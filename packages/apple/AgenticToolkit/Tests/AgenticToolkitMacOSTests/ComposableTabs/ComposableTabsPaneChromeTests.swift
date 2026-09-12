import AppKit
import AgenticDeveloperToolkitUI
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
            project: project,
            workingDirectory: project.directoryURL
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

    // MARK: - The gear menu

    /// `Move` is always in the menu, always with all four directions under it.
    /// Which of them are lit is the tree's business, re-read at every click; the
    /// menu's *shape* never changes, so the user learns one menu.
    func testTheGearMenuOffersMoveInEveryDirectionAboveSettings() throws {
        let pane = try makePane(plain)

        let menu = pane.makeOptionsMenu()
        XCTAssertEqual(menu.items.map(\.title), ["Move", "", "Settings…"])

        let move = try XCTUnwrap(menu.items.first)
        XCTAssertEqual(move.submenu?.items.map(\.title), ["Left", "Right", "Up", "Down"])
        XCTAssertEqual(
            move.submenu?.items.map { $0.accessibilityIdentifier() },
            ["pane.options.move.left", "pane.options.move.right",
             "pane.options.move.up", "pane.options.move.down"]
        )
    }

    /// A pane that is not in a split has nowhere to go. `Move` stays in the
    /// menu — the shape is fixed — but it is greyed out rather than opening
    /// onto four dead items.
    func testMoveIsDisabledForAPaneWithNoSplitAroundIt() throws {
        let pane = try makePane(plain)

        let move = try XCTUnwrap(pane.makeOptionsMenu().items.first)
        XCTAssertFalse(move.isEnabled)
        XCTAssertEqual(move.submenu?.items.filter(\.isEnabled).count, 0)
    }

    /// The overlay's pull-down and the gear menu are the same four items from
    /// the same builder; only the identifiers differ, because a UI test
    /// addresses two different surfaces.
    func testTheMoveItemsComeFromOneBuilder() {
        let builder = ComposableTabsMoveMenu()
        builder.availableDirections = { [.right] }
        var moved: [ComposableTabsViewController.Direction] = []
        builder.onMove = { moved.append($0) }

        let items = builder.makeItems(accessibilityPrefix: "surface.move")
        XCTAssertEqual(items.map(\.title), ["Left", "Right", "Up", "Down"])
        XCTAssertEqual(items.filter(\.isEnabled).map(\.title), ["Right"])
        XCTAssertEqual(items[1].accessibilityIdentifier(), "surface.move.right")

        _ = items[1].target?.perform(items[1].action, with: items[1])
        XCTAssertEqual(moved, [.right])
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

    // MARK: - The two planes a pane's backdrop paints

    /// The track the active-pane border is drawn in is the workspace's own
    /// backdrop — the plane the frame spacing, the gutters and the tab docked
    /// to the workspace's edge all show. Painted in the pane's fill instead, it
    /// put a hairline of window background between a tab and the workspace it
    /// belongs to, all the way round.
    func testTheTrackAroundAPaneIsTheWorkspaceBackdrop() throws {
        let view = try makePane(plain).view
        let palette = view.resolvedThemeScope.palette

        XCTAssertEqual(view.layer?.backgroundColor, NSColor(palette.projectPaneBackdrop).cgColor)
    }

    /// And the pane itself still paints `windowBackground`, inside that track:
    /// a pane reads as an object on the backdrop, which is the whole reason the
    /// two tones differ.
    func testThePaneItselfIsFilledInsideThatTrack() throws {
        let view = try makePane(plain).view
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.layoutSubtreeIfNeeded()

        let fill = try XCTUnwrap(view.subviews.compactMap { $0 as? ThemedBackgroundView }.first)
        let inset = ComposableTabsPaneBackgroundView.borderInset
        XCTAssertEqual(fill.frame, view.bounds.insetBy(dx: inset, dy: inset))
        XCTAssertEqual(fill.role, .windowBackground)
        XCTAssertEqual(view.subviews.firstIndex(of: fill), 0, "the fill must stay under the pane's chrome")
    }

    // MARK: - Identifiers

    func testAPanesIdentifierIsItsContentType() throws {
        XCTAssertEqual(try makePane(plain).view.accessibilityIdentifier(), "pane.plain")
    }

    func testASoleTerminalIsNotNumbered() throws {
        try installLayout()
        let root = ComposableTabsViewController.make(
            from: .leaf(contentType: plain), project: project,
            workingDirectory: project.directoryURL, isRoot: true)
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
        let root = ComposableTabsViewController.make(
            from: node, project: project, workingDirectory: project.directoryURL, isRoot: true)
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
            project: project,
            workingDirectory: project.directoryURL
        )
        pane.loadViewIfNeeded()
        pane.paneWillBeRemoved()

        XCTAssertTrue((pane.contentViewController as? TeardownContent)?.torn == true)
    }
}
