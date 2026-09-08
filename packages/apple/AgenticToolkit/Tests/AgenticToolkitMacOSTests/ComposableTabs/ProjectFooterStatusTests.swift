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

    /// A pane content that names itself and can be renamed afterwards, so the
    /// footer's *pane* segment has a source that changes after the window was
    /// built. Starts on the registry's own display name, so a window made with
    /// it reads the same as one made with content that names nothing.
    private final class TitlingContent: NSViewController, PaneTitleProviding {
        var paneTitle = "Alpha"
        var onPaneTitleChange: (() -> Void)?

        func retitle(_ title: String) {
            paneTitle = title
            onPaneTitleChange?()
        }
    }

    private let alpha = ComposableTabsViewID("test.alpha")

    /// The layout is installed before the workspace is made: `ProjectWorkspace`
    /// captures `ComposableTabsLayout.current` in its initialiser, so a
    /// workspace built first would hold the placeholder layout forever.
    private var contents: [SelectingContent] = []
    private var titlingContents: [TitlingContent] = []

    /// The panes' contents are built in `PaneViewController.loadView()`, so a
    /// controller nobody has loaded has panes but no content in them — and
    /// nothing to describe a selection. Loading the window's content
    /// controller cascades: the footer host loads the tab container, which
    /// mounts the active tab, which loads its split, which loads its panes.
    /// Still no window on screen, which is the point.
    private func makeController() -> ComposableTabsWindowController {
        installLayout { [weak self] in
            let content = SelectingContent()
            self?.contents.append(content)
            return content
        }
        return loadedController()
    }

    /// The same window over content that provides its own title, for the one
    /// segment `SelectingContent` cannot move.
    private func makeTitlingController() -> ComposableTabsWindowController {
        installLayout { [weak self] in
            let content = TitlingContent()
            self?.titlingContents.append(content)
            return content
        }
        return loadedController()
    }

    private func loadedController() -> ComposableTabsWindowController {
        let controller = ComposableTabsWindowController(project: makeWorkspace())
        controller.contentViewController?.loadViewIfNeeded()
        return controller
    }

    private func installLayout(makeContent: @escaping () -> NSViewController) {
        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)) { _ in
            let content = makeContent()
            content.view = NSView()
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

    /// The pane segment has to be invalidated the same way the selection
    /// segment is. The pane's own title bar is not the only reader of
    /// `resolvedTitle`, so a retitle that only repaints the bar leaves the
    /// footer naming the pane by a name it no longer has.
    func testTheFooterFollowsATitleChange() throws {
        let controller = makeTitlingController()
        let content = try XCTUnwrap(titlingContents.first)
        XCTAssertEqual(controller.footerStatus, "api-server › Tab 1 › Alpha")

        content.retitle("Backend")

        XCTAssertEqual(controller.footerStatus, "api-server › Tab 1 › Backend")
        XCTAssertEqual(controller.footer.status, "api-server › Tab 1 › Backend")
    }
}
