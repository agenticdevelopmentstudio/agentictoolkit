import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class SingleWindowControllerTests: XCTestCase {

    // MARK: - Subclasses under test

    private final class ViewControllerBasedWC: SingleWindowController {
        let viewController: FakeVC

        init(windowID: String) {
            let viewController = FakeVC()
            self.viewController = viewController
            super.init(windowID: windowID, contentViewController: viewController)
            self.windowTitle = "VC-Based"
            self.windowStyleMask = [.titled, .closable, .miniaturizable, .resizable]
            self.minSize = NSSize(width: 100, height: 100)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var defaultContentRect: NSRect { NSRect(x: 0, y: 0, width: 321, height: 234) }
    }

    /// A window that grows its own titlebar in `configureWindow`, the way every
    /// real toolbar-bearing window in this framework does.
    private final class ToolbarWC: SingleWindowController {
        init(windowID: String) {
            super.init(windowID: windowID, contentViewController: FakeVC())
            self.windowTitle = "Toolbar"
            self.windowStyleMask = [.titled, .closable, .miniaturizable, .resizable]
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func configureWindow(_ window: NSWindow) {
            window.toolbar = NSToolbar(identifier: "test.toolbar")
            window.toolbarStyle = .unified
        }
    }

    private final class FakeVC: NSViewController {
        private(set) var loadViewCallCount = 0
        override func loadView() {
            loadViewCallCount += 1
            view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        }
    }

    // MARK: - Tests

    func testSubclassOverridesDriveWindowConfig() throws {
        let windowController = ViewControllerBasedWC(windowID: "test.viewController")
        windowController.showWindow()

        let window = try XCTUnwrap(windowController.window)
        XCTAssertEqual(window.title, "VC-Based")
        XCTAssertEqual(window.contentViewController, windowController.viewController)
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertEqual(window.minSize, NSSize(width: 100, height: 100))
    }

    /// A unified toolbar makes the titlebar taller, and AppKit makes room by
    /// growing the frame downward from a fixed top edge. Position the window
    /// before that happens and it settles half the toolbar's height below the
    /// centre it was placed at — so the frame has to be applied after the
    /// chrome is final, not before.
    func testAToolbarInstalledDuringConfigureDoesNotPushTheWindowOffCentre() throws {
        let id = "test.toolbar.centred.\(UUID().uuidString)"
        WindowManager.shared.frames.register(id: id, spec: WindowSpec(
            defaultSize: NSSize(width: 480, height: 320),
            minSize: NSSize(width: 200, height: 150),
            defaultPosition: .center,
            persistsFrame: true
        ))
        WindowManager.shared.frames.clearSavedState(for: id)
        defer { WindowManager.shared.frames.clearSavedState(for: id) }

        let windowController = ToolbarWC(windowID: id)
        windowController.showWindow()

        let window = try XCTUnwrap(windowController.window)
        XCTAssertNotNil(window.toolbar, "the subclass must actually have installed a toolbar")
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
            throw XCTSkip("no screen available in test environment")
        }
        XCTAssertEqual(window.frame.midX, visible.midX, accuracy: 2.0,
                       "a toolbar changes height, not width, so this holds either way")
        XCTAssertEqual(window.frame.midY, visible.midY, accuracy: 2.0,
                       "the window must be centred on the frame it ends up with, not the one it briefly had")
    }

    func testContentViewControllerLifecycleWiresUp() {
        let windowController = ViewControllerBasedWC(windowID: "test.viewController.lifecycle")
        windowController.showWindow()
        XCTAssertGreaterThan(windowController.viewController.loadViewCallCount, 0,
            "loadView should fire when contentViewController is set")
    }

    func testReshowReusesSameWindow() {
        let windowController = ViewControllerBasedWC(windowID: "test.reuse")
        windowController.showWindow()
        let first = windowController.window
        windowController.showWindow()
        XCTAssertTrue(first === windowController.window, "second showWindow should not create a new NSWindow")
    }

    func testIsVisibleReflectsWindowState() {
        let windowController = ViewControllerBasedWC(windowID: "test.visible")
        XCTAssertFalse(windowController.isVisible, "no window created yet")
        windowController.showWindow()
        XCTAssertTrue(windowController.isVisible)
        windowController.dismiss()
        XCTAssertFalse(windowController.isVisible)
    }

    func testWindowWithNoSavedGeometryIsGeometricallyCenteredOnMainScreen() throws {
        // Regression: `NSWindow.center()` places the window at "upper-center"
        // (one-third from the top), NOT the geometric center. A prior
        // iteration called `newWindow.center()` after `WindowManager.restoreFrame`
        // which overrode the correct proportional centering with AppKit's
        // upper-center. Verify BOTH midX and midY match the visible frame's
        // center — an X-only check passed the buggy version.
        let windowController = ViewControllerBasedWC(windowID: "test.center.\(UUID().uuidString)")
        windowController.showWindow()

        let window = try XCTUnwrap(windowController.window)
        let screen = try XCTUnwrap(window.screen ?? NSScreen.main)
        let visible = screen.visibleFrame

        XCTAssertEqual(window.frame.midX, visible.midX, accuracy: 2.0,
            "window with no saved geometry should be horizontally centered on main screen")
        XCTAssertEqual(window.frame.midY, visible.midY, accuracy: 2.0,
            "window with no saved geometry should be VERTICALLY GEOMETRICALLY centered — not AppKit upper-center")
    }

    func testWindowWithRegisteredCenterSpecIsGeometricallyCentered() throws {
        // The spec'd path — what app code does in practice: register a
        // WindowSpec with `.center` and let WindowManager.restoreFrame do
        // the positioning via FrameCalculator.defaultFrame.
        let id = "test.center.spec.\(UUID().uuidString)"
        WindowManager.shared.frames.register(
            id: id,
            spec: WindowSpec(
                defaultSize: NSSize(width: 800, height: 500),
                minSize: NSSize(width: 200, height: 200),
                defaultPosition: .center,
                persistsFrame: true
            )
        )
        WindowManager.shared.frames.clearSavedState(for: id)

        let windowController = ViewControllerBasedWC(windowID: id)
        windowController.showWindow()

        let window = try XCTUnwrap(windowController.window)
        let screen = try XCTUnwrap(window.screen ?? NSScreen.main)
        let visible = screen.visibleFrame

        XCTAssertEqual(window.frame.midX, visible.midX, accuracy: 2.0)
        XCTAssertEqual(window.frame.midY, visible.midY, accuracy: 2.0)
    }

    func testDelegateIsInstalledAfterRestoreFrameSoConstructionEventsDontClobberSavedState() throws {
        // Regression: setting `contentViewController` posts
        // NSWindowDidResizeNotification synchronously. If the delegate is
        // attached before that, `windowDidResize` calls
        // `WindowManager.saveFrame` with the default-NSWindow pre-restore
        // frame, overwriting any prior saved state. Then `restoreFrame`
        // reads back that just-saved default frame and applies it —
        // producing a window positioned at AppKit's initial cascade, not
        // the spec's geometric center.
        //
        // With the delegate installed last, construction-time resize events
        // never reach `saveFrame`, so `restoreFrame` sees a clean "no saved
        // state" and applies the spec's default center.
        let id = "test.delegate.order.\(UUID().uuidString)"
        WindowManager.shared.frames.register(
            id: id,
            spec: WindowSpec(
                defaultSize: NSSize(width: 800, height: 500),
                minSize: NSSize(width: 200, height: 200),
                defaultPosition: .center,
                persistsFrame: true
            )
        )
        WindowManager.shared.frames.clearSavedState(for: id)

        let windowController = ViewControllerBasedWC(windowID: id)
        windowController.showWindow()

        let window = try XCTUnwrap(windowController.window)
        // After construction the persisted state — if anything was saved —
        // must correspond to the spec's default position, not the pre-
        // restore default NSWindow frame. Read the raw persisted state via
        // the shared storage.
        if let saved = WindowManager.shared.frames.storage.loadState(for: id),
           let placement = saved.placements.values.max(by: { $0.savedAt < $1.savedAt }) {
            XCTAssertEqual(placement.width, 800, accuracy: 2.0,
                "saved width must reflect spec default, not pre-restore NSWindow default")
            XCTAssertEqual(placement.height, 500, accuracy: 2.0,
                "saved height must reflect spec default, not pre-restore NSWindow default")
        }
        // And the live window frame must match the spec — proving the
        // construction-time delegate events didn't clobber the restore.
        XCTAssertEqual(window.frame.width, 800, accuracy: 2.0,
            "window width must come from spec, not pre-restore default")
        XCTAssertEqual(window.frame.height, 500, accuracy: 2.0,
            "window height must come from spec, not pre-restore default")
    }

    // MARK: - Not interrupting whoever is running the suite

    func testTestHostDoesNotForceWindowsInFrontOfOtherApps() {
        // This assertion IS the guarantee: the suite exercises a dozen window
        // controllers, and with front-forcing on, every one of them threw an
        // opaque window over the developer's screen for the length of the run.
        XCTAssertFalse(SingleWindowController.forcesWindowFront,
            "a test host must never call orderFrontRegardless")
    }

    func testShownWindowStaysVisibleButSinksBehindTheDesktop() throws {
        let windowController = ViewControllerBasedWC(windowID: "test.unobtrusive.\(UUID().uuidString)")
        windowController.showWindow()

        let window = try XCTUnwrap(windowController.window)
        // Still a real, on-screen, laid-out window — everything the rest of
        // this file asserts about frames and visibility depends on that.
        XCTAssertTrue(window.isVisible)
        XCTAssertNotNil(window.screen)
        // But behind the desktop picture, so nobody watching the screen sees it.
        XCTAssertEqual(window.level, NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow))),
            "a window shown from a test host belongs behind the desktop, not over the user's work")
    }
}
