import AppKit
import XCTest
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// After the rewrite, the only thing this controller still decides is which
/// preference remembers the drawer. These tests pin that, and pin the behaviour
/// its own doc comment argued for: a panel with no prose says so inside the
/// drawer instead of making the window flinch.
@available(macOS, deprecated: 10.13)
@MainActor
final class HelpDrawerControllerTests: XCTestCase {

    private var window: NSWindow!

    override func setUp() async throws {
        try await super.setUp()
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        UserSettings.settingsHelpDrawerVisible.value = false
    }

    override func tearDown() async throws {
        UserSettings.settingsHelpDrawerVisible.value = false
        self.window = nil
        try await super.tearDown()
    }

    func testVisibilityIsThePreferenceAndNothingElse() {
        let controller = ComposableSettings.HelpDrawerController(parentWindow: self.window)
        XCTAssertFalse(controller.isHelpVisible)

        UserSettings.settingsHelpDrawerVisible.value = true
        XCTAssertTrue(controller.isHelpVisible)
    }

    func testToggleFlipsThePreference() {
        let controller = ComposableSettings.HelpDrawerController(parentWindow: self.window)
        controller.toggleHelp()
        XCTAssertTrue(UserSettings.settingsHelpDrawerVisible.value)
        controller.toggleHelp()
        XCTAssertFalse(UserSettings.settingsHelpDrawerVisible.value)
    }

    /// The bug the old comment records: `hasHelp && preference` made the drawer
    /// slam shut on the way to a panel with nothing to say and slide open again
    /// on the way out.
    func testAPanelWithNoHelpDoesNotCloseTheDrawer() {
        let controller = ComposableSettings.HelpDrawerController(parentWindow: self.window)
        UserSettings.settingsHelpDrawerVisible.value = true

        controller.setHelp(HelpContent(topics: [HelpContent.Topic(title: "T", body: "B")]))
        XCTAssertTrue(controller.isHelpVisible)

        controller.setHelp(nil)
        XCTAssertTrue(controller.isHelpVisible, "an empty panel must not move the drawer")
    }

    func testVisibilityChangesAreAnnounced() {
        let controller = ComposableSettings.HelpDrawerController(parentWindow: self.window)
        var announcements = 0
        controller.onVisibilityChange = { announcements += 1 }
        controller.toggleHelp()
        // `preference.onChange` is wired through `UserSettingObserver`, whose
        // `@Published` pipeline hops to the next main-queue turn on purpose
        // (see UserSetting.swift) — it never fires synchronously within
        // `toggleHelp()`. Drain that turn before asserting, matching the same
        // wait already used for another `UserSettingObserver`-driven callback
        // in ThemeManagerTests.swift.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertGreaterThan(announcements, 0)
    }

    /// A drawer can be dragged shut by its outer edge, which goes nowhere near
    /// the `?` button. Without reconciling, the preference still says visible
    /// and the next window focus slides the drawer back out — two clicks to put
    /// away a drawer that will not stay away.
    func testADrawerDraggedShutIsForgotten() throws {
        let controller = ComposableSettings.HelpDrawerController(parentWindow: self.window)
        UserSettings.settingsHelpDrawerVisible.value = true
        controller.setHelp(HelpContent(topics: [HelpContent.Topic(title: "T", body: "B")]))
        XCTAssertTrue(controller.isHelpVisible)

        // The drag, as AppKit reports it: the `NSDrawer` shuts and the delegate
        // is told, with nothing having gone through this controller.
        try XCTUnwrap(self.window.drawers?.first).close()
        controller.drawer.drawerDidClose(
            Notification(name: Notification.Name("NSDrawerDidCloseNotification")))

        XCTAssertFalse(controller.isHelpVisible)
        XCTAssertFalse(UserSettings.settingsHelpDrawerVisible.value)
    }

    /// AppKit shuts a drawer along with the window it hangs off, and announces
    /// it through the same callback a drag uses. A settings window that is
    /// simply closed must not be read as the reader putting help away.
    func testClosingTheWindowDoesNotForgetADisclosedDrawer() throws {
        let controller = ComposableSettings.HelpDrawerController(parentWindow: self.window)
        UserSettings.settingsHelpDrawerVisible.value = true
        controller.setHelp(HelpContent(topics: [HelpContent.Topic(title: "T", body: "B")]))
        XCTAssertTrue(controller.isHelpVisible)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: self.window)
        try XCTUnwrap(self.window.drawers?.first).close()
        controller.drawer.drawerDidClose(
            Notification(name: Notification.Name("NSDrawerDidCloseNotification")))

        XCTAssertTrue(
            controller.isHelpVisible,
            "The reader left help open; closing the window is not them putting it away")
        XCTAssertTrue(UserSettings.settingsHelpDrawerVisible.value)
    }

    /// The settings window's presenter outlives its window — `loadWindow()`
    /// runs once for the life of the app — so the teardown latch that keeps a
    /// ⌘W from erasing the preference has to be lifted again when the window
    /// comes back. Close it, reopen it, then drag the drawer shut: that drag is
    /// the reader putting help away, and must be remembered as one.
    func testADrawerDraggedShutAfterTheWindowReopensIsForgotten() throws {
        let controller = ComposableSettings.HelpDrawerController(parentWindow: self.window)
        UserSettings.settingsHelpDrawerVisible.value = true
        controller.setHelp(HelpContent(topics: [HelpContent.Topic(title: "T", body: "B")]))
        XCTAssertTrue(controller.isHelpVisible)

        // ⌘W.
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: self.window)

        // The reopen, posted through the notification
        // `WindowDrawer.observeParentWindow` actually registers for rather than
        // by poking `reapplyVisibility` directly — the point is that the reset is
        // reachable by the path AppKit takes.
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: self.window)

        // Now the drag, as AppKit reports it.
        try XCTUnwrap(self.window.drawers?.first).close()
        controller.drawer.drawerDidClose(
            Notification(name: Notification.Name("NSDrawerDidCloseNotification")))

        XCTAssertFalse(
            controller.isHelpVisible,
            "A window that came back is live again; the drag that follows is the reader's")
        XCTAssertFalse(UserSettings.settingsHelpDrawerVisible.value)
    }

    /// A drawer comes out of the window's edge, not out of a button, so the
    /// anchor is accepted and ignored — the protocol still requires it because
    /// the popover presenter genuinely needs one.
    func testTheAnchorIsAcceptedAndIgnored() {
        let controller = ComposableSettings.HelpDrawerController(parentWindow: self.window)
        let button = NSButton(title: "?", target: nil, action: nil)
        controller.helpAnchorView = button
        XCTAssertTrue(controller.helpAnchorView === button)
    }
}
