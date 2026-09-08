import AppKit
import XCTest
import AgenticDeveloperToolkitUI
@testable import AgenticToolkitMacOS

/// The project window's help drawer, and the preference that remembers it.
///
/// `WindowDrawer` wraps a deprecated AppKit type, so anything that names one
/// has to carry the quarantine too.
@available(macOS, deprecated: 10.13)
@MainActor
final class ProjectDrawerTests: XCTestCase {

    private let alpha = ComposableTabsViewID("test.alpha")

    /// A project on its own temporary database, so two tests never share a
    /// remembered drawer. The layout is installed before the workspace is made,
    /// because `ProjectWorkspace` captures `ComposableTabsLayout.current` in its
    /// initialiser.
    private func makeProject() -> ProjectWorkspace {
        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)) { _ in
            let controller = NSViewController()
            controller.view = NSView()
            return controller
        }
        // swiftlint:disable:next force_try
        ComposableTabsLayout.install(try! ComposableTabsLayout(
            registry: registry,
            spec: .pane(alpha, allows: [.unbounded(alpha)])
        ))

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectDrawerTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        let repo = GitRepo(path: NSTemporaryDirectory(), name: "api-server")
        // swiftlint:disable:next force_try
        let database = try! ProjectDatabase(path: path)
        // The repo is registered before the workspace is made: every row keyed
        // to a project carries a foreign key onto `git_repo`, so a workspace
        // over an unregistered repo silently persists nothing — and every
        // "the project remembered it" assertion below would be vacuous.
        // swiftlint:disable:next force_try
        try! database.insert(repo)
        return ProjectWorkspace(repo: repo, database: database)
    }

    /// A window controller whose window exists. `showWindow(_:)` is what wires
    /// the drawer to a real `NSWindow`, and `NSDrawer` needs one.
    private func makeController(for project: ProjectWorkspace) -> ComposableTabsWindowController {
        let controller = ComposableTabsWindowController(project: project)
        controller.showWindow(nil)
        return controller
    }

    /// AppKit only asks the delegate for its items once the toolbar is on a
    /// window, and a custom-view item is the only place an accessibility
    /// identifier can live — so the test does the asking itself. The same
    /// helper, for the same reason, as `ProjectWindowSearchTests`.
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
        return identifiers
    }

    nonisolated override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    // MARK: - The preference

    func testAProjectRemembersASettingAndForgetsANilOne() {
        let project = makeProject()
        XCTAssertNil(project.setting("drawer.open"))

        project.setSetting("drawer.open", to: "1")
        XCTAssertEqual(project.setting("drawer.open"), "1")

        project.setSetting("drawer.open", to: nil)
        XCTAssertNil(project.setting("drawer.open"))
    }

    /// Two projects, one key, two answers — the whole reason this is not in
    /// `UserSettings`.
    func testTwoProjectsRememberSeparately() {
        let first = makeProject()
        let second = makeProject()

        first.setSetting("drawer.open", to: "1")

        XCTAssertEqual(first.setting("drawer.open"), "1")
        XCTAssertNil(second.setting("drawer.open"))
    }

    // MARK: - The toolbar button

    func testTheToolbarCarriesAHelpButtonAfterTheSearchField() {
        let identifiers = buildToolbarItems(makeController(for: makeProject()))

        XCTAssertEqual(
            identifiers,
            [
                .flexibleSpace,
                NSToolbarItem.Identifier("project.toolbar.search"),
                NSToolbarItem.Identifier("project.toolbar.help")
            ])
    }

    func testTheHelpButtonIsAddressable() throws {
        let controller = makeController(for: makeProject())
        buildToolbarItems(controller)

        let button = try XCTUnwrap(
            controller.toolbarDelegate.button(for: NSToolbarItem.Identifier("project.toolbar.help")))

        XCTAssertEqual(button.accessibilityIdentifier(), "project.toolbar.help")
    }

    // MARK: - The drawer

    func testTheDrawerHasOneHelpTabAndIsAddressable() throws {
        let controller = makeController(for: makeProject())
        let drawer = try XCTUnwrap(controller.helpDrawer)

        XCTAssertEqual(drawer.selectedTabID, "help")
        XCTAssertEqual(drawer.contentView.accessibilityIdentifier(), "project.drawer")
        XCTAssertEqual(drawer.bodyView.accessibilityIdentifier(), "project.drawer.tab.help")
        XCTAssertTrue(
            drawer.tabStripIsHidden,
            "One tab. A segmented control with one segment is a button that does nothing.")
    }

    func testTheHelpTabRendersTheWindowsHelp() throws {
        let controller = makeController(for: makeProject())
        let drawer = try XCTUnwrap(controller.helpDrawer)
        let view = try XCTUnwrap(drawer.view(forTab: "help"))

        XCTAssertTrue(view is HelpContentView)
        let titles = ComposableTabsWindowController.helpContent.topics.map(\.title)
        XCTAssertFalse(titles.isEmpty, "A help tab with nothing in it is worse than no help tab")
        for title in titles {
            XCTAssertTrue(Self.labels(in: view).contains(title))
        }
    }

    /// The `?` button's contract, in one test: click discloses, click again
    /// puts it away.
    ///
    /// The drawer is asserted alongside the preference every time. `isHelpVisible`
    /// answers from what the reader asked for rather than from `NSDrawer` — the
    /// drawer's own answer is unreliable on a window that is not on screen yet —
    /// so without the second assertion this suite would pass just as happily
    /// over a drawer that never moved.
    func testTheButtonTogglesTheDrawer() throws {
        let controller = makeController(for: makeProject())
        let drawer = try XCTUnwrap(controller.helpDrawer)
        XCTAssertFalse(controller.isHelpVisible)
        XCTAssertFalse(drawer.isOpen)

        controller.toggleHelp()
        XCTAssertTrue(controller.isHelpVisible)
        XCTAssertTrue(drawer.isOpen)

        controller.toggleHelp()
        XCTAssertFalse(controller.isHelpVisible)
        XCTAssertFalse(drawer.isOpen)
    }

    // MARK: - What survives a relaunch

    func testAnOpenDrawerIsRemembered() throws {
        let project = makeProject()
        let first = makeController(for: project)
        first.toggleHelp()
        first.close()

        // A second window on the same project is a relaunch, minus the process.
        let second = makeController(for: project)
        XCTAssertTrue(second.isHelpVisible)
        XCTAssertTrue(
            try XCTUnwrap(second.helpDrawer).isOpen,
            "Remembering it was open is only half the job; the drawer has to open.")
    }

    func testAClosedDrawerStaysClosed() throws {
        let project = makeProject()
        let first = makeController(for: project)
        first.toggleHelp()
        first.toggleHelp()
        first.close()

        let second = makeController(for: project)
        XCTAssertFalse(second.isHelpVisible)
        XCTAssertFalse(try XCTUnwrap(second.helpDrawer).isOpen)
    }

    func testADraggedWidthIsRemembered() throws {
        let project = makeProject()
        let first = makeController(for: project)
        first.toggleHelp()
        try XCTUnwrap(first.helpDrawer).contentWidth = 420
        first.close()

        let second = makeController(for: project)
        XCTAssertEqual(try XCTUnwrap(second.helpDrawer).contentWidth, 420)
    }

    /// A fresh project has no remembered width, and must not get zero.
    func testAFreshProjectGetsTheDefaultWidth() throws {
        let controller = makeController(for: makeProject())

        XCTAssertEqual(
            try XCTUnwrap(controller.helpDrawer).contentWidth, WindowDrawer.defaultContentWidth)
    }

    /// Nonsense in the database is not a reason to hand the user a drawer they
    /// cannot drag back.
    func testACorruptRememberedWidthIsIgnored() throws {
        let project = makeProject()
        project.setSetting("drawer.width", to: "not a number")

        let controller = makeController(for: project)
        XCTAssertEqual(
            try XCTUnwrap(controller.helpDrawer).contentWidth, WindowDrawer.defaultContentWidth)
    }

    private static func labels(in view: NSView) -> [String] {
        var found: [String] = []
        if let field = view as? NSTextField { found.append(field.stringValue) }
        for subview in view.subviews { found.append(contentsOf: labels(in: subview)) }
        return found
    }
}
