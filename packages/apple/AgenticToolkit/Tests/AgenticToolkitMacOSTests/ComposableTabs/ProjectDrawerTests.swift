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
    /// - Parameter registered: pass `false` for a workspace whose repo is *not*
    ///   in `git_repo`. Every row keyed to a project carries a foreign key onto
    ///   that table, so such a workspace persists nothing and `setSetting`
    ///   swallows the failure — which is exactly the state in which the `?`
    ///   button still has to work.
    private func makeProject(registered: Bool = true) -> ProjectWorkspace {
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

        return ProjectWindowTestSupport.makeProject(
            label: "ProjectDrawerTests", registered: registered)
    }

    /// A window controller whose window exists. `showWindow(_:)` is what wires
    /// the drawer to a real `NSWindow`, and `NSDrawer` needs one.
    private func makeController(for project: ProjectWorkspace) -> ComposableTabsWindowController {
        let controller = ComposableTabsWindowController(project: project)
        controller.showWindow(nil)
        return controller
    }

    /// The `?` button, ready to be asserted on.
    ///
    /// In the app AppKit has built the toolbar's items by the time
    /// `showWindow(_:)` refreshes the glyph. With no toolbar on screen nothing
    /// asks the delegate, so the test asks first and then shows the window
    /// again — the same order, made to happen.
    private func helpButton(
        of controller: ComposableTabsWindowController
    ) throws -> NSButton {
        ProjectWindowTestSupport.buildToolbarItems(controller)
        controller.showWindow(nil)
        return try XCTUnwrap(
            controller.toolbarDelegate.button(for: NSToolbarItem.Identifier("project.toolbar.help")))
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
        let identifiers = ProjectWindowTestSupport.buildToolbarItems(makeController(for: makeProject()))

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
        ProjectWindowTestSupport.buildToolbarItems(controller)

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
        let topics = ComposableTabsWindowController.helpContent.topics
        XCTAssertFalse(topics.isEmpty, "A help tab with nothing in it is worse than no help tab")
        let labels = Self.labels(in: view)
        for topic in topics {
            XCTAssertTrue(labels.contains(topic.title), "Missing the title of \(topic.title)")
            // The body too, and not only the heading over it: a `setHelp` that
            // rendered every title and dropped every word of prose would pass
            // an assertion on titles alone, and the drawer would be five
            // headings over nothing.
            XCTAssertFalse(topic.body.isEmpty, "A topic with no prose is a heading, not help")
            XCTAssertTrue(labels.contains(topic.body), "Missing the body of \(topic.title)")
        }
    }

    /// Half the brief's visible contract: the `?` reports the state it toggles.
    ///
    /// The symbol is compared by what it draws rather than by name, because
    /// `NSImage.name()` is `nil` for an image made with
    /// `init(systemSymbolName:accessibilityDescription:)` — AppKit exposes no
    /// symbol name to read back — and the rendering of one symbol at one
    /// configuration is stable within a process.
    func testTheHelpButtonSwapsItsGlyphAndTooltipWithTheDrawer() throws {
        let controller = makeController(for: makeProject())
        let button = try helpButton(of: controller)

        XCTAssertEqual(button.toolTip, "Show Help")
        XCTAssertEqual(button.image?.tiffRepresentation, Self.glyph("questionmark.circle"))

        controller.toggleHelp()
        XCTAssertEqual(button.toolTip, "Hide Help")
        XCTAssertEqual(button.image?.tiffRepresentation, Self.glyph("questionmark.circle.fill"))

        controller.toggleHelp()
        XCTAssertEqual(button.toolTip, "Show Help")
        XCTAssertEqual(button.image?.tiffRepresentation, Self.glyph("questionmark.circle"))
    }

    /// The tint at the two moments the button is restyled anyway. This is the
    /// disclosure contract — outlined and secondary while closed, accented while
    /// open — and nothing more: both assertions hold with no theme observer at
    /// all, because a toggle restyles the button by itself. What the observer is
    /// for is the test below.
    func testTheHelpButtonTintFollowsTheDrawer() throws {
        let controller = makeController(for: makeProject())
        let button = try helpButton(of: controller)

        XCTAssertEqual(button.contentTintColor, button.resolvedThemeScope.palette.secondaryTextColor)
        controller.toggleHelp()
        XCTAssertEqual(button.contentTintColor, button.resolvedThemeScope.palette.accentColor)
    }

    /// The glyph follows the theme *live*, rather than staying tinted for the
    /// palette that happened to be in effect when it was last toggled — a theme
    /// can change while the window just sits there, and nothing toggles then.
    ///
    /// The button is stamped with a colour no palette produces before the theme
    /// moves, so "the tint followed" cannot be satisfied by a tint that was
    /// already correct. Delete the window controller's `helpThemeObserver` and
    /// the stamp survives the theme change, which is the failure this pins.
    func testTheHelpButtonTintFollowsALiveThemeChange() throws {
        let controller = makeController(for: makeProject())
        let button = try helpButton(of: controller)

        button.contentTintColor = .systemPink

        // The notification itself rather than a `ThemeManager` that posts it:
        // `selectTheme(id:)` bails when the theme it names is already the active
        // one, and the active theme is read from `UserSettings`, which outlives
        // this process. A test that depends on which theme happens to be on disk
        // is a test that passes or fails by accident.
        NotificationCenter.default.post(name: ThemeManager.didChangeNotification, object: nil)

        XCTAssertEqual(button.contentTintColor, button.resolvedThemeScope.palette.secondaryTextColor)
        XCTAssertNotEqual(button.contentTintColor, .systemPink)
    }

    /// AppKit asks the toolbar delegate for its items again whenever the toolbar
    /// is rebuilt, and the delegate answers with a *new* `NSButton` every time.
    /// An observer pinned to the first one goes on tinting a button nobody can
    /// see, while the button on screen keeps whatever tint it was born with.
    func testTheHelpButtonTintFollowsAToolbarItemThatWasRebuilt() throws {
        let controller = makeController(for: makeProject())
        let first = try helpButton(of: controller)
        let second = try helpButton(of: controller)
        XCTAssertFalse(
            first === second,
            "The delegate is expected to hand back a new button; the test is vacuous otherwise")

        second.contentTintColor = .systemPink
        NotificationCenter.default.post(name: ThemeManager.didChangeNotification, object: nil)

        XCTAssertEqual(second.contentTintColor, second.resolvedThemeScope.palette.secondaryTextColor)
        XCTAssertNotEqual(second.contentTintColor, .systemPink)
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

    /// The `?` has to work even when the write behind it does not — the button
    /// is not a database row, it is what the reader asked for.
    func testTheButtonWorksWhenThePreferenceCannotBeSaved() throws {
        let controller = makeController(for: makeProject(registered: false))
        let drawer = try XCTUnwrap(controller.helpDrawer)

        controller.toggleHelp()
        XCTAssertTrue(controller.isHelpVisible, "A swallowed write must not make the ? a no-op")
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

    /// "On which tab" is part of what a project remembers, and the only test
    /// that touched `drawer.tab` used it as a generic key. This one is the
    /// round trip: written on the way out, selected on the way back in.
    func testTheDrawerRestoresOntoTheRememberedTab() throws {
        let project = makeProject()
        let first = makeController(for: project)
        first.toggleHelp()
        first.close()

        XCTAssertEqual(project.setting("drawer.tab"), "help")

        let second = makeController(for: project)
        XCTAssertEqual(try XCTUnwrap(second.helpDrawer).selectedTabID, "help")
    }

    /// The moment the brief asks for and the window close cannot cover: drag it
    /// wider, put it away with the `?`, then keep working. Quitting from the
    /// menu bar never closes the window, so a width only written on window
    /// close is a width thrown away.
    func testAWidthDraggedThenPutAwayIsRemembered() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        controller.toggleHelp()
        try XCTUnwrap(controller.helpDrawer).contentWidth = 460
        controller.toggleHelp()

        // No `close()`: the window is still open, exactly as it is when the
        // user quits from the menu bar.
        XCTAssertEqual(project.setting("drawer.width"), "460.0")
        XCTAssertEqual(project.setting("drawer.tab"), "help")
    }

    /// `setSetting`'s contract is that "never set" and "set back to the
    /// default" are one state. A reader who never touched help has never set
    /// anything.
    func testAProjectThatNeverOpenedHelpRemembersNothingAboutIt() {
        let project = makeProject()
        let controller = makeController(for: project)
        controller.close()

        XCTAssertNil(project.setting("drawer.open"))
        XCTAssertNil(project.setting("drawer.tab"))
        XCTAssertNil(project.setting("drawer.width"))
    }

    /// A drawer can be dragged shut by its outer edge, which goes nowhere near
    /// the `?`. Without reconciling, the remembered preference still says open
    /// and the next `didBecomeKey` slides it back out — two clicks to close a
    /// drawer that stays closed.
    func testADrawerClosedBehindThePresentersBackStaysClosed() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        let drawer = try XCTUnwrap(controller.helpDrawer)
        controller.toggleHelp()
        XCTAssertTrue(controller.isHelpVisible)

        // What the drag looks like from here: the drawer closes and announces
        // it, without the button having been clicked.
        drawer.close()

        XCTAssertFalse(controller.isHelpVisible)
        XCTAssertNil(project.setting("drawer.open"))

        // And the re-assert that runs on every window focus leaves it closed.
        drawer.reapplyVisibility?()
        XCTAssertFalse(drawer.isOpen)
        XCTAssertFalse(controller.isHelpVisible)
    }

    /// The same drag, arriving the way AppKit actually reports it: the drawer
    /// shuts and the *delegate* is told, with nothing having gone through
    /// `WindowDrawer.close()`. The test above drives the wrapper; this one
    /// drives the callback, which is the path the guard added for window
    /// teardown has to keep working for.
    func testADragShutDrawerAnnouncedByTheDelegateStaysClosed() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        let drawer = try XCTUnwrap(controller.helpDrawer)
        controller.toggleHelp()
        XCTAssertEqual(project.setting("drawer.open"), "1")

        // The drag itself: the `NSDrawer` the window holds is shut directly, so
        // nothing on this side has announced anything yet.
        try XCTUnwrap(controller.window?.drawers?.first).close()
        drawer.drawerDidClose(Notification(name: Notification.Name("NSDrawerDidCloseNotification")))

        XCTAssertFalse(controller.isHelpVisible)
        XCTAssertNil(project.setting("drawer.open"))
    }

    /// AppKit shuts a drawer along with the window it hangs off, and reports it
    /// through the very same callback a drag uses. Read as a drag, closing the
    /// window with help open erases the preference this whole feature is for —
    /// and `willClose` arrives *before* the drawer shuts, so the last-chance
    /// write cannot save it either.
    func testClosingTheWindowDoesNotForgetADisclosedDrawer() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        let drawer = try XCTUnwrap(controller.helpDrawer)
        controller.toggleHelp()
        XCTAssertEqual(project.setting("drawer.open"), "1")

        // AppKit's order on the way out: the window says it is closing, and the
        // drawer goes with it afterwards.
        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification, object: try XCTUnwrap(controller.window))
        try XCTUnwrap(controller.window?.drawers?.first).close()
        drawer.drawerDidClose(Notification(name: Notification.Name("NSDrawerDidCloseNotification")))

        XCTAssertEqual(
            project.setting("drawer.open"), "1",
            "The reader left help open; a window close is not them putting it away")
        XCTAssertTrue(controller.isHelpVisible)
    }

    /// One window focus re-asserts the drawer twice — `didBecomeKey` and
    /// `didBecomeMain` — and every re-assert announces a visibility change. A
    /// tab and a width written on each of those is two upserts per focus, on the
    /// main thread, for values nobody changed.
    ///
    /// Asserted on the rows rather than on a counter: the remembered width is
    /// poked to something the controller never wrote, so any write it makes from
    /// here shows up as that value being gone.
    func testAnAnnouncementThatChangesNothingWritesNothing() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        let drawer = try XCTUnwrap(controller.helpDrawer)
        controller.toggleHelp()
        drawer.contentWidth = 460
        controller.toggleHelp()
        XCTAssertEqual(project.setting("drawer.width"), "460.0")

        project.setSetting("drawer.width", to: "999.0")
        drawer.reapplyVisibility?()
        drawer.reapplyVisibility?()

        XCTAssertEqual(project.setting("drawer.width"), "999.0")
        XCTAssertEqual(project.setting("drawer.tab"), "help")
    }

    /// What one symbol draws at the configuration `applyDisclosureAppearance`
    /// uses. `NSImage.name()` is `nil` for a system-symbol image, so this is
    /// the only way to say *which* glyph the button is showing.
    private static func glyph(_ symbolName: String) -> Data? {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: "Help")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))?
            .tiffRepresentation
    }

    private static func labels(in view: NSView) -> [String] {
        var found: [String] = []
        if let field = view as? NSTextField { found.append(field.stringValue) }
        for subview in view.subviews { found.append(contentsOf: labels(in: subview)) }
        return found
    }
}
