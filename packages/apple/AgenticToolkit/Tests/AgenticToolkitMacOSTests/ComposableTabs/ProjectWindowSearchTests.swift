import AppKit
import XCTest
import AgenticDeveloperToolkitUI
@testable import AgenticToolkitMacOS

/// The project window's titlebar search field, and what it points at.
@MainActor
final class ProjectWindowSearchTests: XCTestCase {

    /// A pane content that can be searched, and remembers what it was asked.
    private final class SearchableContent: NSViewController, PaneSearchable {
        var paneSearchPlaceholder = "Search Alpha"
        private(set) var queries: [String] = []
        func paneSearch(for query: String) { queries.append(query) }
    }

    /// A pane content that implements none of the capabilities.
    private final class PlainContent: NSViewController {}

    private let alpha = ComposableTabsViewID("test.alpha")
    private var searchables: [SearchableContent] = []

    /// One pane, of the requested kind. The layout is installed before the
    /// workspace is made, because `ProjectWorkspace` captures
    /// `ComposableTabsLayout.current` in its initialiser.
    private func makeController(searchable: Bool) -> ComposableTabsWindowController {
        installLayout(searchable: searchable)
        return ComposableTabsWindowController(project: makeWorkspace())
    }

    private func installLayout(searchable: Bool) {
        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)) { [weak self] _ in
            guard searchable else {
                let plain = PlainContent()
                plain.view = NSView()
                return plain
            }
            let content = SearchableContent()
            content.view = NSView()
            self?.searchables.append(content)
            return content
        }
        // swiftlint:disable:next force_try
        ComposableTabsLayout.install(try! ComposableTabsLayout(
            registry: registry,
            spec: .pane(alpha, allows: [.unbounded(alpha)])
        ))
    }

    private func makeWorkspace() -> ProjectWorkspace {
        ProjectWindowTestSupport.makeProject(label: "ProjectSearchTests")
    }

    /// A window whose one tab holds two panes side by side, with the *first* of
    /// them recorded as the tab's focused leaf.
    ///
    /// Seeded through the database rather than by splitting a live pane,
    /// because the focus record is only read back in `installInitialTabs()`:
    /// a window with no screen has no first responder, so nothing else in a
    /// test can put a leaf on record as focused.
    private func makeTwoPaneController() -> ComposableTabsWindowController {
        installLayout(searchable: true)
        let project = makeWorkspace()
        let first = UUID()
        let second = UUID()
        let tabID = UUID()
        project.persistTabs(
            [TabRecord(
                id: tabID,
                edge: .top,
                title: "Tab 1",
                root: .split(
                    orientation: .horizontal,
                    first: .leaf(id: first, contentType: alpha),
                    second: .leaf(id: second, contentType: alpha)
                ),
                focusedNodeID: first
            )],
            activeTabID: tabID,
            enabledEdges: [.top]
        )
        return ComposableTabsWindowController(project: project)
    }

    /// The split tree behind the tab in front, reached the way anything outside
    /// the window controller has to reach it — through the tab container's own
    /// public accessor, since the controller keeps its map of splits private.
    private func activeSplit(
        of controller: ComposableTabsWindowController
    ) -> ComposableTabsViewController? {
        let host = controller.contentViewController as? WindowFooterContentViewController
        let tabbed = host?.contentViewController as? MultiTabbedViewController
        return tabbed?.selectedTab(on: .top)?.viewController as? ComposableTabsViewController
    }

    /// The delegate's sender is ignored by every method this file calls
    /// (`multiTabbedViewControllerNeedsNewTab` routes straight into the
    /// controller's own `addTabGroup()` without reading it), so a throwaway
    /// stands in for the window's real tab controller rather than widening the
    /// controller's API to expose it. The day one of those methods reads the
    /// sender, this stops being safe.
    private func newTabRequest(to controller: ComposableTabsWindowController) {
        controller.multiTabbedViewControllerNeedsNewTab(MultiTabbedViewController())
    }

    nonisolated override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    func testTheToolbarIsASpacerASearchFieldAndHelp() {
        let identifiers = ProjectWindowTestSupport.buildToolbarItems(makeController(searchable: true))

        XCTAssertEqual(
            identifiers,
            [
                .flexibleSpace,
                NSToolbarItem.Identifier("project.toolbar.search"),
                NSToolbarItem.Identifier("project.toolbar.help")
            ])
    }

    func testTheSearchFieldIsAddressable() throws {
        let controller = makeController(searchable: true)
        ProjectWindowTestSupport.buildToolbarItems(controller)

        let field = try XCTUnwrap(controller.searchField)
        XCTAssertEqual(field.accessibilityIdentifier(), "project.toolbar.search")
    }

    /// Enablement and placeholder are applied as the field is *built*, not by
    /// some later refresh that has to land after AppKit got round to making the
    /// item — hence no `refreshActivePaneChrome()` anywhere in this test.
    func testASearchablePaneEnablesTheFieldAndNamesIt() throws {
        let controller = makeController(searchable: true)
        ProjectWindowTestSupport.buildToolbarItems(controller)

        let field = try XCTUnwrap(controller.searchField)
        XCTAssertTrue(field.isEnabled)
        XCTAssertEqual(field.placeholderString, "Search Alpha")
    }

    /// Never enabled and silent. A fresh `NSSearchField` is enabled by default,
    /// so "the item was built and nobody told it anything" and "the pane cannot
    /// be searched" are two states this has to be able to tell apart.
    func testAPaneThatCannotBeSearchedDisablesTheField() throws {
        let controller = makeController(searchable: false)
        ProjectWindowTestSupport.buildToolbarItems(controller)

        let field = try XCTUnwrap(controller.searchField)
        XCTAssertFalse(field.isEnabled)
        XCTAssertEqual(field.placeholderString, "Search")
    }

    func testTypingRoutesToTheActivePane() throws {
        let controller = makeController(searchable: true)
        ProjectWindowTestSupport.buildToolbarItems(controller)
        let field = try XCTUnwrap(controller.searchField)
        let content = try XCTUnwrap(searchables.first)

        XCTAssertTrue(controller.searchField?.delegate === controller,
                      "AppKit routes keystrokes through the field's delegate; if this is not the "
                      + "controller, every other assertion here passes over a dead feature.")

        field.stringValue = "main"
        controller.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field))

        XCTAssertEqual(content.queries, ["main"])
    }

    /// A query means "search this pane". Carrying it to the next pane would
    /// show one pane's matches under another pane's name.
    func testChangingPanesClearsTheQuery() throws {
        let controller = makeController(searchable: true)
        ProjectWindowTestSupport.buildToolbarItems(controller)
        let field = try XCTUnwrap(controller.searchField)
        field.stringValue = "main"

        // Adding a tab group selects it, which is a change of active pane.
        newTabRequest(to: controller)

        XCTAssertTrue(field.stringValue.isEmpty)
    }

    /// Disabling the edge the active tab lives on hands the window to a tab on
    /// another edge — through `activateFallbackTab()`, which fires no
    /// `didSelectTab`. Driven through `setEdgeEnabled(_:_:)` because that is
    /// the real entry point: the project-settings sheet and the scripting
    /// bridge both arrive there.
    func testDisablingTheActiveEdgeRetargetsTheField() throws {
        let controller = makeController(searchable: true)
        ProjectWindowTestSupport.buildToolbarItems(controller)
        let field = try XCTUnwrap(controller.searchField)

        // Two edges and two tab groups, so the fallback has somewhere to land
        // that is not the tab it just left.
        controller.setEdgeEnabled(.right, true)
        newTabRequest(to: controller)
        field.stringValue = "main"

        controller.setEdgeEnabled(.top, false)

        XCTAssertTrue(field.stringValue.isEmpty)
    }

    /// Closing the pane the tab was focused on changes which pane is in front
    /// without changing the tab. The layout callback is the only thing told
    /// about it, and it is the one that has to notice the focus record going
    /// away — a divider drag reaches the same callback and must not pay for a
    /// search refresh on every frame.
    func testClosingTheFocusedPaneRetargetsTheField() throws {
        let controller = makeTwoPaneController()
        ProjectWindowTestSupport.buildToolbarItems(controller)
        let field = try XCTUnwrap(controller.searchField)
        let split = try XCTUnwrap(activeSplit(of: controller))
        let leaves = split.allLeaves()
        XCTAssertEqual(leaves.count, 2, "the seeded two-pane layout did not survive being loaded")
        field.stringValue = "main"

        split.remove(leaves[0])

        XCTAssertTrue(field.stringValue.isEmpty)
    }

    /// The same pane reporting itself active again is not a change, and must
    /// not throw away what the user has typed.
    func testARedundantRefreshKeepsTheQuery() throws {
        let controller = makeController(searchable: true)
        ProjectWindowTestSupport.buildToolbarItems(controller)
        let field = try XCTUnwrap(controller.searchField)
        field.stringValue = "main"

        controller.refreshActivePaneChrome()

        XCTAssertEqual(field.stringValue, "main")
        // Requires a live pane: with `activePane` nil on both refreshes the
        // guard would early-return and "main" would survive for the wrong
        // reason.
        XCTAssertEqual(field.placeholderString, "Search Alpha")
    }
}
