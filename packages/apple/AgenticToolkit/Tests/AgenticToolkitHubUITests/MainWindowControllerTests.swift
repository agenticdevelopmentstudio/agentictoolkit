#if canImport(AppKit)
import AppKit
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

/// The main window's geometry, which a shipped build got wrong in a way no
/// other test could see: the window opened as a bare 1x32 title bar.
///
/// `NSWindow.contentViewController` resizes the window to the incoming view,
/// and every controller this window hosts builds its root as a plain
/// `NSView()` — frame `.zero`, with constraints that only place its children.
/// So each assignment collapsed the window, and the constraints inside the
/// content had nothing left to lay out in.
final class MainWindowControllerTests: XCTestCase {

    /// Isolates the frame autosave, so a real defaults entry — including a
    /// collapsed one left by the very bug these tests cover — cannot decide
    /// what they measure.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame HubMainWindow")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame HubMainWindow")
        super.tearDown()
    }

    @MainActor
    func testWindowOpensAtItsDefaultContentSize() {
        let controller = MainWindowController()
        let window = controller.hubWindow
        let content = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(content.width, 1100, accuracy: 1)
        XCTAssertEqual(content.height, 720, accuracy: 1)
    }

    @MainActor
    func testShowingTheLaunchSpinnerDoesNotCollapseTheWindow() {
        let controller = MainWindowController()
        let window = controller.hubWindow
        let before = window.contentRect(forFrameRect: window.frame).size
        controller.start()
        let after = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(after.width, before.width, accuracy: 1)
        XCTAssertEqual(after.height, before.height, accuracy: 1)
    }

    /// The window has to refuse a restored frame it could never have produced,
    /// because the collapse autosaved like any other frame: without this, one
    /// bad launch would reinstate the bug on every launch after it, from a
    /// defaults entry the user has no way to see.
    @MainActor
    func testACollapsedAutosavedFrameIsNotRestored() {
        UserDefaults.standard.set(
            "3290 1032 1 32 0 0 7680 2129 ",
            forKey: "NSWindow Frame HubMainWindow"
        )
        let controller = MainWindowController()
        let window = controller.hubWindow
        let content = window.contentRect(forFrameRect: window.frame).size
        XCTAssertGreaterThanOrEqual(content.width, window.contentMinSize.width)
        XCTAssertGreaterThanOrEqual(content.height, window.contentMinSize.height)
    }

    /// A frame a person could have produced is honoured — the point of
    /// autosaving it at all.
    @MainActor
    func testAUsableAutosavedFrameIsRestored() {
        UserDefaults.standard.set(
            "120 240 900 640 0 0 7680 2129 ",
            forKey: "NSWindow Frame HubMainWindow"
        )
        let controller = MainWindowController()
        let window = controller.hubWindow
        XCTAssertEqual(window.frame.width, 900, accuracy: 1)
        XCTAssertEqual(window.frame.height, 640, accuracy: 1)
    }
}
#endif
