import AppKit

public extension NSWindow {

    /// Whether this process is an XCTest host. XCTest links its own framework
    /// into the runner, so the class exists in a test run and nowhere else.
    static var isRunningInTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// Sinks the window behind the desktop picture.
    ///
    /// A test has to put a window genuinely on screen — `isVisible`, the frame,
    /// `window.screen`, first-responder changes and the whole
    /// `viewWillAppear`/`viewDidAppear` cycle are all things a suite asserts,
    /// and every one of them evaporates if the window is ordered out or moved
    /// off the display. But a suite that runs while someone is using the
    /// machine must not put that window *in front of* them. Dropping the level
    /// below the desktop leaves a real, laid-out, visible window to AppKit and
    /// nothing at all to whoever is at the keyboard.
    ///
    /// Level only, deliberately: key status and ordering within the level stay
    /// the caller's to set, because a test that needs `makeFirstResponder` to
    /// take needs a key window.
    func sinkBehindDesktop() {
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
    }

    /// `orderFront(nil)`, except in a test host, where the window is sunk
    /// behind the desktop picture on its way on screen.
    ///
    /// The level is set *before* the ordering, so the window is never briefly
    /// visible at the normal level.
    func orderFrontQuietly() {
        if Self.isRunningInTests { sinkBehindDesktop() }
        orderFront(nil)
    }

    /// `makeKeyAndOrderFront(nil)` with the same treatment. Key status survives
    /// the sinking — a window's level says where it draws, not whether it is
    /// key — so a test that needs the responder chain still gets one.
    func makeKeyAndOrderFrontQuietly() {
        if Self.isRunningInTests { sinkBehindDesktop() }
        makeKeyAndOrderFront(nil)
    }
}
