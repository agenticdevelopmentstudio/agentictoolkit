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
