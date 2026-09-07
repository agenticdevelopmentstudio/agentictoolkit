import AppKit
import XCTest
import AgenticDeveloperToolkitUI
@testable import AgenticToolkitMacOS

/// What the project window puts in its footer.
@MainActor
final class ProjectFooterStatusTests: XCTestCase {

    /// A pane content that has a selection to describe, so the last segment of
    /// the path has a source.
    private final class SelectingContent: NSViewController, PaneSelectionDescribing {
        var paneSelectionDescription: String?
        var onPaneSelectionChange: (() -> Void)?

        func select(_ path: String?) {
            paneSelectionDescription = path
            onPaneSelectionChange?()
        }
    }

    private let alpha = ComposableTabsViewID("test.alpha")

    /// The layout is installed before the workspace is made: `ProjectWorkspace`
    /// captures `ComposableTabsLayout.current` in its initialiser, so a
    /// workspace built first would hold the placeholder layout forever.
    private var contents: [SelectingContent] = []

    /// The panes' contents are built in `PaneViewController.loadView()`, so a
    /// controller nobody has loaded has panes but no content in them — and
    /// nothing to describe a selection. Loading the window's content
    /// controller cascades: the footer host loads the tab container, which
    /// mounts the active tab, which loads its split, which loads its panes.
    /// Still no window on screen, which is the point.
    private func makeController() -> ComposableTabsWindowController {
        installLayout()
        let controller = ComposableTabsWindowController(project: makeWorkspace())
        controller.contentViewController?.loadViewIfNeeded()
        return controller
    }

    private func installLayout() {
        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)) { [weak self] _ in
            let content = SelectingContent()
            content.view = NSView()
            self?.contents.append(content)
            return content
        }
        // swiftlint:disable:next force_try
        ComposableTabsLayout.install(try! ComposableTabsLayout(
            registry: registry,
            spec: .pane(alpha, allows: [.unbounded(alpha)])
        ))
    }

    private func makeWorkspace() -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("FooterStatusTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        // swiftlint:disable:next force_try
        let database = try! ProjectDatabase(path: path)
        return ProjectWorkspace(
            repo: GitRepo(path: NSTemporaryDirectory(), name: "api-server"),
            database: database
        )
    }

    nonisolated override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    func testTheWindowsContentIsTheFooterHostWrappingTheTabs() {
        let controller = makeController()

        let host = controller.contentViewController as? WindowFooterContentViewController
        XCTAssertNotNil(host)
        XCTAssertTrue(host?.contentViewController is MultiTabbedViewController)
        XCTAssertTrue(controller.footer === host?.footer)
    }

    func testAFreshWindowNamesTheProjectTheTabAndThePane() {
        let controller = makeController()

        XCTAssertEqual(controller.footerStatus, "api-server › Tab 1 › Alpha")
    }

    /// The bar shows what the computation produced — the two are not allowed to
    /// be separately true.
    func testTheBarShowsWhatWasComputed() {
        let controller = makeController()

        controller.refreshFooterStatus()

        XCTAssertEqual(controller.footer.status, controller.footerStatus)
        XCTAssertEqual(controller.footer.statusLabel.stringValue, controller.footerStatus)
    }

    func testASelectionAddsTheLastSegment() throws {
        let controller = makeController()
        let content = try XCTUnwrap(contents.first)

        content.select("src/main.swift")

        XCTAssertEqual(controller.footerStatus, "api-server › Tab 1 › Alpha › src/main.swift")
    }

    /// The pane reports; the window does not poll.
    func testTheFooterFollowsASelectionChange() throws {
        let controller = makeController()
        let content = try XCTUnwrap(contents.first)

        content.select("src/main.swift")
        XCTAssertEqual(controller.footer.status, "api-server › Tab 1 › Alpha › src/main.swift")

        content.select(nil)
        XCTAssertEqual(controller.footer.status, "api-server › Tab 1 › Alpha")
    }
}
