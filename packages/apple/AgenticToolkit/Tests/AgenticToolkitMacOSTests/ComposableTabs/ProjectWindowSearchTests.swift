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

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectSearchTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        // swiftlint:disable:next force_try
        let database = try! ProjectDatabase(path: path)
        let project = ProjectWorkspace(
            repo: GitRepo(path: NSTemporaryDirectory(), name: "api-server"),
            database: database
        )
        return ComposableTabsWindowController(project: project)
    }

    /// AppKit only asks the delegate for items once a toolbar is on a window,
    /// and a custom-view item is the only place an accessibility identifier can
    /// live — so the test asks for them itself.
    @discardableResult
    private func buildToolbarItems(
        _ controller: ComposableTabsWindowController
    ) -> [NSToolbarItem.Identifier] {
        let toolbar = controller.toolbarDelegate.makeToolbar(identifier: "test.toolbar")
        let identifiers = controller.toolbarDelegate.toolbarDefaultItemIdentifiers(toolbar)
        for identifier in identifiers {
            _ = controller.toolbarDelegate.toolbar(
                toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: false)
        }
        controller.refreshActivePaneChrome()
        return identifiers
    }

    nonisolated override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    func testTheToolbarIsASpacerAndASearchField() {
        let identifiers = buildToolbarItems(makeController(searchable: true))

        XCTAssertEqual(identifiers, [.flexibleSpace, NSToolbarItem.Identifier("project.toolbar.search")])
    }

    func testTheSearchFieldIsAddressable() throws {
        let controller = makeController(searchable: true)
        buildToolbarItems(controller)

        let field = try XCTUnwrap(controller.searchField)
        XCTAssertEqual(field.accessibilityIdentifier(), "project.toolbar.search")
    }

    func testASearchablePaneEnablesTheFieldAndNamesIt() throws {
        let controller = makeController(searchable: true)
        buildToolbarItems(controller)

        let field = try XCTUnwrap(controller.searchField)
        XCTAssertTrue(field.isEnabled)
        XCTAssertEqual(field.placeholderString, "Search Alpha")
    }

    /// Never enabled and silent.
    func testAPaneThatCannotBeSearchedDisablesTheField() throws {
        let controller = makeController(searchable: false)
        buildToolbarItems(controller)

        let field = try XCTUnwrap(controller.searchField)
        XCTAssertFalse(field.isEnabled)
        XCTAssertEqual(field.placeholderString, "Search")
    }

    func testTypingRoutesToTheActivePane() throws {
        let controller = makeController(searchable: true)
        buildToolbarItems(controller)
        let field = try XCTUnwrap(controller.searchField)
        let content = try XCTUnwrap(searchables.first)

        field.stringValue = "main"
        controller.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field))

        XCTAssertEqual(content.queries, ["main"])
    }

    /// A query means "search this pane". Carrying it to the next pane would
    /// show one pane's matches under another pane's name.
    func testChangingPanesClearsTheQuery() throws {
        let controller = makeController(searchable: true)
        buildToolbarItems(controller)
        let field = try XCTUnwrap(controller.searchField)
        field.stringValue = "main"

        // Adding a tab group selects it, which is a change of active pane.
        controller.multiTabbedViewControllerNeedsNewTab(MultiTabbedViewController())

        XCTAssertTrue(field.stringValue.isEmpty)
    }

    /// The same pane reporting itself active again is not a change, and must
    /// not throw away what the user has typed.
    func testARedundantRefreshKeepsTheQuery() throws {
        let controller = makeController(searchable: true)
        buildToolbarItems(controller)
        let field = try XCTUnwrap(controller.searchField)
        field.stringValue = "main"

        controller.refreshActivePaneChrome()

        XCTAssertEqual(field.stringValue, "main")
    }
}
